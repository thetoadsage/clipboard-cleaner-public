// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClipboardCleaner",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "ClipboardCleanerCore",
            resources: [
                .process("Resources/tracking-rules.json")
            ]
        ),
        .executableTarget(
            name: "ClipboardCleaner",
            dependencies: ["ClipboardCleanerCore"]
        ),
        .testTarget(
            name: "ClipboardCleanerCoreTests",
            dependencies: ["ClipboardCleanerCore"]
        ),
        .testTarget(
            name: "ClipboardCleanerTests",
            dependencies: ["ClipboardCleaner", "ClipboardCleanerCore"]
        ),
    ]
)
