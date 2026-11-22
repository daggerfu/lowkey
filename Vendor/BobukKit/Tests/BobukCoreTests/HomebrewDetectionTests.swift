import Foundation
import XCTest
@testable import BobukCore

/// Every folder here is a temporary one: no test reads the real Homebrew prefixes or runs `brew`.
final class HomebrewDetectionTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    private let cask = HomebrewCask(name: "ting", appBundleName: "Ting.app")

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fm.temporaryDirectory.appendingPathComponent("ting-homebrew-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let testRoot = root { try? fm.removeItem(at: testRoot) }
        root = nil
        super.tearDown()
    }

    /// A fake prefix with an executable `bin/brew`.
    private func prefix(_ name: String, brew: Bool = true) throws -> URL {
        let prefix = root.appendingPathComponent(name)
        try fm.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: prefix.appendingPathComponent("Caskroom"), withIntermediateDirectories: true)
        if brew {
            let file = prefix.appendingPathComponent("bin/brew")
            try "#!/bin/sh\nexit 0\n".write(to: file, atomically: false, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return prefix
    }

    private func app(_ path: String) throws -> URL {
        let app = root.appendingPathComponent(path)
        try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        return app
    }

    /// `<prefix>/Caskroom/<cask>/<version>/Ting.app` as a symlink to `target`.
    private func record(_ prefix: URL, cask: String = "ting", version: String = "0.7.3", to target: URL) throws -> URL {
        let folder = prefix.appendingPathComponent("Caskroom/\(cask)/\(version)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("Ting.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        return link
    }

    func testHomebrewOptPrefixManagesTheApp() throws {
        let brew = try prefix("opt/homebrew")
        let bundle = try app("Applications/Ting.app")
        let link = try record(brew, to: bundle)
        let install = try XCTUnwrap(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [brew]))
        XCTAssertEqual(install.prefix.path, brew.path)
        XCTAssertEqual(install.record.path, link.path)
        XCTAssertEqual(install.brew.path, brew.appendingPathComponent("bin/brew").path)
        XCTAssertEqual(install.app.resolvingSymlinksInPath().path, bundle.resolvingSymlinksInPath().path)
    }

    func testUsrLocalPrefixManagesTheApp() throws {
        let opt = try prefix("opt/homebrew")
        let local = try prefix("usr/local")
        let bundle = try app("Applications/Ting.app")
        _ = try record(local, to: bundle)
        let install = try XCTUnwrap(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [opt, local]))
        XCTAssertEqual(install.prefix.path, local.path)
    }

    func testCustomPrefixFromEnvironmentAndFoundBrew() throws {
        let custom = try prefix("custom")
        let other = try prefix("elsewhere")
        let prefixes = HomebrewDetection.prefixes(environment: [
            "HOMEBREW_PREFIX": custom.path,
            "PATH": "\(root.appendingPathComponent("nothing").path):\(other.appendingPathComponent("bin").path)",
        ])
        XCTAssertEqual(prefixes.map(\.path), [custom.path, other.path, "/opt/homebrew", "/usr/local"])

        let bundle = try app("Applications/Ting.app")
        _ = try record(other, to: bundle)
        let install = try XCTUnwrap(HomebrewDetection.install(of: bundle, cask: cask, prefixes: prefixes.filter { $0.path.hasPrefix(root.path) }))
        XCTAssertEqual(install.prefix.path, other.path)
        XCTAssertEqual(install.brew.path, other.appendingPathComponent("bin/brew").path)
    }

    func testCaskroomCopyOfTheRunningApp() throws {
        let brew = try prefix("opt/homebrew")
        let copy = try app("opt/homebrew/Caskroom/ting/0.7.3/Ting.app")
        let install = try XCTUnwrap(HomebrewDetection.install(of: copy, cask: cask, prefixes: [brew]))
        XCTAssertEqual(install.record.path, copy.path)
    }

    func testRecordPointingElsewhereIsNotManaged() throws {
        let brew = try prefix("opt/homebrew")
        let bundle = try app("Applications/Ting.app")
        let other = try app("Other/Ting.app")
        _ = try record(brew, to: other)
        XCTAssertEqual(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [brew]), nil)
    }

    func testHomebrewWithoutTheTingCaskIsNotManaged() throws {
        let brew = try prefix("opt/homebrew")
        let bundle = try app("Applications/Ting.app")
        _ = try record(brew, cask: "other-app", to: bundle)
        XCTAssertEqual(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [brew]), nil)
        XCTAssertEqual(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [root.appendingPathComponent("missing")]), nil)
    }

    func testUnreadableCaskroomIsNotManaged() throws {
        let brew = try prefix("opt/homebrew")
        let bundle = try app("Applications/Ting.app")
        _ = try record(brew, to: bundle)
        let caskroom = brew.appendingPathComponent("Caskroom/ting")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: caskroom.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: caskroom.path) }
        XCTAssertEqual(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [brew]), nil)
    }

    func testUnclearStatesAreNotManaged() throws {
        // A record without a runnable brew next to it cannot be updated by that prefix.
        let noBrew = try prefix("broken", brew: false)
        let bundle = try app("Applications/Ting.app")
        _ = try record(noBrew, to: bundle)
        XCTAssertEqual(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [noBrew]), nil)

        // Two prefixes that both claim the same copy: nobody knows which brew owns it.
        let first = try prefix("first")
        let second = try prefix("second")
        _ = try record(first, to: bundle)
        _ = try record(second, to: bundle)
        XCTAssertEqual(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [first, second]), nil)
    }

    func testUpdateCommandIsOnlyTheTingCask() throws {
        let brew = try prefix("opt/homebrew")
        let bundle = try app("Applications/Ting.app")
        _ = try record(brew, to: bundle)
        let install = try XCTUnwrap(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [brew]))
        XCTAssertEqual(HomebrewUpdate.arguments(for: cask), ["upgrade", "--cask", "--greedy", "bobuk-io/tap/ting"])
        XCTAssert(HomebrewUpdate.commandLine(for: install)
            == "\(brew.appendingPathComponent("bin/brew").path) upgrade --cask --greedy bobuk-io/tap/ting")
    }

    func testOutcomeOfTheCommand() {
        let upgraded = "==> Upgrading 1 outdated package:\nbobuk-io/tap/ting 0.7.2 -> 0.7.3\n🍺  ting was successfully upgraded!\n"
        XCTAssertEqual(HomebrewUpdate.outcome(exitCode: 0, output: upgraded, cancelled: false), .upgraded)
        let current = "Warning: Not upgrading ting, the latest version is already installed\n"
        XCTAssertEqual(HomebrewUpdate.outcome(exitCode: 0, output: current, cancelled: false), .upToDate)
        XCTAssertEqual(HomebrewUpdate.outcome(exitCode: 0, output: "", cancelled: false), .upToDate)
        let locked = "Error: A `brew upgrade` process has already locked /opt/homebrew/Caskroom/ting.\n"
        XCTAssertEqual(HomebrewUpdate.outcome(exitCode: 1, output: locked, cancelled: false), .failed(exitCode: 1, output: locked))
        let network = "curl: (6) Could not resolve host: github.com\nError: Download failed\n"
        XCTAssertEqual(HomebrewUpdate.outcome(exitCode: 1, output: network, cancelled: false), .failed(exitCode: 1, output: network))
        let sudo = "sudo: a terminal is required to read the password\n"
        XCTAssertEqual(HomebrewUpdate.outcome(exitCode: 1, output: sudo, cancelled: false), .failed(exitCode: 1, output: sudo))
        XCTAssertEqual(HomebrewUpdate.outcome(exitCode: 143, output: "partial", cancelled: true), .cancelled(output: "partial"))
        // A cancel never counts as success, even if brew happened to exit 0.
        XCTAssertEqual(HomebrewUpdate.outcome(exitCode: 0, output: upgraded, cancelled: true), .cancelled(output: upgraded))
    }

    func testUpdaterChoice() throws {
        let brew = try prefix("opt/homebrew")
        let bundle = try app("Applications/Ting.app")
        _ = try record(brew, to: bundle)
        let install = try XCTUnwrap(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [brew]))
        XCTAssertEqual(UpdaterChoice.choose(homebrew: install, hasFeed: true, hasKey: true), .homebrew(install))
        XCTAssertEqual(UpdaterChoice.choose(homebrew: nil, hasFeed: true, hasKey: true), .sparkle)
        XCTAssertEqual(UpdaterChoice.choose(homebrew: nil, hasFeed: false, hasKey: false), .none)
        XCTAssertEqual(UpdaterChoice.choose(homebrew: nil, hasFeed: true, hasKey: false), .none)
    }

    func testBundleNamesWithSpacesAreFound() throws {
        let splash = HomebrewCask(name: "splash-finish", appBundleName: "Splash Finish.app")
        let brew = try prefix("opt/homebrew")
        let bundle = try app("Applications/Splash Finish.app")
        let folder = brew.appendingPathComponent("Caskroom/splash-finish/0.3.14")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Splash Finish.app"), withDestinationURL: bundle)
        let install = try XCTUnwrap(HomebrewDetection.install(of: bundle, cask: splash, prefixes: [brew]))
        XCTAssertEqual(install.caskroom.path, brew.appendingPathComponent("Caskroom/splash-finish").path)
        XCTAssertEqual(HomebrewUpdate.arguments(for: splash), ["upgrade", "--cask", "--greedy", "bobuk-io/tap/splash-finish"])
        XCTAssertEqual(HomebrewDetection.install(of: bundle, cask: cask, prefixes: [brew]), nil)
    }

    func testDevelopmentBuildsNeverLookForHomebrew() throws {
        let brew = try prefix("opt/homebrew")
        let bundle = try app("Applications/Ting.app")
        _ = try record(brew, to: bundle)
        let environment = ["HOMEBREW_PREFIX": brew.path, "PATH": ""]
        let release: [String: Any] = ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "key"]
        XCTAssertEqual(UpdaterChoice.detect(cask: cask, bundle: bundle, info: [:], environment: environment), .none)
        XCTAssertEqual(UpdaterChoice.detect(cask: nil, bundle: bundle, info: release, environment: environment), .sparkle)
        guard case .homebrew = UpdaterChoice.detect(cask: cask, bundle: bundle, info: release, environment: environment) else {
            XCTFail("A release copy in the Caskroom is Homebrew's")
            return
        }
    }

    func testRelaunchArgument() {
        let base = URL(fileURLWithPath: "/tmp/base")
        XCTAssertEqual(HomebrewUpdate.resultDirectory(in: ["--homebrew-update-log", "/tmp/base/run-1"], base: base)?.path, "/tmp/base/run-1")
        XCTAssertEqual(HomebrewUpdate.resultDirectory(in: ["--homebrew-update-log", "/etc"], base: base), nil)
        XCTAssertEqual(HomebrewUpdate.resultDirectory(in: ["--homebrew-update-log", "/tmp/base/../x"], base: base), nil)
        XCTAssertEqual(HomebrewUpdate.resultDirectory(in: ["--homebrew-update-log"], base: base), nil)
        XCTAssertEqual(HomebrewUpdate.resultDirectory(in: [], base: base), nil)
        XCTAssert(HomebrewUpdate.isUpdateLaunch(["app", "--homebrew-update-viewer", "/tmp/base/run"]))
        XCTAssert(!HomebrewUpdate.isUpdateLaunch(["app", "status"]))
    }
}
