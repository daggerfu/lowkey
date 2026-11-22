import BobukCore
import Foundation
import XCTest
@testable import BobukSystem

#if canImport(Carbon)
/// No test registers a real global shortcut: the center gets a fake backend.
final class GlobalHotkeyCenterTests: XCTestCase {
    func testRegistersReportsAndReleases() throws {
        let center = GlobalHotkeyCenter(signature: OSType(fourCharacterCode: "TEST"), register: { _, _ in .active })
        var events: [String] = []
        let key = try XCTUnwrap(Hotkey(string: "option+cmd+s"))
        XCTAssertEqual(center.register(key, id: 1, onPress: { _ in events.append("press") }, onRelease: { events.append("release") }), .active)
        center.receive(1, pressed: true)
        center.receive(1, pressed: true)
        center.receive(1, pressed: false)
        XCTAssertEqual(events, ["press", "press", "release"])
        // A key that is down when it goes away reports a release.
        center.unregister(1)
        XCTAssertEqual(events.last, "release")
        XCTAssertEqual(center.status(1), .inactive)
    }

    func testApplicationShortcutsFireOncePerHold() throws {
        let center = GlobalHotkeyCenter(signature: 1, register: { _, _ in .active })
        var presses = 0
        center.register(try XCTUnwrap(Hotkey(string: "ctrl+f13")), id: 7, repeats: false, onPress: { _ in presses += 1 })
        center.receive(7, pressed: true)
        center.receive(7, pressed: true)
        center.receive(7, pressed: false)
        center.receive(7, pressed: true)
        XCTAssertEqual(presses, 2)
    }

    func testRefusesModifiersAndDuplicates() throws {
        let center = GlobalHotkeyCenter(signature: 1, register: { _, _ in .active })
        let tap = try XCTUnwrap(Hotkey(string: "right-option"))
        guard case .failed = center.register(tap, id: 1, onPress: { _ in }) else { XCTFail("modifier accepted"); return }
        let key = try XCTUnwrap(Hotkey(string: "cmd+f15"))
        center.register(key, id: 2, onPress: { _ in })
        XCTAssertEqual(center.register(key, id: 3, onPress: { _ in }), .failed("⌘F15 is already used here."))
        XCTAssertEqual(OSType(fourCharacterCode: "TING"), 0x5449_4E47)
    }

    func testAvailabilityProbeLeavesNoRegistration() throws {
        let center = GlobalHotkeyCenter(signature: 1, register: { _, _ in .failed("taken") })
        XCTAssertEqual(center.checkAvailable(try XCTUnwrap(Hotkey(string: "cmd+f1"))), "taken")
        XCTAssert(center.registeredIDs.isEmpty)
    }
}
#endif

final class FileWatcherTests: XCTestCase {
    /// FileWatcher delivers through `DispatchQueue.main`; turning the run loop lets those
    /// callbacks run instead of blocking the thread they are scheduled on.
    private func waitForChanges(_ condition: () -> Bool, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func testReportsEditsOfAFileAndOfFilesInAFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bobukkit-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("config.json")
        try Data("1".utf8).write(to: file)
        var fileChanges = 0, folderChanges = 0
        let fileWatcher = FileWatcher(url: file, debounce: 0.05) { fileChanges += 1 }
        let folderWatcher = FileWatcher(folder: folder, debounce: 0.05) { folderChanges += 1 }
        let handle = try FileHandle(forWritingTo: file)
        // seekToEnd() and write(contentsOf:) need 10.15.4; the non-throwing forms work on 10.15.0.
        handle.seekToEndOfFile()
        handle.write(Data("2".utf8))
        handle.closeFile()
        waitForChanges { fileChanges >= 1 && folderChanges >= 1 }
        XCTAssert(fileChanges >= 1 && folderChanges >= 1)
        let before = folderChanges
        try Data("new".utf8).write(to: folder.appendingPathComponent("other.yaml"))
        waitForChanges { folderChanges > before }
        XCTAssert(folderChanges > before)
        withExtendedLifetime((fileWatcher, folderWatcher)) {}
    }
}

final class HotkeyRecordingGateTests: XCTestCase {
    final class Owner: HotkeyRecordingOwner {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    func testOneOwnerAtATime() {
        var changes: [Bool] = []
        let gate = HotkeyRecordingGate { changes.append($0) }
        let first = Owner(), second = Owner()
        gate.begin(first)
        gate.begin(second)
        XCTAssert(first.cancelled)
        gate.end(first)
        XCTAssert(gate.isActive)
        gate.end(second)
        XCTAssert(!gate.isActive)
        XCTAssertEqual(changes, [true, false])
    }
}
