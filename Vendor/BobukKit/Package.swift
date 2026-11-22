// swift-tools-version: 5.3
import PackageDescription

// Rewritten for the Swift 5.3 toolchain (Xcode 12): no `.swiftLanguageMode` setting and no
// products/targets newer than tools-version 5.3. Note: the sources still use APIs from newer
// SDKs (async/await, `MainActor.assumeIsolated`, the Testing library), so building requires a
// compiler new enough to parse them; see README.

let package = Package(
    name: "BobukKit",
    platforms: [.macOS(.v10_15)],
    products: [
        // Foundation only: safe for command-line companions and *Core targets without AppKit.
        .library(name: "BobukCore", targets: ["BobukCore"]),
        // AppKit, Carbon, Security and ServiceManagement services.
        .library(name: "BobukSystem", targets: ["BobukSystem"]),
        // Window shells, panels, strips, glyphs, palettes and picker components.
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
        .executableTarget(name: "BobukUIGallery", dependencies: ["BobukUI", "BobukUpdates"], path: "Examples/Gallery"),
    ]
)
