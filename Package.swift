// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screen-edges",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "screen-edges", targets: ["screen-edges"]),
    ],
    targets: [
        .target(name: "ScreenEdgesCore"),
        .executableTarget(
            name: "screen-edges",
            dependencies: ["ScreenEdgesCore"]
        ),
        .testTarget(
            name: "ScreenEdgesCoreTests",
            dependencies: ["ScreenEdgesCore"]
        ),
    ]
)
