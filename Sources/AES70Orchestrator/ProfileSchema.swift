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

public struct OcaONoMask: Sendable, Equatable {
  public let oNo: OcaONo
  public let mask: OcaONo

  public var instanceCount: Int {
    guard mask != 0 else { return 0 }
    let shifted = mask >> mask.trailingZeroBitCount
    let onesCount = (~shifted).trailingZeroBitCount
    assert(shifted == (1 << onesCount) &- 1, "mask bits must be contiguous")
    return onesCount
  }

  func objectNumber(for index: OcaONo) throws -> OcaONo {
    guard index < (1 << instanceCount) else {
      throw OcaCoordinatorError.profileONoAllocationExhausted
    }
    return oNo | (index << mask.trailingZeroBitCount)
  }
}

public struct OccProfileObjectSchema: Sendable {
  public let role: String

  // the OCA class ID for the profile entry
  public let type: SwiftOCADevice.OcaRoot.Type

  // the optional global type identifier
  public let globalType: OcaGlobalTypeIdentifier?

  // the local number(s). the bits set in the mask determine which bits are free for numbering
  // instances of the object. if optional, then they are allocated by the
  // device (next is assigned).
  public let localObjectNumber: OcaONoMask?

  // the number of instances that can be instantiated locally
  public var localInstanceCount: Int {
    localObjectNumber?.instanceCount ?? 0
  }

  // the remote object number(s). the bits set in the mask determine how many profiles can be bound
  // to a single device.
  public let remoteObjectNumber: OcaONoMask

  public var remoteObjectCount: Int {
    remoteObjectNumber.instanceCount
  }

  public var isContainer: Bool {
    type.classIdentification
      .isSubclass(of: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.classIdentification)
  }

  public var isLeaf: Bool { !isContainer }

  public let actionObjectSchema: [Self]

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
      _ schema: OccProfileObjectSchema,
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

public final class OcaProfileSchema: Sendable {
  public let name: String
  public let blocks: [OccProfileObjectSchema]

  public init(name: String, blocks: [OccProfileObjectSchema]) {
    self.name = name
    self.blocks = blocks
  }
}
