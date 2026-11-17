// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mixer",
    platforms: [.macOS("14.4")],
    targets: [
        .target(name: "MixerCore"),
        .executableTarget(name: "tapspike"),
        .testTarget(name: "MixerCoreTests", dependencies: ["MixerCore"]),
    ]
)
