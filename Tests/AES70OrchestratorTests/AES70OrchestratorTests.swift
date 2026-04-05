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
  func shouldForwardPropertyDefaultsAllowAll() {
    let schema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x0F)
    )
    #expect(schema.includeProperties == nil)
    #expect(schema.excludeProperties.isEmpty)
    #expect(schema.shouldForwardProperty(OcaPropertyID("4.1")))
    #expect(schema.shouldForwardProperty(OcaPropertyID("1.6")))
  }

  @Test
  func shouldForwardPropertyIncludeOnly() {
    let schema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x0F),
      includeProperties: [OcaPropertyID("4.1")]
    )
    #expect(schema.shouldForwardProperty(OcaPropertyID("4.1")))
    #expect(!schema.shouldForwardProperty(OcaPropertyID("3.1")))
  }

  @Test
  func shouldForwardPropertyIncludeEmptyBlocksAll() {
    let schema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x0F),
      includeProperties: []
    )
    #expect(!schema.shouldForwardProperty(OcaPropertyID("4.1")))
    #expect(!schema.shouldForwardProperty(OcaPropertyID("1.1")))
  }

  @Test
  func shouldForwardPropertyExclude() {
    let schema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x0F),
      excludeProperties: [OcaPropertyID("1.6")]
    )
    #expect(schema.shouldForwardProperty(OcaPropertyID("4.1")))
    #expect(!schema.shouldForwardProperty(OcaPropertyID("1.6")))
  }

  @Test
  func shouldForwardPropertyIncludeAndExclude() {
    let schema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x200, mask: 0x0F),
      includeProperties: [OcaPropertyID("4.1"), OcaPropertyID("1.6")],
      excludeProperties: [OcaPropertyID("1.6")]
    )
    #expect(schema.shouldForwardProperty(OcaPropertyID("4.1")))
    #expect(!schema.shouldForwardProperty(OcaPropertyID("1.6")))
    #expect(!schema.shouldForwardProperty(OcaPropertyID("3.1")))
  }

  @Test
  func referencePropertyMetadataStored() {
    let targetMatch = OcaONoMask(oNo: 0x4000_0010, mask: 0x0300_0000)
    let schema = OcaProfileObjectSchema(
      role: "Group",
      type: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x4000_0030, mask: 0x0300_0000),
      referenceProperties: [
        OcaPropertyID("3.1"): OcaProfileReferencePropertySchema(targetMatch: targetMatch),
      ]
    )

    #expect(schema.referenceProperty(for: OcaPropertyID("3.1"))?.targetMatch == targetMatch)
    #expect(schema.referenceProperty(for: OcaPropertyID("3.2")) == nil)
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
    #expect(deviceSchema.paramSetInitialSync == false)
    #expect(deviceSchema.profileSchemas.count == 1)
    #expect(deviceSchema.profileSchemas[0].name == "gain")
  }

  @Test
  func paramSetInitialSyncFlag() {
    let profileSchema = OcaProfileSchema(name: "gain", blocks: [])
    let deviceSchema = OcaDeviceSchema(
      name: "TestDevice",
      paramSetInitialSync: true,
      profileSchemas: [profileSchema]
    )
    #expect(deviceSchema.paramSetInitialSync == true)
  }
}

// MARK: - YAML property filter parsing tests

@OcaDevice
private func _parseYAML(_ yaml: String) throws -> OcaDeviceSchema {
  try OcaDeviceSchema(yaml: yaml)
}

@Suite
struct YAMLPropertyFilterTests {
  @Test
  func includePropertiesParsedFromYAML() async throws {
    let yaml = """
    device:
      name: Test
      profiles:
        - TestProfile:
          - Gain:
              class-id: \(SwiftOCADevice.OcaGain.classID)
              class-version: \(SwiftOCADevice.OcaGain.classVersion)
              match: 0x00000200/0x00000000
              include-props:
                - "4.1"
                - "3.1"
    """
    let schema = try await _parseYAML(yaml)
    let gain = schema.profileSchemas[0].blocks[0]
    #expect(gain.includeProperties == Set([OcaPropertyID("4.1"), OcaPropertyID("3.1")]))
    #expect(gain.excludeProperties.isEmpty)
  }

  @Test
  func excludePropertiesParsedFromYAML() async throws {
    let yaml = """
    device:
      name: Test
      profiles:
        - TestProfile:
          - Gain:
              class-id: \(SwiftOCADevice.OcaGain.classID)
              class-version: \(SwiftOCADevice.OcaGain.classVersion)
              match: 0x00000200/0x00000000
              exclude-props:
                - "1.6"
    """
    let schema = try await _parseYAML(yaml)
    let gain = schema.profileSchemas[0].blocks[0]
    #expect(gain.includeProperties == nil)
    #expect(gain.excludeProperties == Set([OcaPropertyID("1.6")]))
  }

  @Test
  func bothIncludeAndExcludeParsedFromYAML() async throws {
    let yaml = """
    device:
      name: Test
      profiles:
        - TestProfile:
          - Gain:
              class-id: \(SwiftOCADevice.OcaGain.classID)
              class-version: \(SwiftOCADevice.OcaGain.classVersion)
              match: 0x00000200/0x00000000
              include-props:
                - "4.1"
                - "1.6"
              exclude-props:
                - "1.6"
    """
    let schema = try await _parseYAML(yaml)
    let gain = schema.profileSchemas[0].blocks[0]
    #expect(gain.includeProperties == Set([OcaPropertyID("4.1"), OcaPropertyID("1.6")]))
    #expect(gain.excludeProperties == Set([OcaPropertyID("1.6")]))
    #expect(gain.shouldForwardProperty(OcaPropertyID("4.1")))
    #expect(!gain.shouldForwardProperty(OcaPropertyID("1.6")))
  }

  @Test
  func paramSetInitialSyncParsedFromYAML() async throws {
    let yaml = """
    device:
      name: Test
      param-set-initial-sync: true
      profiles:
        - TestProfile:
          - Gain:
              class-id: \(SwiftOCADevice.OcaGain.classID)
              class-version: \(SwiftOCADevice.OcaGain.classVersion)
              match: 0x00000200/0x00000000
    """
    let schema = try await _parseYAML(yaml)
    #expect(schema.paramSetInitialSync == true)
  }

  @Test
  func paramSetInitialSyncDefaultsFalse() async throws {
    let yaml = """
    device:
      name: Test
      profiles:
        - TestProfile:
          - Gain:
              class-id: \(SwiftOCADevice.OcaGain.classID)
              class-version: \(SwiftOCADevice.OcaGain.classVersion)
              match: 0x00000200/0x00000000
    """
    let schema = try await _parseYAML(yaml)
    #expect(schema.paramSetInitialSync == false)
  }

  @Test
  func omittedPropertyFiltersDefaultCorrectly() async throws {
    let yaml = """
    device:
      name: Test
      profiles:
        - TestProfile:
          - Gain:
              class-id: \(SwiftOCADevice.OcaGain.classID)
              class-version: \(SwiftOCADevice.OcaGain.classVersion)
              match: 0x00000200/0x00000000
    """
    let schema = try await _parseYAML(yaml)
    let gain = schema.profileSchemas[0].blocks[0]
    #expect(gain.includeProperties == nil)
    #expect(gain.excludeProperties.isEmpty)
  }

  @Test
  func referencePropertiesParsedFromYAML() async throws {
    let yaml = """
    device:
      name: Test
      profiles:
        - TestProfile:
          - Group:
              class-id: \(SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaRoot>.classID)
              class-version: \(SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaRoot>.classVersion)
              match: 0x40000030/0x03000000
              reference-props:
                "3.1":
                  target-match: 0x40000010/0x03000000
                "3.2": 0x40000010/0x03000000
    """
    let schema = try await _parseYAML(yaml)
    let group = schema.profileSchemas[0].blocks[0]
    let targetMatch = OcaONoMask(oNo: 0x4000_0010, mask: 0x0300_0000)

    #expect(group.referenceProperty(for: OcaPropertyID("3.1"))?.targetMatch == targetMatch)
    #expect(group.referenceProperty(for: OcaPropertyID("3.2"))?.targetMatch == targetMatch)
  }
}

// MARK: - Reference remapping tests

@Suite
struct ReferenceRemappingTests {
  static let localMask = OcaONoMask(oNo: 0, mask: 0x0F00_0000)
  static let remoteMask = OcaONoMask(oNo: 0x4000_0000, mask: 0x0300_0000)
  static let referenceTargetMatch = OcaONoMask(oNo: 0x4000_0010, mask: 0x0300_0000)

