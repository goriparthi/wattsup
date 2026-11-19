// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "wattsup",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure parsing and analysis with no IOKit or AppKit, so every rule is unit tested
        .target(name: "WattsupCore"),
        .executableTarget(name: "wattsup", dependencies: ["WattsupCore"]),
        .testTarget(name: "WattsupCoreTests", dependencies: ["WattsupCore"]),
    ]
)
