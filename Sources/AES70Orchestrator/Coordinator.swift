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
import AES70OrchestratorClient
import Logging
import SwiftOCA
import SwiftOCADevice

let PADLCompanyID = OcaOrganizationID((0x0A, 0xE9, 0x1B))

public let OcaCoordinatorONo = OcaONo(1024)
// FIXME: in order to not conflict with device ONo space we are going to use the reserved ONos
let ProfilesContainerONo = OcaONo(1025)
let ProfileProxiesContainerONo = OcaONo(1026)
// per-schema blocks start at ProfileProxiesContainerONo + 1, with 2 blocks per schema
// (one for profiles, one for proxies), so the profile ONo range starts after those
let MaxProfiles = OcaONo(100)

public enum OcaCoordinatorError: Error {
  case profileONoAllocationExhausted
  case profileSchemaNotFound
  case profileNotFound
  case deviceIndexExhausted
  case deviceIndexInvalid
  case persistenceError
  case schemaParseError(String)
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
  nonisolated let logger: Logger

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var currentDeviceIdentifiers = [OcaString]()

  @OcaDevice
  final class _SchemaEntry {
    let profiles: SwiftOCADevice.OcaBlock<OcaProfile>
    let proxies: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>
    var nextProfileIndex: OcaONo = 0
    var deviceIndices = [SwiftOCA.OcaConnectionBroker.DeviceIdentifier: Set<OcaONo>]()

    init(
      profiles: SwiftOCADevice.OcaBlock<OcaProfile>,
      proxies: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>
    ) {
      self.profiles = profiles
      self.proxies = proxies
    }

    func allocateProfileIndex() -> OcaONo {
      let index = nextProfileIndex
      nextProfileIndex += 1
      return index
    }
  }

  let _profilesBlock: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>
  let _profileProxiesBlock: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>
  var _schemaEntries = [String: _SchemaEntry]()
  private var _nextProfileONo: OcaONo = 0
  private var _brokerEventTask: Task<(), Never>?
  var _persistenceMonitorTask: Task<(), Never>?

  public let events: AsyncStream<SwiftOCA.OcaEvent>
  private let _eventsContinuation: AsyncStream<SwiftOCA.OcaEvent>.Continuation

  private func _schemaEntry(for schemaName: String) throws -> _SchemaEntry {
    guard let entry = _schemaEntries[schemaName] else {
      throw OcaCoordinatorError.profileSchemaNotFound
    }
    return entry
  }

  private var _profileONoLimit: OcaONo {
    _profileONoBase + MaxProfiles
  }

  private var _profileONoBase: OcaONo = 0

  func allocateProfileONo() throws -> OcaONo {
    let oNo = _nextProfileONo
    guard oNo < _profileONoLimit else {
      throw OcaCoordinatorError.profileONoAllocationExhausted
    }
    _nextProfileONo += 1
    return oNo
  }

