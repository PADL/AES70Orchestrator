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
@testable import AES70Orchestrator
import Testing
@testable @_spi(SwiftOCAPrivate) import SwiftOCA
@testable @_spi(SwiftOCAPrivate) import SwiftOCADevice

// MARK: - OcaONoMask tests

@Suite
struct OcaONoMaskTests {
  @Test
  func initFromString() throws {
    let mask = try OcaONoMask("0x80000000/0x00010000")
    #expect(mask.oNo == 0x8000_0000)
    #expect(mask.mask == 0x0001_0000)
  }

  @Test
  func initFromStringZeroMask() throws {
    let mask = try OcaONoMask("0x00002710/0x00000000")
    #expect(mask.oNo == 0x0000_2710)
    #expect(mask.mask == 0)
  }

  @Test
  func initFromStringInvalidThrows() {
    #expect(throws: OcaCoordinatorError.self) {
      try OcaONoMask("invalid")
    }
  }

  @Test
  func instanceCountWithContiguousMask() throws {
    let mask = OcaONoMask(oNo: 0x100, mask: 0x0F)
    #expect(try mask.instanceCount == 16)
  }

  @Test
  func instanceCountWithShiftedMask() throws {
    let mask = OcaONoMask(oNo: 0x100, mask: 0x30)
    #expect(try mask.instanceCount == 4)
  }

  @Test
  func instanceCountZeroMask() throws {
    let mask = OcaONoMask(oNo: 0x100, mask: 0)
    #expect(try mask.instanceCount == 1)
  }

  @Test
  func objectNumberForIndex() throws {
    let mask = OcaONoMask(oNo: 0x100, mask: 0x0F)
    #expect(try mask.objectNumber(for: 0) == 0x100)
    #expect(try mask.objectNumber(for: 1) == 0x101)
    #expect(try mask.objectNumber(for: 15) == 0x10F)
  }

  @Test
  func objectNumberForShiftedIndex() throws {
    let mask = OcaONoMask(oNo: 0x100, mask: 0xF0)
    #expect(try mask.objectNumber(for: 0) == 0x100)
    #expect(try mask.objectNumber(for: 1) == 0x110)
    #expect(try mask.objectNumber(for: 15) == 0x1F0)
  }

  @Test
  func objectNumberOverflowThrows() {
    let mask = OcaONoMask(oNo: 0x100, mask: 0x03)
    #expect(throws: OcaCoordinatorError.self) {
      try mask.objectNumber(for: 4)
    }
  }
}

// MARK: - OcaProfileObjectSchema tests

@Suite
struct OcaProfileObjectSchemaTests {
  @Test
  func leafSchema() throws {
    let schema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x0F)
    )
    #expect(schema.isLeaf)
    #expect(!schema.isContainer)
    #expect(try schema.remoteObjectCount == 16)
    #expect(schema.actionObjectSchema.isEmpty)
  }

  @Test
  func containerSchema() {
    let child = OcaProfileObjectSchema(
      role: "Mute",
      type: SwiftOCADevice.OcaMute.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x300, mask: 0x0F)
    )
    let block = OcaProfileObjectSchema(
      role: "Channel",
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x100, mask: 0x0F),
      actionObjectSchema: [child]
    )
    #expect(block.isContainer)
    #expect(!block.isLeaf)
    #expect(block.actionObjectSchema.count == 1)
  }

  @Test
  func applyRecursiveVisitsAllNodes() async throws {
    let child1 = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x300, mask: 0x0F)
    )
    let child2 = OcaProfileObjectSchema(
      role: "Mute",
      type: SwiftOCADevice.OcaMute.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x400, mask: 0x0F)
    )
    let block = OcaProfileObjectSchema(
      role: "Channel",
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x100, mask: 0x0F),
      actionObjectSchema: [child1, child2]
    )

    var visitedRoles = [String]()
    var visitedParentPaths = [[String]?]()

    try await block.applyRecursive { schema, _, parentRolePath in
      visitedRoles.append(schema.role)
      visitedParentPaths.append(parentRolePath)
    }

    #expect(visitedRoles == ["Channel", "Gain", "Mute"])
    #expect(visitedParentPaths[0] == nil)
    #expect(visitedParentPaths[1] == ["Channel"])
    #expect(visitedParentPaths[2] == ["Channel"])
  }
}

// MARK: - OcaProfileSchema tests

