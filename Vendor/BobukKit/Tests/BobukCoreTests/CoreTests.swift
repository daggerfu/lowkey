import BobukTestSupport
import Foundation
import XCTest
@testable import BobukCore

final class KeyboardLayoutSwapTests: XCTestCase {
    func testVariantsInTingOrder() {
        XCTAssertEqual(KeyboardLayoutSwap.variants(of: "Safari").first, "safari")
        XCTAssertEqual(KeyboardLayoutSwap.variants(of: "ыф"), ["ыф", "sa"])
        XCTAssertEqual(KeyboardLayoutSwap.variants(of: "sa"), ["sa", "ыф", "іф"])
        XCTAssertEqual(KeyboardLayoutSwap.variants(of: "ta"), ["ta", "еф"])
        XCTAssertEqual(KeyboardLayoutSwap.variants(of: "123"), ["123"])
    }

    func testPhysicalKeysAsInLowkey() {
        XCTAssert(KeyboardLayoutSwap.variants(of: "РФ").contains("ha"))
        XCTAssert(KeyboardLayoutSwap.variants(of: "пщщпду").contains("google"))
        XCTAssert(KeyboardLayoutSwap.variants(of: "шї").contains("i]"))
        XCTAssert(KeyboardLayoutSwap.variants(of: "і").contains("s"))
        XCTAssert(KeyboardLayoutSwap.variants(of: "ntktuhfv").contains("телеграм"))
        XCTAssertEqual(KeyboardLayoutSwap.variants(of: "").count, 1)
    }
}

final class AppPathsTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/demo")

    func testDefaultLocations() {
        let ting = AppPaths(supportFolder: "Ting", configFolder: "ting", overrideVariable: "TING_CONFIG", environment: [:], home: home)
        XCTAssertEqual(ting.config.path, "/Users/demo/.config/ting/config.json")
        XCTAssertEqual(ting.file("history.json").path, "/Users/demo/Library/Application Support/Ting/history.json")
        XCTAssert(!ting.isIsolated)
        let lowkey = AppPaths(supportFolder: "Lowkey", overrideVariable: "LOWKEY_CONFIG", environment: [:], home: home)
        XCTAssertEqual(lowkey.config.path, "/Users/demo/Library/Application Support/Lowkey/config.json")
        XCTAssertEqual(lowkey.companion(".history.json").path, "/Users/demo/Library/Application Support/Lowkey/config.json.history.json")
    }

    func testOverrideMovesEveryFile() {
        let paths = AppPaths(supportFolder: "Ting", configFolder: "ting", overrideVariable: "TING_CONFIG",
                             environment: ["TING_CONFIG": "/tmp/x/test.json"], home: home)
        XCTAssert(paths.isIsolated)
        XCTAssertEqual(paths.config.path, "/tmp/x/test.json")
        XCTAssertEqual(paths.file("history.json").path, "/tmp/x/history.json")
        XCTAssertEqual(paths.companion(".history.json").path, "/tmp/x/test.json.history.json")
        XCTAssertEqual(paths.dataFile("launcha-history.json").path, "/tmp/x/test.json.launcha-history.json")
        let plain = AppPaths(supportFolder: "Ting", environment: [:], home: home)
        XCTAssertEqual(plain.dataFile("launcha-history.json").path, "/Users/demo/Library/Application Support/Ting/launcha-history.json")
        let folder = AppPaths(supportFolder: "Splash Finish", configFileName: "state.json", folderOverrideVariable: "SPLASH_FINISH_HOME",
                              environment: ["SPLASH_FINISH_HOME": "/tmp/splash"], home: home)
        XCTAssertEqual(folder.support.path, "/tmp/splash")
        XCTAssertEqual(folder.config.path, "/tmp/splash/state.json")
        XCTAssertEqual(folder.file("app.lock").path, "/tmp/splash/app.lock")
        let empty = AppPaths(supportFolder: "Ting", overrideVariable: "TING_CONFIG", environment: ["TING_CONFIG": ""], home: home)
        XCTAssert(!empty.isIsolated)
    }
}

