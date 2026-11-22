#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest
@testable import BobukUI

/// Windows are created but never shown on screen or activated.
final class ChromeWindowTests: XCTestCase {
    final class Delegate: NSObject, NSWindowDelegate {
        var allowClose = true
        var asked = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool { asked += 1; return allowClose }
    }

    private func key(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = .command, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    func testCloseButtonLivesInTheStripAndUsesPerformClose() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        let delegate = Delegate()
        window.delegate = delegate
        window.orderBack(nil)
        XCTAssert(window.strip.buttons.first === window.closeButton)
        XCTAssertEqual(window.closeButton.glyph, .close)
        XCTAssertEqual(window.closeButton.label, "Close · ⌘W")

        delegate.allowClose = false
        window.closeButton.performPress()
        XCTAssertEqual(delegate.asked, 1)
        XCTAssert(window.isVisible)

        delegate.allowClose = true
        window.closeButton.performPress()
        XCTAssertEqual(delegate.asked, 2)
        XCTAssert(!window.isVisible)
        // NSWindow does not retain its delegate: detach it before the delegate goes away.
        window.delegate = nil
    }

    func testCommandWClosesAndCanBeTurnedOff() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.orderBack(nil)
        window.closesOnCommandW = false
        XCTAssert(!window.performKeyEquivalent(with: key("w", keyCode: 13, window: window)))
        XCTAssert(window.isVisible)
        window.closesOnCommandW = true
        XCTAssert(window.performKeyEquivalent(with: key("w", keyCode: 13, window: window)))
        XCTAssert(!window.isVisible)
    }

    func testLayoutAccentStripSeparatorBody() {
        let left = StripButton(glyph: .back, label: "Back")
        let right = StripButton(glyph: .forward, label: "Forward")
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), leading: [left], trailing: [right])
        window.setContent(NSHostingView(rootView: Color.red))
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.accentBar.frame.height, ChromeMetrics.accentHeight)
        XCTAssert(abs(window.strip.frame.height - ChromeMetrics.stripHeight) < 0.5)
        XCTAssertEqual(window.body.subviews.count, 1)
        XCTAssertEqual(window.strip.buttons.map(\.glyph), [.close, .back, .forward])
        let leftFrame = left.convert(left.bounds, to: nil), rightFrame = right.convert(right.bounds, to: nil)
        XCTAssert(leftFrame.minX < rightFrame.minX)
        XCTAssert(rightFrame.maxX <= 500)
        window.removeContent()
        XCTAssert(window.body.subviews.isEmpty)
    }

    func testEditCommandsReachTheTextFieldWithoutAnEditMenu() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200))
        let field = NSTextField(string: "hello")
        field.frame = NSRect(x: 10, y: 10, width: 200, height: 24)
        window.body.addSubview(field)
        window.orderBack(nil)
        XCTAssert(window.makeFirstResponder(field))
        XCTAssert(window.performKeyEquivalent(with: key("a", keyCode: 0, window: window)))
        XCTAssertEqual((field.currentEditor() as? NSTextView)?.selectedRange(), NSRange(location: 0, length: 5))
        // ⌘Q and other commands are left to the app's menu.
        XCTAssert(!window.performKeyEquivalent(with: key("q", keyCode: 12, window: window)))
        // A non-text first responder (a web view) keeps the normal path for edit keys.
        let custom = NSView(frame: NSRect(x: 0, y: 50, width: 50, height: 50))
        window.body.addSubview(custom)
        _ = window.makeFirstResponder(window.contentView)
        XCTAssert(!window.performKeyEquivalent(with: key("a", keyCode: 0, window: window)))
        window.close()
    }

    func testChromeHeightSizesTheBody() {
        XCTAssertEqual(ChromeMetrics.chromeHeight(), ChromeMetrics.accentHeight + ChromeMetrics.stripHeight + 1)
        XCTAssertEqual(ChromeMetrics.windowSize(forBody: NSSize(width: 540, height: 485)).height, 485 + ChromeMetrics.chromeHeight())
    }

    func testFixedWindowsHaveNoResizeOrFullScreen() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), resizable: false, showsTitle: true)
        window.title = "Demo Settings"
        XCTAssert(!window.styleMask.contains(.resizable))
        XCTAssert(!window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssert(!window.strip.handlesDoubleClick)
        XCTAssertEqual(window.strip.title, "Demo Settings")
    }

    func testStripButtonColorsFollowTheWindowStyle() {
        let style = ChromeStyle(panel: .white, ink: .black, muted: .gray, accent: .orange, separator: .lightGray)
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), style: style)
        XCTAssertEqual(window.closeButton.resolvedStyle, style)
        XCTAssertEqual(window.closeButton.glyphColor(), .gray)
        XCTAssert(window.closeButton.isDestructive)
        var tinted = style
        tinted.destructiveHover = nil
        window.setChromeStyle(tinted)
        XCTAssertEqual(window.closeButton.resolvedStyle.destructiveHover, nil)
        XCTAssertEqual(window.accentBar.color, .orange)
        window.closeButton.isEnabled = false
        var pressed = false
        window.closeButton.onPress = { _ in pressed = true }
        window.closeButton.performPress()
        XCTAssert(!pressed)
    }

    func testHostedWindowControllerReleasesContent() {
        var builds = 0
        var closes = 0
        let controller = HostedWindowController(window: { ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200)) },
                                                content: { builds += 1; return NSView() })
        controller.onClose = { closes += 1 }
        controller.show(activate: false)
        let first = controller.window as? ChromeWindow
        XCTAssertEqual(first?.body.subviews.count, 1)
        XCTAssert(controller.isOpen)
        (controller.window as? ChromeWindow)?.closeButton.performPress()
        XCTAssertEqual(controller.window, nil)
        XCTAssertEqual(first?.body.subviews.isEmpty, true)
        XCTAssertEqual(closes, 1)
        controller.show(activate: false)
        XCTAssertEqual(builds, 2)
        controller.close()
    }

    func testSwiftUIContentStartsRightBelowTheChrome() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 223))
        let hosting = window.setContent(Color.red.frame(width: 300, height: 200))
        window.contentView?.layoutSubtreeIfNeeded()
        // The hosting view's 13.3+ safe-area property is unavailable on 10.15; verify it fills the body instead.
        XCTAssertEqual(hosting.frame, window.body.bounds)
        XCTAssertEqual(hosting.fittingSize.height, 200)
        XCTAssert(abs(window.body.frame.height - 200) < 0.5)
        XCTAssertEqual(window.contentSize(forBody: NSSize(width: 300, height: 600)).height, 600 + ChromeMetrics.chromeHeight())
    }

    func testHostedControllerPreparesWithoutShowingAndFitsContent() {
        let controller = HostedWindowController(window: { ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), resizable: false) },
                                                rootView: { Color.blue.frame(width: 320, height: 180) })
        controller.sizesToFitContent = true
        let window = controller.prepare()
        XCTAssert(!window.isVisible && !controller.isOpen)
        XCTAssert(controller.prepare() === window)
        XCTAssert(abs((window as! ChromeWindow).body.frame.height - 180) < 0.5)
        XCTAssert(abs(window.contentLayoutRect.width - 320) < 0.5)
    }

    func testWindowReferenceFindsItsHost() {
        let reference = WindowReference()
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.setContent(Color.clear.windowReference(reference))
        window.contentView?.layoutSubtreeIfNeeded()
        window.orderBack(nil)
        XCTAssert(reference.window === window)
        reference.close()
        XCTAssert(!window.isVisible)
    }
}

