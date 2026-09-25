// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RealTimeCounter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "RealTimeCounter", path: "Sources/RealTimeCounter")
    ]
)