@Suite
struct OcaProfileSchemaTests {
  @Test
  func minimumRemoteObjectCount() throws {
    let block1 = OcaProfileObjectSchema(
      role: "Block1",
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x100, mask: 0x0F)
    )
    let block2 = OcaProfileObjectSchema(
      role: "Block2",
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x03)
    )
    let schema = OcaProfileSchema(name: "test", blocks: [block1, block2])
    let minInstances = try schema.blocks.map { try $0.remoteObjectCount }.min() ?? 0
    #expect(minInstances == 4)
  }
}

// MARK: - OcaDeviceSchema tests

@Suite
struct OcaDeviceSchemaTests {
  @Test
  func memberwise() {
    let profileSchema = OcaProfileSchema(name: "gain", blocks: [])
    let deviceSchema = OcaDeviceSchema(
      name: "TestDevice",
      profileSchemas: [profileSchema]
    )
    #expect(deviceSchema.name == "TestDevice")
    #expect(deviceSchema.models == nil)
    #expect(deviceSchema.profileSchemas.count == 1)
    #expect(deviceSchema.profileSchemas[0].name == "gain")
  }
}

// MARK: - Coordinator profile lifecycle tests

@Suite
struct CoordinatorTests {
  static func _makeTestSchema() -> OcaDeviceSchema {
    let gainSchema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: OcaONoMask(oNo: 0x2000, mask: 0x0F),
      remoteObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x03)
    )
    let muteSchema = OcaProfileObjectSchema(
      role: "Mute",
      type: SwiftOCADevice.OcaMute.self,
      localObjectNumber: OcaONoMask(oNo: 0x3000, mask: 0x0F),
      remoteObjectNumber: OcaONoMask(oNo: 0x300, mask: 0x03)
    )
    let channelBlock = OcaProfileObjectSchema(
      role: "Channel",
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      localObjectNumber: OcaONoMask(oNo: 0x1000, mask: 0x0F),
      remoteObjectNumber: OcaONoMask(oNo: 0x100, mask: 0x03),
      actionObjectSchema: [gainSchema, muteSchema]
    )
    let profileSchema = OcaProfileSchema(name: "ChannelStrip", blocks: [channelBlock])

    let simpleSchema = OcaProfileObjectSchema(
      role: "Switch",
      type: SwiftOCADevice.OcaSwitch.self,
      localObjectNumber: OcaONoMask(oNo: 0x4000, mask: 0x0F),
      remoteObjectNumber: OcaONoMask(oNo: 0x400, mask: 0x03)
    )
    let simpleProfileSchema = OcaProfileSchema(name: "SimpleSwitch", blocks: [simpleSchema])

    return OcaDeviceSchema(
      name: "TestDevice",
      profileSchemas: [profileSchema, simpleProfileSchema]
    )
  }

  @OcaDevice
  static func _makeCoordinator() async throws -> (OcaCoordinator, OcaDevice) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let broker = await OcaConnectionBroker(
      connectionOptions: .init(),
      serviceTypes: nil,
      deviceModels: nil
    )
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: _makeTestSchema(),
      deviceDelegate: device
    )
    return (coordinator, device)
  }

  @Test
  func addProfile() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo = try await coordinator.addProfile(schema: "ChannelStrip", name: "My Channel")
    #expect(oNo != 0)
  }

  @Test
  func addProfileInvalidSchemaThrows() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.addProfile(schema: "NonExistent")
    }
  }

  @Test
  func addMultipleProfilesDifferentSchemas() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo1 = try await coordinator.addProfile(schema: "ChannelStrip", name: "Ch1")
    let oNo2 = try await coordinator.addProfile(schema: "SimpleSwitch", name: "Sw1")
    let oNo3 = try await coordinator.addProfile(schema: "ChannelStrip", name: "Ch2")
    #expect(oNo1 != oNo2)
    #expect(oNo1 != oNo3)
    #expect(oNo2 != oNo3)
  }

  @Test
  func findProfileByUUID() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo = try await coordinator.addProfile(schema: "ChannelStrip")
    let profile = try await coordinator._findProfile(oNo: oNo)
    let uuid = await UUID(uuidString: profile.role)!
    let found = try await coordinator.findProfile(uuid: uuid)
    #expect(await found.objectNumber == oNo)
  }

  @Test
  func findProfileByName() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    _ = try await coordinator.addProfile(schema: "ChannelStrip", name: "TestProfile")
    let found = try await coordinator.findProfile(named: "TestProfile", schema: "ChannelStrip")
    #expect(await found.label == "TestProfile")
  }

  @Test
  func findProfileByNameWrongSchemaThrows() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    _ = try await coordinator.addProfile(schema: "ChannelStrip", name: "TestProfile")
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.findProfile(named: "TestProfile", schema: "SimpleSwitch")
    }
  }

  @Test
  func duplicateNamesAcrossSchemas() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo1 = try await coordinator.addProfile(schema: "ChannelStrip", name: "Shared")
    let oNo2 = try await coordinator.addProfile(schema: "SimpleSwitch", name: "Shared")
    #expect(oNo1 != oNo2)
    let p1 = try await coordinator.findProfile(named: "Shared", schema: "ChannelStrip")
    let p2 = try await coordinator.findProfile(named: "Shared", schema: "SimpleSwitch")
    #expect(await p1.objectNumber == oNo1)
    #expect(await p2.objectNumber == oNo2)
  }

  @Test
  func deleteProfileByUUID() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo = try await coordinator.addProfile(schema: "ChannelStrip", name: "ToDelete")
    let profile = try await coordinator._findProfile(oNo: oNo)
    let uuid = await UUID(uuidString: profile.role)!
    try await coordinator.deleteProfile(uuid: uuid)
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.findProfile(uuid: uuid)
    }
  }

  @Test
  func deleteProfileByName() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    _ = try await coordinator.addProfile(schema: "ChannelStrip", name: "ToDelete")
    try await coordinator.deleteProfile(named: "ToDelete", schema: "ChannelStrip")
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.findProfile(named: "ToDelete", schema: "ChannelStrip")
    }
  }

  @Test
  func profileONoAllocationIsSequential() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo1 = try await coordinator.addProfile(schema: "ChannelStrip")
    let oNo2 = try await coordinator.addProfile(schema: "ChannelStrip")
    let oNo3 = try await coordinator.addProfile(schema: "SimpleSwitch")
    // each addProfile allocates 2 ONos: one for the profile, one for its proxy block
    #expect(oNo2 == oNo1 + 2)
    #expect(oNo3 == oNo2 + 2)
  }

  @Test
  func profileIndexIsPerSchema() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo1 = try await coordinator.addProfile(schema: "ChannelStrip")
    let oNo2 = try await coordinator.addProfile(schema: "SimpleSwitch")
    let p1 = try await coordinator._findProfile(oNo: oNo1)
    let p2 = try await coordinator._findProfile(oNo: oNo2)
    #expect(await p1.profileIndex == 0)
    #expect(await p2.profileIndex == 0)
  }

  @Test
  func profileLocalObjectsCreated() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo = try await coordinator.addProfile(schema: "ChannelStrip")
    let profile = try await coordinator._findProfile(oNo: oNo)
    // channel block schema creates 3 local objects: block, gain, mute
    let blockONo = try OcaONoMask(oNo: 0x1000, mask: 0x0F).objectNumber(for: 0)
    let gainONo = try OcaONoMask(oNo: 0x2000, mask: 0x0F).objectNumber(for: 0)
    let muteONo = try OcaONoMask(oNo: 0x3000, mask: 0x0F).objectNumber(for: 0)
    #expect(await profile.objectBinding(for: blockONo) != nil)
    #expect(await profile.objectBinding(for: gainONo) != nil)
    #expect(await profile.objectBinding(for: muteONo) != nil)
  }

  @Test
  func localObjectsWithoutSchemaONoGetReservedONos() async throws {
    // schema where the container has no localObjectNumber
    let gainSchema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x0F),
      remoteObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x03)
    )
    let containerSchema = OcaProfileObjectSchema(
      role: "Container",
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x100, mask: 0x03),
      actionObjectSchema: [gainSchema]
    )
    let profileSchema = OcaProfileSchema(name: "NoLocalONo", blocks: [containerSchema])
    let deviceSchema = OcaDeviceSchema(
      name: "TestDevice",
      profileSchemas: [profileSchema]
    )
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let broker = await OcaConnectionBroker(
      connectionOptions: .init(),
      serviceTypes: nil,
      deviceModels: nil
    )
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: deviceSchema,
      deviceDelegate: device
    )

    let oNo = try await coordinator.addProfile(schema: "NoLocalONo")
    let profile = try await coordinator._findProfile(oNo: oNo)

    // all locally created object numbers (including the container without a schema-defined
    // localObjectNumber) must be below ReservedONoLimit
    var allLocalONos = [OcaONo]()
    for oNo in await profile.localObjectNumbers {
      allLocalONos.append(oNo)
    }
    #expect(!allLocalONos.isEmpty)
    for localONo in allLocalONos {
      #expect(
        localONo < ReservedONoLimit,
        "Local ONo \(localONo) must be below \(ReservedONoLimit)"
      )
    }
  }

  static let _testDeviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
    serviceType: .tcp,
    modelGUID: OcaModelGUID(mfrCode: .init((0, 0, 0)), modelCode: (1, 2, 3, 4)),
    serialNumber: "TestDevice-001",
    name: "Test"
  )

  @Test
  func addDuplicateProfileNameThrows() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    _ = try await coordinator.addProfile(schema: "ChannelStrip", name: "Dup")
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.addProfile(schema: "ChannelStrip", name: "Dup")
    }
  }

  @Test
  func addDuplicateProfileUUIDThrows() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let uuid = UUID()
    _ = try await coordinator.addProfile(schema: "ChannelStrip", uuid: uuid)
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.addProfile(schema: "ChannelStrip", uuid: uuid)
    }
  }

  @Test
  func bindAlreadyBoundThrows() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo = try await coordinator.addProfile(schema: "ChannelStrip")
    let profile = try await coordinator._findProfile(oNo: oNo)
    try await coordinator.bindProfile(profile, to: Self._testDeviceIdentifier)
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.bindProfile(profile, to: Self._testDeviceIdentifier)
    }
  }

  @Test
  func unbindNotBoundThrows() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo = try await coordinator.addProfile(schema: "ChannelStrip")
    let profile = try await coordinator._findProfile(oNo: oNo)
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.unbindProfile(profile, from: Self._testDeviceIdentifier)
    }
  }

  static let _zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

  @Test
  func autobindRejectsManualBind() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo = try await coordinator.addProfile(
      schema: "ChannelStrip",
      uuid: Self._zeroUUID
    )
    let profile = try await coordinator._findProfile(oNo: oNo)

    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.bindProfile(profile, to: Self._testDeviceIdentifier)
    }
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.unbindProfile(profile, from: Self._testDeviceIdentifier)
    }
  }

  @Test
  func autobindEnforcesSingleProfile() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    _ = try await coordinator.addProfile(
      schema: "ChannelStrip",
      uuid: Self._zeroUUID
    )
    await #expect(throws: OcaCoordinatorError.self) {
      try await coordinator.addProfile(
        schema: "ChannelStrip",
        uuid: Self._zeroUUID
      )
    }
  }
}

