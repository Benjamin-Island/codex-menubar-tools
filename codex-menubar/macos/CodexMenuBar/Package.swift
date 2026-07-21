// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexMenuBarCore", targets: ["CodexMenuBarCore"]),
        .executable(name: "CodexMenuBar", targets: ["CodexMenuBar"])
    ],
    targets: [
        .target(name: "CodexMenuBarCore"),
        .executableTarget(
            name: "CodexMenuBar",
            dependencies: ["CodexMenuBarCore"]
        ),
        .testTarget(
            name: "CodexMenuBarCoreTests",
            dependencies: ["CodexMenuBarCore"]
        ),
        .testTarget(
            name: "CodexMenuBarTests",
            dependencies: ["CodexMenuBar", "CodexMenuBarCore"]
        )
    ]
)
