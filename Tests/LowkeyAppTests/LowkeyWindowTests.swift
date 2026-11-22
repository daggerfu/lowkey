import AppKit
import SwiftUI
import LowkeyCore
import BobukUI
import XCTest
@testable import LowkeyLib

/// lowkey's theme on BobukKit's window shell and prompt panel. No visible windows or keypresses.
final class LowkeyWindowTests: XCTestCase {
    private func withMode<T>(_ mode: ThemeMode, _ body: () throws -> T) rethrows -> T {
        let saved = ThemeCenter.shared.appearance
        defer { ThemeCenter.shared.appearance = saved }
        ThemeCenter.shared.appearance.mode = mode
        return try body()
    }

    private func makeWindow() -> LowkeyWindow {
        _ = NSApplication.shared
        return LowkeyWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
                            trailing: [StripButton(glyph: .back, label: "Back"), StripButton(glyph: .start, label: "Start"),
                                       StripButton(glyph: .forward, label: "Forward")])
    }

    func testMenuOwnsCommandWAndPaletteChromeUsesStrokeAndRed() {
        UITest.onMain {
            try? self.withMode(.light) {
                let window = self.makeWindow()
                defer { window.close() }
                XCTAssertFalse(window.closesOnCommandW)
                XCTAssertFalse(window.routesEditCommands)
                let tokens = ThemeCenter.shared.stripTokens(page: window.pageTheme)
                let style = window.chromeStyle
                XCTAssertEqual(style.panel, NSColor(tokens.panel))
                XCTAssertEqual(style.ink, NSColor(tokens.ink))
                XCTAssertEqual(style.muted, NSColor(tokens.muted))
                XCTAssertEqual(style.accent, NSColor(tokens.accent))
                XCTAssertEqual(style.separator, NSColor(tokens.stroke))
                XCTAssertEqual(style.destructiveHover, tokens.dangerNSColor)
                XCTAssertEqual(window.strip.appearance?.name, .aqua)
            }
        }
    }

    func testTintedStripTakesThePageColorWithoutLineOrRed() {
        UITest.onMain {
            try? self.withMode(.tint) {
                let window = self.makeWindow()
                defer { window.close() }
                let tint = RGB(r: 0.1, g: 0.2, b: 0.5)
                window.tint = tint
                let style = window.chromeStyle
                XCTAssertEqual(style.panel, NSColor(tint))
                XCTAssertEqual(style.separator, style.panel)
                XCTAssertNil(style.destructiveHover)
                XCTAssertEqual(window.strip.appearance?.name, .darkAqua)
                // A mode change recolors open windows.
                ThemeCenter.shared.appearance.mode = .dark
                XCTAssertEqual(window.chromeStyle.separator,
                               NSColor(ThemeCenter.shared.stripTokens(page: window.pageTheme).stroke))
                XCTAssertNotNil(window.chromeStyle.destructiveHover)
            }
        }
    }

    func testSettingsWindowIsFixedWithTerminateClose() throws {
        try UITest.onMain {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let app = AppController(store: Store(configURL: root.appendingPathComponent("config.json")))
            let controller = SettingsWindowController(app: app)
            defer { NSWindow.removeFrame(usingName: "LowkeySettings") }
            let window = try XCTUnwrap(controller.window as? LowkeyWindow)
            defer { window.close() }
            XCTAssertFalse(window.styleMask.contains(.resizable))
            XCTAssertFalse(window.collectionBehavior.contains(.fullScreenPrimary))
            XCTAssertFalse(window.closesOnCommandW)
            XCTAssertEqual(window.closeButton.glyph, .terminate)
            XCTAssertEqual(window.closeButton.label, "Close · ⌘W")
            XCTAssertEqual(window.title, "lowkey Settings")
        }
    }

    func testAddressPanelIsAPrompt() {
        UITest.onMain {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let app = AppController(store: Store(configURL: root.appendingPathComponent("config.json")))
            let panel = AddressPanel(app: app)
            defer { panel.close() }
            XCTAssertEqual(panel.kind, .prompt)
            XCTAssertEqual(panel.level, .floating)
            XCTAssertEqual(panel.collectionBehavior, [.moveToActiveSpace, .fullScreenAuxiliary])
            XCTAssertTrue(panel.dismissesOnResignKey && panel.dismissesOnAppDeactivation && panel.dismissesOnCommandW)
            XCTAssertFalse(panel.routesEditCommands)
            XCTAssertTrue(panel.canBecomeKey)
            XCTAssertFalse(panel.canBecomeMain)
        }
    }

    func testRendersPreviews() throws {
        try UITest.onMain {
            guard let folder = ProcessInfo.processInfo.environment["BOBUKKIT_PREVIEW_DIR"] else { return }
            let output = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            func render(_ window: LowkeyWindow, _ name: String) throws {
                let content = try XCTUnwrap(window.contentView)
                content.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
            }
            try self.withMode(.light) {
                let window = self.makeWindow()
                defer { window.close() }
                try render(window, "lowkey-window-light.png")
            }
            try self.withMode(.tint) {
                let window = self.makeWindow()
                defer { window.close() }
                window.tint = RGB(r: 0.1, g: 0.2, b: 0.5)
                window.accentBar.progress = 0.4
                try render(window, "lowkey-window-tint.png")
            }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = Store(configURL: root.appendingPathComponent("config.json"))
            let app = AppController(store: store)
            let model = SettingsModel(app: app)
            model.draft.appearance.mode = .dark
            model.editingDark = true
            model.applyPreset("catppuccin")
            let size = NSSize(width: 648, height: 540)
            let host = ChromeWindow.hosting(AppearancePane(model: model).environment(\.colorScheme, .dark))
            let win = LowkeyWindow(contentRect: NSRect(origin: .zero, size: ChromeMetrics.windowSize(forBody: size)), resizable: false)
            defer { win.close() }
            win.appearance = NSAppearance(named: .darkAqua)
            win.setContent(host)
            win.setContentSize(ChromeMetrics.windowSize(forBody: size))
            host.setFrameSize(size)
            host.layoutSubtreeIfNeeded()
            UITest.pump(until: { true }, timeout: 0.1)
            let bmp = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bmp)
            try XCTUnwrap(bmp.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("lowkey-appearance-dark.png"))
        }
    }
}
