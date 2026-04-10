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

/// Client-side proxy for the coordinator manager that manages profile lifecycle,
/// device discovery, and binding on the orchestrator device.
open class OcaCoordinator: SwiftOCA.OcaManager, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID(
    parent: super.classID,
    authority: PADLCompanyID,
    1
  ) }

  /// The identifiers of all devices currently discovered by the connection broker.
  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var currentDeviceIdentifiers: OcaListProperty<OcaString>.PropertyValue

  /// Timestamp of the most recent event processed by the coordinator; updated
  /// after the debounce interval and used to trigger persistence.
  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.12")
  )
  public var mostRecentEventTime: OcaProperty<OcaTime>.PropertyValue

  // MARK: - Profile management

  public struct AddProfileParameters: Ocp1ParametersReflectable, Sendable {
    public let schema: OcaString
    public let name: OcaString?

    public init(schema: OcaString, name: OcaString? = nil) {
      self.schema = schema
      self.name = name
    }
  }

  /// Creates a new profile for the given schema, returning its object number.
  /// An optional display name may be provided; if omitted, the profile is unnamed.
  public func addProfile(schema: String, name: String? = nil) async throws -> OcaONo {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.2"),
      parameters: AddProfileParameters(schema: schema, name: name)
    )
  }

  /// Sentinel value indicating the coordinator should automatically allocate a device index.
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

  /// Binds a profile to a device, optionally at a specific device index. If `index` is
  /// `nil`, the coordinator automatically allocates the next available index. If the
  /// device is already connected, the profile's proxy objects are activated immediately.
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

  /// Unbinds a profile from a device, deactivating its proxy objects and releasing
  /// the device index.
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

  /// Deletes a profile by its display name and schema.
  public func deleteProfile(named name: String, schema: String) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.5"),
      parameters: FindOrDeleteProfileByNameParameters(name: name, schema: schema)
    )
  }

  /// Deletes a profile by its UUID string.
  public func deleteProfile(uuid: String) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.6"),
      parameters: uuid
    )
  }

  /// Deletes a profile by its object number.
  public func deleteProfile(oNo: OcaONo) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.11"),
      parameters: oNo
    )
  }

  // MARK: - Profile lookup

  /// Looks up a profile by its display name and schema, returning its object number.
  public func findProfile(named name: String, schema: String) async throws -> OcaONo {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.7"),
      parameters: FindOrDeleteProfileByNameParameters(name: name, schema: schema)
    )
  }

  /// Looks up a profile by its UUID string, returning its object number.
  public func findProfile(uuid: String) async throws -> OcaONo {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.8"),
      parameters: uuid
    )
  }

  // MARK: - State import/export

  /// Exports the coordinator's complete profile state as a compressed archive blob.
  public func export() async throws -> OcaLongBlob {
    try await sendCommandRrq(methodID: OcaMethodID("3.9"))
  }

  /// Imports profile state from a previously exported compressed archive blob,
  /// recreating profiles and restoring their device bindings.
  public func `import`(from blob: OcaLongBlob) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("3.10"),
      parameters: blob
    )
  }
}
