// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AlignKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AlignCore", targets: ["AlignCore"]),
        .library(name: "PostureDetection", targets: ["PostureDetection"]),
        .library(name: "Sensors", targets: ["Sensors"]),
    ],
    targets: [
        // Shared contract types. Owned by the Lead Architect; changes go through docs/agents/decisions.md.
        .target(name: "AlignCore"),
        // Pure-Swift, platform-independent posture pipeline. Owned by the Algorithm agent.
        .target(name: "PostureDetection", dependencies: ["AlignCore"]),
        // Core Motion integration and mock sensor source. Owned by the Sensor agent.
        .target(name: "Sensors", dependencies: ["AlignCore"]),

        .testTarget(name: "AlignCoreTests", dependencies: ["AlignCore"]),
        .testTarget(name: "PostureDetectionTests", dependencies: ["PostureDetection", "AlignCore"]),
        .testTarget(name: "SensorsTests", dependencies: ["Sensors", "AlignCore"]),
    ]
)