final class SafeFileTests: XCTestCase {
    func testWritesAtomicallyAndKeepsPermissions() throws {
        let folder = try TemporaryDirectory()
        let file = folder.url.appendingPathComponent("nested/data.json")
        try SafeFile.write(Data("one".utf8), to: file)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try SafeFile.write(Data("two".utf8), to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "two")
        let kept = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(kept?.intValue, 0o644)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["data.json"])
    }

    func testRefusesSymlinks() throws {
        let folder = try TemporaryDirectory()
        let target = folder.url.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = folder.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try SafeFile.write(Data(), to: link.appendingPathComponent("x"))) { error in
            XCTAssert(error is SafeFileError)
        }
    }

    func testLockIsExclusive() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("app.lock")
        var first: FileLock? = try FileLock(url: url, nonblocking: true)
        XCTAssertThrowsError(try FileLock(url: url, nonblocking: true, busyMessage: "busy")) { error in
            XCTAssert(error is SafeFileError)
        }
        first = nil
        _ = first
        _ = try FileLock(url: url, nonblocking: true)
    }
}

final class JSONFileStoreTests: XCTestCase {
    struct Settings: Codable, Equatable { var name = "default" }

    func testMissingLoadedAndSaved() throws {
        let folder = try TemporaryDirectory()
        let store = JSONFileStore<Settings>(url: folder.url.appendingPathComponent("settings.json")) { Settings() }
        guard case .missing(let value) = store.load() else { XCTFail("expected missing"); return }
        XCTAssertEqual(value, Settings())
        try store.save(Settings(name: "saved"))
        XCTAssertEqual(store.load().value, Settings(name: "saved"))
    }

    func testRefusesToOverwriteAnUnreadableFile() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("settings.json")
        try Data("{broken".utf8).write(to: url)
        let store = JSONFileStore<Settings>(url: url) { Settings() }
        XCTAssertEqual(store.load().value, nil)
        XCTAssertThrowsError(try store.save(Settings(name: "x"))) { error in
            XCTAssert(error is JSONFileStoreError)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{broken")
    }

    func testBacksUpAnUnreadableFile() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("history.json")
        try Data("{broken".utf8).write(to: url)
        let store = JSONFileStore<Settings>(url: url, policy: .backUp) { Settings() }
        guard case .recovered(let value, let backup) = store.load() else { XCTFail("expected recovery"); return }
        XCTAssertEqual(value, Settings())
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "{broken")
        try store.save(Settings(name: "fresh"))
        XCTAssertEqual(store.load().value, Settings(name: "fresh"))
    }
}

final class RecentListTests: XCTestCase {
    func testMostRecentFirstCaseInsensitiveWithLimit() {
        var list = RecentList(limit: 3)
        for entry in ["a", "b", "c", "A", "  ", "d"] { list.record(entry) }
        XCTAssertEqual(list.entries, ["d", "A", "c"])
        list.remove("a")
        XCTAssertEqual(list.entries, ["d", "c"])
        XCTAssert(list.contains("D"))
        let decoded = try? JSONDecoder().decode(RecentList.self, from: Data(#"{"entries":["x","X","y"]}"#.utf8))
        XCTAssertEqual(decoded?.entries, ["x", "y"])
    }
}

final class PanelPlacementTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 400, height: 200)

    func testAnchors() {
        XCTAssertEqual(PanelPlacement.frame(size: size, in: area, anchor: .center()), CGRect(x: 300, y: 300, width: 400, height: 200))
        // launcha: top edge max(40, 16 %) below the top.
        XCTAssert(abs(PanelPlacement.frame(size: size, in: area, anchor: .upper()).maxY - 672) < 0.001)
        XCTAssert(abs(PanelPlacement.top(in: area, anchor: .upper()) - 672) < 0.001)
        XCTAssertEqual(PanelPlacement.frame(size: size, in: area, anchor: .top(inset: 80)).maxY, 720)
        // Splash Finish: 55 points below the center.
        XCTAssertEqual(PanelPlacement.frame(size: size, in: area, anchor: .center(offsetUp: -55)).minY, 245)
        // A panel taller than the screen keeps its top on screen.
        let tall = PanelPlacement.frame(size: CGSize(width: 400, height: 900), in: area, anchor: .center())
        XCTAssertEqual(tall.minY, 16)
    }

