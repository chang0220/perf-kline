// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerfKline",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "KlineCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "PerfKline",
            dependencies: ["KlineCore"]
        ),
        .testTarget(
            name: "KlineCoreTests",
            dependencies: ["KlineCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
