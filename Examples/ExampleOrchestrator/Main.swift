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

import AsyncAlgorithms
import Foundation
import AES70Orchestrator
import Logging
import SocketAddress
import SwiftOCA
import SwiftOCADevice
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

private extension SocketAddress {
  var socketAddressData: Data {
    withSockAddr { sa, size in
      Data(bytes: sa, count: Int(size))
    }
  }
}

// Schema loaded from OCADevice.yaml, matching SwiftOCA's Examples/OCADevice

@main
enum ExampleOrchestrator {
  static let port: UInt16 = 65100
  static let defaultStateFile = "ExampleOrchestratorState.zip"

  static func main() async throws {
    let stateFile = CommandLine.arguments.count > 1
      ? CommandLine.arguments[1]
      : defaultStateFile
    let stateURL = URL(fileURLWithPath: stateFile)

    var logger = Logger(label: "com.padl.ExampleOrchestrator")
    logger.logLevel = .debug

    var listenAddress = sockaddr_in()
    listenAddress.sin_family = sa_family_t(AF_INET)
    listenAddress.sin_addr.s_addr = 0
    listenAddress.sin_port = port.bigEndian
    #if canImport(Darwin) || os(FreeBSD) || os(OpenBSD)
    listenAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif

    let device = OcaDevice.shared
    try await device.initializeDefaultObjects()
    let deviceManager = await device.deviceManager!
    Task { @OcaDevice in
      deviceManager.deviceName = "AES70 Orchestrator"
    }

    #if os(Linux)
    let endpoint = try await Ocp1IORingStreamDeviceEndpoint(
      address: listenAddress.socketAddressData
    )
    #elseif canImport(FlyingSocks)
    let endpoint = try await Ocp1FlyingSocksStreamDeviceEndpoint(
      address: listenAddress.socketAddressData
    )
    #else
    let endpoint = try await Ocp1StreamDeviceEndpoint(
      address: listenAddress.socketAddressData
    )
    #endif

    guard let yamlURL = Bundle.module.url(
      forResource: "OCADevice",
      withExtension: "yaml"
    ) else {
      fatalError("OCADevice.yaml not found in bundle")
    }
    let yamlString = try String(contentsOf: yamlURL, encoding: .utf8)
    let ocaDeviceSchema = try await OcaDeviceSchema(yaml: yamlString)

    let connectionOptions = Ocp1ConnectionOptions(
      flags: [.automaticReconnect, .refreshDeviceTreeOnConnection]
    )
    let coordinator = try await OcaCoordinator(
      connectionOptions: connectionOptions,
      serviceTypes: [.tcp],
      deviceSchema: ocaDeviceSchema,
      deviceDelegate: device,
      logger: logger
    )

    if FileManager.default.fileExists(atPath: stateURL.path) {
      try await coordinator.load(from: stateURL)
      print("Loaded state from \(stateFile)")
    } else {
      let profileONo = try await coordinator.addProfile(
        schema: "OCADevice",
        name: "Test Profile"
      )
      print("Created profile with ONo \(profileONo)")

      let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
        serviceType: .tcp,
        modelGUID: OcaModelGUID(mfrCode: .init((0, 0, 0)), modelCode: (1, 2, 3, 4)),
        serialNumber: "OCADevice-00000001",
        name: "OCA Test"
      )
      let profile = try await coordinator.findProfile(named: "Test Profile", schema: "OCADevice")
      try await coordinator.bindProfile(profile, to: deviceIdentifier, deviceIndex: 0)
      print("Bound profile to \(deviceIdentifier)")
    }

    await coordinator.startPersistenceMonitor(url: stateURL)

    signal(SIGPIPE, SIG_IGN)

    print("Starting OCP.1 endpoint on port \(port)...")
    try await endpoint.run()
  }
}
