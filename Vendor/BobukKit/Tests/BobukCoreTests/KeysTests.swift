import Foundation
import XCTest
@testable import BobukCore

final class SequenceKeyTests: XCTestCase {
    static let names = Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init) + ["space", "return"] + (1...20).map { "f\($0)" }

    func testValidNames() {
        for name in SequenceKeyTests.names { validNames(name) }
    }

    private func validNames(_ name: String) {
        XCTAssert(SequenceKey.isValid(name))
        XCTAssertEqual(SequenceKey.normalize(name.uppercased()), name)
        if name != name.uppercased() { XCTAssert(!SequenceKey.isValid(name.uppercased())) }
        let label = name == "space" ? "␣" : name == "return" ? "↩" : name.uppercased()
        XCTAssertEqual(SequenceKey.display(name), label)
        XCTAssertEqual(SequenceKey.spoken(name), (name == "space" ? "Space" : name == "return" ? "Return" : name.uppercased()))
    }

    func testInvalidNames() {
        for name in ["", "ab", "f0", "f21", "-", "ф", "tab", " a", "a "] { invalidNames(name) }
    }

    private func invalidNames(_ name: String) {
        XCTAssert(!SequenceKey.isValid(name))
        XCTAssertEqual(SequenceKey.normalize(name), nil)
    }

    func testSpecialPhysicalKeysIgnoreLatin() {
        let pairs: [(UInt16, String)] = [(49, "space"), (36, "return"), (76, "return")] + SequenceKey.functionKeyCodes.map { ($0.key, $0.value) }
        XCTAssertEqual(SequenceKey.functionKeyCodes.count, 20)
        for (code, name) in pairs {
            XCTAssertEqual(SequenceKey.name(keyCode: code, latin: nil), name)
            XCTAssertEqual(SequenceKey.name(keyCode: code, latin: "ф"), name)
        }
    }

    func testLatinInput() {
        for latin in Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init) { latinInput(latin) }
    }

    private func latinInput(_ latin: String) {
        XCTAssertEqual(SequenceKey.name(keyCode: 0, latin: latin), latin.lowercased())
    }

    func testRejectedLatin() {
        let values: [String?] = [nil, "", "ab", "é", "ф", "İ", "-", " ", "\n"]
        for latin in values { rejectedLatin(latin) }
    }

    private func rejectedLatin(_ latin: String?) { XCTAssertEqual(SequenceKey.name(keyCode: 0, latin: latin), nil) }
}

final class ModifierKeyTests: XCTestCase {
    func testPhysicalMappings() {
        let cases: [(ModifierKey, UInt16, ModifierSet, String)] = [
            (.leftCommand, 55, .command, "Left ⌘"), (.rightCommand, 54, .command, "Right ⌘"),
            (.leftShift, 56, .shift, "Left ⇧"), (.rightShift, 60, .shift, "Right ⇧"),
            (.leftOption, 58, .option, "Left ⌥"), (.rightOption, 61, .option, "Right ⌥"),
            (.leftControl, 59, .control, "Left ⌃"), (.rightControl, 62, .control, "Right ⌃"),
            (.function, 63, .function, "fn")]
        XCTAssertEqual(cases.count, ModifierKey.allCases.count)
        for (key, code, flag, label) in cases {
            XCTAssertEqual(key.keyCode, code)
            XCTAssertEqual(ModifierKey(keyCode: code), key)
            XCTAssertEqual(key.flag, flag)
            XCTAssertEqual(key.display, label)
        }
        XCTAssertEqual(ModifierKey(keyCode: 0), nil)
        XCTAssertEqual(ModifierKey(keyCode: UInt16.max), nil)
    }
    func testSymbols() {
        XCTAssertEqual(ModifierSet().symbols, "")
        XCTAssertEqual(ModifierSet.function.symbols, "")
        XCTAssertEqual(ModifierSet([.command, .shift, .option, .control, .function]).symbols, "⌃⌥⇧⌘")
        XCTAssertEqual(ModifierSet([.command, .option]).symbols, "⌥⌘")
    }
}

