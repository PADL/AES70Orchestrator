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

@OcaDevice
public final class OcaProfile: SwiftOCADevice.OcaAgent {
  override public class var classID: OcaClassID { OcaClassID(
    parent: super.classID,
    authority: PADLCompanyID,
    1
  ) }

  let profileIndex: OcaONo
  nonisolated let schemaName: String
  weak var coordinator: OcaCoordinator?

  override public nonisolated var description: String {
    "OcaProfile(oNo: \(objectNumber), index: \(profileIndex), schema: \(schemaName), role: \(role))"
  }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1"),
    setMethodID: OcaMethodID("3.2")
  )
  public var schema = ""

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.3")
    // setMethodID: OcaMethodID("3.4")
  )
  public var boundDevices = [String]()

  // maps device identifier to its allocated device index (not exposed via OCA)
  var deviceIndices = [SwiftOCA.OcaConnectionBroker.DeviceIdentifier: OcaONo]()

  // the proxy block in the "Profile Proxies" hierarchy for this profile's local objects
  var proxyBlock: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>?

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

  func remoteObjectCount(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) -> Int {
    objectBindings.values.filter { binding in
      binding.hasRemoteObject(for: deviceIdentifier)
    }.count
  }

  func handleLocalEvent(_ event: OcaEvent, parameters: Data) async {
    if let binding = objectBindings[event.emitterONo] {
      coordinator?.logger.debug(
        "handleLocalEvent: \(self) matched binding for ONo \(event.emitterONo)"
      )
      await binding.handleLocalEvent(event, parameters: parameters)
    }
  }

  // to allow for renames, we identify a profile by a UUID, where the label can be changed

  var profileSchema: OcaProfileSchema {
    get throws {
      guard let coordinator else { throw Ocp1Error.status(.deviceError) }
      return try coordinator.profileSchema(named: schema)
    }
  }

  init(
    role: UUID,
    objectNumber: OcaONo,
    profileIndex: OcaONo,
    schema: String,
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
  }

  func objectNumber(for oNoMask: OcaONoMask?) throws -> OcaONo? {
    try oNoMask?.objectNumber(for: profileIndex)
  }

  @OcaDevice
  func createLocalObjects(
    proxyBlock: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>
  ) async throws {
    guard let coordinator else { throw Ocp1Error.status(.deviceError) }
    let schema = try profileSchema

    var blocks = [[String]: any _OcaBlockContainer]()

    for block in schema.blocks {
      try await block.applyRecursive { objectSchema, rolePath, parentRolePath in
        let oNo = try self.objectNumber(for: objectSchema.localObjectNumber)
        let object = try await objectSchema.createLocalObject(
          objectNumber: oNo,
          deviceDelegate: coordinator.device
        )

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
          profile: self
        ), for: object.objectNumber)
      }
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
