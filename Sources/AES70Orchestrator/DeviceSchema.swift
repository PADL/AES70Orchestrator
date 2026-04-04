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

/// A top-level schema describing a device class, including the hardware models it targets
/// and the profile schemas available for that device.
public struct OcaDeviceSchema: Sendable, CustomStringConvertible {
  public let name: String

  public let models: [OcaModelGUID]?

  /// When enabled, initial property synchronization at bind time uses the
  /// SwiftOCADevice parameter-dataset serialization format (a gzip'd JSON blob)
  /// instead of copying properties individually. This is faster but assumes the
  /// remote device uses the same SwiftOCA implementation; the param-set format
  /// is implementation-dependent.
  public let paramSetInitialSync: Bool

  public let profileSchemas: [OcaProfileSchema]

  public var description: String {
    "OcaDeviceSchema(name: \(name), schemas: \(profileSchemas.map(\.name)))"
  }

  public init(
    name: String,
    models: [OcaModelGUID]? = nil,
    paramSetInitialSync: Bool = false,
    profileSchemas: [OcaProfileSchema]
  ) {
    self.name = name
    self.models = models
    self.paramSetInitialSync = paramSetInitialSync
    self.profileSchemas = profileSchemas
  }
}
