// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mixer",
    platforms: [.macOS("14.4")],
    targets: [
        .target(name: "MixerCore"),
        .target(name: "MixerAtomics"),
        .target(name: "MixerAudio", dependencies: ["MixerCore", "MixerAtomics"]),
        .executableTarget(name: "Mixer", dependencies: ["MixerCore", "MixerAudio"]),
        .executableTarget(name: "tapspike", dependencies: ["MixerAudio"]),
        .executableTarget(name: "notchspike"),
        .testTarget(name: "MixerCoreTests", dependencies: ["MixerCore"]),
    ]
)