final class KeyCodesTests: XCTestCase {
    func testAnsiRoundTrips() {
        XCTAssertEqual(KeyCodes.ansi.count, 100)
        for (name, code) in KeyCodes.ansi {
            XCTAssertEqual(KeyCodes.code(for: name), code)
            XCTAssertEqual(KeyCodes.name(for: code), name)
        }
        XCTAssertEqual(KeyCodes.code(for: "unknown"), nil)
        XCTAssertEqual(KeyCodes.code(for: ""), nil)
        XCTAssertEqual(KeyCodes.name(for: UInt16.max), nil)
    }
}

final class HotkeyTests: XCTestCase {
    func testPauseAlias() throws {
        for text in ["pause", "PAUSE", "Pause"] { try pauseAlias(text) }
    }

    private func pauseAlias(_ text: String) throws {
        let h = try XCTUnwrap(Hotkey(string: text))
        XCTAssertEqual(h, .combo(keyCode: 113, modifiers: []))
        XCTAssert(h.isValid)
        XCTAssertEqual(h.string, "f15")
        XCTAssertEqual(h.display, "F15")
        XCTAssertEqual(KeyCodes.name(for: 113), "f15")
    }

    func testPauseAliasWithModifiers() {
        let h = Hotkey(string: "shift+pause")
        XCTAssertEqual(h, .combo(keyCode: 113, modifiers: .shift))
        XCTAssertEqual(h?.string, "shift+f15")
    }

    func testRealLeader() throws {
        for text in ["option+shift+cmd+f", "Cmd+Shift+Option+F", "f+COMMAND+alt+SHIFT", "shift+opt+command+f"] { try realLeader(text) }
    }

    private func realLeader(_ text: String) throws {
        let h = try XCTUnwrap(Hotkey(string: text))
        XCTAssertEqual(h, .combo(keyCode: 3, modifiers: [.option, .shift, .command]))
        XCTAssertEqual(h.string, "option+shift+cmd+f")
        XCTAssertEqual(h.display, "⌥⇧⌘F")
        XCTAssert(h.isValid)
    }

    func testDisplaysAndCanonicalOrder() {
        let cases: [(String, Hotkey, String)] = [
            ("shift+f15", .combo(keyCode: 113, modifiers: .shift), "⇧F15"),
            ("f13", .combo(keyCode: 105, modifiers: []), "F13"),
            ("control+space", .combo(keyCode: 49, modifiers: .control), "⌃Space"),
            ("right-option", .modifierTap(.rightOption), "Right ⌥"),
            ("cmd+return", .combo(keyCode: 36, modifiers: .command), "⌘↩"),
            ("cmd+tab", .combo(keyCode: 48, modifiers: .command), "⌘⇥"),
            ("cmd+escape", .combo(keyCode: 53, modifiers: .command), "⌘⎋"),
            ("cmd+delete", .combo(keyCode: 51, modifiers: .command), "⌘⌫")]
        for (text, h, label) in cases {
            XCTAssertEqual(Hotkey(string: text), h)
            XCTAssertEqual(h.display, label)
            if case .modifierTap = h { XCTAssert(!h.isValid) } else { XCTAssert(h.isValid) }
        }
        XCTAssertEqual(Hotkey.combo(keyCode: 0, modifiers: [.command, .shift, .control, .option]).string, "ctrl+option+shift+cmd+a")
    }

    func testInvalidParsing() {
        for text in ["", "unknown+a", "cmd+unknown", "cmd+a+b", "cmd+", "+cmd+a"] { invalidParsing(text) }
    }

    private func invalidParsing(_ text: String) { XCTAssertEqual(Hotkey(string: text), nil) }

    func testValidity() {
        XCTAssert(Hotkey.combo(keyCode: 0, modifiers: []).isValid)
        XCTAssert(!Hotkey.combo(keyCode: 0, modifiers: [.function, .command]).isValid)
        for code in SequenceKey.functionKeyCodes.keys { XCTAssert(Hotkey.combo(keyCode: code, modifiers: []).isValid) }
        for key in ModifierKey.allCases {
            XCTAssert(!Hotkey.modifierTap(key).isValid)
            XCTAssert(!Hotkey.combo(keyCode: key.keyCode, modifiers: []).isValid)
        }
        XCTAssert(!Hotkey.combo(keyCode: 57, modifiers: []).isValid)
    }

