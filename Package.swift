// swift-tools-version:5.4
import PackageDescription

// macOS: the AppKit/WebKit browser (LowkeyLib), the CLI, the core logic and tests.
// Linux (Ubuntu): the same core and CLI plus a GTK 4 / WebKitGTK 6.0 app (LowkeyLinux).
// BobukCore provides the local IPC; it already has a Linux Unix-socket backend.
#if os(Linux)
let targets: [Target] = [
    .target(name: "LowkeyCore", dependencies: [.product(name: "BobukCore", package: "BobukKit")],
            path: "Sources/LowkeyCore"),
    .executableTarget(name: "lowkeyctl", dependencies: ["LowkeyCore", .product(name: "BobukCore", package: "BobukKit")],
            path: "Sources/lowkeyctl"),
    .systemLibrary(name: "CGTK", path: "Sources/CGTK",
                   pkgConfig: "webkitgtk-6.0",
                   providers: [.apt(["libwebkitgtk-6.0-dev"])]),
    .target(name: "LowkeyLinux", dependencies: ["LowkeyCore", "CGTK"], path: "Sources/LowkeyLinux"),
    .testTarget(name: "LowkeyCoreTests", dependencies: ["LowkeyCore"], path: "Tests/LowkeyCoreTests"),
]
#else
let targets: [Target] = [
        // Pure logic: configuration, deep links, address input, history, link policy, themes. No AppKit.
        // BobukCore is Foundation-only (layout swap, recent list, message port).
        .target(name: "LowkeyCore", dependencies: [.product(name: "BobukCore", package: "BobukKit")],
                path: "Sources/LowkeyCore"),
        .executableTarget(name: "lowkeyctl", dependencies: ["LowkeyCore", .product(name: "BobukCore", package: "BobukKit")]),
        // The browser app (AppKit + WebKit + SwiftUI settings). A library plus a thin
        // executable: SwiftPM 5.3 cannot @testable-import an executable target.
        .target(name: "LowkeyLib", dependencies: ["LowkeyCore",
                                                  .product(name: "BobukCore", package: "BobukKit"),
                                                  .product(name: "BobukSystem", package: "BobukKit"),
                                                  .product(name: "BobukUI", package: "BobukKit")],
                path: "Sources/Lowkey"),
        .executableTarget(name: "Lowkey", dependencies: ["LowkeyLib"], path: "Sources/LowkeyMain"),
        .testTarget(name: "LowkeyCoreTests", dependencies: ["LowkeyCore"], path: "Tests/LowkeyCoreTests"),
        .testTarget(name: "LowkeyAppTests", dependencies: ["LowkeyLib", .product(name: "BobukUI", package: "BobukKit")], path: "Tests/LowkeyAppTests"),
    ]
#endif

let package = Package(
    name: "Lowkey",
    platforms: [.macOS(.v10_15)],
    dependencies: [.package(path: "Vendor/BobukKit")],
    targets: targets
)