// MARK: - Persistence tests

@Suite
struct PersistenceTests {
  static let _testDeviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
    serviceType: .tcp,
    modelGUID: OcaModelGUID(mfrCode: .init((0, 0, 0)), modelCode: (1, 2, 3, 4)),
    serialNumber: "TestDevice-001",
    name: "Test"
  )

  @Test
  func saveAndLoadRoundTrip() async throws {
    let (coordinator, _device) = try await CoordinatorTests._makeCoordinator()

    // add profiles with specific UUIDs
    let uuid1 = UUID()
    let uuid2 = UUID()
    _ = try await coordinator.addProfile(schema: "ChannelStrip", name: "Ch1", uuid: uuid1)
    _ = try await coordinator.addProfile(schema: "SimpleSwitch", name: "Sw1", uuid: uuid2)

    // bind a device to the first profile
    let profile1 = try await coordinator.findProfile(uuid: uuid1)
    try await coordinator.bindProfile(profile1, to: Self._testDeviceIdentifier)

    // save
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".zip")
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try await coordinator.export(to: tempURL)
    #expect(FileManager.default.fileExists(atPath: tempURL.path))

    // create a fresh coordinator and load
    let (coordinator2, _device2) = try await CoordinatorTests._makeCoordinator()
    try await coordinator2.import(from: tempURL)

    // verify profiles were restored
    let restored1 = try await coordinator2.findProfile(uuid: uuid1)
    #expect(await restored1.label == "Ch1")
    #expect(await restored1.schema == "ChannelStrip")

    let restored2 = try await coordinator2.findProfile(uuid: uuid2)
    #expect(await restored2.label == "Sw1")
    #expect(await restored2.schema == "SimpleSwitch")

    // verify binding was restored
    #expect(await restored1.boundDevices.contains(Self._testDeviceIdentifier.id))
    #expect(await restored1.deviceIndices[Self._testDeviceIdentifier] != nil)
  }

  @Test
  func saveEmptyCoordinator() async throws {
    let (coordinator, _device) = try await CoordinatorTests._makeCoordinator()

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".zip")
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try await coordinator.export(to: tempURL)
    #expect(FileManager.default.fileExists(atPath: tempURL.path))

    // load into fresh coordinator — should succeed with no profiles
    let (coordinator2, _device2) = try await CoordinatorTests._makeCoordinator()
    try await coordinator2.import(from: tempURL)
  }

  @Test
  func saveAndLoadMultipleBindings() async throws {
    let (coordinator, _device) = try await CoordinatorTests._makeCoordinator()

    let uuid = UUID()
    _ = try await coordinator.addProfile(schema: "ChannelStrip", name: "Multi", uuid: uuid)
    let profile = try await coordinator.findProfile(uuid: uuid)

    let device1 = Self._testDeviceIdentifier
    let device2 = OcaConnectionBroker.DeviceIdentifier(
      serviceType: .tcp,
      modelGUID: OcaModelGUID(mfrCode: .init((0, 0, 0)), modelCode: (5, 6, 7, 8)),
      serialNumber: "TestDevice-002",
      name: "Test2"
    )
    try await coordinator.bindProfile(profile, to: device1)
    try await coordinator.bindProfile(profile, to: device2)

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".zip")
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try await coordinator.export(to: tempURL)

    let (coordinator2, _device2) = try await CoordinatorTests._makeCoordinator()
    try await coordinator2.import(from: tempURL)

    let restored = try await coordinator2.findProfile(uuid: uuid)
    #expect(await restored.boundDevices.count == 2)
    #expect(await restored.boundDevices.contains(device1.id))
    #expect(await restored.boundDevices.contains(device2.id))
  }

  @Test
  func saveAndLoadPreservesProxyBlock() async throws {
    let (coordinator, _device) = try await CoordinatorTests._makeCoordinator()

    let uuid = UUID()
    _ = try await coordinator.addProfile(schema: "ChannelStrip", name: "WithProxy", uuid: uuid)
    let profile = try await coordinator.findProfile(uuid: uuid)
    #expect(await profile.proxyBlock != nil)

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".zip")
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try await coordinator.export(to: tempURL)

    let (coordinator2, _device2) = try await CoordinatorTests._makeCoordinator()
    try await coordinator2.import(from: tempURL)

    let restored = try await coordinator2.findProfile(uuid: uuid)
    #expect(await restored.proxyBlock != nil)
    // verify local objects exist in the restored profile
    let blockONo = try OcaONoMask(oNo: 0x1000, mask: 0x0F).objectNumber(for: 0)
    let gainONo = try OcaONoMask(oNo: 0x2000, mask: 0x0F).objectNumber(for: 0)
    let muteONo = try OcaONoMask(oNo: 0x3000, mask: 0x0F).objectNumber(for: 0)
    #expect(await restored.objectBinding(for: blockONo) != nil)
    #expect(await restored.objectBinding(for: gainONo) != nil)
    #expect(await restored.objectBinding(for: muteONo) != nil)
  }

  @Test
  func blobSaveAndLoadRoundTrip() async throws {
    let (coordinator, _device) = try await CoordinatorTests._makeCoordinator()

    let uuid = UUID()
    _ = try await coordinator.addProfile(schema: "ChannelStrip", name: "BlobTest", uuid: uuid)
    let profile = try await coordinator.findProfile(uuid: uuid)
    try await coordinator.bindProfile(profile, to: Self._testDeviceIdentifier)

    let blob = try await coordinator.export()
    #expect(blob.wrappedValue.count > 0)

    let (coordinator2, _device2) = try await CoordinatorTests._makeCoordinator()
    try await coordinator2.import(from: blob)

    let restored = try await coordinator2.findProfile(uuid: uuid)
    #expect(await restored.label == "BlobTest")
    #expect(await restored.schema == "ChannelStrip")
    #expect(await restored.boundDevices.contains(Self._testDeviceIdentifier.id))
    #expect(await restored.proxyBlock != nil)
  }
}

