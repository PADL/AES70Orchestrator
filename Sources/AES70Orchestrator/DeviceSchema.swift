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

  public let profileSchemas: [OcaProfileSchema]

  public var description: String {
    "OcaDeviceSchema(name: \(name), schemas: \(profileSchemas.map(\.name)))"
  }

  public init(
    name: String,
    models: [OcaModelGUID]? = nil,
    profileSchemas: [OcaProfileSchema]
  ) {
    self.name = name
    self.models = models
    self.profileSchemas = profileSchemas
  }
}
