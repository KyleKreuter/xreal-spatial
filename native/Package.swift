// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XrealSpatial",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CVDShim",
            path: "Sources/CVDShim"
        ),
        .executableTarget(
            name: "XrealSpatial",
            dependencies: ["CVDShim"],
            path: "Sources/XrealSpatial",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
    ]
)