final class BobukPanelTests: XCTestCase {
    func testKinds() {
        let launcher = BobukPanel(kind: .launcher)
        XCTAssertEqual(launcher.level, .popUpMenu)
        XCTAssert(launcher.styleMask.contains(.nonactivatingPanel))
        XCTAssert(launcher.collectionBehavior.contains(.stationary))
        XCTAssert(launcher.routesEditCommands)
        XCTAssert(launcher.canBecomeKey && !launcher.canBecomeMain)
        let prompt = BobukPanel(kind: .prompt)
        XCTAssert(!prompt.styleMask.contains(.nonactivatingPanel))
        XCTAssert(prompt.dismissesOnAppDeactivation && !prompt.routesEditCommands)
        let hud = BobukPanel(kind: .hud)
        XCTAssert(hud.ignoresMouseEvents && !hud.canBecomeKey && !hud.dismissesOnResignKey)
    }

    func testDismissalIsSuspendedWhileAMenuTracks() {
        let panel = BobukPanel(kind: .floating)
        var reasons: [BobukPanel.DismissReason] = []
        panel.onDismiss = { reasons.append($0); panel.orderOut(nil) }
        panel.orderBack(nil)
        panel.suspendDismissal()
        panel.resignKey()
        XCTAssert(reasons.isEmpty)
        panel.resumeDismissal()
        panel.resignKey()
        panel.orderBack(nil)
        panel.cancelOperation(nil)
        XCTAssert(reasons.contains(.resignedKey) || reasons.contains(.escape))
        XCTAssertEqual(reasons.last, .escape)
    }