  @OcaDevice
  public init(
    connectionBroker: SwiftOCA.OcaConnectionBroker,
    deviceSchema: OcaDeviceSchema,
    deviceDelegate: OcaDevice? = nil,
    logger: Logger = Logger(label: "com.padl.AES70Orchestrator")
  ) async throws {
    self.deviceSchema = deviceSchema
    self.connectionBroker = connectionBroker
    self.logger = logger
    let (stream, continuation) = AsyncStream<SwiftOCA.OcaEvent>.makeStream()
    events = stream
    _eventsContinuation = continuation
    _profilesBlock = try await .init(
      objectNumber: ProfilesContainerONo,
      lockable: false,
      role: "Profiles",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
    _profileProxiesBlock = try await .init(
      objectNumber: ProfileProxiesContainerONo,
      lockable: false,
      role: "Profile Proxies",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
    try await super.init(
      objectNumber: OcaCoordinatorONo,
      role: "Profile Manager",
      deviceDelegate: deviceDelegate
    )
    let device = try device
    let schemaCount = OcaONo(deviceSchema.profileSchemas.count)
    for (index, schema) in deviceSchema.profileSchemas.enumerated() {
      let profilesONo = ProfileProxiesContainerONo + 1 + OcaONo(index)
      let proxiesONo = ProfileProxiesContainerONo + 1 + schemaCount + OcaONo(index)
      let profilesBlock = try await SwiftOCADevice.OcaBlock<OcaProfile>(
        objectNumber: profilesONo,
        lockable: false,
        role: schema.name,
        deviceDelegate: device,
        addToRootBlock: false
      )
      let proxiesBlock = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
        objectNumber: proxiesONo,
        lockable: false,
        role: schema.name,
        deviceDelegate: device,
        addToRootBlock: false
      )
      try await _profilesBlock.add(actionObject: profilesBlock)
      try await _profileProxiesBlock.add(actionObject: proxiesBlock)
      _schemaEntries[schema.name] = _SchemaEntry(
        profiles: profilesBlock,
        proxies: proxiesBlock
      )
    }
    let baseONo = ProfileProxiesContainerONo + 1 + schemaCount * 2
    _profileONoBase = baseONo
    _nextProfileONo = baseONo
    await device.setEventDelegate(self)
    logger.info("Coordinator initialized with schemas: \(deviceSchema.profileSchemas.map(\.name))")
  }

  @OcaDevice
  public convenience init(
    connectionOptions: Ocp1ConnectionOptions = .init(),
    serviceTypes: Set<OcaNetworkAdvertisingServiceType>? = nil,
    deviceSchema: OcaDeviceSchema,
    deviceDelegate: OcaDevice? = nil,
    logger: Logger = Logger(label: "com.padl.AES70Orchestrator")
  ) async throws {
    let broker = await OcaConnectionBroker(
      connectionOptions: connectionOptions,
      serviceTypes: serviceTypes,
      deviceModels: deviceSchema.models
    )
    try await self.init(
      connectionBroker: broker,
      deviceSchema: deviceSchema,
      deviceDelegate: deviceDelegate,
      logger: logger
    )
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
    _persistenceMonitorTask?.cancel()
    _eventsContinuation.finish()
  }

  public func handleBrokerEvent(
    _ event: SwiftOCA.OcaConnectionBroker.Event
  ) async {
    switch event.eventType {
    case .deviceAdded, .deviceUpdated:
      logger
        .debug(
          "Device \(event.eventType == .deviceAdded ? "added" : "updated"): \(event.deviceIdentifier)"
        )
      if !currentDeviceIdentifiers.contains(event.deviceIdentifier.id) {
        currentDeviceIdentifiers.append(event.deviceIdentifier.id)
      }
      for entry in _schemaEntries.values {
        for profile in entry.profiles.actionObjects {
          guard profile.deviceIndices[event.deviceIdentifier] != nil else { continue }
          guard profile.remoteObjectCount(for: event.deviceIdentifier) == 0 else { continue }
          await _activateProfile(profile, to: event.deviceIdentifier)
        }
      }
    case .deviceRemoved:
      logger.debug("Device removed: \(event.deviceIdentifier)")
      for entry in _schemaEntries.values {
        for profile in entry.profiles.actionObjects {
          guard profile.deviceIndices[event.deviceIdentifier] != nil else { continue }
          await _deactivateProfile(profile, from: event.deviceIdentifier)
        }
      }
      currentDeviceIdentifiers.removeAll { $0 == event.deviceIdentifier.id }
    default:
      break
    }
  }

  public func onEvent(_ event: SwiftOCA.OcaEvent, parameters: Data) async {
    logger.trace("onEvent: emitterONo=\(event.emitterONo), eventID=\(event.eventID)")
    for entry in _schemaEntries.values {
      for profile in entry.profiles.actionObjects {
        await profile.handleLocalEvent(event, parameters: parameters)
      }
    }
    _eventsContinuation.yield(event)
  }

  public func onControllerExpiry(_ controller: any SwiftOCADevice.OcaController) async {}

  func profileSchema(named name: String) throws -> OcaProfileSchema {
    guard let schema = deviceSchema.profileSchemas.first(where: { $0.name == name }) else {
      throw OcaCoordinatorError.profileSchemaNotFound
    }
    return schema
  }

  @discardableResult
  public func addProfile(
    schema: String,
    name: String? = nil,
    uuid: UUID? = nil
  ) async throws -> OcaONo {
    let entry = try _schemaEntry(for: schema)
    let profileUUID = uuid ?? UUID()
    let profileIndex = entry.allocateProfileIndex()
    let profileONo = try allocateProfileONo()
    let proxyBlockONo = try allocateProfileONo()
    let profile = try await OcaProfile(
      role: profileUUID,
      objectNumber: profileONo,
      profileIndex: profileIndex,
      schema: schema,
      coordinator: self
    )
    let proxyBlock = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: proxyBlockONo,
      lockable: false,
      role: profileUUID.description,
      deviceDelegate: device,
      addToRootBlock: false
    )
    if let name { proxyBlock.label = name }
    try await profile.createLocalObjects(proxyBlock: proxyBlock)
    try await entry.proxies.add(actionObject: proxyBlock)
    try await entry.profiles.add(actionObject: profile)
    profile.proxyBlock = proxyBlock
    logger.debug("Added \(profile)")
    return profile.objectNumber
  }

