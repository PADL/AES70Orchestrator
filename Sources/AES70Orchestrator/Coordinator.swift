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
import SwiftOCADevice

let PADLCompanyID = OcaOrganizationID((0x0A, 0xE9, 0x1B))

public let OcaCoordinatorONo = OcaONo(1024)
// FIXME: in order to not conflict with device ONo space we are going to use the reserved ONos
let ProfilesContainerONo = OcaONo(1025)
let MaxProfiles = OcaONo(100)
let ProfilesONoRange: Range<OcaONo> = ProfilesContainerONo +
  1..<(ProfilesContainerONo + MaxProfiles)

public enum OcaCoordinatorError: Error {
  case profileONoAllocationExhausted
  case profileSchemaNotFound
  case profileNotFound
  case deviceIndexExhausted
  case deviceIndexInvalid
}

@OcaDevice
public final class OcaCoordinator: SwiftOCADevice.OcaManager, Sendable, OcaDeviceEventDelegate {
  override public class var classID: OcaClassID { OcaClassID(
    parent: super.classID,
    authority: PADLCompanyID,
    1
  ) }

  var device: OcaDevice {
    get throws {
      guard let device = deviceDelegate else { throw Ocp1Error.status(.deviceError) }
      return device
    }
  }

  let connectionBroker: SwiftOCA.OcaConnectionBroker
  let deviceSchema: OcaDeviceSchema

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var currentDeviceIdentifiers = [OcaString]()

  // profiles are conatined in blocks but we should also be able to look them up by UUID or name
  var profiles: SwiftOCADevice.OcaBlock<OcaProfile>
  private var nextProfileIndex: OcaONo = 0
  private var _deviceIndices = [SwiftOCA.OcaConnectionBroker.DeviceIdentifier: Set<OcaONo>]()
  private var _brokerEventTask: Task<(), Never>?

  func allocateProfileIndex() throws -> OcaONo {
    let index = nextProfileIndex
    let oNo = ProfilesONoRange.lowerBound + index
    guard ProfilesONoRange.contains(oNo) else {
      throw OcaCoordinatorError.profileONoAllocationExhausted
    }
    nextProfileIndex += 1
    return index
  }

  @OcaDevice
  public init(
    connectionBroker: SwiftOCA.OcaConnectionBroker,
    deviceSchema: OcaDeviceSchema
  ) async throws {
    self.deviceSchema = deviceSchema
    self.connectionBroker = connectionBroker
    try await profiles = .init(
      objectNumber: ProfilesContainerONo,
      lockable: false,
      role: "Profiles"
    )
    try await super.init(
      objectNumber: OcaCoordinatorONo,
      role: "Profile Manager"
    )
    try await device.setEventDelegate(self)
  }

  @OcaDevice
  public convenience init(
    connectionOptions: Ocp1ConnectionOptions = .init(),
    serviceTypes: Set<OcaNetworkAdvertisingServiceType>? = nil,
    deviceSchema: OcaDeviceSchema
  ) async throws {
    let broker = await OcaConnectionBroker(
      connectionOptions: connectionOptions,
      serviceTypes: serviceTypes,
      deviceModels: deviceSchema.models
    )
    try await self.init(connectionBroker: broker, deviceSchema: deviceSchema)
    _brokerEventTask = Task { [weak self] in
      guard let self else { return }
      for await event in await broker.events {
        await handleBrokerEvent(event)
      }
    }
  }

  public required init(from decoder: Decoder) throws {
    fatalError("not supported")
  }

  public required init(
    objectNumber: OcaONo? = nil,
    lockable: OcaBoolean = true,
    role: OcaString? = nil,
    deviceDelegate: OcaDevice? = nil,
    addToRootBlock: Bool = true
  ) async throws {
    fatalError("not supported")
  }

  deinit {
    _brokerEventTask?.cancel()
  }

  public func handleBrokerEvent(
    _ event: SwiftOCA.OcaConnectionBroker.Event
  ) async {
    switch event.eventType {
    case .deviceAdded:
      if !currentDeviceIdentifiers.contains(event.deviceIdentifier.id) {
        currentDeviceIdentifiers.append(event.deviceIdentifier.id)
      }
    case .deviceRemoved:
      for profile in profiles.actionObjects {
        guard profile.deviceIndices[event.deviceIdentifier] != nil else { continue }
        try? await unbindProfile(profile, from: event.deviceIdentifier)
      }
      currentDeviceIdentifiers.removeAll { $0 == event.deviceIdentifier.id }
    default:
      break
    }
  }

  public func onEvent(_ event: SwiftOCA.OcaEvent, parameters: Data) async {
    for profile in profiles.actionObjects {
      await profile.handleLocalEvent(event, parameters: parameters)
    }
  }

