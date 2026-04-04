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
  private static func _node(in mapping: Node.Mapping?, keys: [String]) -> Node? {
    guard let mapping else { return nil }
    for key in keys {
      if let node = mapping[key] {
        return node
      }
    }
    return nil
  }

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

    let paramSetInitialSync =
      Self._node(
        in: device.mapping,
        keys: ["param-set-initial-sync", "paramSetInitialSync"]
      )?.bool ?? false

    guard let profileNodes = device.mapping?["profiles"]?.sequence else {
      throw OcaCoordinatorError.schemaParseError("missing profiles array")
    }

    var profileSchemas = [OcaProfileSchema]()
    for node in profileNodes {
      try profileSchemas.append(Self._parseProfileSchema(node))
    }

    self.init(
      name: name,
      models: models,
      paramSetInitialSync: paramSetInitialSync,
      profileSchemas: profileSchemas
    )
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

  private static func _parseReferencePropertySchema(
    propertyID: OcaPropertyID,
    node: Node
  ) throws -> OcaProfileReferencePropertySchema {
    if let string = node.string {
      return OcaProfileReferencePropertySchema(targetMatch: try OcaONoMask(string))
    }

    guard let mapping = node.mapping else {
      throw OcaCoordinatorError.schemaParseError(
        "reference property '\(propertyID)' must be a string or mapping"
      )
    }
    guard let targetMatchString = Self._node(in: mapping, keys: ["target-match", "targetMatch"])?
      .string
    else {
      throw OcaCoordinatorError.schemaParseError(
        "reference property '\(propertyID)' missing 'target-match'"
      )
    }

    return OcaProfileReferencePropertySchema(targetMatch: try OcaONoMask(targetMatchString))
  }

  private static func _parsePropertyDefaults(
    _ node: Node?
  ) throws -> [OcaPropertyID: [String: any Sendable]] {
    guard let mapping = node?.mapping else { return [:] }

    var defaults = [OcaPropertyID: [String: any Sendable]]()
    for (propertyNode, valueNode) in mapping {
      guard let propertyString = propertyNode.string else {
        throw OcaCoordinatorError.schemaParseError(
          "property-defaults key must be a property ID string"
        )
      }
      let propertyID = try OcaPropertyID(unsafeString: propertyString)

      guard let valueMapping = valueNode.mapping else {
        throw OcaCoordinatorError.schemaParseError(
          "property-defaults value for '\(propertyString)' must be a mapping"
        )
      }

      var dict = [String: any Sendable]()
      for (key, val) in valueMapping {
        guard let keyString = key.string else { continue }
        if let doubleValue = val.float {
          dict[keyString] = doubleValue
        } else if let intValue = val.int {
          dict[keyString] = Double(intValue)
        } else if let boolValue = val.bool {
          dict[keyString] = boolValue
        } else if let stringValue = val.string {
          dict[keyString] = stringValue
        }
      }
      defaults[propertyID] = dict
    }
    return defaults
  }

  private static func _parseReferenceProperties(
    _ node: Node?
  ) throws -> [OcaPropertyID: OcaProfileReferencePropertySchema] {
    guard let mapping = node?.mapping else { return [:] }

    var referenceProperties = [OcaPropertyID: OcaProfileReferencePropertySchema]()
    for (propertyNode, valueNode) in mapping {
      guard let propertyString = propertyNode.string else {
        throw OcaCoordinatorError.schemaParseError(
          "reference property identifier must be a string"
        )
      }

      let propertyID = try OcaPropertyID(unsafeString: propertyString)
      referenceProperties[propertyID] = try _parseReferencePropertySchema(
        propertyID: propertyID,
        node: valueNode
      )
    }

    return referenceProperties
  }

  @OcaDevice
  private static func _parseProfileSchema(_ node: Node) throws -> OcaProfileSchema {
    guard let mapping = node.mapping, mapping.count == 1,
          let (nameNode, valueNode) = mapping.first
    else {
      throw OcaCoordinatorError
        .schemaParseError("profile must be a single-key mapping {name: [blocks]}")
    }
    guard let name = nameNode.string else {
      throw OcaCoordinatorError.schemaParseError("profile name must be a string")
    }

    let blockSequence: Node.Sequence

    if let sequence = valueNode.sequence {
      blockSequence = sequence
    } else if let valueMapping = valueNode.mapping {
      guard let seq = valueMapping["blocks"]?.sequence else {
        throw OcaCoordinatorError
          .schemaParseError("profile '\(name)' mapping must contain 'blocks' sequence")
      }
      blockSequence = seq
    } else {
      throw OcaCoordinatorError
        .schemaParseError("profile '\(name)' value must be a sequence of blocks or a mapping")
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
    if let actionObjectNodes = Self._node(in: props, keys: ["action-objects", "actionObjects", "members"])?
      .sequence
    {
      for child in actionObjectNodes {
        try actionObjects.append(_parseObjectSchema(child))
      }
    }

    // resolve type from classID via registry, or infer
    let declaredClassID = Self._node(in: props, keys: ["class-id", "classID"])?
      .string
      .map { OcaClassID($0) }
    let declaredClassVersion = Self._node(in: props, keys: ["class-version", "classVersion"])?
      .int
      .map(OcaClassVersionNumber.init)

    let type: SwiftOCADevice.OcaRoot.Type
    if let classID = declaredClassID {
      type = try OcaDeviceClassRegistry.shared.match(
        classIdentification: OcaClassIdentification(
          classID: classID,
          classVersion: declaredClassVersion ?? SwiftOCA.OcaRoot.classVersion
        )
      )
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
    if let oNoString = Self._node(in: props, keys: ["object-number", "objectNumber", "ono", "oNo"])?.string {
      localObjectNumber = try OcaONoMask(oNoString)
    }

    let lockRemote = Self._node(in: props, keys: ["lock-remote", "lockRemote"])?.bool ?? false
    let remoteFollowerOnly =
      Self._node(in: props, keys: ["remote-follower-only", "remoteFollowerOnly"])?.bool ?? false

    let includeProperties: Set<OcaPropertyID>? =
      if let seq = Self._node(in: props, keys: ["include-props", "includeProperties"])?.sequence {
        Set(seq.compactMap { $0.string.map { OcaPropertyID($0) } })
      } else {
        nil
      }

    var excludeProperties = Set<OcaPropertyID>()
    if let seq = Self._node(in: props, keys: ["exclude-props", "excludeProperties"])?.sequence {
      excludeProperties = Set(seq.compactMap { $0.string.map { OcaPropertyID($0) } })
    }

    let referenceProperties = try _parseReferenceProperties(
      Self._node(in: props, keys: ["reference-props", "referenceProperties"])
    )

    let propertyDefaults = try _parsePropertyDefaults(
      Self._node(in: props, keys: ["property-defaults", "propertyDefaults"])
    )

    return OcaProfileObjectSchema(
      role: role,
      declaredClassID: declaredClassID,
      declaredClassVersion: declaredClassVersion,
      type: type,
      localObjectNumber: localObjectNumber,
      remoteObjectNumber: remoteObjectNumber,
      lockRemote: lockRemote,
      remoteFollowerOnly: remoteFollowerOnly,
      includeProperties: includeProperties,
      excludeProperties: excludeProperties,
      referenceProperties: referenceProperties,
      propertyDefaults: propertyDefaults,
      actionObjectSchema: actionObjects
    )
  }
}
