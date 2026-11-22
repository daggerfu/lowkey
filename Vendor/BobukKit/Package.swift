// swift-tools-version:5.3
import PackageDescription

// Swift 5.3 / Xcode 12 package manifest. The sources and tests use only Swift 5.3 language
// features and macOS 10.15 SDK APIs: no concurrency annotations, Observation or Swift Testing.
// BobukCore, BobukSystem (FileWatcher, HotkeyRecordingGate) and BobukTestSupport also build on
// Linux: Darwin-only imports are behind `#if canImport(Darwin)` and the UI/update targets
// compile to empty modules where AppKit is missing.
let package = Package(
    name: "BobukKit",
    platforms: [.macOS(.v10_15)],
    products: [
        // Foundation only: safe for command-line companions and *Core targets without AppKit.
        .library(name: "BobukCore", targets: ["BobukCore"]),
        // AppKit, Carbon, Security and ServiceManagement services.
        .library(name: "BobukSystem", targets: ["BobukSystem"]),
        .library(name: "BobukUI", targets: ["BobukUI"]),
        // Homebrew updates and the Sparkle seam. Sparkle itself stays in the app's Package.swift.
        .library(name: "BobukUpdates", targets: ["BobukUpdates"]),
        // Test-only helpers: temporary folders, fake executables and app bundles, isolated defaults.
        .library(name: "BobukTestSupport", targets: ["BobukTestSupport"]),
    ],
    targets: [
        .target(name: "BobukCore"),
        .target(name: "BobukSystem", dependencies: ["BobukCore"]),
        .target(name: "BobukUI", dependencies: ["BobukCore", "BobukSystem"]),
        .target(name: "BobukUpdates", dependencies: ["BobukCore", "BobukSystem", "BobukUI"]),
        .target(name: "BobukTestSupport", dependencies: ["BobukCore"]),
        .testTarget(name: "BobukCoreTests", dependencies: ["BobukCore", "BobukTestSupport"]),
        .testTarget(name: "BobukSystemTests", dependencies: ["BobukSystem", "BobukTestSupport"]),
        .testTarget(name: "BobukUITests", dependencies: ["BobukUI", "BobukTestSupport"]),
        .testTarget(name: "BobukUpdatesTests", dependencies: ["BobukUpdates", "BobukTestSupport"]),
        .target(name: "BobukUIGallery", dependencies: ["BobukUI", "BobukUpdates"], path: "Examples/Gallery"),
    ]
)