  static func _makeSchema() -> OcaDeviceSchema {
    let gain1 = OcaProfileObjectSchema(
      role: "Gain 1",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: OcaONoMask(oNo: 0x0000_0010, mask: localMask.mask),
      remoteObjectNumber: OcaONoMask(oNo: 0x4000_0010, mask: remoteMask.mask)
    )
    let gain2 = OcaProfileObjectSchema(
      role: "Gain 2",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: OcaONoMask(oNo: 0x0000_0020, mask: localMask.mask),
      remoteObjectNumber: OcaONoMask(oNo: 0x4000_0020, mask: remoteMask.mask)
    )
    let group = OcaProfileObjectSchema(
      role: "Group",
      type: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>.self,
      localObjectNumber: OcaONoMask(oNo: 0x0000_0030, mask: localMask.mask),
      remoteObjectNumber: OcaONoMask(oNo: 0x4000_0030, mask: remoteMask.mask),
      referenceProperties: [
        OcaPropertyID("3.1"): OcaProfileReferencePropertySchema(targetMatch: referenceTargetMatch),
        OcaPropertyID("3.2"): OcaProfileReferencePropertySchema(targetMatch: referenceTargetMatch),
      ]
    )

    return OcaDeviceSchema(
      name: "ReferenceDevice",
      profileSchemas: [OcaProfileSchema(name: "References", blocks: [gain1, gain2, group])]
    )
  }

  @OcaDevice
  static func _makeProfile() async throws -> OcaProfile {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()

    let broker = await OcaConnectionBroker(
      connectionOptions: .init(),
      serviceTypes: nil,
      deviceModels: nil
    )
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: _makeSchema(),
      deviceDelegate: device
    )
    let profileONo = try await coordinator.addProfile(schema: "References")
    return try await coordinator._findProfile(oNo: profileONo)
  }

  @Test
  func scalarReferenceONoRemapsBetweenLocalAndRemote() async throws {
    let profile = try await Self._makeProfile()
    let localGainONo = try OcaONoMask(oNo: 0x0000_0010, mask: Self.localMask.mask)
      .objectNumber(for: 1)
    let remoteGainONo = try OcaONoMask(oNo: 0x4000_0010, mask: Self.remoteMask.mask)
      .objectNumber(for: 2)

    #expect(
      try await profile.remapReferenceONoToRemote(
        localGainONo,
        targetMatch: Self.referenceTargetMatch,
        deviceIndex: 2
      ) == remoteGainONo
    )
    #expect(
      try await profile.remapReferenceONoToLocal(
        remoteGainONo,
        targetMatch: Self.referenceTargetMatch,
        deviceIndex: 2
      ) == localGainONo
    )
  }

  @Test
  func arrayReferenceONosRemapBetweenLocalAndRemote() async throws {
    let profile = try await Self._makeProfile()
    let localONos = try [
      OcaONoMask(oNo: 0x0000_0010, mask: Self.localMask.mask).objectNumber(for: 1),
      OcaONoMask(oNo: 0x0000_0020, mask: Self.localMask.mask).objectNumber(for: 1),
    ]
    let remoteONos = try [
      OcaONoMask(oNo: 0x4000_0010, mask: Self.remoteMask.mask).objectNumber(for: 2),
      OcaONoMask(oNo: 0x4000_0020, mask: Self.remoteMask.mask).objectNumber(for: 2),
    ]

    #expect(
      try await profile.remapReferenceONosToRemote(
        localONos,
        targetMatch: Self.referenceTargetMatch,
        deviceIndex: 2
      ) == remoteONos
    )
    #expect(
      try await profile.remapReferenceONosToLocal(
        remoteONos,
        targetMatch: Self.referenceTargetMatch,
        deviceIndex: 2
      ) == localONos
    )
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
    #expect(await p1.profileIndex == 1)
    #expect(await p2.profileIndex == 1)
  }

  @Test
  func profileIndexSkipsConflictingLocalObjectNumbers() async throws {
    let collidingSchema = OcaProfileObjectSchema(
      role: "Inputs",
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      localObjectNumber: OcaONoMask(oNo: 0x00000001, mask: 0x0F000000),
      remoteObjectNumber: OcaONoMask(oNo: 0x00000100, mask: 0x0000000F),
      actionObjectSchema: [
        OcaProfileObjectSchema(
          role: "Input 1",
          type: SwiftOCADevice.OcaGain.self,
          localObjectNumber: OcaONoMask(oNo: 0x00000005, mask: 0x0F000000),
          remoteObjectNumber: OcaONoMask(oNo: 0x00000200, mask: 0x0000000F)
        )
      ]
    )
    let deviceSchema = OcaDeviceSchema(
      name: "TestDevice",
      profileSchemas: [OcaProfileSchema(name: "Colliding", blocks: [collidingSchema])]
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

    let oNo = try await coordinator.addProfile(schema: "Colliding")
    let profile = try await coordinator._findProfile(oNo: oNo)

    #expect(await profile.profileIndex == 1)

    let blockONo = try OcaONoMask(oNo: 0x00000001, mask: 0x0F000000).objectNumber(for: 1)
    let inputONo = try OcaONoMask(oNo: 0x00000005, mask: 0x0F000000).objectNumber(for: 1)
    #expect(await profile.objectBinding(for: blockONo) != nil)
    #expect(await profile.objectBinding(for: inputONo) != nil)
  }

  @Test
  func profileLocalObjectsCreated() async throws {
    let (coordinator, _device) = try await Self._makeCoordinator()
    let oNo = try await coordinator.addProfile(schema: "ChannelStrip")
    let profile = try await coordinator._findProfile(oNo: oNo)
    // channel block schema creates 3 local objects: block, gain, mute
    let blockONo = try OcaONoMask(oNo: 0x1000, mask: 0x0F).objectNumber(for: 1)
    let gainONo = try OcaONoMask(oNo: 0x2000, mask: 0x0F).objectNumber(for: 1)
    let muteONo = try OcaONoMask(oNo: 0x3000, mask: 0x0F).objectNumber(for: 1)
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
    try await coordinator.bindProfile(
      profile1,
      to: Self._testDeviceIdentifier,
      deviceIndex: 2
    )

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
    #expect(await restored1.deviceIndices[Self._testDeviceIdentifier] == 2)
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
    let blockONo = try OcaONoMask(oNo: 0x1000, mask: 0x0F).objectNumber(for: 1)
    let gainONo = try OcaONoMask(oNo: 0x2000, mask: 0x0F).objectNumber(for: 1)
    let muteONo = try OcaONoMask(oNo: 0x3000, mask: 0x0F).objectNumber(for: 1)
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

  @Test
  func blobSaveAndLoadPreservesGroupMembersAndReferenceProperties() async throws {
    let modelGUID = OcaModelGUID(
      mfrCode: .init((0xE2, 0xE2, 0xE2)),
      modelCode: (
        UInt8.random(in: 1...255),
        UInt8.random(in: 0...255),
        UInt8.random(in: 0...255),
        UInt8.random(in: 0...255)
      )
    )
    try? await OcaDeviceClassRegistry.shared.register(_ReferenceScalarDeviceObject.self)
    try? await OcaClassRegistry.shared.register(_ReferenceScalarProxyObject.self)

    let localDevice = OcaDevice()
    try await localDevice.initializeDefaultObjects()
    let broker = await OcaConnectionBroker(
      connectionOptions: Ocp1ConnectionOptions(flags: [.automaticReconnect, .refreshDeviceTreeOnConnection]),
      serviceTypes: [],
      deviceModels: nil
    )
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: EndToEndTests._makeReferenceSchema(modelGUID: modelGUID),
      deviceDelegate: localDevice
    )

    let profileONo = try await coordinator.addProfile(schema: "E2EReferences")
    let profile = try await coordinator._findProfile(oNo: profileONo)

    let localGain1: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceGain1ONo
    )!
    let localGain2: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceGain2ONo
    )!
    let localGroup: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain> = await localDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceGroupONo
    )!
    let localScalar: _ReferenceScalarDeviceObject = await localDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceScalarONo
    )!

    try await localGroup.set(members: [localGain2])
    await { @OcaDevice in localScalar.target = localGain2.objectNumber }()

    let blob = try await coordinator.export()

    let restoredDevice = OcaDevice()
    try await restoredDevice.initializeDefaultObjects()
    let restoredBroker = await OcaConnectionBroker(
      connectionOptions: Ocp1ConnectionOptions(flags: [.automaticReconnect, .refreshDeviceTreeOnConnection]),
      serviceTypes: [],
      deviceModels: nil
    )
    let restoredCoordinator = try await OcaCoordinator(
      connectionBroker: restoredBroker,
      deviceSchema: EndToEndTests._makeReferenceSchema(modelGUID: modelGUID),
      deviceDelegate: restoredDevice
    )

    try await restoredCoordinator.import(from: blob)

    let restoredProfile = try await restoredCoordinator._findProfile(oNo: profile.objectNumber)
    #expect(await restoredProfile.proxyBlock != nil)

    let restoredGroup: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain> = await restoredDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceGroupONo
    )!
    let restoredScalar: _ReferenceScalarDeviceObject = await restoredDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceScalarONo
    )!
    let expectedGain2ONo = try EndToEndTests.localReferenceGain2ONo

    #expect(await restoredGroup.members.map(\.objectNumber) == [expectedGain2ONo])
    #expect(await restoredScalar.target == expectedGain2ONo)
  }

  @Test
  func blobSaveAndLoadRemapsObjectReferencesWhenProfileIndexChanges() async throws {
    let modelGUID = OcaModelGUID(
      mfrCode: .init((0xE2, 0xE2, 0xE2)),
      modelCode: (
        UInt8.random(in: 1...255),
        UInt8.random(in: 0...255),
        UInt8.random(in: 0...255),
        UInt8.random(in: 0...255)
      )
    )
    try? await OcaDeviceClassRegistry.shared.register(_ReferenceScalarDeviceObject.self)
    try? await OcaClassRegistry.shared.register(_ReferenceScalarProxyObject.self)

    let localDevice = OcaDevice()
    try await localDevice.initializeDefaultObjects()
    let broker = await OcaConnectionBroker(
      connectionOptions: Ocp1ConnectionOptions(flags: [.automaticReconnect, .refreshDeviceTreeOnConnection]),
      serviceTypes: [],
      deviceModels: nil
    )
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: EndToEndTests._makeReferenceSchema(modelGUID: modelGUID),
      deviceDelegate: localDevice
    )

    let profileONo = try await coordinator.addProfile(schema: "E2EReferences")
    let profile = try await coordinator._findProfile(oNo: profileONo)
    let uuid = profile.uuid

    let localGain2: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceGain2ONo
    )!
    let localGroup: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain> = await localDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceGroupONo
    )!
    let localScalar: _ReferenceScalarDeviceObject = await localDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceScalarONo
    )!

    try await localGroup.set(members: [localGain2])
    await { @OcaDevice in localScalar.target = localGain2.objectNumber }()

    let blob = try await coordinator.export()
    try await coordinator.deleteProfile(uuid: uuid)
    try await coordinator.import(from: blob)

    let restoredProfile = try await coordinator.findProfile(uuid: uuid)
    #expect(await restoredProfile.profileIndex == 2)

    let expectedGain2ONo = try EndToEndTests.localReferenceGain2Mask.objectNumber(for: 2)
    let expectedGroupONo = try EndToEndTests.localReferenceGroupMask.objectNumber(for: 2)
    let expectedScalarONo = try EndToEndTests.localReferenceScalarMask.objectNumber(for: 2)

    let restoredGroup: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain> = await localDevice.resolve(
      objectNumber: expectedGroupONo
    )!
    let restoredScalar: _ReferenceScalarDeviceObject = await localDevice.resolve(
      objectNumber: expectedScalarONo
    )!
    let restoredGain2: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: expectedGain2ONo
    )!

    #expect(await restoredGroup.members.map(\.objectNumber) == [expectedGain2ONo])
    #expect(await restoredScalar.target == expectedGain2ONo)
    #expect(await restoredGain2.owner == restoredProfile.proxyBlock?.objectNumber)
  }

  @Test
  func blobSaveAndLoadDoesNotRemapNonReferenceIntegerProperties() async throws {
    let modelGUID = OcaModelGUID(
      mfrCode: .init((0xE2, 0xE2, 0xE2)),
      modelCode: (
        UInt8.random(in: 1...255),
        UInt8.random(in: 0...255),
        UInt8.random(in: 0...255),
        UInt8.random(in: 0...255)
      )
    )
    try? await OcaDeviceClassRegistry.shared.register(_ReferenceScalarDeviceObject.self)
    try? await OcaClassRegistry.shared.register(_ReferenceScalarProxyObject.self)

    let localDevice = OcaDevice()
    try await localDevice.initializeDefaultObjects()
    let broker = await OcaConnectionBroker(
      connectionOptions: Ocp1ConnectionOptions(flags: [.automaticReconnect, .refreshDeviceTreeOnConnection]),
      serviceTypes: [],
      deviceModels: nil
    )
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: EndToEndTests._makeReferenceSchemaWithPlainScalar(modelGUID: modelGUID),
      deviceDelegate: localDevice
    )

    let profileONo = try await coordinator.addProfile(schema: "E2EReferencesWithPlainScalar")
    let profile = try await coordinator._findProfile(oNo: profileONo)
    let uuid = profile.uuid

    let localGain2: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceGain2ONo
    )!
    let localScalar: _ReferenceScalarDeviceObject = await localDevice.resolve(
      objectNumber: try EndToEndTests.localReferenceScalarONo
    )!
    let plainScalar: _PlainScalarDeviceObject = await localDevice.resolve(
      objectNumber: try EndToEndTests.localPlainScalarONo
    )!
    let rawIntegerValue = OcaUint32(localGain2.objectNumber)

    await { @OcaDevice in
      localScalar.target = localGain2.objectNumber
      plainScalar.value = rawIntegerValue
    }()

    let blob = try await coordinator.export()
    try await coordinator.deleteProfile(uuid: uuid)
    try await coordinator.import(from: blob)

    let restoredProfile = try await coordinator.findProfile(uuid: uuid)
    #expect(await restoredProfile.profileIndex == 2)

    let expectedPlainScalarONo = try EndToEndTests.localPlainScalarMask.objectNumber(for: 2)
    let expectedReferenceScalarONo = try EndToEndTests.localReferenceScalarMask.objectNumber(for: 2)
    let expectedGain2ONo = try EndToEndTests.localReferenceGain2Mask.objectNumber(for: 2)

    let restoredScalar: _ReferenceScalarDeviceObject = await localDevice.resolve(
      objectNumber: expectedReferenceScalarONo
    )!
    let restoredPlainScalar: _PlainScalarDeviceObject = await localDevice.resolve(
      objectNumber: expectedPlainScalarONo
    )!

    #expect(await restoredScalar.target == expectedGain2ONo)
    #expect(await restoredPlainScalar.value == rawIntegerValue)
  }
}

