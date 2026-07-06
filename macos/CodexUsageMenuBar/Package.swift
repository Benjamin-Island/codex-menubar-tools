// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsageMenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"]),
        .executable(name: "CodexUsageMenuBar", targets: ["CodexUsageMenuBar"])
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .executableTarget(
            name: "CodexUsageMenuBar",
            dependencies: ["CodexUsageCore"]
        ),
        .testTarget(
            name: "CodexUsageCoreTests",
            dependencies: ["CodexUsageCore"]
        )
    ]
)
