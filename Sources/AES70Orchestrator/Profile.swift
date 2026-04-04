//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftOCA
@_spi(SwiftOCAPrivate) import SwiftOCADevice
import Synchronization

private protocol _OcaBlockContainer: OcaBlockContainer {
  func _add(actionObject: SwiftOCADevice.OcaRoot) async throws
  func _delete(actionObject: SwiftOCADevice.OcaRoot) async throws
}

extension SwiftOCADevice.OcaBlock: _OcaBlockContainer {
  func _add(actionObject object: SwiftOCADevice.OcaRoot) async throws {
    guard let object = object as? ActionObject else {
      throw Ocp1Error.status(.parameterError)
    }
    try await add(actionObject: object)
  }

  func _delete(actionObject object: SwiftOCADevice.OcaRoot) async throws {
    guard let object = object as? ActionObject else {
      throw Ocp1Error.status(.parameterError)
    }
    try await delete(actionObject: object)
  }
}

/// An OCA agent representing a single profile instance. Each profile is bound to one or more
/// remote devices and manages a set of local proxy objects that mirror remote device objects.
@OcaDevice
public final class OcaProfile: SwiftOCADevice.OcaAgent {
  private nonisolated static let _actionObjectsPropertyID = OcaPropertyID("3.2")
  private nonisolated static let _ownerPropertyID = OcaPropertyID("2.4")

  override public class var classID: OcaClassID { OcaClassID(
    parent: super.classID,
    authority: PADLCompanyID,
    1
  ) }

  let profileIndex: OcaONo
  nonisolated let schemaName: String
  weak var coordinator: OcaCoordinator?

  private nonisolated static let _zeroUUID = UUID(uuid: (
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  ))

  nonisolated var uuid: UUID {
    UUID(uuidString: role) ?? Self._zeroUUID
  }

  /// A profile with a zero UUID is automatically bound to all discovered devices.
  nonisolated var isAutomaticallyBound: Bool {
    uuid == Self._zeroUUID
  }