    func testRememberedCornerIsClampedOrIgnored() {
        let screens = [area, CGRect(x: 1000, y: 0, width: 800, height: 600)]
        let kept = PanelPlacement.place(size: size, remembered: CGPoint(x: 1700, y: 590), screens: screens, active: area)
        XCTAssertEqual(kept.frame, CGRect(x: 1400, y: 390, width: 400, height: 200))
        XCTAssertEqual(kept.area, screens[1])
        let gone = PanelPlacement.place(size: size, remembered: CGPoint(x: 5000, y: 5000), screens: screens, active: area)
        XCTAssertEqual(gone.frame.minY, 245)
    }

    func testResizeKeepsTheTopEdge() {
        let frame = CGRect(x: 10, y: 400, width: 300, height: 200)
        XCTAssertEqual(PanelPlacement.resize(frame, toHeight: 100).maxY, 600)
        XCTAssert(PanelPlacement.over(parent: CGRect(x: 0, y: 0, width: 800, height: 600), size: size, inset: 56)
            == CGRect(x: 200, y: 344, width: 400, height: 200))
    }
}

final class ChildProcessTests: XCTestCase {
    func testCollectsOutputAndExitCode() {
        let request = ChildProcessRequest(executable: "/bin/sh", arguments: ["-c", "cat; echo err >&2; exit 3"],
                                          stdin: Data("hello".utf8), timeLimit: 5)
        let outcome = ChildProcess.run(request)
        XCTAssertEqual(outcome.end, .exited(3))
        XCTAssertEqual(outcome.stdoutText, "hello")
        XCTAssertEqual(outcome.stderrText, "err\n")
    }

    func testTimeLimitStopsTheGroupAndOutputIsCut() {
        let slow = ChildProcess.run(ChildProcessRequest(executable: "/bin/sleep", arguments: ["5"], timeLimit: 0.2))
        XCTAssertEqual(slow.end, .timedOut)
        let loud = ChildProcess.run(ChildProcessRequest(executable: "/bin/sh", arguments: ["-c", "yes | head -c 5000"],
                                                              timeLimit: 5, outputLimit: 100))
        XCTAssertEqual(loud.stdout.count, 100)
        XCTAssert(loud.stdoutCut)
        let missing = ChildProcess.run(ChildProcessRequest(executable: "/nonexistent", timeLimit: 1))
        guard case .notStarted = missing.end else { XCTFail("expected notStarted"); return }
    }
}

final class MessagePortTests: XCTestCase {
    func testRoundTrip() {
        let name = MessagePortServer.name(prefix: "io.bobuk.bobukkit-test.\(UUID().uuidString)")
        let server = MessagePortServer(name: name) { _, payload in Data(("echo:" + String(decoding: payload, as: UTF8.self)).utf8) }
        XCTAssertNotNil(server)
        XCTAssert(MessagePortClient.isListening(name))
        let reply = MessagePortClient.send(Data("ping".utf8), to: name, timeout: 2)
        XCTAssertEqual((try? reply.get()).map { String(decoding: $0, as: UTF8.self) }, "echo:ping")
        XCTAssertEqual(MessagePortClient.send(Data(), to: name + ".missing", timeout: 0.2), .failure(.notListening))
        withExtendedLifetime(server) {}
    }
}

final class AppBundleTests: XCTestCase {
    func testApplicationURLOnlyForBundles() {
        let inside = URL(fileURLWithPath: "/Applications/Splash Finish.app/Contents/MacOS/SplashFinish")
        XCTAssertEqual(AppBundle.applicationURL(for: inside)?.path, "/Applications/Splash Finish.app")
        XCTAssertEqual(AppBundle.applicationURL(for: URL(fileURLWithPath: "/usr/local/bin/tool")), nil)
        XCTAssert(AppBundle.isProcessSerialNumber("-psn_0_1234"))
        XCTAssert(AppBundle.hasSparkleFeed(info: ["SUFeedURL": "https://x", "SUPublicEDKey": "k"]))
        XCTAssert(!AppBundle.hasSparkleFeed(info: ["SUFeedURL": "https://x"]))
    }

    func testVirtualKeys() {
        XCTAssertEqual(VirtualKey.digit(18), 1)
        XCTAssertEqual(VirtualKey.digit(29), 0)
        XCTAssertEqual(VirtualKey.digit(92), 9)
        XCTAssert(VirtualKey.isReturn(36) && VirtualKey.isReturn(76) && !VirtualKey.isReturn(53))
    }
}
