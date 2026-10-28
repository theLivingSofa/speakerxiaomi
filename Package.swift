// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SoundOutdoorEQ",
    platforms: [.macOS("14.2")],
    products: [
        .executable(name: "SoundOutdoorEQ", targets: ["SoundOutdoorEQ"]),
        .library(name: "EQCore", targets: ["EQCore"]),
    ],
    targets: [
        // Pure Swift DSP, settings and presets. No Apple-only frameworks, so it is easy to test.
        .target(name: "EQCore"),
        // The menu-bar app: Core Audio capture/playback and the SwiftUI interface.
        .executableTarget(name: "SoundOutdoorEQ", dependencies: ["EQCore"]),
        .testTarget(name: "EQCoreTests", dependencies: ["EQCore"]),
    ]
)