    func testCommandKeysAreRoutedAndSwallowed() {
        let panel = BobukPanel(kind: .launcher)
        var seen: [EditCommand] = []
        panel.onCommandKey = { _, command in seen.append(command); return command == .commandReturn }
        func event(_ c: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = .command) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)!
        }
        XCTAssert(panel.performKeyEquivalent(with: event("q", 12)))      // ⌘Q swallowed
        XCTAssert(!panel.performKeyEquivalent(with: event("", 123)))     // ⌘← to the editor
        XCTAssert(panel.performKeyEquivalent(with: event("\r", 36)))     // ⌘↩ handled by the app
        XCTAssertEqual(seen, [.other, .editor, .commandReturn])
        // Panels with their own SwiftUI shortcuts let other ⌘ keys through.
        panel.swallowsOtherCommandKeys = false
        XCTAssert(!panel.performKeyEquivalent(with: event("q", 12)))
        XCTAssert(panel.routesEditCommands)
    }
}

final class EditCommandTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(EditCommand.classify(keyCode: 9, latin: "v", flags: .command), .text(#selector(NSText.paste(_:))))
        XCTAssertEqual(EditCommand.classify(keyCode: 6, latin: "z", flags: [.command, .shift]), .text(Selector(("redo:"))))
        XCTAssertEqual(EditCommand.classify(keyCode: 13, latin: "w", flags: .command), .close)
        XCTAssertEqual(EditCommand.classify(keyCode: 12, latin: "q", flags: .command), .other)
        XCTAssertEqual(EditCommand.classify(keyCode: 36, latin: nil, flags: .command), .commandReturn)
        XCTAssertEqual(EditCommand.classify(keyCode: 36, latin: nil, flags: [.command, .shift]), .other)
        XCTAssertEqual(EditCommand.classify(keyCode: 51, latin: nil, flags: [.command, .option]), .editor)
        XCTAssertEqual(EditCommand.classify(keyCode: 9, latin: "v", flags: []), .notCommand)
        // The physical V key typed with a Cyrillic layout still pastes: the router gets "v".
        XCTAssertEqual(EditCommand.classify(keyCode: 9, latin: "v", flags: [.command, .capsLock]), .text(#selector(NSText.paste(_:))))
    }
}

final class GlyphTests: XCTestCase {
    func testEveryGlyphHasAnOutlineInsideItsBox() {
        let box = CGRect(x: 0, y: 0, width: 16, height: 16)
        for glyph in Glyph.allCases {
            let bounds = glyph.path(in: box).boundingBoxOfPath
            XCTAssert(!bounds.isNull && bounds.width + bounds.height > 1, "\(glyph)")
            XCTAssert(box.insetBy(dx: -1, dy: -1).contains(bounds), "\(glyph)")
        }
        XCTAssert(Glyph.close.isDestructive && Glyph.terminate.isDestructive && !Glyph.back.isDestructive)
        XCTAssertEqual(Glyph.lineWidth(for: CGRect(x: 0, y: 0, width: 8, height: 8)), 0.8)
    }

    func testPaletteHelpers() {
        let color = NSColor(hex: 0x885500).usingColorSpace(.sRGB)!
        XCTAssert(abs(color.redComponent - 0x88 / 255.0) < 0.001)
        XCTAssertEqual(AppearanceChoice.light.appearance?.name, .aqua)
        XCTAssertEqual(AppearanceChoice.system.appearance, nil)
        let suite = UserDefaults(suiteName: "bobukkit-appearance-\(UUID().uuidString)")!
        XCTAssertEqual(AppearanceChoice.stored(in: suite, key: "theme", fallback: .dark), .dark)
        suite.set("light", forKey: "theme")
        XCTAssertEqual(AppearanceChoice.stored(in: suite, key: "theme"), .light)
    }
}
#endif
