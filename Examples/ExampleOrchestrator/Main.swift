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

import AES70Orchestrator
import AsyncAlgorithms
import Foundation
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

let SwiftOCADeviceExampleSchemaName = "com.padl.OCADevice"

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

  static func main() async throws {
    let args = CommandLine.arguments.dropFirst()
    let trace = args.contains("--trace") || args.contains("-v")
    let stateFile = args.first { !$0.hasPrefix("-") }
    let stateURL = stateFile.map { URL(fileURLWithPath: $0) }

    var logger = Logger(label: "com.padl.ExampleOrchestrator")
    logger.logLevel = trace ? .trace : .debug

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

    if let stateURL, FileManager.default.fileExists(atPath: stateURL.path) {
      try await coordinator.import(from: stateURL)
      print("Loaded state from \(stateFile!)")
    } else {
      let profileONo = try await coordinator.addProfile(
        schema: SwiftOCADeviceExampleSchemaName,
        name: "Test Profile"
      )
      print("Created profile with ONo \(profileONo)")

      let deviceIdentifier = OcaConnectionBroker.DeviceIdentifier(
        serviceType: .tcp,
        modelGUID: OcaModelGUID(mfrCode: .init((0, 0, 0)), modelCode: (1, 2, 3, 4)),
        serialNumber: "OCADevice-00000001",
        name: "OCA Test"
      )
      let profile = try await coordinator.findProfile(
        named: "Test Profile",
        schema: SwiftOCADeviceExampleSchemaName
      )
      try await coordinator.bindProfile(profile, to: deviceIdentifier, deviceIndex: 0)
      print("Bound profile to \(deviceIdentifier)")
    }

    if let stateURL {
      await coordinator.setPersistenceURL(stateURL)
    }

    signal(SIGPIPE, SIG_IGN)

    print("Starting OCP.1 endpoint on port \(port)...")
    try await endpoint.run()
  }
}
