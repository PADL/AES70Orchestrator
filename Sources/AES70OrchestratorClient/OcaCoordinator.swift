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

let PADLCompanyID = OcaOrganizationID((0x0A, 0xE9, 0x1B))

open class OcaCoordinator: SwiftOCA.OcaManager, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID(
    parent: super.classID,
    authority: PADLCompanyID,
    1
  ) }

  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var currentDeviceIdentifiers: OcaListProperty<OcaString>.PropertyValue

  // MARK: - Profile management

  public struct AddProfileParameters: Ocp1ParametersReflectable, Sendable {
    public let schema: OcaString
    public let name: OcaString?

    public init(schema: OcaString, name: OcaString? = nil) {
      self.schema = schema
      self.name = name
    }
  }

  public func addProfile(schema: String, name: String? = nil) async throws -> OcaONo {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.2"),
      parameters: AddProfileParameters(schema: schema, name: name)
    )
  }

  public static let AutoDeviceIndex: OcaUint16 = 0xFFFF

  public struct BindProfileParameters: Ocp1ParametersReflectable, Sendable {
    public let profileONo: OcaONo
    public let deviceIdentifier: OcaString
    public let deviceIndex: OcaUint16

    public init(profileONo: OcaONo, deviceIdentifier: OcaString, deviceIndex: OcaUint16) {
      self.profileONo = profileONo
      self.deviceIdentifier = deviceIdentifier
      self.deviceIndex = deviceIndex
    }
  }

  public func bind(
    profile profileONo: OcaONo,
    to deviceIdentifier: String,
    index: Int? = nil
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.3"),
      parameters: BindProfileParameters(
        profileONo: profileONo,
        deviceIdentifier: deviceIdentifier,
        deviceIndex: index.map { OcaUint16($0) } ?? Self.AutoDeviceIndex
      )
    )
  }

  public struct UnbindProfileParameters: Ocp1ParametersReflectable, Sendable {
    public let profileONo: OcaONo
    public let deviceIdentifier: OcaString

    public init(profileONo: OcaONo, deviceIdentifier: OcaString) {
      self.profileONo = profileONo
      self.deviceIdentifier = deviceIdentifier
    }
  }

  public func unbind(
    profile profileONo: OcaONo,
    from deviceIdentifier: String
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.4"),
      parameters: UnbindProfileParameters(
        profileONo: profileONo,
        deviceIdentifier: deviceIdentifier
      )
    )
  }

  // MARK: - Profile deletion

  public struct FindOrDeleteProfileByNameParameters: Ocp1ParametersReflectable, Sendable {
    public let name: OcaString
    public let schema: OcaString

    public init(name: OcaString, schema: OcaString) {
      self.name = name
      self.schema = schema
    }
  }

  public func deleteProfile(named name: String, schema: String) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.5"),
      parameters: FindOrDeleteProfileByNameParameters(name: name, schema: schema)
    )
  }

  public func deleteProfile(uuid: String) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.6"),
      parameters: uuid
    )
  }

  // MARK: - Profile lookup

  public func findProfile(named name: String, schema: String) async throws -> OcaONo {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.7"),
      parameters: FindOrDeleteProfileByNameParameters(name: name, schema: schema)
    )
  }

  public func findProfile(uuid: String) async throws -> OcaONo {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.8"),
      parameters: uuid
    )
  }

  // MARK: - State import/export

  public func exportState() async throws -> OcaLongBlob {
    try await sendCommandRrq(methodID: OcaMethodID("3.9"))
  }

  public func importState(from blob: OcaLongBlob) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.10"),
      parameters: blob
    )
  }
}