  public func onControllerExpiry(_ controller: any SwiftOCADevice.OcaController) async {}

  func profileSchema(named name: String) throws -> OcaProfileSchema {
    guard let schema = deviceSchema.profileSchemas.first(where: { $0.name == name }) else {
      throw OcaCoordinatorError.profileSchemaNotFound
    }
    return schema
  }

  @discardableResult
  public func addProfile(schema: String, name: String? = nil) async throws -> OcaONo {
    let profileUUID = UUID()
    let profile = try await OcaProfile(
      role: profileUUID,
      schema: schema,
      coordinator: self
    )
    if let name { profile.label = name }
    try await profile.createLocalObjects()
    try await profiles.add(actionObject: profile)
    return profile.objectNumber
  }

  private func _findProfile(oNo: OcaONo) throws -> OcaProfile {
    guard let profile = profiles.actionObjects.first(where: { $0.objectNumber == oNo }) else {
      throw OcaCoordinatorError.profileNotFound
    }
    return profile
  }

  public struct AddProfileParameters: Ocp1ParametersReflectable, Sendable {
    public let schema: OcaString
    public let name: OcaString?
  }

  public static let AutoDeviceIndex: OcaUint16 = 0xFFFF

  public struct BindProfileParameters: Ocp1ParametersReflectable, Sendable {
    public let profileONo: OcaONo
    public let deviceIdentifier: OcaString
    public let deviceIndex: OcaUint16
  }

  public struct UnbindProfileParameters: Ocp1ParametersReflectable, Sendable {
    public let profileONo: OcaONo
    public let deviceIdentifier: OcaString
  }

  override public func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.2"):
      let params: AddProfileParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      let oNo = try await addProfile(schema: params.schema, name: params.name)
      return try encodeResponse(oNo)
    case OcaMethodID("3.3"):
      let params: BindProfileParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      guard let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(params.deviceIdentifier)
      else {
        throw Ocp1Error.status(.parameterError)
      }
      try await bindProfile(
        _findProfile(oNo: params.profileONo),
        to: deviceIdentifier,
        deviceIndex: params.deviceIndex == Self.AutoDeviceIndex
          ? nil : OcaONo(params.deviceIndex)
      )
      return Ocp1Response()
    case OcaMethodID("3.4"):
      let params: UnbindProfileParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      guard let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(params.deviceIdentifier)
      else {
        throw Ocp1Error.status(.parameterError)
      }
      try await unbindProfile(_findProfile(oNo: params.profileONo), from: deviceIdentifier)
      return Ocp1Response()
    case OcaMethodID("3.5"):
      let name: OcaString = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await deleteProfile(named: name)
      return Ocp1Response()
    case OcaMethodID("3.6"):
      let uuid: OcaString = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      guard let uuid = UUID(uuidString: uuid) else {
        throw Ocp1Error.status(.parameterError)
      }
      try await deleteProfile(uuid: uuid)
      return Ocp1Response()
    case OcaMethodID("3.7"):
      let name: OcaString = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      let profile = try findProfile(named: name)
      return try encodeResponse(profile.objectNumber)
    case OcaMethodID("3.8"):
      let uuid: OcaString = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      guard let uuid = UUID(uuidString: uuid) else {
        throw Ocp1Error.status(.parameterError)
      }
      let profile = try findProfile(uuid: uuid)
      return try encodeResponse(profile.objectNumber)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  private func _allocateDeviceIndex(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    requestedIndex: OcaONo?,
    maxInstances: Int
  ) throws -> OcaONo {
    let used = _deviceIndices[deviceIdentifier, default: []]
    if let requestedIndex {
      guard requestedIndex < OcaONo(maxInstances) else {
        throw OcaCoordinatorError.deviceIndexInvalid
      }
      guard !used.contains(requestedIndex) else {
        throw OcaCoordinatorError.deviceIndexExhausted
      }
      _deviceIndices[deviceIdentifier, default: []].insert(requestedIndex)
      return requestedIndex
    }
    for index in OcaONo(0)..<OcaONo(maxInstances) {
      if !used.contains(index) {
        _deviceIndices[deviceIdentifier, default: []].insert(index)
        return index
      }
    }
    throw OcaCoordinatorError.deviceIndexExhausted
  }

  private func _releaseDeviceIndex(
    _ index: OcaONo,
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) {
    _deviceIndices[deviceIdentifier]?.remove(index)
    if _deviceIndices[deviceIdentifier]?.isEmpty == true {
      _deviceIndices.removeValue(forKey: deviceIdentifier)
    }
  }

