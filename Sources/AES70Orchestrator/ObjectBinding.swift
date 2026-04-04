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
@_spi(SwiftOCAPrivate) import SwiftOCA
@_spi(SwiftOCAPrivate) import SwiftOCADevice

private final class _CapturedPropertyValues: @unchecked Sendable {
  var values = [(OcaPropertyID, any Codable & Sendable)]()
}

/// Type-erased protocol for object bindings, allowing the profile to dispatch events
/// and manage remote object lifecycle without knowing the concrete local/remote types.
@OcaDevice
protocol OcaObjectBindingRepresentable: Sendable {
  func handleLocalEvent(_ event: OcaEvent, parameters: Data) async
  func hasRemoteObject(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) -> Bool
  func forgetRemoteObject(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  )
  func bind(
    remoteObject: SwiftOCA.OcaRoot,
    from remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws
  func subscribe(
    to remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws
  func unbind(
    remoteObject: SwiftOCA.OcaRoot,
    from remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws
}

/// Binds a local proxy object to its corresponding remote objects on one or more devices,
/// forwarding property changes and events bidirectionally between them.
@OcaDevice
public final class OcaObjectBinding<
  Local: SwiftOCADevice.OcaRoot,
  Remote: SwiftOCA.OcaRoot
>: OcaObjectBindingRepresentable, Sendable {
  let localObject: Local
  let flags: OcaProfileObjectFlags
  let includeProperties: Set<OcaPropertyID>?
  let excludeProperties: Set<OcaPropertyID>
  let referenceProperties: [OcaPropertyID: OcaProfileReferencePropertySchema]
  var remoteObjects = [SwiftOCA.OcaConnectionBroker.DeviceIdentifier: Remote]()
  var remoteSubscriptions =
    [SwiftOCA.OcaConnectionBroker.DeviceIdentifier: Ocp1Connection.SubscriptionCancellable]()
  weak var profile: OcaProfile?
  private var _forwardingFromRemote = false

  private static var _lockStatePropertyID: OcaPropertyID { OcaPropertyID("1.6") }

  private var lockRemote: Bool {
    flags.contains(.lockRemote)
  }

  private var remoteFollowerOnly: Bool {
    flags.contains(.remoteFollowerOnly)
  }

  private func _shouldForwardProperty(_ propertyID: OcaPropertyID) -> Bool {
    if let includeProperties {
      guard includeProperties.contains(propertyID) else { return false }
    }
    return !excludeProperties.contains(propertyID)
  }

  public init(
    localObject: Local,
    profile: OcaProfile,
    flags: OcaProfileObjectFlags = [],
    includeProperties: Set<OcaPropertyID>? = nil,
    excludeProperties: Set<OcaPropertyID> = [],
    referenceProperties: [OcaPropertyID: OcaProfileReferencePropertySchema] = [:]
  ) {
    self.localObject = localObject
    self.flags = flags
    self.includeProperties = includeProperties
    self.excludeProperties = excludeProperties
    self.referenceProperties = referenceProperties
    self.profile = profile
    profile.addObjectBinding(self, for: localObject.objectNumber)
  }

  deinit {
    let localObjectNumber = localObject.objectNumber
    guard let profile else { return }
    Task { @OcaDevice in profile.removeObjectBinding(for: localObjectNumber) }
  }

  func hasRemoteObject(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) -> Bool {
    guard let remoteObject = remoteObjects[deviceIdentifier] else {
      return false
    }

    guard remoteObject.connectionDelegate != nil else {
      forgetRemoteObject(for: deviceIdentifier)
      return false
    }

    return true
  }

  func forgetRemoteObject(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) {
    remoteObjects.removeValue(forKey: deviceIdentifier)
    remoteSubscriptions.removeValue(forKey: deviceIdentifier)
  }

  private func _remapEventDataForRemote(
    _ eventData: OcaAnyPropertyChangedEventData,
    deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) throws -> OcaAnyPropertyChangedEventData {
    guard let profile,
          let referenceProperty = referenceProperties[eventData.propertyID],
          let deviceIndex = profile.deviceIndices[deviceIdentifier]
    else {
      return eventData
    }

    return OcaAnyPropertyChangedEventData(
      propertyID: eventData.propertyID,
      propertyValue: try profile.remapReferencePropertyDataToRemote(
        eventData.propertyValue,
        targetMatch: referenceProperty.targetMatch,
        deviceIndex: deviceIndex,
        deviceIdentifier: deviceIdentifier
      ),
      changeType: eventData.changeType
    )
  }

  private func _remapEventDataForLocal(
    _ eventData: OcaAnyPropertyChangedEventData,
    deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) throws -> OcaAnyPropertyChangedEventData {
    guard let profile,
          let referenceProperty = referenceProperties[eventData.propertyID],
          let deviceIndex = profile.deviceIndices[deviceIdentifier]
    else {
      return eventData
    }

    return OcaAnyPropertyChangedEventData(
      propertyID: eventData.propertyID,
      propertyValue: try profile.remapReferencePropertyDataToLocal(
        eventData.propertyValue,
        targetMatch: referenceProperty.targetMatch,
        deviceIndex: deviceIndex
      ),
      changeType: eventData.changeType
    )
  }

  private func _applyReferencePropertyToLocal(
    _ eventData: OcaAnyPropertyChangedEventData
  ) async throws {
    let propertyValue: any Sendable

    if let onos = try? Ocp1Decoder().decode([OcaONo].self, from: eventData.propertyValue) {
      propertyValue = onos
    } else if let oNo = try? Ocp1Decoder().decode(OcaONo.self, from: eventData.propertyValue) {
      propertyValue = oNo
    } else {
      throw Ocp1Error.status(.badFormat)
    }

    try await localObject.deserialize(
      jsonObject: [
        "_oNo": localObject.objectNumber,
        "_classID": type(of: localObject).classID.description,
        eventData.propertyID.description: propertyValue,
      ],
      flags: [.ignoreMissingProperties]
    )
  }

  private func _copyProperties(
    to remoteObject: Remote,
    remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws {
    guard !referenceProperties.isEmpty || includeProperties != nil || !excludeProperties.isEmpty
    else {
      try await localObject.copyProperties(to: remoteObject)
      return
    }

    let capturedValues = _CapturedPropertyValues()
    let lockRemote = self.lockRemote
    let lockStatePropertyID = Self._lockStatePropertyID
    let includeProperties = self.includeProperties
    let excludeProperties = self.excludeProperties
    _ = try localObject.serialize(flags: [.ignoreEncodingErrors]) { [capturedValues] _, propertyID, value in
      if lockRemote, propertyID == lockStatePropertyID {
        return .ignore
      }
      if let includeProperties, !includeProperties.contains(propertyID) {
        return .ignore
      }
      if excludeProperties.contains(propertyID) {
        return .ignore
      }
      capturedValues.values.append((propertyID, value))
      return .ignore
    }

    for (propertyID, value) in capturedValues.values {
      let encodedValue: Data
      do {
        encodedValue = try Ocp1Encoder().encode(value)
      } catch {
        continue
      }

      let eventData = OcaAnyPropertyChangedEventData(
        propertyID: propertyID,
        propertyValue: encodedValue,
        changeType: .currentChanged
      )
      let remoteEvent = OcaEvent(
        emitterONo: remoteObject.objectNumber,
        eventID: OcaPropertyChangedEventID
      )
      let remappedEventData = try _remapEventDataForRemote(eventData, deviceIdentifier: remoteDevice)
      if referenceProperties[propertyID] != nil || propertyID == OcaPropertyID("3.1") {
        if let onos = try? Ocp1Decoder().decode([OcaONo].self, from: remappedEventData.propertyValue) {
          profile?.coordinator?.logger.trace(
            "bind copy: local \(localObject.objectNumber) -> remote \(remoteObject.objectNumber) property \(propertyID) remoteONos=\(onos)"
          )
        } else if let oNo = try? Ocp1Decoder().decode(OcaONo.self, from: remappedEventData.propertyValue) {
          profile?.coordinator?.logger.trace(
            "bind copy: local \(localObject.objectNumber) -> remote \(remoteObject.objectNumber) property \(propertyID) remoteONo=\(oNo)"
          )
        } else {
          profile?.coordinator?.logger.trace(
            "bind copy: local \(localObject.objectNumber) -> remote \(remoteObject.objectNumber) property \(propertyID) bytes=\(remappedEventData.propertyValue.count)"
          )
        }
      }
      try await remoteObject.forward(
        event: remoteEvent,
        eventData: remappedEventData
      )
    }
  }

  // handle a local event propagated from the OcaDevice's global onEvent handler; this should
  // forward to all the remote devices
  @OcaDevice
  func handleLocalEvent(_ event: OcaEvent, parameters: Data) async {
    guard !_forwardingFromRemote else { return }
    guard let eventData = try? OcaPropertyChangedEventData<Data>(data: parameters) else {
      profile?.coordinator?.logger.warning(
        "handleLocalEvent: failed to decode event data for ONo \(event.emitterONo)"
      )
      return
    }

    if lockRemote, eventData.propertyID == Self._lockStatePropertyID { return }
    guard _shouldForwardProperty(eventData.propertyID) else { return }

    profile?.coordinator?.logger.trace(
      "handleLocalEvent: forwarding propertyID \(eventData.propertyID) to \(remoteObjects.count) remote object(s)"
    )
    for (deviceID, remoteObject) in remoteObjects {
      guard remoteObject.connectionDelegate != nil else {
        forgetRemoteObject(for: deviceID)
        profile?.coordinator?.logger.trace(
          "handleLocalEvent: dropped stale remote object for \(deviceID)"
        )
        continue
      }

      let remoteEvent = OcaEvent(emitterONo: remoteObject.objectNumber, eventID: event.eventID)
      do {
        try await remoteObject.forward(
          event: remoteEvent,
          eventData: try _remapEventDataForRemote(eventData, deviceIdentifier: deviceID)
        )
      } catch Ocp1Error.noConnectionDelegate {
        forgetRemoteObject(for: deviceID)
        profile?.coordinator?.logger.trace(
          "handleLocalEvent: dropped stale remote object for \(deviceID) after missing connection delegate"
        )
      } catch {
        profile?.coordinator?.logger.warning(
          "handleLocalEvent: failed to forward to \(deviceID): \(error)"
        )
      }
    }
  }

  // handle a remote event from a subscription. this should forward to all the _other_ remote
  // objects and the local object
  private func handleRemoteEvent(
    _ event: OcaEvent,
    parameters: Data,
    deviceIdentifier origin: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async {
    guard let eventData = try? OcaPropertyChangedEventData<Data>(data: parameters) else {
      profile?.coordinator?.logger.trace(
        "handleRemoteEvent: failed to decode event data from \(origin) for ONo \(event.emitterONo)"
      )
      return
    }
    guard let localEventData = try? _remapEventDataForLocal(eventData, deviceIdentifier: origin) else {
      profile?.coordinator?.logger.trace(
        "handleRemoteEvent: failed to remap event data from \(origin) for propertyID \(eventData.propertyID)"
      )
      return
    }

    if remoteFollowerOnly {
      profile?.coordinator?.logger.trace(
        "handleRemoteEvent: ignoring propertyID \(localEventData.propertyID) from \(origin) for remote-follower-only object \(localObject.objectNumber)"
      )
      return
    }

    _forwardingFromRemote = true
    defer { _forwardingFromRemote = false }

    guard _shouldForwardProperty(localEventData.propertyID) else { return }

    // don't forward lockState changes to the local object when lockRemote is set
    if !(lockRemote && localEventData.propertyID == Self._lockStatePropertyID) {
      let localEvent = OcaEvent(emitterONo: localObject.objectNumber, eventID: event.eventID)
      if referenceProperties[localEventData.propertyID] != nil {
        do {
          try await _applyReferencePropertyToLocal(localEventData)
        } catch {
          profile?.coordinator?.logger.trace(
            "handleRemoteEvent: failed to apply reference property \(localEventData.propertyID) to local object \(localObject.objectNumber): \(error)"
          )
        }
      } else {
        do {
          try await localObject.forward(event: localEvent, eventData: localEventData)
        } catch {
          profile?.coordinator?.logger.trace(
            "handleRemoteEvent: failed to forward propertyID \(localEventData.propertyID) to local object \(localObject.objectNumber): \(error)"
          )
        }
      }
    }

    // forward to all other remote objects (excluding origin)
    for (deviceID, remoteObject) in remoteObjects where deviceID != origin {
      let remoteEvent = OcaEvent(emitterONo: remoteObject.objectNumber, eventID: event.eventID)
      let forwardedEventData: OcaAnyPropertyChangedEventData
      do {
        forwardedEventData = try _remapEventDataForRemote(localEventData, deviceIdentifier: deviceID)
      } catch {
        profile?.coordinator?.logger.trace(
          "handleRemoteEvent: failed to remap event data for \(deviceID): \(error)"
        )
        forwardedEventData = localEventData
      }
      do {
        try await remoteObject.forward(event: remoteEvent, eventData: forwardedEventData)
      } catch {
        profile?.coordinator?.logger.trace(
          "handleRemoteEvent: failed to forward to remote \(deviceID): \(error)"
        )
      }
    }
  }

  public func bind(
    remoteObject: SwiftOCA.OcaRoot,
    from remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws {
    guard let remoteObject = remoteObject as? Remote else {
      throw Ocp1Error.status(.parameterError)
    }
    remoteObjects[remoteDevice] = remoteObject
    profile?.coordinator?.logger.trace(
      "bind: local object \(localObject.objectNumber) bound to remote object \(remoteObject.objectNumber) on \(remoteDevice)"
    )
    try await _copyProperties(to: remoteObject, remoteDevice: remoteDevice)

    if lockRemote {
      try? await remoteObject.setLockNoReadWrite()
    }
  }

  public func subscribe(
    to remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws {
    guard let remoteObject = remoteObjects[remoteDevice] else { return }
    guard let connectionDelegate = remoteObject.connectionDelegate else {
      throw Ocp1Error.noConnectionDelegate
    }
    let event = OcaEvent(
      emitterONo: remoteObject.objectNumber,
      eventID: OcaPropertyChangedEventID
    )
    let cancellable = try await connectionDelegate.addSubscription(
      event: event
    ) { [weak self] event, data in
      await self?.handleRemoteEvent(event, parameters: data, deviceIdentifier: remoteDevice)
    }
    remoteSubscriptions[remoteDevice] = cancellable
  }

  public func unbind(
    remoteObject: SwiftOCA.OcaRoot,
    from remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws {
    if lockRemote {
      try? await remoteObject.unlock()
    }
    remoteObjects.removeValue(forKey: remoteDevice)
    if let cancellable = remoteSubscriptions.removeValue(forKey: remoteDevice) {
      try await remoteObject.connectionDelegate?.removeSubscription(cancellable)
    }
  }
}