    func testBareLeader() throws {
        for name in ["home", "end", "pageup", "pagedown", "space", "return", "a", "1", "left", "keypad0", "escape"] { try bareLeader(name) }
    }

    private func bareLeader(_ name: String) throws {
        let hotkey = try XCTUnwrap(Hotkey(string: name))
        XCTAssert(hotkey.isValid)
        XCTAssertEqual(hotkey.string, name)
        XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: JSONEncoder().encode(hotkey)), hotkey)
    }

    func testHomeLeader() {
        XCTAssertEqual(Hotkey(string: "home"), .combo(keyCode: 115, modifiers: []))
        XCTAssertEqual(Hotkey(string: "HOME")?.display, "Home")
        XCTAssertEqual(Hotkey(string: "shift+home")?.isValid, true)
    }

    func testRoundTripsAndCodable() throws {
        var hotkeys = ModifierKey.allCases.map(Hotkey.modifierTap)
        hotkeys += SequenceKey.functionKeyCodes.keys.map { .combo(keyCode: $0, modifiers: []) }
        for code in KeyCodes.ansi.values {
            for flags: ModifierSet in [.control, .option, .shift, .command, [.control, .option, .shift, .command]] {
                hotkeys.append(.combo(keyCode: code, modifiers: flags))
            }
        }
        for h in hotkeys {
            XCTAssertEqual(Hotkey(string: h.string), h)
            let data = try JSONEncoder().encode(h)
            XCTAssertEqual(try JSONDecoder().decode(String.self, from: data), h.string)
            XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: data), h)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(Hotkey.self, from: Data("\"nonsense\"".utf8))) { error in
            XCTAssert(error is DecodingError)
        }
    }
}

final class ModifierTapDetectorTests: XCTestCase {
    func testConsecutiveTaps() {
        for key in ModifierKey.allCases { consecutiveTaps(key) }
    }

    private func consecutiveTaps(_ key: ModifierKey) {
        var d = ModifierTapDetector()
        for time in [0.0, 1.0] {
            XCTAssertEqual(d.flagsChanged(keyCode: key.keyCode, modifiers: key.flag, time: time), nil)
            XCTAssertEqual(d.flagsChanged(keyCode: key.keyCode, modifiers: [], time: time + 0.1), key)
        }
    }

    func testNoCandidate() {
        var d = ModifierTapDetector()
        XCTAssertEqual(d.flagsChanged(keyCode: 61, modifiers: [], time: 0), nil)
        XCTAssertEqual(d.flagsChanged(keyCode: 61, modifiers: [.option, .shift], time: 1), nil)
        XCTAssertEqual(d.flagsChanged(keyCode: 61, modifiers: [], time: 1.1), nil)
    }

    func testCancellations() {
        for scenario in ["slow", "second", "normal", "different", "unknown"] { cancellations(scenario) }
    }

    private func cancellations(_ scenario: String) {
        var d = ModifierTapDetector(maxDuration: 0.2)
        XCTAssertEqual(d.flagsChanged(keyCode: 61, modifiers: .option, time: 0), nil)
        switch scenario {
        case "second": XCTAssertEqual(d.flagsChanged(keyCode: 56, modifiers: [.shift, .option], time: 0.05), nil)
        case "normal": d.keyDown()
        case "different": XCTAssertEqual(d.flagsChanged(keyCode: 58, modifiers: [], time: 0.1), nil); return
        case "unknown": XCTAssertEqual(d.flagsChanged(keyCode: 0, modifiers: .option, time: 0.05), nil)
        default: break
        }
        XCTAssertEqual(d.flagsChanged(keyCode: 61, modifiers: [], time: scenario == "slow" ? 0.3 : 0.15), nil)
    }
}
