// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "GlowUp",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "GlowKit", targets: ["GlowKit"]),
    // Product/binary named GlowUpApp so it doesn't collide with the case-insensitive `glowup` CLI binary.
    .executable(name: "GlowUpApp", targets: ["GlowUp"]),
    .executable(name: "glowup", targets: ["GlowUpExec"]),
  ],
  targets: [
    .target(
      name: "GlowKit",
      resources: [.copy("Resources/catalog.json")],
      linkerSettings: [.linkedFramework("AppKit")]
    ),
    // Shared test fixtures/doubles. Not a product, so it never ships; uses only public GlowKit API.
    .target(name: "GlowTestSupport", dependencies: ["GlowKit"], path: "Tests/GlowTestSupport"),
    .testTarget(
      name: "GlowKitTests",
      dependencies: ["GlowKit", "GlowTestSupport"]
    ),
    .target(
      name: "GlowUpUI",
      dependencies: ["GlowKit"]
    ),
    .executableTarget(
      name: "GlowUp",
      dependencies: ["GlowUpUI"]
    ),
    .testTarget(
      name: "GlowUpUITests",
      dependencies: ["GlowUpUI", "GlowTestSupport"]
    ),
    .target(name: "GlowUpCLI", dependencies: ["GlowKit"]),
    .executableTarget(name: "GlowUpExec", dependencies: ["GlowUpCLI"], path: "Sources/GlowUpCLIExec"),
    .testTarget(name: "GlowUpCLITests", dependencies: ["GlowUpCLI", "GlowTestSupport"]),
  ]
)
