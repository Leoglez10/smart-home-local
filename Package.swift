// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "smart-home-local",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SmartHomeCore", targets: ["SmartHomeCore"]),
        .executable(name: "shl", targets: ["shl"]),
    ],
    targets: [
        .target(name: "SmartHomeCore"),
        .executableTarget(name: "shl", dependencies: ["SmartHomeCore"]),
        .testTarget(name: "SmartHomeCoreTests", dependencies: ["SmartHomeCore"]),
    ]
)
