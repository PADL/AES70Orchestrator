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
@_spi(SwiftOCAPrivate) import SwiftOCADevice
import Yams

extension OcaDeviceSchema {
  @OcaDevice
  public init(yaml: String) throws {
    guard let doc = try Yams.compose(yaml: yaml),
          let device = doc.mapping?["device"]
    else {
      throw OcaCoordinatorError.schemaParseError("missing top-level 'device' key")
    }

    guard let name = device.mapping?["name"]?.string else {
      throw OcaCoordinatorError.schemaParseError("missing device name")
    }

    let models = try device.mapping?["models"]?.sequence?.map { node -> OcaModelGUID in
      let hexString = try Self._parseHexString(node)
      return try OcaModelGUID(hexString)
    }

    guard let profileNodes = device.mapping?["profiles"]?.sequence else {
      throw OcaCoordinatorError.schemaParseError("missing profiles array")
    }

    var profileSchemas = [OcaProfileSchema]()
    for node in profileNodes {
      try profileSchemas.append(Self._parseProfileSchema(node))
    }

    self.init(name: name, models: models, profileSchemas: profileSchemas)
  }

  private static func _parseHexString(_ node: Node) throws -> String {
    // Yams may parse 0xHEX as an integer or as a string
    if let intValue = node.int {
      var hex = String(intValue, radix: 16, uppercase: true)
      if hex.count % 2 != 0 { hex = "0" + hex }
      return hex
    }
    guard var string = node.string else {
      throw OcaCoordinatorError.schemaParseError("expected hex string or integer")
    }
    if string.hasPrefix("0x") || string.hasPrefix("0X") {
      string = String(string.dropFirst(2))
    }
    return string
  }

  @OcaDevice
  private static func _parseProfileSchema(_ node: Node) throws -> OcaProfileSchema {
    guard let mapping = node.mapping, mapping.count == 1,
          let (nameNode, blocksNode) = mapping.first
    else {
      throw OcaCoordinatorError
        .schemaParseError("profile must be a single-key mapping {name: [blocks]}")
    }
    guard let name = nameNode.string else {
      throw OcaCoordinatorError.schemaParseError("profile name must be a string")
    }
    guard let blockSequence = blocksNode.sequence else {
      throw OcaCoordinatorError
        .schemaParseError("profile '\(name)' value must be a sequence of blocks")
    }
    var blocks = [OcaProfileObjectSchema]()
    for node in blockSequence {
      try blocks.append(_parseObjectSchema(node))
    }
    return OcaProfileSchema(name: name, blocks: blocks)
  }

  @OcaDevice
  private static func _parseObjectSchema(_ node: Node) throws -> OcaProfileObjectSchema {
    guard let mapping = node.mapping, mapping.count == 1,
          let (roleNode, propsNode) = mapping.first
    else {
      throw OcaCoordinatorError
        .schemaParseError("object schema must be a single-key mapping {role: {props}}")
    }
    guard let role = roleNode.string else {
      throw OcaCoordinatorError.schemaParseError("object role must be a string")
    }

    let props = propsNode.mapping

    // parse children first to determine if this is a container
    var actionObjects = [OcaProfileObjectSchema]()
    if let actionObjectNodes = props?["actionObjects"]?.sequence {
      for child in actionObjectNodes {
        try actionObjects.append(_parseObjectSchema(child))
      }
    }

    // resolve type from classID via registry, or infer
    let type: SwiftOCADevice.OcaRoot.Type
    if let classIDString = props?["classID"]?.string {
      let classID = OcaClassID(classIDString)
      type = try OcaDeviceClassRegistry.shared.match(classID: classID)
    } else if !actionObjects.isEmpty {
      type = SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaRoot>.self
    } else {
      type = SwiftOCADevice.OcaRoot.self
    }

    // parse remote object number (match)
    guard let matchString = props?["match"]?.string else {
      throw OcaCoordinatorError
        .schemaParseError("object '\(role)' missing 'match' (remote object number)")
    }
    let remoteObjectNumber = try OcaONoMask(matchString)

    // parse optional local object number
    var localObjectNumber: OcaONoMask?
    if let oNoString = props?["objectNumber"]?.string {
      localObjectNumber = try OcaONoMask(oNoString)
    }

    return OcaProfileObjectSchema(
      role: role,
      type: type,
      localObjectNumber: localObjectNumber,
      remoteObjectNumber: remoteObjectNumber,
      actionObjectSchema: actionObjects
    )
  }
}
