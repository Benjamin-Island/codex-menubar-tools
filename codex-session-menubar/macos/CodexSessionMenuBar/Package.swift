// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSessionMenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexSessionCore", targets: ["CodexSessionCore"]),
        .executable(name: "CodexSessionMenuBar", targets: ["CodexSessionMenuBar"])
    ],
    targets: [
        .target(name: "CodexSessionCore"),
        .executableTarget(
            name: "CodexSessionMenuBar",
            dependencies: ["CodexSessionCore"]
        ),
        .testTarget(
            name: "CodexSessionCoreTests",
            dependencies: ["CodexSessionCore"]
        ),
        .testTarget(
            name: "CodexSessionMenuBarTests",
            dependencies: ["CodexSessionMenuBar", "CodexSessionCore"]
        )
    ]
)
