// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "core_ai",
  platforms: [
    .iOS("15.0"),
    .macOS("12.0"),
  ],
  products: [
    .library(name: "core-ai", targets: ["core_ai"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "core_ai",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      // Core AI ships with iOS 27 / macOS 27. Every use is behind
      // `@available`, so the linker weak-links CoreAI automatically and apps with
      // a lower deployment target still launch; `isSupported()` returns false.
      resources: [
        .process("Resources")
      ]
    )
  ]
)
