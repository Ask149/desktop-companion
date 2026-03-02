// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesktopCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DesktopCompanion",
            path: "Sources/DesktopCompanion"
        ),
        .testTarget(
            name: "DesktopCompanionTests",
            dependencies: ["DesktopCompanion"],
            path: "Tests/DesktopCompanionTests"
        ),
    ]
)
