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
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AES70Orchestrator",
            dependencies: [
              .product(name: "SwiftOCA", package: "SwiftOCA"),
              .product(name: "SwiftOCADevice", package: "SwiftOCA"),
              ],
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency"),
        .enableExperimentalFeature("NonisolatedNonsendingByDefault"),
      ]
        ),
        .testTarget(
            name: "AES70OrchestratorTests",
            dependencies: ["AES70Orchestrator"]
        ),
    ]
)
