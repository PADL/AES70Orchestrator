// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AES70Orchestrator",
    platforms: [
      .macOS(.v15),
      .iOS(.v17),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AES70Orchestrator",
            targets: ["AES70Orchestrator"]
        ),
    ],
    dependencies: [
      .package(url: "https://github.com/PADL/SwiftOCA", branch: "main"),
      .package(url: "https://github.com/PADL/SocketAddress", from: "0.4.5"),
      .package(url: "https://github.com/apple/swift-log", from: "1.6.2"),
      .package(url: "https://github.com/jpsim/Yams", from: "6.2.1"),
      .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0"),
      .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AES70Orchestrator",
            dependencies: [
              .product(name: "Yams", package: "Yams"),
              .product(name: "SwiftOCA", package: "SwiftOCA"),
              .product(name: "SwiftOCADevice", package: "SwiftOCA"),
              .product(name: "Logging", package: "swift-log"),
              .product(name: "ZIPFoundation", package: "ZIPFoundation"),
              ],
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency"),
        .enableExperimentalFeature("NonisolatedNonsendingByDefault"),
      ]
        ),
        .executableTarget(
            name: "ExampleOrchestrator",
            dependencies: [
              "AES70Orchestrator",
              .product(name: "SwiftOCA", package: "SwiftOCA"),
              .product(name: "SwiftOCADevice", package: "SwiftOCA"),
              .product(name: "SocketAddress", package: "SocketAddress"),
              .product(name: "Logging", package: "swift-log"),
              .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            path: "Examples/ExampleOrchestrator",
            resources: [
              .copy("Resources/OCADevice.yaml"),
            ],
            swiftSettings: [
              .enableExperimentalFeature("StrictConcurrency"),
              .enableExperimentalFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "AES70OrchestratorTests",
            dependencies: [
              "AES70Orchestrator",
              .product(name: "SwiftOCA", package: "SwiftOCA"),
              .product(name: "SwiftOCADevice", package: "SwiftOCA"),
            ],
            swiftSettings: [
              .enableExperimentalFeature("StrictConcurrency"),
              .enableExperimentalFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ]
)
