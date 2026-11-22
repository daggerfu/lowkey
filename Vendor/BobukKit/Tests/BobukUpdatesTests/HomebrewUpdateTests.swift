#if canImport(AppKit)
import Foundation
import XCTest
import BobukCore
@testable import BobukUpdates

/// The runner and the updater choice of the app. `brew` and `open` are fake scripts in a temporary
/// folder: no test runs the real Homebrew, touches /Applications or opens an app.
final class HomebrewUpdateTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    /// Spaces in the names exercise the quoting of the helper script, as "Splash Finish.app" does.
    private let demo = AppUpdateIdentity(displayName: "Demo App", executableName: "DemoApp",
                                         cask: HomebrewCask(name: "demo-app", appBundleName: "Demo App.app"),
                                         bundleIdentifier: "io.bobuk.demo-app", keptNotice: "Settings are kept.")

    override func setUp() {
        super.setUp()
        root = fm.temporaryDirectory.appendingPathComponent("bobukkit-brew-run-\(UUID().uuidString)")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func script(_ path: String, _ body: String) throws -> URL {
        let file = root.appendingPathComponent(path)
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n\(body)\n".write(to: file, atomically: false, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    /// A Homebrew prefix whose fake `brew` records its arguments and then runs `body`.
    private func install(brew body: String) throws -> HomebrewInstall {
        let prefix = root.appendingPathComponent("prefix")
        let calls = root.appendingPathComponent("brew-calls").path
        _ = try script("prefix/bin/brew", "printf '%s\\n' \"$*\" >> '\(calls)'\n\(body)")
        let app = root.appendingPathComponent("Applications/Demo App.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let folder = prefix.appendingPathComponent("Caskroom/demo-app/0.7.3")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Demo App.app"), withDestinationURL: app)
        return try XCTUnwrap(HomebrewDetection.install(of: app, cask: demo.cask, prefixes: [prefix]))
    }

    private func runner(_ install: HomebrewInstall, pid: pid_t = ProcessInfo.processInfo.processIdentifier) throws -> HomebrewUpdateRunner {
        let opener = try script("bin/open", "printf '%s\\n' \"$*\" >> '\(root.appendingPathComponent("open-calls").path)'")
        // A fake Demo App.app whose executable records how the helper started the progress viewer.
        _ = try script("ViewerSource/Demo App.app/Contents/MacOS/DemoApp",
                       "printf '%s\\n' \"$*\" >> '\(root.appendingPathComponent("viewer-calls").path)'")
        return HomebrewUpdateRunner(app: demo, install: install, appPID: pid, base: root.appendingPathComponent("runs"),
                                    opener: opener, viewerSource: root.appendingPathComponent("ViewerSource/Demo App.app"),
                                    pollInterval: 0.05)
    }

    /// A stand-in for the viewer process: alive until the test ends it, like a window the person closes.
    private func viewerProcess() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        return process
    }

    /// Waits for a copy that only watches a run another copy started.
    private func attach(_ directory: URL, pid: pid_t) throws -> (HomebrewUpdateRunner, HomebrewUpdateOutcome, [String]) {
        let watcher = HomebrewUpdateRunner(app: demo, install: nil, appPID: pid, base: root.appendingPathComponent("runs"),
                                           viewerSource: nil, pollInterval: 0.05)
        var seen: [String] = []
        var result: HomebrewUpdateOutcome?
        let finished = expectation(description: "watcher finished")
        let started = watcher.watch(directory, onOutput: { seen.append($0) }, onFinish: { outcome in
            result = outcome
            finished.fulfill()
        })
        if !started {
            XCTFail("Could not watch \(directory.path)")
            finished.fulfill()
        }
        wait(for: [finished], timeout: 20)
        guard let outcome = result else { return (watcher, .failed(exitCode: -1, output: ""), seen) }
        return (watcher, outcome, seen)
    }

    /// Runs one update synchronously; the expectation keeps the main run loop alive so the
    /// runner's polling timer can see the helper's log and status files.
    private func finish(_ runner: HomebrewUpdateRunner, output: ((String) -> Void)? = nil) throws -> HomebrewUpdateOutcome {
        var result: HomebrewUpdateOutcome?
        let finished = expectation(description: "update finished")
        let started = runner.start(onOutput: { output?($0) }, onFinish: { outcome in
            result = outcome
            finished.fulfill()
        })
        if !started {
            XCTFail("The update did not start")
            finished.fulfill()
        }
        wait(for: [finished], timeout: 20)
        guard let outcome = result else { return .failed(exitCode: -1, output: "") }
        return outcome
    }

    private func read(_ name: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    /// Polls a log file written by a fake script, with the same bound as the original wait.
    private func waitFor(_ name: String) throws -> String {
        for _ in 0..<200 {
            let text = read(name)
            if !text.isEmpty { return text }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return ""
    }

    func testHomebrewSuccessRunsOnlyTheTingCask() throws {
        let brewInstall = try install(brew: "echo '==> Upgrading 1 outdated package:'\necho '🍺  ting was successfully upgraded!'")
        let runner = try self.runner(brewInstall)
        var lines = ""
        let outcome = try finish(runner) { lines = $0 }
        XCTAssertEqual(outcome, .upgraded)
        XCTAssertEqual(read("brew-calls"), "upgrade --cask --greedy bobuk-io/tap/demo-app\n")
        XCTAssert(lines.contains("successfully upgraded"))
        let directory = try XCTUnwrap(runner.directory)
        runner.acknowledge(relaunch: true)
        // The helper starts the installed copy again once this process is gone; here it is
        // still alive, so the opener has not run yet.
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssert(read("open-calls").isEmpty)
        XCTAssert(fm.fileExists(atPath: directory.appendingPathComponent("relaunch").path))
    }

    func testHomebrewUpToDate() throws {
        let brewInstall = try install(brew: "echo 'Warning: Not upgrading ting, the latest version is already installed' >&2")
        let runner = try self.runner(brewInstall)
        XCTAssertEqual(try finish(runner), .upToDate)
        runner.acknowledge(relaunch: false)
    }

    func testHomebrewFailureKeepsTheOutput() throws {
        let brewInstall = try install(brew: "echo 'Error: Download failed: Could not resolve host' >&2\nexit 1")
        let runner = try self.runner(brewInstall)
        let outcome = try finish(runner)
        XCTAssertEqual(outcome, .failed(exitCode: 1, output: "Error: Download failed: Could not resolve host\n"))
        runner.acknowledge(relaunch: false)
    }

    func testHomebrewSecondStartIsRefused() throws {
        let brewInstall = try install(brew: "sleep 1\necho done")
        let runner = try self.runner(brewInstall)
        var firstOutcome: HomebrewUpdateOutcome?
        let finished = expectation(description: "first update finished")
        XCTAssert(runner.start(onOutput: { _ in }, onFinish: { outcome in
            firstOutcome = outcome
            finished.fulfill()
        }))
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssert(runner.isRunning)
        XCTAssert(!runner.start(onOutput: { _ in }, onFinish: { _ in }))
        wait(for: [finished], timeout: 20)
        XCTAssertEqual(firstOutcome, .upToDate)
        XCTAssertEqual(read("brew-calls"), "upgrade --cask --greedy bobuk-io/tap/demo-app\n")
        runner.acknowledge(relaunch: false)
    }

    func testHomebrewCancelIsNotSuccess() throws {
        let brewInstall = try install(brew: "echo started\nsleep 5\necho '🍺  ting was successfully upgraded!'")
        let runner = try self.runner(brewInstall)
        var outcome: HomebrewUpdateOutcome?
        let finished = expectation(description: "cancelled update finished")
        XCTAssert(runner.start(onOutput: { _ in }, onFinish: { result in
            outcome = result
            finished.fulfill()
        }))
        Thread.sleep(forTimeInterval: 0.3)
        runner.cancel()
        wait(for: [finished], timeout: 20)
        guard let result = outcome else { XCTFail("No result from the update"); return }
        guard case .cancelled = result else { XCTFail("Expected a cancel, got \(String(describing: result))"); return }
        runner.acknowledge(relaunch: false)
    }

    /// The path with every symlink resolved, as `cd -P` in the helper gives it.
    private func real(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// A process that has already exited: a Ting that brew stopped or that crashed.
    private func deadPID() throws -> pid_t {
        let dead = Process()
        dead.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try dead.run()
        dead.waitUntilExit()
        return dead.processIdentifier
    }

    /// brew may stop or replace Ting while it runs. The helper sees that Ting is gone while brew
    /// still works and starts the progress viewer from the copy in the run folder at once, not the
    /// installed app; the viewer gets the output that brew writes after Ting's exit and the result,
    /// and after the success hands over to the installed copy.
    func testHomebrewProgressStaysVisibleAfterTingQuits() throws {
        let brewInstall = try install(brew: "echo first\nsleep 1\necho second\necho '🍺  ting was successfully upgraded!'")
        let runner = try self.runner(brewInstall, pid: try deadPID())
        _ = runner.start(onOutput: { _ in }, onFinish: { _ in })
        let directory = try XCTUnwrap(runner.directory)
        let viewed = try waitFor("viewer-calls")
        XCTAssertEqual(viewed, "--homebrew-update-viewer \(directory.path)\n")
        // Started while brew still runs: no result yet, and the rest of the output is still to come.
        XCTAssertEqual(HomebrewUpdateRunner.outcome(in: directory), nil)
        XCTAssert(!HomebrewUpdateRunner.output(in: directory).contains("second"))
        XCTAssert(read("open-calls").isEmpty)

        let viewer = try viewerProcess()
        let (watcher, outcome, seen) = try attach(directory, pid: viewer.processIdentifier)
        XCTAssertEqual(outcome, .upgraded)
        XCTAssert(seen.contains { $0.contains("second") })
        XCTAssert(try String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)
            == String(viewer.processIdentifier))
        XCTAssert(watcher.conclude(outcome, role: .viewer))
        viewer.terminate()
        viewer.waitUntilExit()
        XCTAssertEqual(try waitFor("open-calls"), "\(real(brewInstall.app)) --args --homebrew-update-log \(directory.path)\n")
    }

    /// brew removes the installed app and then fails to place the new one: no Demo App.app exists, yet
    /// the viewer (a copy outside the installed bundle) shows the progress and the failure.
    func testHomebrewFailedReplacementStaysVisible() throws {
        let brewInstall = try install(brew: "")
        _ = try script("prefix/bin/brew", """
            rm -rf '\(brewInstall.app.path)'
            echo 'Removing old Demo App.app'
            sleep 1
            echo 'Error: could not move the new Demo App.app into place' >&2
            exit 1
            """)
        let runner = try self.runner(brewInstall, pid: try deadPID())
        _ = runner.start(onOutput: { _ in }, onFinish: { _ in })
        let directory = try XCTUnwrap(runner.directory)
        XCTAssertEqual(try waitFor("viewer-calls"), "--homebrew-update-viewer \(directory.path)\n")

        let viewer = try viewerProcess()
        let (watcher, outcome, _) = try attach(directory, pid: viewer.processIdentifier)
        guard case .failed(1, let output) = outcome else { XCTFail("Expected a failure, got \(String(describing: outcome))"); return }
        XCTAssert(output.contains("could not move the new Demo App.app"))
        XCTAssert(!fm.fileExists(atPath: brewInstall.app.path))
        // The viewer keeps the failure on screen until the person closes it.
        XCTAssert(!watcher.conclude(outcome, role: .viewer))
        viewer.terminate()
        viewer.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.8)
        // Nothing to start: no installed copy, and the result was already seen.
        XCTAssert(read("open-calls").isEmpty)
        XCTAssertEqual(read("viewer-calls"), "--homebrew-update-viewer \(directory.path)\n")
    }

    /// The helper starts the viewer while brew runs, but the viewer attaches only after brew is
    /// done. It is still a recovery launch: after the success it hands over to the installed copy.
    /// Only the copy started after brew (`.final`) never restarts.
    func testHomebrewLateRecoveryStillRestarts() throws {
        let allowBrewToFinish = root.appendingPathComponent("allow-brew-to-finish")
        let brewInstall = try self.install(brew: "while [ ! -f '\(allowBrewToFinish.path)' ]; do sleep 0.01; done\necho '🍺  ting was successfully upgraded!'")
        let runner = try self.runner(brewInstall, pid: try deadPID())
        _ = runner.start(onOutput: { _ in }, onFinish: { _ in })
        let directory = try XCTUnwrap(runner.directory)
        _ = try waitFor("viewer-calls")
        XCTAssertEqual(HomebrewUpdateRunner.outcome(in: directory), nil)
        try Data().write(to: allowBrewToFinish)
        for _ in 0..<200 {
            if HomebrewUpdateRunner.outcome(in: directory) != nil { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let viewer = try viewerProcess()
        let (watcher, outcome, _) = try attach(directory, pid: viewer.processIdentifier)
        XCTAssertEqual(outcome, .upgraded)
        XCTAssert(watcher.conclude(outcome, role: .viewer))
        XCTAssert(fm.fileExists(atPath: directory.appendingPathComponent("relaunch").path))
        viewer.terminate()
        viewer.waitUntilExit()
        XCTAssertEqual(try waitFor("open-calls"), "\(real(brewInstall.app)) --args --homebrew-update-log \(directory.path)\n")

        XCTAssert(!HomebrewUpdateRole.final.restarts(after: .upgraded))
        XCTAssert(!HomebrewUpdateRole.final.relaunchWhenDone(after: .upgraded))
        XCTAssert(HomebrewUpdateRole.owner.restarts(after: .upgraded))
        XCTAssert(!HomebrewUpdateRole.owner.restarts(after: .upToDate))
    }

    /// The reopened copy has no helper of its own; its Cancel still stops brew, and is no success.
    func testHomebrewWatcherCancelIsNotSuccess() throws {
        let brewInstall = try self.install(brew: "echo started\nsleep 5\necho '🍺  ting was successfully upgraded!'")
        let runner = try self.runner(brewInstall)
        _ = runner.start(onOutput: { _ in }, onFinish: { _ in })
        let directory = try XCTUnwrap(runner.directory)
        let watcher = HomebrewUpdateRunner(app: demo, install: nil, base: root.appendingPathComponent("runs"), pollInterval: 0.05)
        var outcome: HomebrewUpdateOutcome?
        let finished = expectation(description: "watcher finished")
        let started = watcher.watch(directory, onOutput: { _ in }, onFinish: { result in
            outcome = result
            finished.fulfill()
        })
        if !started {
            XCTFail("Could not watch \(directory.path)")
            finished.fulfill()
        }
        watcher.cancel()
        wait(for: [finished], timeout: 20)
        guard let result = outcome else { XCTFail("No result from the watcher"); return }
        guard case .cancelled = result else { XCTFail("Expected a cancel, got \(String(describing: result))"); return }
        watcher.acknowledge(relaunch: false)
    }

    /// A copy that runs from the Caskroom: the upgrade removes its version folder. The restart
    /// opens the new record, not the old path.
    func testHomebrewRestartOpensTheReplacement() throws {
        let prefix = root.appendingPathComponent("prefix")
        let caskroom = prefix.appendingPathComponent("Caskroom/demo-app")
        let old = caskroom.appendingPathComponent("0.7.3/Demo App.app")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        _ = try script("prefix/bin/brew", """
            rm -rf '\(caskroom.appendingPathComponent("0.7.3").path)'
            mkdir -p '\(caskroom.appendingPathComponent("0.7.4/Demo App.app").path)'
            echo '🍺  ting was successfully upgraded!'
            """)
        let brewInstall = try XCTUnwrap(HomebrewDetection.install(of: old, cask: demo.cask, prefixes: [prefix]))
        let ting = Process()
        ting.executableURL = URL(fileURLWithPath: "/bin/sleep")
        ting.arguments = ["30"]
        try ting.run()
        let runner = try self.runner(brewInstall, pid: ting.processIdentifier)
        XCTAssertEqual(try finish(runner), .upgraded)
        let directory = try XCTUnwrap(runner.directory)
        runner.acknowledge(relaunch: true)
        ting.terminate()
        ting.waitUntilExit()
        let opened = try waitFor("open-calls")
        XCTAssert(!fm.fileExists(atPath: old.path))
        XCTAssertEqual(opened, "\(real(caskroom.appendingPathComponent("0.7.4/Demo App.app"))) --args --homebrew-update-log \(directory.path)\n")
    }

    /// Without a complete copy of Demo App.app for the progress viewer, nothing could show the
    /// progress while brew replaces Ting: brew is never started, and the window shows why.
    func testHomebrewViewerCopyFailureStartsNoBrew() throws {
        let brewInstall = try self.install(brew: "echo '🍺  ting was successfully upgraded!'")
        let broken = root.appendingPathComponent("Broken/Demo App.app")
        try fm.createDirectory(at: broken.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let cases: [(URL?, String)] = [
            (nil, "not running from an app bundle"),
            (root.appendingPathComponent("Missing/Demo App.app"), "Could not prepare the progress window"),
            (broken, "has no executable"),
        ]
        for (source, reason) in cases {
            let runner = HomebrewUpdateRunner(app: demo, install: brewInstall, base: root.appendingPathComponent("runs"),
                                              viewerSource: source, pollInterval: 0.05)
            let outcome = try finish(runner)
            guard case .failed(-1, let text) = outcome else { XCTFail("Expected a failure, got \(String(describing: outcome))"); continue }
            XCTAssert(text.contains("Could not prepare the progress window"))
            XCTAssert(text.contains(reason))
            let model = HomebrewUpdateModel(appName: "Demo App")
            model.finish(outcome, log: runner.directory.map(HomebrewUpdateRunner.output(in:)))
            XCTAssertEqual(model.output, text)
            XCTAssert(!runner.isRunning)
        }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssert(read("brew-calls").isEmpty)
    }

    /// A run that cannot start shows its reason, not an empty log.
    func testHomebrewStartupFailuresShowTheReason() throws {
        let brewInstall = try self.install(brew: "exit 0")
        _ = try script("ViewerSource/Demo App.app/Contents/MacOS/DemoApp", "exit 0")
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let unpreparable = HomebrewUpdateRunner(app: demo, install: brewInstall, base: blocker, viewerSource: nil, pollInterval: 0.05)
        let unstartable = HomebrewUpdateRunner(app: demo, install: brewInstall, base: root.appendingPathComponent("runs"),
                                               shell: root.appendingPathComponent("missing/sh"),
                                               viewerSource: root.appendingPathComponent("ViewerSource/Demo App.app"),
                                               pollInterval: 0.05)
        for (runner, reason) in [(unpreparable, "Could not prepare the update"), (unstartable, "Could not start the update helper")] {
            let outcome = try finish(runner)
            guard case .failed(let code, let text) = outcome else { XCTFail("Expected a failure, got \(String(describing: outcome))"); continue }
            XCTAssertEqual(code, -1)
            XCTAssert(text.contains(reason))
            let model = HomebrewUpdateModel(appName: "Demo App")
            model.finish(outcome, log: runner.directory.map(HomebrewUpdateRunner.output(in:)))
            XCTAssertEqual(model.output, text)
            XCTAssertEqual(model.phase, .finished(outcome))
            XCTAssert(!model.succeeded)
        }
        XCTAssert(read("brew-calls").isEmpty)
    }

    func testHomebrewChoiceStartsNoSparkle() throws {
        let brewInstall = try self.install(brew: "exit 0")
        var made = 0
        let service = UpdateService(app: demo, choice: .homebrew(brewInstall), makeSparkle: { made += 1; return FakeSparkle() })
        XCTAssertEqual(made, 0)
        XCTAssertEqual(service.homebrew, brewInstall)
        XCTAssert(!service.isAvailable)
        XCTAssertEqual(service.menuTitle, "Update Demo App via Homebrew…")
    }

    func testHomebrewChoiceSparkleAndNone() {
        var made = 0
        let sparkle = UpdateService(app: demo, choice: .sparkle, makeSparkle: { made += 1; return FakeSparkle() })
        XCTAssertEqual(made, 1)
        XCTAssert(sparkle.isAvailable)
        XCTAssertEqual(sparkle.homebrew, nil)
        XCTAssertEqual(sparkle.menuTitle, "Check for Updates…")

        let none = UpdateService(app: demo, choice: .none, makeSparkle: { made += 1; return FakeSparkle() })
        XCTAssertEqual(made, 1)
        XCTAssert(!none.isAvailable)
        XCTAssertEqual(none.menuTitle, nil)
    }
}

private final class FakeSparkle: SparkleUpdating {
    var automaticallyChecks = true
    var canCheck = true
    func check() {}
}
#endif
