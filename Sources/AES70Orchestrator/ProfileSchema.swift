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

import SwiftOCA
import SwiftOCADevice

/// A struct that pairs a base OCA object number with a bitmask. The mask bits determine
/// how many instances can be numbered within the base object number. For example,
/// `OcaONoMask(oNo: 0x100, mask: 0x0F)` allows 16 instances (0x100–0x10F).
public struct OcaONoMask: Sendable, Equatable, CustomStringConvertible {
  public let oNo: OcaONo
  public let mask: OcaONo

  public init(oNo: OcaONo, mask: OcaONo) {
    self.oNo = oNo
    self.mask = mask
  }

  public var instanceCount: Int {
    get throws {
      guard mask != 0 else { return 1 }

      let shifted = mask >> mask.trailingZeroBitCount
      let bitCount = (~shifted).trailingZeroBitCount

      guard shifted == (1 << bitCount) &- 1 else {
        throw OcaCoordinatorError.schemaParseError("mask bits must be contiguous")
      }

      return 1 << bitCount
    }
  }

  public var description: String {
    "0x\(String(oNo, radix: 16))/0x\(String(mask, radix: 16))"
  }

  public init(_ string: String) throws {
    let parts = string.split(separator: "/")
    guard parts.count == 2 else {
      throw OcaCoordinatorError.schemaParseError("invalid OcaONoMask format: \(string)")
    }
    guard let oNo = OcaONo(parts[0].dropFirst(2), radix: 16) else {
      throw OcaCoordinatorError.schemaParseError("invalid oNo hex value: \(parts[0])")
    }
    guard let mask = OcaONo(parts[1].dropFirst(2), radix: 16) else {
      throw OcaCoordinatorError.schemaParseError("invalid mask hex value: \(parts[1])")
    }
    self.oNo = oNo
    self.mask = mask
  }

  func objectNumber(for index: OcaONo) throws -> OcaONo {
    guard try index < instanceCount else {
      throw OcaCoordinatorError.profileONoAllocationExhausted
    }
    return oNo | (index << mask.trailingZeroBitCount)
  }

  /// Returns the base ONo with profile index bits cleared.
  func maskedObjectNumber(for objectNumber: OcaONo) -> OcaONo {
    objectNumber & ~mask
  }
}

/// Describes a single object within a profile schema, specifying its role name, OCA class type,
/// optional local object number allocation, remote object number matching pattern, and any
/// nested action objects for container types.
public struct OcaProfileObjectSchema: Sendable, CustomStringConvertible {
  public let role: String

  // the OCA class ID for the profile entry
  public let type: SwiftOCADevice.OcaRoot.Type

  // the local number(s). the bits set in the mask determine which bits are free for numbering
  // instances of the object. if optional, then they are allocated by the
  // device (next is assigned).
  public let localObjectNumber: OcaONoMask?

  // the number of instances that can be instantiated locally
  public var localInstanceCount: Int {
    get throws {
      guard let localObjectNumber else { return 0 }
      return try localObjectNumber.instanceCount
    }
  }

  // the remote object number(s). the bits set in the mask determine how many profiles can be bound
  // to a single device.
  public let remoteObjectNumber: OcaONoMask

  public var remoteObjectCount: Int {
    get throws {
      try remoteObjectNumber.instanceCount
    }
  }

  public var isContainer: Bool {
    type.classIdentification
      .isSubclass(of: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classIdentification)
  }

  public var isLeaf: Bool { !isContainer }

  // if true, the remote object is locked when bound and unlocked when unbound
  public let lockRemote: Bool

  public let actionObjectSchema: [Self]

  public var description: String {
    let children = actionObjectSchema.isEmpty ? "" : ", children: \(actionObjectSchema.count)"
    return "OcaProfileObjectSchema(role: \(role), type: \(type), remote: \(remoteObjectNumber)\(children))"
  }

  public init(
    role: String,
    type: SwiftOCADevice.OcaRoot.Type,
    localObjectNumber: OcaONoMask? = nil,
    remoteObjectNumber: OcaONoMask,
    lockRemote: Bool = false,
    actionObjectSchema: [Self] = []
  ) {
    self.role = role
    self.type = type
    self.localObjectNumber = localObjectNumber
    self.remoteObjectNumber = remoteObjectNumber
    self.lockRemote = lockRemote
    self.actionObjectSchema = actionObjectSchema
  }

  func createLocalObject(
    objectNumber: OcaONo? = nil,
    deviceDelegate: OcaDevice?
  ) async throws -> SwiftOCADevice.OcaRoot {
    try await type.init(
      objectNumber: objectNumber,
      role: role,
      deviceDelegate: deviceDelegate,
      addToRootBlock: false
    )
  }

  func applyRecursive(
    parentRolePath: [String] = [],
    _ body: (
      _ schema: OcaProfileObjectSchema,
      _ rolePath: [String],
      _ parentRolePath: [String]?
    ) async throws -> ()
  ) async rethrows {
    let rolePath = parentRolePath + [role]
    try await body(self, rolePath, parentRolePath.isEmpty ? nil : parentRolePath)
    guard isContainer, !actionObjectSchema.isEmpty else { return }
    for child in actionObjectSchema {
      try await child.applyRecursive(parentRolePath: rolePath, body)
    }
  }

  func applyRecursive(
    parentRolePath: [String] = [],
    _ body: (
      _ schema: OcaProfileObjectSchema,
      _ rolePath: [String],
      _ parentRolePath: [String]?
    ) throws -> ()
  ) rethrows {
    let rolePath = parentRolePath + [role]
    try body(self, rolePath, parentRolePath.isEmpty ? nil : parentRolePath)
    guard isContainer, !actionObjectSchema.isEmpty else { return }
    for child in actionObjectSchema {
      try child.applyRecursive(parentRolePath: rolePath, body)
    }
  }
}

/// A named profile schema consisting of one or more top-level block definitions. When
/// `automaticallyBind` is set, profiles of this schema are automatically bound to all
/// discovered devices and only a single profile instance is permitted.
public final class OcaProfileSchema: Sendable, CustomStringConvertible {
  public let name: String
  public let blocks: [OcaProfileObjectSchema]
  public let automaticallyBind: Bool

  public var description: String {
    "OcaProfileSchema(name: \(name), blocks: \(blocks.count), autobind: \(automaticallyBind))"
  }

  public init(name: String, blocks: [OcaProfileObjectSchema], automaticallyBind: Bool = false) {
    self.name = name
    self.blocks = blocks
    self.automaticallyBind = automaticallyBind
  }
}