  private func _connection(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws -> Ocp1Connection {
    try await connectionBroker
      .withDeviceConnection(deviceIdentifier) { @Sendable connection in connection }
  }

  private func _forEachBinding(
    profile: OcaProfile,
    deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    deviceIndex: OcaONo,
    connection: Ocp1Connection,
    schema: OccProfileObjectSchema,
    _ body: (any OcaObjectBindingRepresentable, SwiftOCA.OcaRoot) async throws -> ()
  ) async throws {
    try await schema.applyRecursive { objectSchema, _, _ in
      let remoteONo = try objectSchema.remoteObjectNumber.objectNumber(for: deviceIndex)
      let remoteObject: SwiftOCA.OcaRoot = try await connection.resolve(
        objectOfUnknownClass: remoteONo
      )
      guard let localONo = try profile.objectNumber(
        for: objectSchema.localObjectNumber
      ) else {
        return
      }
      guard let binding = profile.objectBinding(for: localONo) else {
        return
      }
      try await body(binding, remoteObject)
    }
  }

  private func _bindProfile(
    _ profile: OcaProfile,
    to deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    deviceIndex: OcaONo,
    connection: Ocp1Connection,
    schema: OccProfileObjectSchema
  ) async throws {
    try await _forEachBinding(
      profile: profile,
      deviceIdentifier: deviceIdentifier,
      deviceIndex: deviceIndex,
      connection: connection,
      schema: schema
    ) { binding, remoteObject in
      try await binding.enroll(remoteObject: remoteObject, from: deviceIdentifier)
    }
  }

  private func _unbindProfile(
    _ profile: OcaProfile,
    from deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    deviceIndex: OcaONo,
    connection: Ocp1Connection,
    schema: OccProfileObjectSchema
  ) async {
    try? await _forEachBinding(
      profile: profile,
      deviceIdentifier: deviceIdentifier,
      deviceIndex: deviceIndex,
      connection: connection,
      schema: schema
    ) { binding, remoteObject in
      try await binding.unenroll(remoteObject: remoteObject, from: deviceIdentifier)
    }
  }

  public func bindProfile(
    _ profile: OcaProfile,
    to deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    deviceIndex: OcaONo? = nil
  ) async throws {
    let connection = try await _connection(for: deviceIdentifier)
    let schema = try profile.profileSchema
    let maxInstances = schema.blocks.first?.remoteObjectCount ?? 0
    let index = try _allocateDeviceIndex(
      for: deviceIdentifier, requestedIndex: deviceIndex, maxInstances: maxInstances
    )
    var boundBlocks = [OccProfileObjectSchema]()
    do {
      for block in schema.blocks {
        try await _bindProfile(
          profile, to: deviceIdentifier, deviceIndex: index,
          connection: connection, schema: block
        )
        boundBlocks.append(block)
      }
    } catch {
      for block in boundBlocks {
        await _unbindProfile(
          profile, from: deviceIdentifier, deviceIndex: index,
          connection: connection, schema: block
        )
      }
      _releaseDeviceIndex(index, for: deviceIdentifier)
      throw error
    }
    profile.deviceIndices[deviceIdentifier] = index
    profile.boundDevices.append(deviceIdentifier.id)
  }

  public func unbindProfile(
    _ profile: OcaProfile,
    from deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws {
    guard let index = profile.deviceIndices[deviceIdentifier] else {
      return
    }
    let connection = try await _connection(for: deviceIdentifier)
    let schema = try profile.profileSchema
    for block in schema.blocks {
      await _unbindProfile(
        profile, from: deviceIdentifier, deviceIndex: index,
        connection: connection, schema: block
      )
    }
    _releaseDeviceIndex(index, for: deviceIdentifier)
    profile.deviceIndices.removeValue(forKey: deviceIdentifier)
    profile.boundDevices.removeAll { $0 == deviceIdentifier.id }
  }

  private func _deleteProfile(_ profile: OcaProfile) async throws {
    for (deviceIdentifier, _) in profile.deviceIndices {
      try? await unbindProfile(profile, from: deviceIdentifier)
    }
    try await profile.deleteLocalObjects()
    try await profiles.delete(actionObject: profile)
  }

  public func deleteProfile(uuid: UUID) async throws {
    try await _deleteProfile(findProfile(uuid: uuid))
  }

  public func deleteProfile(named name: String) async throws {
    try await _deleteProfile(findProfile(named: name))
  }

  public func findProfile(named name: String) throws -> OcaProfile {
    guard let profile = profiles.actionObjects.first(where: { $0.role == name }) else {
      throw OcaCoordinatorError.profileNotFound
    }
    return profile
  }

  public func findProfile(uuid: UUID) throws -> OcaProfile {
    guard let profile = profiles.actionObjects.first(where: { $0.role == uuid.description }) else {
      throw OcaCoordinatorError.profileNotFound
    }
    return profile
  }
}
