// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSessionMenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexSessionCore", targets: ["CodexSessionCore"])
    ],
    targets: [
        .target(name: "CodexSessionCore"),
        .testTarget(
            name: "CodexSessionCoreTests",
            dependencies: ["CodexSessionCore"]
        )
    ]
)