// MARK: - YAML schema parsing tests

@Suite
struct YAMLSchemaTests {
  static let _minimalYAML = """
  device:
    name: TestDevice
    profiles:
      - SimpleGain:
        - Gain:
            classID: 1.1.1.5
            match: 0x00000200/0x0000000F
            objectNumber: 0x00002000/0x000000F0
  """

  static let _nestedYAML = """
  device:
    name: NestedDevice
    profiles:
      - Channel:
        - ChannelBlock:
            classID: 1.1.3
            match: 0x00000100/0x0000000F
            objectNumber: 0x00001000/0x000000F0
            actionObjects:
              - Mute:
                  classID: 1.1.1.2
                  match: 0x00000300/0x0000000F
                  objectNumber: 0x00003000/0x000000F0
              - Gain:
                  classID: 1.1.1.5
                  match: 0x00000200/0x0000000F
                  objectNumber: 0x00002000/0x000000F0
  """

  static let _inferredBlockYAML = """
  device:
    name: InferredDevice
    profiles:
      - TestProfile:
        - Container:
            match: 0x00000100/0x0000000F
            actionObjects:
              - Gain:
                  classID: 1.1.1.5
                  match: 0x00000200/0x0000000F
  """

  static let _modelsYAML = """
  device:
    name: ModelDevice
    models: [ 0x0AE91B00010100 ]
    profiles:
      - Simple:
        - Gain:
            classID: 1.1.1.5
            match: 0x00000200/0x0000000F
  """

