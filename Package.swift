// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Lowkey",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "Vendor/BobukKit")],
    targets: [
        // Pure logic: configuration, deep links, address input, history, link policy, themes. No AppKit.
        // BobukCore is Foundation-only (layout swap, recent list, message port).
        .target(name: "LowkeyCore", dependencies: [.product(name: "BobukCore", package: "BobukKit")],
                path: "Sources/LowkeyCore"),
        .target(name: "lowkeyctl", dependencies: ["LowkeyCore", .product(name: "BobukCore", package: "BobukKit")]),
        // The browser app (AppKit + WebKit + SwiftUI settings). A library plus a thin
        // executable: SwiftPM 5.3 cannot @testable-import an executable target.
        .target(name: "LowkeyLib", dependencies: ["LowkeyCore",
                                                  .product(name: "BobukCore", package: "BobukKit"),
                                                  .product(name: "BobukSystem", package: "BobukKit"),
                                                  .product(name: "BobukUI", package: "BobukKit")],
                path: "Sources/Lowkey"),
        .target(name: "Lowkey", dependencies: ["LowkeyLib"], path: "Sources/LowkeyMain"),
        .testTarget(name: "LowkeyCoreTests", dependencies: ["LowkeyCore"], path: "Tests/LowkeyCoreTests"),
        .testTarget(name: "LowkeyAppTests", dependencies: ["LowkeyLib", .product(name: "BobukUI", package: "BobukKit")], path: "Tests/LowkeyAppTests"),
    ]
)