// MARK: - YAML schema parsing tests

@OcaDevice
final class _LateRegisteredLevelSensor: SwiftOCADevice.OcaLevelSensor {
  override class var classID: OcaClassID {
    OcaClassID(parent: SwiftOCADevice.OcaLevelSensor.classID, authority: PADLCompanyID, 999)
  }
}

@OcaConnection
final class _ReferenceScalarProxyObject: SwiftOCA.OcaWorker {
  override class var classID: OcaClassID { OcaClassID(
    parent: SwiftOCA.OcaWorker.classID,
    authority: PADLCompanyID,
    2000
  ) }

  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  var target: OcaProperty<OcaONo>.PropertyValue
}

@OcaDevice
final class _ReferenceScalarDeviceObject: SwiftOCADevice.OcaWorker {
  override class var classID: OcaClassID { _ReferenceScalarProxyObject.classID }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  var target: OcaONo = OcaInvalidONo
}

@OcaDevice
final class _PlainScalarDeviceObject: SwiftOCADevice.OcaWorker {
  override class var classID: OcaClassID { OcaClassID(
    parent: SwiftOCADevice.OcaWorker.classID,
    authority: PADLCompanyID,
    2001
  ) }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  var value: OcaUint32 = 0
}

@Suite
struct YAMLSchemaTests {
  static let _minimalYAML = """
  device:
    name: TestDevice
    profiles:
      - SimpleGain:
        - Gain:
            classID: \(SwiftOCADevice.OcaGain.classID)
            classVersion: \(SwiftOCADevice.OcaGain.classVersion)
            match: 0x00000200/0x0000000F
            objectNumber: 0x00002000/0x000000F0
  """

  static let _nestedYAML = """
  device:
    name: NestedDevice
    profiles:
      - Channel:
        - ChannelBlock:
            classID: \(SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classID)
            classVersion: \(SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classVersion)
            match: 0x00000100/0x0000000F
            objectNumber: 0x00001000/0x000000F0
            actionObjects:
              - Mute:
                  classID: \(SwiftOCADevice.OcaMute.classID)
                  classVersion: \(SwiftOCADevice.OcaMute.classVersion)
                  match: 0x00000300/0x0000000F
                  objectNumber: 0x00003000/0x000000F0
              - Gain:
                  classID: \(SwiftOCADevice.OcaGain.classID)
                  classVersion: \(SwiftOCADevice.OcaGain.classVersion)
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
                  classID: \(SwiftOCADevice.OcaGain.classID)
                  classVersion: \(SwiftOCADevice.OcaGain.classVersion)
                  match: 0x00000200/0x0000000F
  """