  @Test
  func parseMinimalSchema() async throws {
    let schema = try await OcaDeviceSchema(yaml: Self._minimalYAML)
    #expect(schema.name == "TestDevice")
    #expect(schema.models == nil)
    #expect(schema.profileSchemas.count == 1)
    #expect(schema.profileSchemas[0].name == "SimpleGain")
    #expect(schema.profileSchemas[0].blocks.count == 1)

    let gain = schema.profileSchemas[0].blocks[0]
    #expect(gain.role == "Gain")
    #expect(gain.type == SwiftOCADevice.OcaGain.self)
    #expect(gain.remoteObjectNumber == OcaONoMask(oNo: 0x200, mask: 0x0F))
    #expect(gain.localObjectNumber == OcaONoMask(oNo: 0x2000, mask: 0xF0))
    #expect(gain.isLeaf)
  }

  @Test
  func parseNestedSchema() async throws {
    let schema = try await OcaDeviceSchema(yaml: Self._nestedYAML)
    #expect(schema.name == "NestedDevice")
    #expect(schema.profileSchemas.count == 1)

    let block = schema.profileSchemas[0].blocks[0]
    #expect(block.role == "ChannelBlock")
    #expect(block.isContainer)
    #expect(block.actionObjectSchema.count == 2)
    #expect(block.actionObjectSchema[0].role == "Mute")
    #expect(block.actionObjectSchema[0].type == SwiftOCADevice.OcaMute.self)
    #expect(block.actionObjectSchema[1].role == "Gain")
    #expect(block.actionObjectSchema[1].type == SwiftOCADevice.OcaGain.self)
  }

