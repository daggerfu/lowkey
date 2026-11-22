// swift-tools-version:5.3
import PackageDescription

// Swift 5.3 / macOS 10.15 (Xcode 12) manifest. Newer toolchains build Package.swift instead.
// Covers all four targets; the app builds with the macOS 10.15 SDK only.
// Strict 5.3 manifest API only: no .executableTarget, no .product dependencies.
let package = Package(
    name: "Lowkey",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "Vendor/BobukKit")],
    targets: [
        .target(name: "LowkeyCore", dependencies: [.product(name: "BobukCore", package: "BobukKit")],
                path: "Sources/LowkeyCore"),
        .target(name: "lowkeyctl", dependencies: ["LowkeyCore", .product(name: "BobukCore", package: "BobukKit")],
                path: "Sources/lowkeyctl"),
        .target(name: "LowkeyLib", dependencies: ["LowkeyCore",
                                                  .product(name: "BobukCore", package: "BobukKit"),
                                                  .product(name: "BobukSystem", package: "BobukKit"),
                                                  .product(name: "BobukUI", package: "BobukKit")],
                path: "Sources/Lowkey"),
        .target(name: "Lowkey", dependencies: ["LowkeyLib"], path: "Sources/LowkeyMain"),
        .testTarget(name: "LowkeyCoreTests", dependencies: ["LowkeyCore"], path: "Tests/LowkeyCoreTests"),
        .testTarget(name: "LowkeyAppTests", dependencies: ["LowkeyLib", .product(name: "BobukUI", package: "BobukKit")],
                    path: "Tests/LowkeyAppTests"),
    ]
)
