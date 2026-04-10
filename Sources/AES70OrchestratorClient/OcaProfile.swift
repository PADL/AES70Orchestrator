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

/// Client-side proxy for a profile instance. Each profile is bound to one or more
/// remote devices and manages a set of local proxy objects that mirror remote device objects.
open class OcaProfile: SwiftOCA.OcaAgent, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID(
    parent: super.classID,
    authority: PADLCompanyID,
    1
  ) }

  /// The name of the profile schema this profile was created from.
  @OcaProperty(
    propertyID: OcaPropertyID("3.1"),
    getMethodID: OcaMethodID("3.1")
  )
  public var schema: OcaProperty<OcaString>.PropertyValue

  /// The device identifiers this profile is currently bound to.
  @OcaProperty(
    propertyID: OcaPropertyID("3.2"),
    getMethodID: OcaMethodID("3.3")
  )
  public var boundDevices: OcaListProperty<OcaString>.PropertyValue

  /// Maps each bound device identifier to its allocated device index. The device index
  /// selects which instance slot is used when the profile schema's remote object number
  /// mask supports multiple concurrent bindings to the same device.
  @OcaProperty(
    propertyID: OcaPropertyID("3.3"),
    getMethodID: OcaMethodID("3.4")
  )
  public var boundDeviceIndices: OcaMapProperty<OcaString, OcaONo>.PropertyValue
}
