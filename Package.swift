// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "GlowUp",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "GlowKit", targets: ["GlowKit"]),
    .executable(name: "GlowUp", targets: ["GlowUp"]),
    .executable(name: "glowup", targets: ["GlowUpExec"]),
  ],
  targets: [
    .target(
      name: "GlowKit",
      resources: [.copy("Resources/catalog.json")],
      linkerSettings: [.linkedFramework("AppKit")]
    ),
    .testTarget(
      name: "GlowKitTests",
      dependencies: ["GlowKit"]
    ),
    .target(
      name: "GlowUpUI",
      dependencies: ["GlowKit"]
    ),
    .executableTarget(
      name: "GlowUp",
      dependencies: ["GlowUpUI", "GlowUpCLI"],
      exclude: ["main.swift"]
    ),
    .testTarget(
      name: "GlowUpUITests",
      dependencies: ["GlowUpUI"]
    ),
    .target(name: "GlowUpCLI", dependencies: ["GlowKit"]),
    .executableTarget(name: "GlowUpExec", dependencies: ["GlowUpCLI"], path: "Sources/GlowUpCLIExec"),
    .testTarget(name: "GlowUpCLITests", dependencies: ["GlowUpCLI"]),
  ]
)