  @Test
  func parseInferredBlockType() async throws {
    let schema = try await OcaDeviceSchema(yaml: Self._inferredBlockYAML)
    let block = schema.profileSchemas[0].blocks[0]
    #expect(block.isContainer)
    #expect(block.type == SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self)
    #expect(block.localObjectNumber == nil)
    #expect(block.actionObjectSchema.count == 1)
  }

  @Test
  func parseModels() async throws {
    let schema = try await OcaDeviceSchema(yaml: Self._modelsYAML)
    #expect(schema.models != nil)
    #expect(schema.models?.count == 1)
    let model = schema.models![0]
    #expect(model.mfrCode == OcaOrganizationID((0x0A, 0xE9, 0x1B)))
    #expect(model.modelCode == (0x00, 0x01, 0x01, 0x00))
  }

  @Test
  func parseMissingDeviceKeyThrows() async {
    await #expect(throws: OcaCoordinatorError.self) {
      try await OcaDeviceSchema(yaml: "foo: bar")
    }
  }

  @Test
  func parseMissingProfilesThrows() async {
    await #expect(throws: OcaCoordinatorError.self) {
      try await OcaDeviceSchema(yaml: "device:\n  name: X")
    }
  }

  @Test
  func parseMissingMatchThrows() async {
    let yaml = """
    device:
      name: Bad
      profiles:
        - P:
          - Obj:
              classID: 1.1.1.5
    """
    await #expect(throws: OcaCoordinatorError.self) {
      try await OcaDeviceSchema(yaml: yaml)
    }
  }

  static let _blockMappingYAML = """
  device:
    name: BlockMappingDevice
    profiles:
      - BlockProfile:
          blocks:
            - Gain:
                classID: 1.1.1.5
                match: 0x00000200/0x0000000F
                objectNumber: 0x00002000/0x000000F0
  """

  @Test
  func parseBlockMapping() async throws {
    let schema = try await OcaDeviceSchema(yaml: Self._blockMappingYAML)
    #expect(schema.profileSchemas.count == 1)
    #expect(schema.profileSchemas[0].name == "BlockProfile")
    #expect(schema.profileSchemas[0].blocks.count == 1)
  }

  @Test
  func parseLockRemote() async throws {
    let yaml = """
    device:
      name: LockDevice
      profiles:
        - LockProfile:
            blocks:
              - Gain:
                  classID: 1.1.1.5
                  match: 0x00000200/0x0000000F
                  lockRemote: true
    """
    let schema = try await OcaDeviceSchema(yaml: yaml)
    #expect(schema.profileSchemas[0].blocks[0].lockRemote == true)
  }

  @Test
  func parseLockRemoteDefaultsFalse() async throws {
    let schema = try await OcaDeviceSchema(yaml: Self._minimalYAML)
    #expect(schema.profileSchemas[0].blocks[0].lockRemote == false)
  }
}

