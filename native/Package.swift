// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XrealSpatial",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "XrealSpatial",
            path: "Sources/XrealSpatial"
        )
    ]
)
