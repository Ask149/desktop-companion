// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CompanionCore",
            path: "Sources/CompanionCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-enable-testing"], .when(configuration: .release))
            ],
            linkerSettings: [
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
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