// MARK: - End-to-end tests

import SocketAddress
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private extension SocketAddress {
  var socketAddressData: Data {
    withSockAddr { sa, size in
      Data(bytes: sa, count: Int(size))
    }
  }
}

@OcaDevice
private func _setDeviceManagerProperties(
  _ deviceManager: SwiftOCADevice.OcaDeviceManager,
  name: String,
  serialNumber: String,
  modelGUID: OcaModelGUID
) {
  deviceManager.deviceName = name
  deviceManager.serialNumber = serialNumber
  deviceManager.modelGUID = modelGUID
}

@OcaDevice
private func _setControlNetworkRunning(_ controlNetwork: SwiftOCADevice.OcaControlNetwork) {
  controlNetwork.state = .running
}

@Suite(.serialized)
struct EndToEndTests {
  static let remoteGainONo: OcaONo = 0x200
  static let localGainONo: OcaONo = 0x2000

  private static func _randomModelGUID() -> OcaModelGUID {
    OcaModelGUID(
      mfrCode: .init((0xE2, 0xE2, 0xE2)),
      modelCode: (
        UInt8.random(in: 1...255),
        UInt8.random(in: 0...255),
        UInt8.random(in: 0...255),
        UInt8.random(in: 0...255)
      )
    )
  }

  static func _makeRemoteDevice(
    port: UInt16,
    serialNumber: String,
    modelGUID: OcaModelGUID
  ) async throws -> (
    device: OcaDevice,
    gain: SwiftOCADevice.OcaGain,
    endpointTask: Task<(), Error>
  ) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let deviceManager = await device.deviceManager!
    await _setDeviceManagerProperties(
      deviceManager,
      name: "E2E Test Remote Device",
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )

    let gain = try await SwiftOCADevice.OcaGain(
      objectNumber: remoteGainONo,
      role: "Gain",
      deviceDelegate: device
    )

    let controlNetwork = try await SwiftOCADevice.OcaControlNetwork(deviceDelegate: device)
    await _setControlNetworkRunning(controlNetwork)

    var listenAddress = sockaddr_in()
    listenAddress.sin_family = sa_family_t(AF_INET)
    listenAddress.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
    listenAddress.sin_port = port.bigEndian
    #if canImport(Darwin) || os(FreeBSD) || os(OpenBSD)
    listenAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif

    let endpoint = try await Ocp1DeviceEndpoint(
      address: listenAddress.socketAddressData,
      device: device
    )

    let endpointTask = Task {
      try await endpoint.run()
    }

    // allow time for the endpoint to start listening
    try await Task.sleep(for: .milliseconds(500))