  static let _modelsYAML = """
  device:
    name: ModelDevice
    models: [ 0x0AE91B00010100 ]
    profiles:
      - Simple:
        - Gain:
            classID: \(SwiftOCADevice.OcaGain.classID)
            classVersion: \(SwiftOCADevice.OcaGain.classVersion)
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
              classID: \(SwiftOCADevice.OcaGain.classID)
              classVersion: \(SwiftOCADevice.OcaGain.classVersion)
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
                classID: \(SwiftOCADevice.OcaGain.classID)
                classVersion: \(SwiftOCADevice.OcaGain.classVersion)
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
                  classID: \(SwiftOCADevice.OcaGain.classID)
                  classVersion: \(SwiftOCADevice.OcaGain.classVersion)
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

  @Test
  func createLocalObjectReResolvesDeclaredClassID() async throws {
    let yaml = """
    device:
      name: ProprietaryDevice
      profiles:
        - ProprietaryProfile:
          - Sensor:
              classID: \(_LateRegisteredLevelSensor.classID)
              classVersion: \(_LateRegisteredLevelSensor.classVersion)
              match: 0x00000200/0x00000000
              objectNumber: 0x00002000/0x00000000
    """

    let schema = try await OcaDeviceSchema(yaml: yaml)
    let sensorSchema = schema.profileSchemas[0].blocks[0]

    #expect(sensorSchema.declaredClassID == _LateRegisteredLevelSensor.classID)
    #expect(sensorSchema.declaredClassVersion == _LateRegisteredLevelSensor.classVersion)
    #expect(sensorSchema.type == SwiftOCADevice.OcaLevelSensor.self)

    try? await OcaDeviceClassRegistry.shared.register(_LateRegisteredLevelSensor.self)

    let sensor = try await sensorSchema.createLocalObject(objectNumber: 0x2000, deviceDelegate: nil)
    let sensorClassID = await sensor.objectIdentification.classIdentification.classID
    #expect(type(of: sensor) == _LateRegisteredLevelSensor.self)
    #expect(sensorClassID == _LateRegisteredLevelSensor.classID)
  }

  @Test
  func parseClassIDWithoutClassVersionUsesLatestSupportedVersion() async throws {
    let yaml = """
    device:
      name: OptionalVersionSchema
      profiles:
        - P:
          - Gain:
              classID: \(SwiftOCADevice.OcaGain.classID)
              match: 0x00000200/0x00000000
    """

    let schema = try await OcaDeviceSchema(yaml: yaml)
    let gainSchema = schema.profileSchemas[0].blocks[0]

    #expect(gainSchema.declaredClassID == SwiftOCADevice.OcaGain.classID)
    #expect(gainSchema.declaredClassVersion == nil)
    #expect(gainSchema.type == SwiftOCADevice.OcaGain.self)
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
  static let remoteMissingMuteONo: OcaONo = 0x300
  static let localGainONo: OcaONo = 0x2000
  static let localMissingMuteONo: OcaONo = 0x3000
  static let referenceDeviceIndex: OcaONo = 2
  static let localReferenceGain1Mask = OcaONoMask(oNo: 0x0000_0010, mask: 0x0F00_0000)
  static let localReferenceGain2Mask = OcaONoMask(oNo: 0x0000_0020, mask: 0x0F00_0000)
  static let localReferenceGroupMask = OcaONoMask(oNo: 0x0000_0030, mask: 0x0F00_0000)
  static let remoteReferenceGain1Mask = OcaONoMask(oNo: 0x4000_0010, mask: 0x0300_0000)
  static let remoteReferenceGain2Mask = OcaONoMask(oNo: 0x4000_0020, mask: 0x0300_0000)
  static let remoteReferenceGroupMask = OcaONoMask(oNo: 0x4000_0030, mask: 0x0300_0000)
  static let localReferenceScalarMask = OcaONoMask(oNo: 0x0000_0040, mask: 0x0F00_0000)
  static let remoteReferenceScalarMask = OcaONoMask(oNo: 0x4000_0040, mask: 0x0300_0000)
  static let localPlainScalarMask = OcaONoMask(oNo: 0x0000_0050, mask: 0x0F00_0000)
  static let remotePlainScalarMask = OcaONoMask(oNo: 0x4000_0050, mask: 0x0300_0000)

  static var localReferenceGain1ONo: OcaONo {
    get throws { try localReferenceGain1Mask.objectNumber(for: 1) }
  }

  static var localReferenceGain2ONo: OcaONo {
    get throws { try localReferenceGain2Mask.objectNumber(for: 1) }
  }

  static var localReferenceGroupONo: OcaONo {
    get throws { try localReferenceGroupMask.objectNumber(for: 1) }
  }

  static var remoteReferenceGain1ONo: OcaONo {
    get throws { try remoteReferenceGain1Mask.objectNumber(for: referenceDeviceIndex) }
  }

  static var remoteReferenceGain2ONo: OcaONo {
    get throws { try remoteReferenceGain2Mask.objectNumber(for: referenceDeviceIndex) }
  }

  static var remoteReferenceGroupONo: OcaONo {
    get throws { try remoteReferenceGroupMask.objectNumber(for: referenceDeviceIndex) }
  }

  static var localReferenceScalarONo: OcaONo {
    get throws { try localReferenceScalarMask.objectNumber(for: 1) }
  }

  static var remoteReferenceScalarONo: OcaONo {
    get throws { try remoteReferenceScalarMask.objectNumber(for: referenceDeviceIndex) }
  }

  static var localPlainScalarONo: OcaONo {
    get throws { try localPlainScalarMask.objectNumber(for: 1) }
  }

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

  static func _makeRemoteFollowerOnlySchema(modelGUID: OcaModelGUID) -> OcaDeviceSchema {
    let gainSchema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: OcaONoMask(oNo: localGainONo, mask: 0),
      remoteObjectNumber: OcaONoMask(oNo: remoteGainONo, mask: 0),
      remoteFollowerOnly: true
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

  static func _makeSchemaWithMissingRemoteObject(modelGUID: OcaModelGUID) -> OcaDeviceSchema {
    let gainSchema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: OcaONoMask(oNo: localGainONo, mask: 0),
      remoteObjectNumber: OcaONoMask(oNo: remoteGainONo, mask: 0)
    )
    let missingMuteSchema = OcaProfileObjectSchema(
      role: "Mute",
      type: SwiftOCADevice.OcaMute.self,
      localObjectNumber: OcaONoMask(oNo: localMissingMuteONo, mask: 0),
      remoteObjectNumber: OcaONoMask(oNo: remoteMissingMuteONo, mask: 0)
    )
    let profileSchema = OcaProfileSchema(
      name: "E2EGain",
      blocks: [gainSchema, missingMuteSchema]
    )
    return OcaDeviceSchema(
      name: "E2ETestDevice",
      models: [modelGUID],
      profileSchemas: [profileSchema]
    )
  }

  static func _makeReferenceSchema(modelGUID: OcaModelGUID) -> OcaDeviceSchema {
    let referenceTarget = OcaONoMask(oNo: 0x4000_0010, mask: 0x0300_0000)
    let gain1 = OcaProfileObjectSchema(
      role: "Gain 1",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: localReferenceGain1Mask,
      remoteObjectNumber: remoteReferenceGain1Mask
    )
    let gain2 = OcaProfileObjectSchema(
      role: "Gain 2",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: localReferenceGain2Mask,
      remoteObjectNumber: remoteReferenceGain2Mask
    )
    let group = OcaProfileObjectSchema(
      role: "Group",
      type: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>.self,
      localObjectNumber: localReferenceGroupMask,
      remoteObjectNumber: remoteReferenceGroupMask,
      includeProperties: [OcaPropertyID("3.1")],
      referenceProperties: [
        OcaPropertyID("3.1"): OcaProfileReferencePropertySchema(targetMatch: referenceTarget),
      ]
    )
    let scalar = OcaProfileObjectSchema(
      role: "Scalar",
      type: _ReferenceScalarDeviceObject.self,
      localObjectNumber: localReferenceScalarMask,
      remoteObjectNumber: remoteReferenceScalarMask,
      referenceProperties: [
        OcaPropertyID("4.1"): OcaProfileReferencePropertySchema(targetMatch: referenceTarget),
      ]
    )

    return OcaDeviceSchema(
      name: "E2EReferenceDevice",
      models: [modelGUID],
      profileSchemas: [OcaProfileSchema(name: "E2EReferences", blocks: [gain1, gain2, group, scalar])]
    )
  }

  static func _makeReferenceSchemaWithPlainScalar(modelGUID: OcaModelGUID) -> OcaDeviceSchema {
    let referenceTarget = OcaONoMask(oNo: 0x4000_0010, mask: 0x0300_0000)
    let gain1 = OcaProfileObjectSchema(
      role: "Gain 1",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: localReferenceGain1Mask,
      remoteObjectNumber: remoteReferenceGain1Mask
    )
    let gain2 = OcaProfileObjectSchema(
      role: "Gain 2",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: localReferenceGain2Mask,
      remoteObjectNumber: remoteReferenceGain2Mask
    )
    let group = OcaProfileObjectSchema(
      role: "Group",
      type: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>.self,
      localObjectNumber: localReferenceGroupMask,
      remoteObjectNumber: remoteReferenceGroupMask,
      includeProperties: [OcaPropertyID("3.1")],
      referenceProperties: [
        OcaPropertyID("3.1"): OcaProfileReferencePropertySchema(targetMatch: referenceTarget),
      ]
    )
    let scalar = OcaProfileObjectSchema(
      role: "Scalar",
      type: _ReferenceScalarDeviceObject.self,
      localObjectNumber: localReferenceScalarMask,
      remoteObjectNumber: remoteReferenceScalarMask,
      referenceProperties: [
        OcaPropertyID("4.1"): OcaProfileReferencePropertySchema(targetMatch: referenceTarget),
      ]
    )
    let plainScalar = OcaProfileObjectSchema(
      role: "Plain Scalar",
      type: _PlainScalarDeviceObject.self,
      localObjectNumber: localPlainScalarMask,
      remoteObjectNumber: remotePlainScalarMask
    )

    return OcaDeviceSchema(
      name: "E2EReferenceDevice",
      models: [modelGUID],
      profileSchemas: [
        OcaProfileSchema(
          name: "E2EReferencesWithPlainScalar",
          blocks: [gain1, gain2, group, scalar, plainScalar]
        )
      ]
    )
  }

  static func _makeReferenceRemoteDevice(
    port: UInt16,
    serialNumber: String,
    modelGUID: OcaModelGUID
  ) async throws -> (
    device: OcaDevice,
    gain1: SwiftOCADevice.OcaGain,
    gain2: SwiftOCADevice.OcaGain,
    group: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>,
    scalar: _ReferenceScalarDeviceObject,
    endpointTask: Task<(), Error>
  ) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let deviceManager = await device.deviceManager!
    await _setDeviceManagerProperties(
      deviceManager,
      name: "E2E Reference Remote Device",
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )

    let gain1 = try await SwiftOCADevice.OcaGain(
      objectNumber: try remoteReferenceGain1ONo,
      role: "Gain 1",
      deviceDelegate: device
    )
    let gain2 = try await SwiftOCADevice.OcaGain(
      objectNumber: try remoteReferenceGain2ONo,
      role: "Gain 2",
      deviceDelegate: device
    )
    let group = try await SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>(
      objectNumber: try remoteReferenceGroupONo,
      role: "Group",
      deviceDelegate: device
    )
    let scalar = try await _ReferenceScalarDeviceObject(
      objectNumber: try remoteReferenceScalarONo,
      role: "Scalar",
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
    try await Task.sleep(for: .milliseconds(500))

    return (device, gain1, gain2, group, scalar, endpointTask)
  }

  static func _makeReferenceRemoteDeviceMissingSecondGain(
    port: UInt16,
    serialNumber: String,
    modelGUID: OcaModelGUID
  ) async throws -> (
    device: OcaDevice,
    gain1: SwiftOCADevice.OcaGain,
    group: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>,
    scalar: _ReferenceScalarDeviceObject,
    endpointTask: Task<(), Error>
  ) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let deviceManager = await device.deviceManager!
    await _setDeviceManagerProperties(
      deviceManager,
      name: "E2E Reference Remote Device Missing Gain 2",
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )

    let gain1 = try await SwiftOCADevice.OcaGain(
      objectNumber: try remoteReferenceGain1ONo,
      role: "Gain 1",
      deviceDelegate: device
    )
    let group = try await SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>(
      objectNumber: try remoteReferenceGroupONo,
      role: "Group",
      deviceDelegate: device
    )
    let scalar = try await _ReferenceScalarDeviceObject(
      objectNumber: try remoteReferenceScalarONo,
      role: "Scalar",
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
    try await Task.sleep(for: .milliseconds(500))

    return (device, gain1, group, scalar, endpointTask)
  }

  private static func _makeCoordinator(
    port: UInt16,
    modelGUID: OcaModelGUID,
    serialNumber: String,
    schema: OcaDeviceSchema? = nil
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
    let schema = schema ?? _makeSchema(modelGUID: modelGUID)
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
  func activationPreservesLocalProxyState() async throws {
    let port: UInt16 = 12350
    let serialNumber = "E2ETest-Activation-\(UUID().uuidString)"
    let modelGUID = Self._randomModelGUID()

    // start remote device with a gain of -20 dB
    let (remoteDevice, remoteGain, endpointTask) = try await Self._makeRemoteDevice(
      port: port,
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )
    defer { endpointTask.cancel() }
    let remoteInitialValue: OcaDB = -20.0
    await { @OcaDevice in remoteGain.gain.value = remoteInitialValue }()

    // build coordinator and profile WITHOUT connecting yet
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
    let schema = Self._makeSchema(modelGUID: modelGUID)
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: schema,
      deviceDelegate: localDevice
    )

    let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    let profileONo = try await coordinator.addProfile(schema: "E2EGain", uuid: zeroUUID)
    let profile = try await coordinator._findProfile(oNo: profileONo)

    // set local proxy gain to -7 dB (different from remote)
    let localInitialValue: OcaDB = -7.0
    let localGain: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: Self.localGainONo
    )!
    await { @OcaDevice in localGain.gain.value = localInitialValue }()

    // now connect — this triggers auto-bind + activation
    let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
      serviceType: .tcp,
      modelGUID: modelGUID,
      serialNumber: serialNumber,
      name: "E2E Test Remote Device"
    )
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
    await broker.register(device: deviceIdentifier, connection: connection)
    let brokerEventTask = Task { [weak coordinator] in
      guard let coordinator else { return }
      for await event in await broker.events {
        await coordinator.handleConnectionBrokerEvent(event)
      }
    }
    _ = brokerEventTask

    // wait for activation
    for _ in 0..<20 {
      let count = await profile.remoteObjectCount(for: deviceIdentifier)
      if count > 0 { break }
      try await Task.sleep(for: .milliseconds(250))
    }

    // allow time for any stray remote events to propagate
    try await Task.sleep(for: .seconds(2))

    // local proxy must retain its pre-activation value
    let localValue = await localGain.gain.value
    #expect(
      localValue == localInitialValue,
      "local proxy gain should be preserved during activation, not overwritten by remote device state"
    )

    // remote device should have been updated to match the local proxy
    let remoteValue = await remoteGain.gain.value
    #expect(
      remoteValue == localInitialValue,
      "remote device gain should have been updated to match local proxy"
    )

    _ = remoteDevice
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

  @Test(.timeLimit(.minutes(1)))
  func remoteFollowerOnlyIgnoresRemoteChanges() async throws {
    let port: UInt16 = 12349
    let serialNumber = "E2ETest-RemoteFollowerOnly-\(UUID().uuidString)"
    let modelGUID = Self._randomModelGUID()
    let (remoteDevice, remoteGain, endpointTask) = try await Self._makeRemoteDevice(
      port: port,
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )
    defer { endpointTask.cancel() }

    let schema = Self._makeRemoteFollowerOnlySchema(modelGUID: modelGUID)
    let (_coordinator, localDevice, _) = try await Self._makeCoordinator(
      port: port,
      modelGUID: modelGUID,
      serialNumber: serialNumber,
      schema: schema
    )

    let localGain: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: Self.localGainONo
    )!

    let initialValue = await localGain.gain.value
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

    #expect(await remoteGain.gain.value == testValue, "remote device gain should have been updated")
    #expect(await localGain.gain.value == initialValue, "local proxy gain should ignore remote-originated changes when remoteFollowerOnly is enabled")

    _ = remoteDevice
  }

  @Test(.timeLimit(.minutes(1)))
  func missingRemoteObjectDoesNotAbortActivation() async throws {
    let port: UInt16 = 12347
    let serialNumber = "E2ETest-Missing-\(UUID().uuidString)"
    let modelGUID = Self._randomModelGUID()
    let (_remoteDevice, remoteGain, endpointTask) = try await Self._makeRemoteDevice(
      port: port,
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )
    defer { endpointTask.cancel() }

    let schema = Self._makeSchemaWithMissingRemoteObject(modelGUID: modelGUID)
    let (coordinator, localDevice, deviceIdentifier) = try await Self._makeCoordinator(
      port: port,
      modelGUID: modelGUID,
      serialNumber: serialNumber,
      schema: schema
    )
    let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    let profile = try await coordinator.findProfile(uuid: zeroUUID)

    for _ in 0..<20 {
      let count = await profile.remoteObjectCount(for: deviceIdentifier)
      if count == 1 { break }
      try await Task.sleep(for: .milliseconds(250))
    }

    #expect(await profile.remoteObjectCount(for: deviceIdentifier) == 1)

    let localGain: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: Self.localGainONo
    )!

    let testValue: OcaDB = -6.0
    await { @OcaDevice in localGain.gain.value = testValue }()
    try await Task.sleep(for: .seconds(2))
    #expect(await remoteGain.gain.value == testValue)
  }

  @Test(.timeLimit(.minutes(1)))
  func referencePropertiesRemapOnBindAndLiveSync() async throws {
    let port: UInt16 = 12348
    let serialNumber = "E2EReference-\(UUID().uuidString)"
    let modelGUID = Self._randomModelGUID()
    try? await OcaDeviceClassRegistry.shared.register(_ReferenceScalarDeviceObject.self)
    try? await OcaClassRegistry.shared.register(_ReferenceScalarProxyObject.self)
    let (remoteDevice, remoteGain1, remoteGain2, remoteGroup, remoteScalar, endpointTask) =
      try await Self._makeReferenceRemoteDevice(
        port: port,
        serialNumber: serialNumber,
        modelGUID: modelGUID
      )
    defer { endpointTask.cancel() }

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
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: Self._makeReferenceSchema(modelGUID: modelGUID),
      deviceDelegate: localDevice
    )
    let profileONo = try await coordinator.addProfile(schema: "E2EReferences")
    let profile = try await coordinator._findProfile(oNo: profileONo)

    let localGain1: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: try Self.localReferenceGain1ONo
    )!
    let localGain2: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: try Self.localReferenceGain2ONo
    )!
    let localGroup: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain> = await localDevice.resolve(
      objectNumber: try Self.localReferenceGroupONo
    )!
    let localScalar: _ReferenceScalarDeviceObject = await localDevice.resolve(
      objectNumber: try Self.localReferenceScalarONo
    )!

    try await localGroup.set(members: [localGain1, localGain2])
    await { @OcaDevice in localScalar.target = localGain2.objectNumber }()

    let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
      serviceType: .tcp,
      modelGUID: modelGUID,
      serialNumber: serialNumber,
      name: "E2E Reference Remote Device"
    )
    try await { @OcaDevice in
      try await coordinator.bindProfile(
        profile,
        to: deviceIdentifier,
        deviceIndex: Self.referenceDeviceIndex
      )
    }()

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
    defer { Task { try? await connection.disconnect() } }

    await broker.register(device: deviceIdentifier, connection: connection)
    let brokerEventTask = Task { [weak coordinator] in
      guard let coordinator else { return }
      for await event in await broker.events {
        await coordinator.handleConnectionBrokerEvent(event)
      }
    }
    defer { brokerEventTask.cancel() }

    for _ in 0..<20 {
      if await profile.remoteObjectCount(for: deviceIdentifier) == 4 { break }
      try await Task.sleep(for: .milliseconds(250))
    }

    #expect(await profile.remoteObjectCount(for: deviceIdentifier) == 4)
    #expect(await remoteGroup.members.map(\.objectNumber) == [remoteGain1.objectNumber, remoteGain2.objectNumber])
    #expect(await remoteScalar.target == remoteGain2.objectNumber)

    try await localGroup.set(members: [localGain1])
    await { @OcaDevice in localScalar.target = localGain1.objectNumber }()
    try await Task.sleep(for: .seconds(2))

    #expect(await remoteGroup.members.map(\.objectNumber) == [remoteGain1.objectNumber])
    #expect(await remoteScalar.target == remoteGain1.objectNumber)

    try await remoteGroup.set(members: [remoteGain2])
    await { @OcaDevice in remoteScalar.target = remoteGain2.objectNumber }()
    try await Task.sleep(for: .seconds(2))

    #expect(await localGroup.members.map(\.objectNumber) == [localGain2.objectNumber])
    #expect(await localScalar.target == localGain2.objectNumber)

    _ = remoteDevice
  }

  @Test(.timeLimit(.minutes(1)))
  func referencePropertyListsSkipMissingRemoteObjects() async throws {
    let port: UInt16 = 12350
    let serialNumber = "E2EReferenceMissing-\(UUID().uuidString)"
    let modelGUID = Self._randomModelGUID()
    try? await OcaDeviceClassRegistry.shared.register(_ReferenceScalarDeviceObject.self)
    try? await OcaClassRegistry.shared.register(_ReferenceScalarProxyObject.self)
    let (remoteDevice, remoteGain1, remoteGroup, remoteScalar, endpointTask) =
      try await Self._makeReferenceRemoteDeviceMissingSecondGain(
        port: port,
        serialNumber: serialNumber,
        modelGUID: modelGUID
      )
    defer { endpointTask.cancel() }

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
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: Self._makeReferenceSchema(modelGUID: modelGUID),
      deviceDelegate: localDevice
    )
    let profileONo = try await coordinator.addProfile(schema: "E2EReferences")
    let profile = try await coordinator._findProfile(oNo: profileONo)

    let localGain1: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: try Self.localReferenceGain1ONo
    )!
    let localGain2: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: try Self.localReferenceGain2ONo
    )!
    let localGroup: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain> = await localDevice.resolve(
      objectNumber: try Self.localReferenceGroupONo
    )!
    let localScalar: _ReferenceScalarDeviceObject = await localDevice.resolve(
      objectNumber: try Self.localReferenceScalarONo
    )!

    try await localGroup.set(members: [localGain1, localGain2])
    await { @OcaDevice in localScalar.target = localGain2.objectNumber }()

    let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
      serviceType: .tcp,
      modelGUID: modelGUID,
      serialNumber: serialNumber,
      name: "E2E Reference Remote Device Missing Gain 2"
    )
    try await { @OcaDevice in
      try await coordinator.bindProfile(
        profile,
        to: deviceIdentifier,
        deviceIndex: Self.referenceDeviceIndex
      )
    }()

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
    defer { Task { try? await connection.disconnect() } }

    await broker.register(device: deviceIdentifier, connection: connection)
    let brokerEventTask = Task { [weak coordinator] in
      guard let coordinator else { return }
      for await event in await broker.events {
        await coordinator.handleConnectionBrokerEvent(event)
      }
    }
    defer { brokerEventTask.cancel() }

    for _ in 0..<20 {
      if await profile.remoteObjectCount(for: deviceIdentifier) == 3 { break }
      try await Task.sleep(for: .milliseconds(250))
    }

    #expect(await profile.remoteObjectCount(for: deviceIdentifier) == 3)
    #expect(await remoteGroup.members.map(\.objectNumber) == [remoteGain1.objectNumber])
    #expect(await remoteScalar.target == OcaInvalidONo)

    _ = remoteDevice
  }

  // MARK: - param-set initial sync

  private static let remoteParamSetBlockONo: OcaONo = 0x100
  private static let remoteParamSetGainONo: OcaONo = 0x200
  private static let localParamSetBlockMask = OcaONoMask(oNo: 0x1000, mask: 0xF0)
  private static let localParamSetGainMask = OcaONoMask(oNo: 0x2000, mask: 0xF0)

  static func _makeParamSetSchema(modelGUID: OcaModelGUID) -> OcaDeviceSchema {
    let gainSchema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: localParamSetGainMask,
      remoteObjectNumber: OcaONoMask(oNo: remoteParamSetGainONo, mask: 0)
    )
    let blockSchema = OcaProfileObjectSchema(
      role: "Block",
      declaredClassID: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classID,
      declaredClassVersion: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classVersion,
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      localObjectNumber: localParamSetBlockMask,
      remoteObjectNumber: OcaONoMask(oNo: remoteParamSetBlockONo, mask: 0),
      actionObjectSchema: [gainSchema]
    )
    return OcaDeviceSchema(
      name: "ParamSetDevice",
      models: [modelGUID],
      paramSetInitialSync: true,
      profileSchemas: [OcaProfileSchema(name: "ParamSetGain", blocks: [blockSchema])]
    )
  }

  static func _makeParamSetRemoteDevice(
    port: UInt16,
    serialNumber: String,
    modelGUID: OcaModelGUID
  ) async throws -> (
    device: OcaDevice,
    block: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>,
    gain: SwiftOCADevice.OcaGain,
    endpointTask: Task<(), Error>
  ) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let deviceManager = await device.deviceManager!
    await _setDeviceManagerProperties(
      deviceManager,
      name: "E2E ParamSet Remote Device",
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )

    let block = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: remoteParamSetBlockONo,
      role: "Block",
      deviceDelegate: device,
      addToRootBlock: true
    )
    let gain = try await SwiftOCADevice.OcaGain(
      objectNumber: remoteParamSetGainONo,
      role: "Gain",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await block.add(actionObject: gain)

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
    try await Task.sleep(for: .milliseconds(500))

    return (device, block, gain, endpointTask)
  }

  @Test(.timeLimit(.minutes(1)))
  func paramSetInitialSyncCopiesLocalToRemote() async throws {
    let port: UInt16 = 12351
    let serialNumber = "E2EParamSet-\(UUID().uuidString)"
    let modelGUID = Self._randomModelGUID()
    let (remoteDevice, _remoteBlock, remoteGain, endpointTask) =
      try await Self._makeParamSetRemoteDevice(
        port: port,
        serialNumber: serialNumber,
        modelGUID: modelGUID
      )
    defer { endpointTask.cancel() }

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
    let schema = Self._makeParamSetSchema(modelGUID: modelGUID)
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: schema,
      deviceDelegate: localDevice
    )

    let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    let profileONo = try await coordinator.addProfile(schema: "ParamSetGain", uuid: zeroUUID)
    let profile = try await coordinator._findProfile(oNo: profileONo)

    // set local proxy gain to a known value before connecting
    let localGainONo = try Self.localParamSetGainMask.objectNumber(for: 1)
    let localGain: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: localGainONo
    )!
    let testValue: OcaDB = -12.5
    await { @OcaDevice in localGain.gain.value = testValue }()

    // connect to the remote device
    let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
      serviceType: .tcp,
      modelGUID: modelGUID,
      serialNumber: serialNumber,
      name: "E2E ParamSet Remote Device"
    )
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
    defer { Task { try? await connection.disconnect() } }

    await broker.register(device: deviceIdentifier, connection: connection)
    let brokerEventTask = Task { [weak coordinator] in
      guard let coordinator else { return }
      for await event in await broker.events {
        await coordinator.handleConnectionBrokerEvent(event)
      }
    }
    defer { brokerEventTask.cancel() }

    // wait for activation
    for _ in 0..<20 {
      let count = await profile.remoteObjectCount(for: deviceIdentifier)
      if count > 0 { break }
      try await Task.sleep(for: .milliseconds(250))
    }

    // allow time for param-set apply to complete
    try await Task.sleep(for: .seconds(2))

    // verify the param-set path was actually used (not the per-property fallback)
    let syncCount = await profile.paramSetSyncCount
    #expect(
      syncCount > 0,
      "param-set sync path should have been used, but paramSetSyncCount is \(syncCount)"
    )

    // remote gain should have been updated via param-set blob
    let remoteValue = await remoteGain.gain.value
    #expect(
      remoteValue == testValue,
      "remote device gain should have been updated to \(testValue) via param-set initial sync, got \(remoteValue)"
    )

    // local proxy should retain its value
    let localValue = await localGain.gain.value
    #expect(localValue == testValue)

    // verify ongoing sync still works after param-set initial sync
    let liveTestValue: OcaDB = -3.0
    await { @OcaDevice in localGain.gain.value = liveTestValue }()
    try await Task.sleep(for: .seconds(2))
    #expect(
      await remoteGain.gain.value == liveTestValue,
      "live property sync should still work after param-set initial sync"
    )

    _ = remoteDevice
  }

  // MARK: - param-set reference property remapping

  private static let remoteParamSetGroupBlockONo: OcaONo = 0x400
  private static let remoteParamSetGroupONo: OcaONo = 0x500
  private static let remoteParamSetGroupGain1ONo: OcaONo = 0x600
  private static let remoteParamSetGroupGain2ONo: OcaONo = 0x700
  private static let localParamSetGroupBlockMask = OcaONoMask(oNo: 0x4000, mask: 0xF0)
  private static let localParamSetGroupMask = OcaONoMask(oNo: 0x5000, mask: 0xF0)
  private static let localParamSetGroupGain1Mask = OcaONoMask(oNo: 0x6000, mask: 0xF0)
  private static let localParamSetGroupGain2Mask = OcaONoMask(oNo: 0x7000, mask: 0xF0)

  static func _makeParamSetGroupSchema(modelGUID: OcaModelGUID) -> OcaDeviceSchema {
    let gain1Schema = OcaProfileObjectSchema(
      role: "Gain 1",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: localParamSetGroupGain1Mask,
      remoteObjectNumber: OcaONoMask(oNo: remoteParamSetGroupGain1ONo, mask: 0)
    )
    let gain2Schema = OcaProfileObjectSchema(
      role: "Gain 2",
      type: SwiftOCADevice.OcaGain.self,
      localObjectNumber: localParamSetGroupGain2Mask,
      remoteObjectNumber: OcaONoMask(oNo: remoteParamSetGroupGain2ONo, mask: 0)
    )
    let groupSchema = OcaProfileObjectSchema(
      role: "Group",
      type: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>.self,
      localObjectNumber: localParamSetGroupMask,
      remoteObjectNumber: OcaONoMask(oNo: remoteParamSetGroupONo, mask: 0),
      includeProperties: [OcaPropertyID("3.1")],
      referenceProperties: [
        OcaPropertyID("3.1"): OcaProfileReferencePropertySchema(
          targetMatch: OcaONoMask(oNo: 0x6000, mask: 0xF0)
        ),
      ]
    )
    let blockSchema = OcaProfileObjectSchema(
      role: "Block",
      declaredClassID: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classID,
      declaredClassVersion: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classVersion,
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      localObjectNumber: localParamSetGroupBlockMask,
      remoteObjectNumber: OcaONoMask(oNo: remoteParamSetGroupBlockONo, mask: 0),
      actionObjectSchema: [gain1Schema, gain2Schema, groupSchema]
    )
    return OcaDeviceSchema(
      name: "ParamSetGroupDevice",
      models: [modelGUID],
      paramSetInitialSync: true,
      profileSchemas: [OcaProfileSchema(name: "ParamSetGroup", blocks: [blockSchema])]
    )
  }

  static func _makeParamSetGroupRemoteDevice(
    port: UInt16,
    serialNumber: String,
    modelGUID: OcaModelGUID
  ) async throws -> (
    device: OcaDevice,
    block: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>,
    group: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>,
    gain1: SwiftOCADevice.OcaGain,
    gain2: SwiftOCADevice.OcaGain,
    endpointTask: Task<(), Error>
  ) {
    let device = OcaDevice()
    try await device.initializeDefaultObjects()
    let deviceManager = await device.deviceManager!
    await _setDeviceManagerProperties(
      deviceManager,
      name: "E2E ParamSet Group Remote Device",
      serialNumber: serialNumber,
      modelGUID: modelGUID
    )

    let block = try await SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>(
      objectNumber: remoteParamSetGroupBlockONo,
      role: "Block",
      deviceDelegate: device,
      addToRootBlock: true
    )
    let gain1 = try await SwiftOCADevice.OcaGain(
      objectNumber: remoteParamSetGroupGain1ONo,
      role: "Gain 1",
      deviceDelegate: device,
      addToRootBlock: false
    )
    let gain2 = try await SwiftOCADevice.OcaGain(
      objectNumber: remoteParamSetGroupGain2ONo,
      role: "Gain 2",
      deviceDelegate: device,
      addToRootBlock: false
    )
    let group = try await SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>(
      objectNumber: remoteParamSetGroupONo,
      role: "Group",
      deviceDelegate: device,
      addToRootBlock: false
    )
    try await block.add(actionObject: gain1)
    try await block.add(actionObject: gain2)
    try await block.add(actionObject: group)

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
    try await Task.sleep(for: .milliseconds(500))

    return (device, block, group, gain1, gain2, endpointTask)
  }

  @Test(.timeLimit(.minutes(1)))
  func paramSetInitialSyncRemapsGroupMembers() async throws {
    let port: UInt16 = 12352
    let serialNumber = "E2EParamSetGroup-\(UUID().uuidString)"
    let modelGUID = Self._randomModelGUID()
    let (remoteDevice, _remoteBlock, remoteGroup, _remoteGain1, _remoteGain2, endpointTask) =
      try await Self._makeParamSetGroupRemoteDevice(
        port: port,
        serialNumber: serialNumber,
        modelGUID: modelGUID
      )
    defer { endpointTask.cancel() }

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
    let schema = Self._makeParamSetGroupSchema(modelGUID: modelGUID)
    let coordinator = try await OcaCoordinator(
      connectionBroker: broker,
      deviceSchema: schema,
      deviceDelegate: localDevice
    )

    let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    let profileONo = try await coordinator.addProfile(schema: "ParamSetGroup", uuid: zeroUUID)
    let profile = try await coordinator._findProfile(oNo: profileONo)

    // resolve local proxy objects
    let localGroupONo = try Self.localParamSetGroupMask.objectNumber(for: 1)
    let localGain1ONo = try Self.localParamSetGroupGain1Mask.objectNumber(for: 1)
    let localGain2ONo = try Self.localParamSetGroupGain2Mask.objectNumber(for: 1)

    let localGroup: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain> = await localDevice.resolve(
      objectNumber: localGroupONo
    )!
    let localGain1: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: localGain1ONo
    )!
    let localGain2: SwiftOCADevice.OcaGain = await localDevice.resolve(
      objectNumber: localGain2ONo
    )!

    // assign both gains as group members on local proxy
    try await localGroup.add(member: localGain1)
    try await localGroup.add(member: localGain2)
    #expect(await localGroup.members.count == 2)

    // connect to the remote device
    let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
      serviceType: .tcp,
      modelGUID: modelGUID,
      serialNumber: serialNumber,
      name: "E2E ParamSet Group Remote Device"
    )
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
    defer { Task { try? await connection.disconnect() } }

    await broker.register(device: deviceIdentifier, connection: connection)
    let brokerEventTask = Task { [weak coordinator] in
      guard let coordinator else { return }
      for await event in await broker.events {
        await coordinator.handleConnectionBrokerEvent(event)
      }
    }
    defer { brokerEventTask.cancel() }

    // wait for activation
    for _ in 0..<20 {
      let count = await profile.remoteObjectCount(for: deviceIdentifier)
      if count > 0 { break }
      try await Task.sleep(for: .milliseconds(250))
    }

    // allow time for param-set apply to complete
    try await Task.sleep(for: .seconds(2))

    // verify the param-set path was actually used
    let syncCount = await profile.paramSetSyncCount
    #expect(
      syncCount > 0,
      "param-set sync path should have been used, but paramSetSyncCount is \(syncCount)"
    )

    // remote group should have both gains as members with REMOTE ONos
    let remoteMemberONos = await remoteGroup.members.map(\.objectNumber)
    #expect(
      remoteMemberONos.contains(Self.remoteParamSetGroupGain1ONo),
      "remote group should contain gain 1 (ONo \(Self.remoteParamSetGroupGain1ONo)), got \(remoteMemberONos)"
    )
    #expect(
      remoteMemberONos.contains(Self.remoteParamSetGroupGain2ONo),
      "remote group should contain gain 2 (ONo \(Self.remoteParamSetGroupGain2ONo)), got \(remoteMemberONos)"
    )
    #expect(
      remoteMemberONos.count == 2,
      "remote group should have exactly 2 members, got \(remoteMemberONos.count)"
    )

    _ = remoteDevice
  }
}

// MARK: - _remapObjectNumbers unit tests

@Suite
struct RemapObjectNumbersTests {
  private static let groupClassID = SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>.classID

  @Test
  func remapsONoKeysWithoutReferenceProperties() {
    let jsonObject: [String: Any] = [
      "_oNo": OcaONo(0x1000),
      "_classID": "1.1.3",
      "4.1": OcaONo(42),
      "3.2": [
        ["_oNo": OcaONo(0x2000), "_classID": "1.1.1.5", "4.1": OcaFloat32(-12.5)],
      ] as [[String: Any]],
    ]

    let result = OcaProfile._remapObjectNumbers(
      in: jsonObject,
      transform: { $0 + 0x100 }
    ) as! [String: Any]

    // _oNo keys are remapped
    #expect(result["_oNo"] as? OcaONo == 0x1100)
    let actionObjects = result["3.2"] as! [[String: Any]]
    #expect(actionObjects[0]["_oNo"] as? OcaONo == 0x2100)

    // non-_oNo integer values are NOT remapped
    #expect(result["4.1"] as? OcaONo == 42)
    #expect(actionObjects[0]["4.1"] as? OcaFloat32 == -12.5)
  }

  @Test
  func remapsArrayReferenceProperty() {
    let refProps: [String: Set<String>] = [
      Self.groupClassID.description: ["3.1"],
    ]

    let jsonObject: [String: Any] = [
      "_oNo": OcaONo(0x5000),
      "_classID": Self.groupClassID.description,
      "3.1": [OcaONo(0x6000), OcaONo(0x7000)],
    ]

    let result = OcaProfile._remapObjectNumbers(
      in: jsonObject,
      referencePropertyIDs: refProps,
      transform: { $0 + 0x100 }
    ) as! [String: Any]

    #expect(result["_oNo"] as? OcaONo == 0x5100)
    let members = result["3.1"] as! [OcaONo]
    #expect(members == [0x6100, 0x7100])
  }

  @Test
  func remapsScalarReferenceProperty() {
    let scalarClassID = _ReferenceScalarDeviceObject.classID

    let refProps: [String: Set<String>] = [
      scalarClassID.description: ["4.1"],
    ]

    let jsonObject: [String: Any] = [
      "_oNo": OcaONo(0x4000),
      "_classID": scalarClassID.description,
      "4.1": OcaONo(0x6000),
    ]

    let result = OcaProfile._remapObjectNumbers(
      in: jsonObject,
      referencePropertyIDs: refProps,
      transform: { $0 + 0x100 }
    ) as! [String: Any]

    #expect(result["_oNo"] as? OcaONo == 0x4100)
    #expect(result["4.1"] as? OcaONo == 0x6100)
  }

  @Test
  func doesNotRemapNonReferenceIntegerProperties() {
    let refProps: [String: Set<String>] = [
      Self.groupClassID.description: ["3.1"],
    ]

    let jsonObject: [String: Any] = [
      "_oNo": OcaONo(0x5000),
      "_classID": Self.groupClassID.description,
      "3.1": [OcaONo(0x6000)],
      "2.1": OcaONo(0x9999),
    ]

    let result = OcaProfile._remapObjectNumbers(
      in: jsonObject,
      referencePropertyIDs: refProps,
      transform: { $0 + 0x100 }
    ) as! [String: Any]

    // reference property remapped
    let members = result["3.1"] as! [OcaONo]
    #expect(members == [0x6100])

    // non-reference integer property left untouched
    #expect(result["2.1"] as? OcaONo == 0x9999)
  }

  @Test
  func doesNotRemapWhenClassIDMissing() {
    let refProps: [String: Set<String>] = [
      Self.groupClassID.description: ["3.1"],
    ]

    let jsonObject: [String: Any] = [
      "_oNo": OcaONo(0x5000),
      // no _classID — should not remap reference properties
      "3.1": [OcaONo(0x6000)],
    ]

    let result = OcaProfile._remapObjectNumbers(
      in: jsonObject,
      referencePropertyIDs: refProps,
      transform: { $0 + 0x100 }
    ) as! [String: Any]

    #expect(result["_oNo"] as? OcaONo == 0x5100)
    // without _classID, 3.1 is not recognized as a reference property
    let members = result["3.1"] as! [OcaONo]
    #expect(members == [0x6000])
  }

  @Test
  func doesNotRemapWhenClassIDDoesNotMatchSchema() {
    let refProps: [String: Set<String>] = [
      Self.groupClassID.description: ["3.1"],
    ]

    let jsonObject: [String: Any] = [
      "_oNo": OcaONo(0x5000),
      "_classID": "1.1.1.5",  // OcaGain, not a group
      "3.1": [OcaONo(0x6000)],
    ]

    let result = OcaProfile._remapObjectNumbers(
      in: jsonObject,
      referencePropertyIDs: refProps,
      transform: { $0 + 0x100 }
    ) as! [String: Any]

    #expect(result["_oNo"] as? OcaONo == 0x5100)
    let members = result["3.1"] as! [OcaONo]
    #expect(members == [0x6000])
  }

  @Test
  func remapsNestedReferenceProperties() {
    let refProps: [String: Set<String>] = [
      Self.groupClassID.description: ["3.1"],
    ]

    let jsonObject: [String: Any] = [
      "_oNo": OcaONo(0x1000),
      "_classID": "1.1.3",
      "3.2": [
        [
          "_oNo": OcaONo(0x5000),
          "_classID": Self.groupClassID.description,
          "3.1": [OcaONo(0x6000), OcaONo(0x7000)],
        ] as [String: Any],
        [
          "_oNo": OcaONo(0x6000),
          "_classID": "1.1.1.5",
          "4.1": OcaFloat32(-6.0),
        ] as [String: Any],
      ] as [[String: Any]],
    ]

    let result = OcaProfile._remapObjectNumbers(
      in: jsonObject,
      referencePropertyIDs: refProps,
      transform: { $0 + 0x100 }
    ) as! [String: Any]

    let actionObjects = result["3.2"] as! [[String: Any]]
    let groupObj = actionObjects[0]
    #expect(groupObj["_oNo"] as? OcaONo == 0x5100)
    let members = groupObj["3.1"] as! [OcaONo]
    #expect(members == [0x6100, 0x7100])

    let gainObj = actionObjects[1]
    #expect(gainObj["_oNo"] as? OcaONo == 0x6100)
    // gain's float property untouched
    #expect(gainObj["4.1"] as? OcaFloat32 == -6.0)
  }

  @Test
  func referencePropertyIDsByClassIDExtractsFromSchema() {
    let targetMatch = OcaONoMask(oNo: 0x6000, mask: 0xF0)
    let groupSchema = OcaProfileObjectSchema(
      role: "Group",
      declaredClassID: Self.groupClassID,
      declaredClassVersion: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>.classVersion,
      type: SwiftOCADevice.OcaGroup<SwiftOCADevice.OcaGain>.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x500, mask: 0),
      referenceProperties: [
        OcaPropertyID("3.1"): OcaProfileReferencePropertySchema(targetMatch: targetMatch),
      ]
    )
    let gainSchema = OcaProfileObjectSchema(
      role: "Gain",
      type: SwiftOCADevice.OcaGain.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x600, mask: 0)
    )
    let blockSchema = OcaProfileObjectSchema(
      role: "Block",
      declaredClassID: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classID,
      declaredClassVersion: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classVersion,
      type: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self,
      remoteObjectNumber: OcaONoMask(oNo: 0x400, mask: 0),
      actionObjectSchema: [gainSchema, groupSchema]
    )
    let profileSchema = OcaProfileSchema(name: "Test", blocks: [blockSchema])

    let lookup = OcaProfile._referencePropertyIDsByClassID(from: profileSchema)

    #expect(lookup[Self.groupClassID.description] == ["3.1"])
    // gain and block should not appear
    #expect(lookup[SwiftOCADevice.OcaGain.classID.description] == nil)
    #expect(lookup[SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classID.description] == nil)
  }

  @Test
  func emptyReferencePropertyIDsPreservesLegacyBehavior() {
    let jsonObject: [String: Any] = [
      "_oNo": OcaONo(0x1000),
      "_classID": "1.1.3",
      "4.1": OcaONo(999),
    ]

    // default (no referencePropertyIDs) should behave like the original function
    let result = OcaProfile._remapObjectNumbers(
      in: jsonObject,
      transform: { $0 + 1 }
    ) as! [String: Any]

    #expect(result["_oNo"] as? OcaONo == 0x1001)
    #expect(result["4.1"] as? OcaONo == 999) // untouched
  }
}
