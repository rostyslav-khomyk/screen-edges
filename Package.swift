// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screen-edges",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "screen-edges", targets: ["screen-edges"]),
        .executable(name: "screen-edges-stream-fixture", targets: ["StreamFixture"]),
    ],
    targets: [
        .target(
            name: "ScreenEdgesCore",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "screen-edges",
            dependencies: ["ScreenEdgesCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "ScreenEdgesCoreTests",
            dependencies: ["ScreenEdgesCore"]
        ),
        .executableTarget(name: "StreamFixture", dependencies: ["ScreenEdgesCore"], path: "Tests/StreamFixture"),
    ]
)