  func _findProfile(oNo: OcaONo) throws -> OcaProfile {
    for entry in _schemaEntries.values {
      if let profile = entry.profiles.actionObjects
        .first(where: { $0.objectNumber == oNo })
      {
        return profile
      }
    }
    throw OcaCoordinatorError.profileNotFound
  }

  private func _allocateDeviceIndex(
    entry: _SchemaEntry,
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier,
    requestedIndex: OcaONo?,
    maxInstances: Int
  ) throws -> OcaONo {
    let used = entry.deviceIndices[deviceIdentifier, default: []]
    if let requestedIndex {
      guard requestedIndex < OcaONo(maxInstances) else {
        throw OcaCoordinatorError.deviceIndexInvalid
      }
      guard !used.contains(requestedIndex) else {
        throw OcaCoordinatorError.deviceIndexExhausted
      }
      entry.deviceIndices[deviceIdentifier, default: []].insert(requestedIndex)
      return requestedIndex
    }
    for index in OcaONo(0)..<OcaONo(maxInstances) {
      if !used.contains(index) {
        entry.deviceIndices[deviceIdentifier, default: []].insert(index)
        return index
      }
    }
    throw OcaCoordinatorError.deviceIndexExhausted
  }

  private func _releaseDeviceIndex(
    entry: _SchemaEntry,
    _ index: OcaONo,
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) {
    entry.deviceIndices[deviceIdentifier]?.remove(index)
    if entry.deviceIndices[deviceIdentifier]?.isEmpty == true {
      entry.deviceIndices.removeValue(forKey: deviceIdentifier)
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
    schema: OcaProfileObjectSchema,
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
    schema: OcaProfileObjectSchema
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
    schema: OcaProfileObjectSchema
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
  ) throws {
    let entry = try _schemaEntry(for: profile.schema)
    let schema = try profile.profileSchema
    let maxInstances = schema.blocks.map(\.remoteObjectCount).min() ?? 0
    let index = try _allocateDeviceIndex(
      entry: entry,
      for: deviceIdentifier, requestedIndex: deviceIndex, maxInstances: maxInstances
    )
    profile.deviceIndices[deviceIdentifier] = index
    profile.boundDevices.append(deviceIdentifier.id)
    logger.debug("Bound \(profile) to \(deviceIdentifier) at index \(index)")
  }

  public func unbindProfile(
    _ profile: OcaProfile,
    from deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws {
    let entry = try _schemaEntry(for: profile.schema)
    guard let index = profile.deviceIndices[deviceIdentifier] else {
      return
    }
    await _deactivateProfile(profile, from: deviceIdentifier)
    _releaseDeviceIndex(entry: entry, index, for: deviceIdentifier)
    profile.deviceIndices.removeValue(forKey: deviceIdentifier)
    profile.boundDevices.removeAll { $0 == deviceIdentifier.id }
    logger.debug("Unbound \(profile) from \(deviceIdentifier)")
  }

  private func _activateProfile(
    _ profile: OcaProfile,
    to deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async {
    guard let index = profile.deviceIndices[deviceIdentifier] else { return }
    logger.trace("Activating \(profile) for \(deviceIdentifier)")
    do {
      try await connectionBroker.connect(device: deviceIdentifier)
      let connection = try await _connection(for: deviceIdentifier)
      let schema = try profile.profileSchema
      var activatedBlocks = [OcaProfileObjectSchema]()
      do {
        for block in schema.blocks {
          try await _bindProfile(
            profile, to: deviceIdentifier, deviceIndex: index,
            connection: connection, schema: block
          )
          activatedBlocks.append(block)
        }
        logger.trace("Activated \(profile) for \(deviceIdentifier)")
      } catch {
        logger.warning("Failed to activate \(profile) for \(deviceIdentifier): \(error)")
        for block in activatedBlocks {
          await _unbindProfile(
            profile, from: deviceIdentifier, deviceIndex: index,
            connection: connection, schema: block
          )
        }
      }
    } catch {
      logger.warning("Failed to connect to \(deviceIdentifier) for activation: \(error)")
    }
  }

  private func _deactivateProfile(
    _ profile: OcaProfile,
    from deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async {
    guard let index = profile.deviceIndices[deviceIdentifier] else { return }
    logger.trace("Deactivating \(profile) from \(deviceIdentifier)")
    guard let connection = try? await _connection(for: deviceIdentifier) else { return }
    let schema = try? profile.profileSchema
    guard let schema else { return }
    for block in schema.blocks {
      await _unbindProfile(
        profile, from: deviceIdentifier, deviceIndex: index,
        connection: connection, schema: block
      )
    }
    logger.trace("Deactivated \(profile) from \(deviceIdentifier)")
  }

  private func _deleteProfile(_ profile: OcaProfile) async throws {
    let entry = try _schemaEntry(for: profile.schema)
    for (deviceIdentifier, _) in profile.deviceIndices {
      try? await unbindProfile(profile, from: deviceIdentifier)
    }
    try await profile.deleteLocalObjects()
    if let proxyBlock = profile.proxyBlock {
      try await entry.proxies.delete(actionObject: proxyBlock)
      try await (device).deregister(objectNumber: proxyBlock.objectNumber)
      profile.proxyBlock = nil
    }
    try await entry.profiles.delete(actionObject: profile)
    logger.debug("Deleted \(profile)")
  }

  public func deleteProfile(uuid: UUID) async throws {
    try await _deleteProfile(findProfile(uuid: uuid))
  }

  public func deleteProfile(named name: String, schema: String) async throws {
    try await _deleteProfile(findProfile(named: name, schema: schema))
  }

  public func findProfile(named name: String, schema: String) throws -> OcaProfile {
    let entry = try _schemaEntry(for: schema)
    guard let profile = entry.profiles.actionObjects.first(where: { $0.label == name }) else {
      throw OcaCoordinatorError.profileNotFound
    }
    return profile
  }

  public func findProfile(uuid: UUID) throws -> OcaProfile {
    let uuidString = uuid.description
    for entry in _schemaEntries.values {
      if let profile = entry.profiles.actionObjects
        .first(where: { $0.role == uuidString })
      {
        return profile
      }
    }
    throw OcaCoordinatorError.profileNotFound
  }

  // MARK: - OCP.1 command handling

  typealias AddProfileParameters =
    AES70OrchestratorClient.OcaCoordinator.AddProfileParameters
  typealias BindProfileParameters =
    AES70OrchestratorClient.OcaCoordinator.BindProfileParameters
  typealias UnbindProfileParameters =
    AES70OrchestratorClient.OcaCoordinator.UnbindProfileParameters
  typealias FindOrDeleteProfileByNameParameters =
    AES70OrchestratorClient.OcaCoordinator.FindOrDeleteProfileByNameParameters

  override public func handleCommand(
    _ command: Ocp1Command,
    from controller: any OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("3.2"): // AddProfile(schema, name?) → ONo
      let params: AddProfileParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      let oNo = try await addProfile(schema: params.schema, name: params.name)
      return try encodeResponse(oNo)
    case OcaMethodID("3.3"): // BindProfile(oNo, deviceId, index)
      let params: BindProfileParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      guard let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(params.deviceIdentifier)
      else {
        throw Ocp1Error.status(.parameterError)
      }
      try bindProfile(
        _findProfile(oNo: params.profileONo),
        to: deviceIdentifier,
        deviceIndex: params.deviceIndex ==
          AES70OrchestratorClient.OcaCoordinator.AutoDeviceIndex
          ? nil : OcaONo(params.deviceIndex)
      )
      return Ocp1Response()
    case OcaMethodID("3.4"): // UnbindProfile(oNo, deviceId)
      let params: UnbindProfileParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      guard let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(params.deviceIdentifier)
      else {
        throw Ocp1Error.status(.parameterError)
      }
      try await unbindProfile(_findProfile(oNo: params.profileONo), from: deviceIdentifier)
      return Ocp1Response()
    case OcaMethodID("3.5"): // DeleteProfileByName(name, schema)
      let params: FindOrDeleteProfileByNameParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await deleteProfile(named: params.name, schema: params.schema)
      return Ocp1Response()
    case OcaMethodID("3.6"): // DeleteProfileByUUID(uuid)
      let uuid: OcaString = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      guard let uuid = UUID(uuidString: uuid) else {
        throw Ocp1Error.status(.parameterError)
      }
      try await deleteProfile(uuid: uuid)
      return Ocp1Response()
    case OcaMethodID("3.7"): // FindProfileByName(name, schema) → ONo
      let params: FindOrDeleteProfileByNameParameters = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      let profile = try findProfile(named: params.name, schema: params.schema)
      return try encodeResponse(profile.objectNumber)
    case OcaMethodID("3.8"): // FindProfileByUUID(uuid) → ONo
      let uuid: OcaString = try decodeCommand(command)
      try await ensureReadable(by: controller, command: command)
      guard let uuid = UUID(uuidString: uuid) else {
        throw Ocp1Error.status(.parameterError)
      }
      let profile = try findProfile(uuid: uuid)
      return try encodeResponse(profile.objectNumber)
    case OcaMethodID("3.9"): // ExportState() → OcaLongBlob
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let blob = try await exportState()
      return try encodeResponse(blob)
    case OcaMethodID("3.10"): // ImportState(OcaLongBlob)
      let blob: OcaLongBlob = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await importState(from: blob)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