  override public nonisolated var description: String {
    "OcaProfile(oNo: \(objectNumber), index: \(profileIndex), schema: \(schemaName), role: \(role))"
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public private(set) var schema = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.3")
  )
  public private(set) var boundDevices = [String]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.4")
  )
  public private(set) var boundDeviceIndices = [String: OcaONo]()

  // maps device identifier to its allocated device index for activation lookups
  private(set) var deviceIndices = [SwiftOCA.OcaConnectionBroker.DeviceIdentifier: OcaONo]()

  func bindDevice(
    _ deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    index: OcaONo
  ) {
    deviceIndices[deviceIdentifier] = index
    boundDeviceIndices[deviceIdentifier.id] = index
    boundDevices.append(deviceIdentifier.id)
  }

  func unbindDevice(
    _ deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) {
    deviceIndices.removeValue(forKey: deviceIdentifier)
    boundDeviceIndices.removeValue(forKey: deviceIdentifier.id)
    boundDevices.removeAll { $0 == deviceIdentifier.id }
  }

  // the proxy block in the "Profile Proxies" hierarchy for this profile's local objects
  var proxyBlock: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>? {
    didSet { _startLabelMonitor() }
  }

  private var _labelMonitorTask: Task<(), Never>?

  /// When true, remote subscription events are suppressed to prevent the
  /// remote device's current values from overwriting the local proxy state
  /// during activation (initial property copy).
  var isActivating = false

  // maps local device object numbers to their bindings for efficient event dispatch
  private var objectBindings = [OcaONo: any OcaObjectBindingRepresentable]()

  func addObjectBinding(_ binding: some OcaObjectBindingRepresentable, for oNo: OcaONo) {
    objectBindings[oNo] = binding
  }

  func objectBinding(for oNo: OcaONo) -> (any OcaObjectBindingRepresentable)? {
    objectBindings[oNo]
  }

  func removeObjectBinding(for oNo: OcaONo) {
    objectBindings.removeValue(forKey: oNo)
  }

  var localObjectNumbers: Dictionary<OcaONo, any OcaObjectBindingRepresentable>.Keys {
    objectBindings.keys
  }

  func remoteObjectCount(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) -> Int {
    objectBindings.values.filter { binding in
      binding.hasRemoteObject(for: deviceIdentifier)
    }.count
  }

  func forgetRemoteObjects(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) {
    for binding in objectBindings.values {
      binding.forgetRemoteObject(for: deviceIdentifier)
    }
  }

  func handleLocalEvent(_ event: OcaEvent, parameters: Data) async {
    if let binding = objectBindings[event.emitterONo] {
      coordinator?.logger.trace(
        "handleLocalEvent: \(self) matched binding for ONo \(event.emitterONo)"
      )
      await binding.handleLocalEvent(event, parameters: parameters)
    }
  }

  override public func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("2.2"): // SetLabel — blocked, set via proxy block instead
      throw Ocp1Error.status(.permissionDenied)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  private func _startLabelMonitor() {
    _labelMonitorTask?.cancel()
    guard let proxyBlock else {
      _labelMonitorTask = nil
      return
    }
    // sync initial label from profile to proxy block
    if !label.isEmpty {
      proxyBlock.label = label
    } else if !proxyBlock.label.isEmpty {
      label = proxyBlock.label
    }
    _labelMonitorTask = Task { [weak self] in
      do {
        for try await newLabel in proxyBlock.$label {
          guard let self, !Task.isCancelled else { break }
          if label != newLabel {
            label = newLabel
          }
        }
      } catch {}
    }
  }

  var profileSchema: OcaProfileSchema {
    get throws {
      guard let coordinator else { throw Ocp1Error.status(.deviceError) }
      return try coordinator.profileSchema(named: schema)
    }
  }

  init(
    role: UUID,
    objectNumber: OcaONo,
    proxyBlockObjectNumber: OcaONo,
    profileIndex: OcaONo,
    schema: String,
    name: String?,
    entry: _SchemaEntry,
    coordinator: OcaCoordinator
  ) async throws {
    self.profileIndex = profileIndex
    schemaName = schema
    self.coordinator = coordinator
    self.schema = schema
    try await super.init(
      objectNumber: objectNumber,
      role: role.description,
      deviceDelegate: coordinator.device,
      addToRootBlock: false
    )
    let proxyBlock = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: proxyBlockObjectNumber,
      lockable: false,
      role: role.description,
      deviceDelegate: coordinator.device,
      addToRootBlock: false
    )
    if let name { proxyBlock.label = name }
    try await _createLocalObjects(proxyBlock: proxyBlock)
    self.proxyBlock = proxyBlock
    try await entry.proxies.add(actionObject: proxyBlock)
    try await entry.profiles.add(actionObject: self)
    _startLabelMonitor()
  }

  func objectNumber(for oNoMask: OcaONoMask?) throws -> OcaONo? {
    guard let oNoMask else { return nil }
    if oNoMask.mask == 0 {
      return oNoMask.oNo
    }
    return try oNoMask.objectNumber(for: profileIndex)
  }

  private func _referenceMaps(
    deviceIndex: OcaONo,
    targetMatch: OcaONoMask
  ) throws -> (localToRemote: [OcaONo: OcaONo], remoteToLocal: [OcaONo: OcaONo]) {
    _ = targetMatch
    let schema = try profileSchema
    var localToRemote = [OcaONo: OcaONo]()
    var remoteToLocal = [OcaONo: OcaONo]()

    for block in schema.blocks {
      try block.applyRecursive { objectSchema, _, _ in
        guard let localObjectNumber = objectSchema.localObjectNumber,
              let localONo = try objectNumber(for: localObjectNumber)
        else {
          return
        }

        let remoteONo = try objectSchema.remoteObjectNumber.objectNumber(for: deviceIndex)
        localToRemote[localONo] = remoteONo
        remoteToLocal[remoteONo] = localONo
      }
    }

    return (localToRemote, remoteToLocal)
  }

  func remapReferenceONoToRemote(
    _ oNo: OcaONo,
    targetMatch: OcaONoMask,
    deviceIndex: OcaONo
  ) throws -> OcaONo {
    guard oNo != OcaInvalidONo else { return oNo }
    let maps = try _referenceMaps(deviceIndex: deviceIndex, targetMatch: targetMatch)
    return maps.localToRemote[oNo] ?? oNo
  }

  func remapReferenceONoToLocal(
    _ oNo: OcaONo,
    targetMatch: OcaONoMask,
    deviceIndex: OcaONo
  ) throws -> OcaONo {
    guard oNo != OcaInvalidONo else { return oNo }
    let maps = try _referenceMaps(deviceIndex: deviceIndex, targetMatch: targetMatch)
    return maps.remoteToLocal[oNo] ?? oNo
  }

  func remapReferenceONosToRemote(
    _ onos: [OcaONo],
    targetMatch: OcaONoMask,
    deviceIndex: OcaONo
  ) throws -> [OcaONo] {
    try onos.map { try remapReferenceONoToRemote($0, targetMatch: targetMatch, deviceIndex: deviceIndex) }
  }

  private func _remoteReferenceExists(
    for localONo: OcaONo,
    deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) -> Bool {
    guard localONo != OcaInvalidONo else { return true }
    guard let binding = objectBinding(for: localONo) else { return false }
    return binding.hasRemoteObject(for: deviceIdentifier)
  }

  func remapReferencePropertyDataToRemote(
    _ data: Data,
    targetMatch: OcaONoMask,
    deviceIndex: OcaONo,
    deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) throws -> Data {
    if let onos = try? Ocp1Decoder().decode([OcaONo].self, from: data) {
      let filteredONos = onos.filter {
        _remoteReferenceExists(for: $0, deviceIdentifier: deviceIdentifier)
      }
      return try Ocp1Encoder().encode(
        remapReferenceONosToRemote(filteredONos, targetMatch: targetMatch, deviceIndex: deviceIndex)
      )
    }

    if let oNo = try? Ocp1Decoder().decode(OcaONo.self, from: data) {
      let resolvedONo =
        _remoteReferenceExists(for: oNo, deviceIdentifier: deviceIdentifier)
          ? try remapReferenceONoToRemote(oNo, targetMatch: targetMatch, deviceIndex: deviceIndex)
          : OcaInvalidONo
      return try Ocp1Encoder().encode(resolvedONo)
    }

    return try remapReferencePropertyDataToRemote(
      data,
      targetMatch: targetMatch,
      deviceIndex: deviceIndex
    )
  }

  func remapReferenceONosToLocal(
    _ onos: [OcaONo],
    targetMatch: OcaONoMask,
    deviceIndex: OcaONo
  ) throws -> [OcaONo] {
    try onos.map { try remapReferenceONoToLocal($0, targetMatch: targetMatch, deviceIndex: deviceIndex) }
  }

  func remapReferencePropertyDataToRemote(
    _ data: Data,
    targetMatch: OcaONoMask,
    deviceIndex: OcaONo
  ) throws -> Data {
    if let onos = try? Ocp1Decoder().decode([OcaONo].self, from: data) {
      return try Ocp1Encoder().encode(
        remapReferenceONosToRemote(onos, targetMatch: targetMatch, deviceIndex: deviceIndex)
      )
    }

    if let oNo = try? Ocp1Decoder().decode(OcaONo.self, from: data) {
      return try Ocp1Encoder().encode(
        remapReferenceONoToRemote(oNo, targetMatch: targetMatch, deviceIndex: deviceIndex)
      )
    }

    return data
  }

  func remapReferencePropertyDataToLocal(
    _ data: Data,
    targetMatch: OcaONoMask,
    deviceIndex: OcaONo
  ) throws -> Data {
    if let onos = try? Ocp1Decoder().decode([OcaONo].self, from: data) {
      return try Ocp1Encoder().encode(
        remapReferenceONosToLocal(onos, targetMatch: targetMatch, deviceIndex: deviceIndex)
      )
    }

    if let oNo = try? Ocp1Decoder().decode(OcaONo.self, from: data) {
      return try Ocp1Encoder().encode(
        remapReferenceONoToLocal(oNo, targetMatch: targetMatch, deviceIndex: deviceIndex)
      )
    }

    return data
  }

  private func _createLocalObjects(
    proxyBlock: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>
  ) async throws {
    guard let coordinator else { throw Ocp1Error.status(.deviceError) }
    let schema = try profileSchema

    var blocks = [[String]: any _OcaBlockContainer]()

    for block in schema.blocks {
      try await block.applyRecursive { objectSchema, rolePath, parentRolePath in
        let oNo: OcaONo? = if let localObjectNumber = objectSchema.localObjectNumber {
          try self.objectNumber(for: localObjectNumber)
        } else {
          try coordinator.allocateLocalONo()
        }
        let object = try await objectSchema.createLocalObject(
          objectNumber: oNo,
          deviceDelegate: coordinator.device
        )

        if !objectSchema.propertyDefaults.isEmpty {
          try await object.deserialize(
            jsonObject: Self._propertyDefaultsJsonObject(
              for: object,
              from: objectSchema.propertyDefaults
            ),
            flags: .ignoreMissingProperties
          )
        }

        if objectSchema.isContainer, let block = object as? (any _OcaBlockContainer) {
          blocks[rolePath] = block
        }

        if let parentRolePath {
          let parentBlock = blocks[parentRolePath]!
          try await parentBlock._add(actionObject: object)
        } else {
          try await proxyBlock.add(actionObject: object)
        }
        addObjectBinding(OcaObjectBinding<SwiftOCADevice.OcaRoot, SwiftOCA.OcaRoot>(
          localObject: object,
          profile: self,
          flags: objectSchema.flags,
          includeProperties: objectSchema.includeProperties,
          excludeProperties: objectSchema.excludeProperties,
          referenceProperties: objectSchema.referenceProperties
        ), for: object.objectNumber)
      }
    }
  }

  /// Convert YAML-friendly property defaults into the JSON format expected by
  /// ``SwiftOCADevice.OcaRoot/deserialize(jsonObject:flags:filter:)``.
  ///
  /// Bounded properties use `{value, min, max}` in the YAML which maps to
  /// the `{v, l, u}` keys used by ``OcaBoundedDeviceProperty``.
  private static func _propertyDefaultsJsonObject(
    for object: SwiftOCADevice.OcaRoot,
    from defaults: [OcaPropertyID: [String: any Sendable]]
  ) -> [String: any Sendable] {
    var json: [String: any Sendable] = [
      "_oNo": object.objectNumber,
      "_classID": type(of: object).classID.description,
    ]
    for (propertyID, dict) in defaults {
      if dict["value"] != nil, dict["min"] != nil, dict["max"] != nil {
        // Bounded property: remap to the {v, l, u} format
        json[propertyID.description] = [
          "v": dict["value"]!,
          "l": dict["min"]!,
          "u": dict["max"]!,
        ]
      } else {
        // Scalar property: use value directly
        if let value = dict["value"] {
          json[propertyID.description] = value
        }
      }
    }
    return json
  }

  private func _buildONoMap() throws -> [OcaONo: OcaONoMask] {
    let schema = try profileSchema
    var map = [OcaONo: OcaONoMask]()
    for block in schema.blocks {
      try block.applyRecursive { objectSchema, _, _ in
        guard let localONoMask = objectSchema.localObjectNumber else { return }
        guard let actualONo = try objectNumber(for: localONoMask) else { return }
        map[actualONo] = localONoMask
      }
    }
    return map
  }

  private func _remapStoredONo(
    _ oNo: OcaONo,
    oNoMap: [OcaONo: OcaONoMask],
    proxyBlockONo: OcaONo,
    toMasked: Bool
  ) -> OcaONo {
    if oNo == proxyBlockONo || (!toMasked && oNo == 0) {
      // proxy block: use sentinel 0 when serializing, restore actual on deserialize
      return toMasked ? OcaONo(0) : proxyBlockONo
    }

    if toMasked, let mask = oNoMap[oNo] {
      return mask.maskedObjectNumber(for: oNo)
    }

    if !toMasked {
      for (_, mask) in oNoMap where mask.oNo == oNo {
        if let remapped = try? objectNumber(for: mask) {
          return remapped
        }
      }
    }

    return oNo
  }

  private func _remapPropertyValue(
    _ value: any Sendable,
    propertyID: OcaPropertyID,
    schema: OcaProfileObjectSchema?,
    childSchemas: [OcaProfileObjectSchema],
    oNoMap: [OcaONo: OcaONoMask],
    proxyBlockONo: OcaONo,
    toMasked: Bool
  ) -> any Sendable {
    if propertyID == Self._actionObjectsPropertyID,
       let children = value as? [[String: any Sendable]]
    {
      let nestedSchemas = schema?.actionObjectSchema ?? childSchemas
      return children.enumerated().map { index, child in
        let childSchema: OcaProfileObjectSchema? =
          nestedSchemas.indices.contains(index) ? nestedSchemas[index] : nil
        return _remapONos(
          in: child,
          schema: childSchema,
          childSchemas: childSchema?.actionObjectSchema ?? [],
          oNoMap: oNoMap,
          proxyBlockONo: proxyBlockONo,
          toMasked: toMasked
        )
      }
    } else if propertyID != Self._ownerPropertyID,
              schema?.referenceProperty(for: propertyID) == nil
    {
      return value
    } else if let onos = value as? [OcaONo] {
      return onos.map {
        _remapStoredONo($0, oNoMap: oNoMap, proxyBlockONo: proxyBlockONo, toMasked: toMasked)
      }
    } else if let numbers = value as? [NSNumber] {
      return numbers.map {
        _remapStoredONo(
          OcaONo(truncating: $0),
          oNoMap: oNoMap,
          proxyBlockONo: proxyBlockONo,
          toMasked: toMasked
        )
      }
    } else if let oNo = value as? OcaONo {
      return _remapStoredONo(oNo, oNoMap: oNoMap, proxyBlockONo: proxyBlockONo, toMasked: toMasked)
    } else if let number = value as? NSNumber {
      return _remapStoredONo(
        OcaONo(truncating: number),
        oNoMap: oNoMap,
        proxyBlockONo: proxyBlockONo,
        toMasked: toMasked
      )
    } else {
      return value
    }
  }

  private func _remapONos(
    in jsonObject: [String: any Sendable],
    schema: OcaProfileObjectSchema?,
    childSchemas: [OcaProfileObjectSchema],
    oNoMap: [OcaONo: OcaONoMask],
    proxyBlockONo: OcaONo,
    toMasked: Bool
  ) -> [String: any Sendable] {
    var result = jsonObject

    if let oNo = result["_oNo"] as? OcaONo {
      result["_oNo"] = _remapStoredONo(
        oNo,
        oNoMap: oNoMap,
        proxyBlockONo: proxyBlockONo,
        toMasked: toMasked
      )
    } else if let number = result["_oNo"] as? NSNumber {
      result["_oNo"] = _remapStoredONo(
        OcaONo(truncating: number),
        oNoMap: oNoMap,
        proxyBlockONo: proxyBlockONo,
        toMasked: toMasked
      )
    }

    for (key, value) in result {
      guard let propertyID = try? OcaPropertyID(unsafeString: key),
            propertyID == Self._actionObjectsPropertyID
              || propertyID == Self._ownerPropertyID
              || schema?.referenceProperty(for: propertyID) != nil
      else {
        continue
      }

      result[key] = _remapPropertyValue(
        value,
        propertyID: propertyID,
        schema: schema,
        childSchemas: childSchemas,
        oNoMap: oNoMap,
        proxyBlockONo: proxyBlockONo,
        toMasked: toMasked
      )
    }

    return result
  }

  func serializeState() async throws -> [String: any Sendable] {
    guard let proxyBlock else { throw Ocp1Error.status(.deviceError) }
    let schema = try profileSchema
    let oNoMap = try _buildONoMap()
    let jsonObject = try await proxyBlock.serializeParameterDataset()
    return _remapONos(
      in: jsonObject,
      schema: nil,
      childSchemas: schema.blocks,
      oNoMap: oNoMap,
      proxyBlockONo: proxyBlock.objectNumber,
      toMasked: true
    )
  }

  func deserializeState(_ jsonObject: [String: any Sendable]) async throws {
    guard let proxyBlock else { throw Ocp1Error.status(.deviceError) }
    let schema = try profileSchema
    let oNoMap = try _buildONoMap()
    let remapped = _remapONos(
      in: jsonObject,
      schema: nil,
      childSchemas: schema.blocks,
      oNoMap: oNoMap,
      proxyBlockONo: proxyBlock.objectNumber,
      toMasked: false
    )
    try await proxyBlock.deserializeParameterDataset(remapped)
  }

  private func _forEachBinding(
    deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    deviceIndex: OcaONo,
    connection: Ocp1Connection,
    schema: OcaProfileObjectSchema,
    _ body: (any OcaObjectBindingRepresentable, SwiftOCA.OcaRoot) async throws -> ()
  ) async throws {
    try await _forEachBinding(
      deviceIdentifier: deviceIdentifier,
      deviceIndex: deviceIndex,
      connection: connection,
      schema: schema,
      rolePath: [schema.role],
      body,
    )
  }

  private func _forEachBinding(
    deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    deviceIndex: OcaONo,
    connection: Ocp1Connection,
    schema: OcaProfileObjectSchema,
    rolePath: [String],
    _ body: (any OcaObjectBindingRepresentable, SwiftOCA.OcaRoot) async throws -> ()
  ) async throws {
    let remoteONo = try schema.remoteObjectNumber.objectNumber(for: deviceIndex)
    let remoteObject: SwiftOCA.OcaRoot

    do {
      remoteObject = try await connection.resolve(objectOfUnknownClass: remoteONo)
    } catch let error as Ocp1Error where error == .status(.badONo) {
      coordinator?.logger.trace(
        "Skipping missing remote object for \(self) at \(rolePath.joined(separator: "/")) on \(deviceIdentifier) (oNo=\(remoteONo))"
      )
      return
    }

    if let localONo = try objectNumber(for: schema.localObjectNumber),
       let binding = objectBinding(for: localONo)
    {
      try await body(binding, remoteObject)
    }

    for child in schema.actionObjectSchema {
      try await _forEachBinding(
        deviceIdentifier: deviceIdentifier,
        deviceIndex: deviceIndex,
        connection: connection,
        schema: child,
        rolePath: rolePath + [child.role],
        body,
      )
    }
  }

  func bindRemoteObjects(
    to deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    deviceIndex: OcaONo,
    connection: Ocp1Connection,
    schema: OcaProfileObjectSchema
  ) async throws {
    // Flatten the schema tree so we can resolve remote objects concurrently.
    var entries = [OcaProfileObjectSchema]()
    schema.applyRecursive { objectSchema, _, _ in
      entries.append(objectSchema)
    }

    // Resolve all remote objects in parallel. Each task returns the local
    // binding together with the resolved remote object, or nil if the remote
    // object does not exist or has no local binding.
    let resolvedBindings = try await withThrowingTaskGroup(
      of: (any OcaObjectBindingRepresentable, SwiftOCA.OcaRoot)?.self
    ) { group in
      for entry in entries {
        let remoteONo = try entry.remoteObjectNumber.objectNumber(for: deviceIndex)

        guard let localONo = try objectNumber(for: entry.localObjectNumber),
              let binding = objectBinding(for: localONo)
        else {
          continue
        }

        group.addTask {
          let remoteObject: SwiftOCA.OcaRoot
          do {
            remoteObject = try await connection.resolve(objectOfUnknownClass: remoteONo)
          } catch let error as Ocp1Error where error == .status(.badONo) {
            return nil
          }
          return (binding, remoteObject)
        }
      }

      var results = [(any OcaObjectBindingRepresentable, SwiftOCA.OcaRoot)]()
      for try await result in group {
        if let result {
          results.append(result)
        }
      }
      return results
    }

    // Bind each resolved pair. These are @OcaDevice-isolated operations that
    // also perform network I/O (copying properties, setting up subscriptions).
    for (binding, remoteObject) in resolvedBindings {
      try await binding.bind(remoteObject: remoteObject, from: deviceIdentifier)
    }
  }

  func unbindRemoteObjects(
    from deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    deviceIndex: OcaONo,
    connection: Ocp1Connection,
    schema: OcaProfileObjectSchema
  ) async {
    try? await _forEachBinding(
      deviceIdentifier: deviceIdentifier,
      deviceIndex: deviceIndex,
      connection: connection,
      schema: schema
    ) { binding, remoteObject in
      try await binding.unbind(remoteObject: remoteObject, from: deviceIdentifier)
    }
  }

  @OcaDevice
  func deleteLocalObjects() async throws {
    let device = try coordinator?.device
    for oNo in objectBindings.keys {
      try await device?.deregister(objectNumber: oNo)
    }
    objectBindings.removeAll()
  }

  deinit {
    _labelMonitorTask?.cancel()
  }

  required init(from decoder: Decoder) throws {
    throw Ocp1Error.notImplemented
  }

  public required init(
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString? = nil,
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = false
  ) async throws {
    profileIndex = 0
    schemaName = ""
    try await super.init(
      objectNumber: objectNumber,
      lockable: lockable,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: addToRootBlock
    )
  }
}