    return (device, gain, endpointTask)
  }

  static func _makeSchema(modelGUID: OcaModelGUID) -> OcaDeviceSchema {
    let gainSchema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: OcaONoMask(oNo: localGainONo, mask: 0),
      remoteObjectNumber: OcaONoMask(oNo: remoteGainONo, mask: 0)
    )
    let profileSchema = OcaProfileSchema(
      name: "E2EGain",
      blocks: [gainSchema]
    )
    return OcaDeviceSchema(
      name: "E2ETestDevice",
      models: [modelGUID],
      profileSchemas: [profileSchema]
    )
  }

  private static func _makeCoordinator(
    port: UInt16,
    modelGUID: OcaModelGUID,
    serialNumber: String
  ) async throws -> (
    coordinator: OcaCoordinator,
    localDevice: OcaDevice,
    deviceIdentifier: OcaConnectionBroker.DeviceIdentifier
  ) {
    let localDevice = OcaDevice()
    try await localDevice.initializeDefaultObjects()

    let connectionOptions = Ocp1ConnectionOptions(
      flags: [.automaticReconnect, .refreshDeviceTreeOnConnection]
    )
    let broker = await OcaConnectionBroker(
      connectionOptions: connectionOptions,
      serviceTypes: [],
      deviceModels: nil
    )
    let schema = _makeSchema(modelGUID: modelGUID)
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: schema,
      deviceDelegate: localDevice
    )

    let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    let profileONo = try await coordinator.addProfile(schema: "E2EGain", uuid: zeroUUID)
    let profile = try await coordinator._findProfile(oNo: profileONo)

    let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
      serviceType: .tcp,
      modelGUID: modelGUID,
      serialNumber: serialNumber,
      name: "E2E Test Remote Device"
    )

    // connect directly to the remote device, bypassing mDNS discovery
    var remoteAddress = sockaddr_in()
    remoteAddress.sin_family = sa_family_t(AF_INET)
    remoteAddress.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
    remoteAddress.sin_port = port.bigEndian
    #if canImport(Darwin) || os(FreeBSD) || os(OpenBSD)
    remoteAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif
    let connection = try await Ocp1TCPConnection(
      deviceAddress: remoteAddress.socketAddressData,
      options: connectionOptions
    )
    try await connection.connect()

    // register the connection and start listening for broker events
    await broker.register(device: deviceIdentifier, connection: connection)
    let brokerEventTask = Task { [weak coordinator] in
      guard let coordinator else { return }
      for await event in await broker.events {
        await coordinator.handleConnectionBrokerEvent(event)
      }
    }
    _ = brokerEventTask

    // wait for the auto-bind profile activation to complete
    for _ in 0..<20 {
      let count = await profile.remoteObjectCount(for: deviceIdentifier)
      if count > 0 { break }
      try await Task.sleep(for: .milliseconds(250))
    }

    return (coordinator, localDevice, deviceIdentifier)
  }

  @Test(.timeLimit(.minutes(1)))
  func localChangePropagatesToRemote() async throws {
    let port: UInt16 = 12345
    let serialNumber = "E2ETest-\(UUID().uuidString)"
    let modelGUID = Self._randomModelGUID()
    let (remoteDevice, remoteGain, endpointTask) = try await Self._makeRemoteDevice(
      port: port,
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )
    defer { endpointTask.cancel() }

    let (coordinator, localDevice, _) = try await Self._makeCoordinator(
      port: port,
      modelGUID: modelGUID,
      serialNumber: serialNumber
    )

    let localGain: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: Self.localGainONo
    )!

    // set local proxy gain and verify remote device gain is updated
    let testValue: OcaDB = -10.0
    await { @OcaDevice in localGain.gain.value = testValue }()
    try await Task.sleep(for: .seconds(2))
    let remoteValue = await remoteGain.gain.value
    #expect(remoteValue == testValue)

    _ = remoteDevice
  }

  @Test(.timeLimit(.minutes(1)))
  func remoteChangePropagatesToLocal() async throws {
    let port: UInt16 = 12346
    let serialNumber = "E2ETest-\(UUID().uuidString)"
    let modelGUID = Self._randomModelGUID()
    let (remoteDevice, remoteGain, endpointTask) = try await Self._makeRemoteDevice(
      port: port,
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )
    defer { endpointTask.cancel() }

    let (coordinator, localDevice, _) = try await Self._makeCoordinator(
      port: port,
      modelGUID: modelGUID,
      serialNumber: serialNumber
    )

    let localGain: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: Self.localGainONo
    )!

    // connect a separate client to the remote device and set gain via OCP.1
    let testValue: OcaDB = -5.0
    var remoteAddress = sockaddr_in()
    remoteAddress.sin_family = sa_family_t(AF_INET)
    remoteAddress.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
    remoteAddress.sin_port = port.bigEndian
    #if canImport(Darwin) || os(FreeBSD) || os(OpenBSD)
    remoteAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif
    let clientConnection = try await Ocp1TCPConnection(
      deviceAddress: remoteAddress.socketAddressData
    )
    try await clientConnection.connect()
    defer { Task { try? await clientConnection.disconnect() } }
    let remoteClientGain: SwiftOCA.OcaRoot =
      try await clientConnection.resolve(objectOfUnknownClass: Self.remoteGainONo)
    try await remoteClientGain.sendCommandRrq(
      methodID: OcaMethodID("4.2"),
      parameters: testValue
    )
    try await Task.sleep(for: .seconds(3))
    let remoteValue = await remoteGain.gain.value
    #expect(remoteValue == testValue, "remote device gain should have been updated")
    let localValue = await localGain.gain.value
    #expect(localValue == testValue, "local proxy gain should have been updated")

    _ = remoteDevice
  }
}
