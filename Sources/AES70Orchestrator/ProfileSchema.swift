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

public struct OcaONoMask: Sendable, Equatable, CustomStringConvertible {
  public let oNo: OcaONo
  public let mask: OcaONo

  public init(oNo: OcaONo, mask: OcaONo) {
    self.oNo = oNo
    self.mask = mask
  }

  public var instanceCount: Int {
    guard mask != 0 else { return 0 }
    let shifted = mask >> mask.trailingZeroBitCount
    let onesCount = (~shifted).trailingZeroBitCount
    assert(shifted == (1 << onesCount) &- 1, "mask bits must be contiguous")
    return onesCount
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
    guard index < (1 << instanceCount) else {
      throw OcaCoordinatorError.profileONoAllocationExhausted
    }
    return oNo | (index << mask.trailingZeroBitCount)
  }
}

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
    guard let localObjectNumber else { return 0 }
    return 1 << localObjectNumber.instanceCount
  }

  // the remote object number(s). the bits set in the mask determine how many profiles can be bound
  // to a single device.
  public let remoteObjectNumber: OcaONoMask

  public var remoteObjectCount: Int {
    1 << remoteObjectNumber.instanceCount
  }

  public var isContainer: Bool {
    type.classIdentification
      .isSubclass(of: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classIdentification)
  }

  public var isLeaf: Bool { !isContainer }

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
    actionObjectSchema: [Self] = []
  ) {
    self.role = role
    self.type = type
    self.localObjectNumber = localObjectNumber
    self.remoteObjectNumber = remoteObjectNumber
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
}

public final class OcaProfileSchema: Sendable, CustomStringConvertible {
  public let name: String
  public let blocks: [OcaProfileObjectSchema]

  public var description: String {
    "OcaProfileSchema(name: \(name), blocks: \(blocks.count))"
  }

  public init(name: String, blocks: [OcaProfileObjectSchema]) {
    self.name = name
    self.blocks = blocks
  }
}
