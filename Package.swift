// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        // Library target containing all logic (testable)
        .target(
            name: "CompanionCore",
            path: "Sources/CompanionCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-enable-testing"], .when(configuration: .release))
            ]
        ),
        // Executable target — thin wrapper, just launches the app
        .executableTarget(
            name: "DesktopCompanion",
            dependencies: ["CompanionCore"],
            path: "Sources/DesktopCompanion"
        ),
        // Test runner executable (workaround: no Xcode = no xctest/XCTest/swift-testing runner)
        .executableTarget(
            name: "CompanionTests",
            dependencies: ["CompanionCore"],
            path: "Tests/CompanionTests"
        ),
    ]
)
