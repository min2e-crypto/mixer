// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mixer",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(name: "tapspike"),
    ]
)
