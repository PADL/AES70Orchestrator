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

@OcaDevice
protocol OcaObjectBindingRepresentable: Sendable {
  func handleLocalEvent(_ event: OcaEvent, parameters: Data) async
  func hasRemoteObject(
    for deviceIdentifier: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) -> Bool
  func enroll(
    remoteObject: SwiftOCA.OcaRoot,
    from remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws
  func unenroll(
    remoteObject: SwiftOCA.OcaRoot,
    from remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws
}

@OcaDevice
public final class OcaObjectBinding<
  Local: SwiftOCADevice.OcaRoot,
  Remote: SwiftOCA.OcaRoot
>: OcaObjectBindingRepresentable, Sendable {
  let localObject: Local
  var remoteObjects = [SwiftOCA.OcaConnectionBroker.DeviceIdentifier: Remote]()
  var remoteSubscriptions =
    [SwiftOCA.OcaConnectionBroker.DeviceIdentifier: Ocp1Connection.SubscriptionCancellable]()
  weak var profile: OcaProfile?

  public init(localObject: Local, profile: OcaProfile) {
    self.localObject = localObject
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
    remoteObjects[deviceIdentifier] != nil
  }

  // handle a local event propagated from the OcaDevice's global onEvent handler; this should
  // forward to all the remote devices
  @OcaDevice
  func handleLocalEvent(_ event: OcaEvent, parameters: Data) async {
    guard let eventData = try? OcaPropertyChangedEventData<Data>(data: parameters) else {
      profile?.coordinator?.logger.warning(
        "handleLocalEvent: failed to decode event data for ONo \(event.emitterONo)"
      )
      return
    }

    profile?.coordinator?.logger.debug(
      "handleLocalEvent: forwarding propertyID \(eventData.propertyID) to \(remoteObjects.count) remote object(s)"
    )
    for (deviceID, remoteObject) in remoteObjects {
      let remoteEvent = OcaEvent(emitterONo: remoteObject.objectNumber, eventID: event.eventID)
      do {
        try await remoteObject.forward(event: remoteEvent, eventData: eventData)
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
    guard let eventData = try? OcaPropertyChangedEventData<Data>(data: parameters) else { return }

    // forward to local object
    let localEvent = OcaEvent(emitterONo: localObject.objectNumber, eventID: event.eventID)
    try? await localObject.forward(event: localEvent, eventData: eventData)

    // forward to all other remote objects (excluding origin)
    for (deviceID, remoteObject) in remoteObjects where deviceID != origin {
      let remoteEvent = OcaEvent(emitterONo: remoteObject.objectNumber, eventID: event.eventID)
      try? await remoteObject.forward(event: remoteEvent, eventData: eventData)
    }
  }

  public func enroll(
    remoteObject: SwiftOCA.OcaRoot,
    from remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws {
    guard let remoteObject = remoteObject as? Remote else {
      throw Ocp1Error.status(.parameterError)
    }
    remoteObjects[remoteDevice] = remoteObject
    try await localObject.copyProperties(to: remoteObject)

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

  public func unenroll(
    remoteObject: SwiftOCA.OcaRoot,
    from remoteDevice: SwiftOCA.OcaConnectionBroker.DeviceIdentifier
  ) async throws {
    remoteObjects.removeValue(forKey: remoteDevice)
    if let cancellable = remoteSubscriptions.removeValue(forKey: remoteDevice) {
      try await remoteObject.connectionDelegate?.removeSubscription(cancellable)
    }
  }
}
