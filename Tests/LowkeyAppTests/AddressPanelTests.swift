import AppKit
import SwiftUI
import LowkeyCore
import BobukUI
import XCTest
@testable import LowkeyLib

final class AddressPanelTests: XCTestCase {
    func testSharedRowsKeepColumnsAlignedAndNavigationReturnsToTypedInput() throws {
        try UITest.onMain {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = Store(configURL: root.appendingPathComponent("config.json"))
            let sites = [Site(alias: "HA", title: "Home Control", startURL: "https://home.example.test"),
                         Site(alias: "NOTES", title: "Project Notes", startURL: "https://notes.example.test")]
            XCTAssertTrue(store.update(Config(sites: sites)).isEmpty)
            store.record("https://example.com/demo")
            let app = AppController(store: store)
            let panel = AddressPanel(app: app)
            defer { panel.close() }
            let key = NSApp.keyWindow
            panel.configure(target: nil, newWindow: false, prefill: nil, message: nil)
            XCTAssertTrue(NSApp.keyWindow === key)
            XCTAssertFalse(panel.isVisible)
            guard let content = panel.contentView else { XCTFail("Missing content"); return }
            func rows(_ view: NSView) -> [NSHostingView<SuggestionRow>] {
                if let row = view as? NSHostingView<SuggestionRow> { return [row] }
                return view.subviews.flatMap { rows($0) }
            }
            func fields(_ view: NSView) -> [NSTextField] {
                return (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
            }
            let initial = rows(content)
            XCTAssertEqual(initial.map { $0.rootView.suggestion }, sites.map(Suggestion.site))
            XCTAssertTrue(initial.allSatisfy { !$0.rootView.selected })
            XCTAssertEqual(Set(initial.map { $0.rootView.badgeWidth }).count, 1)
            XCTAssertTrue(initial.allSatisfy { abs($0.frame.height - PickerMetrics.rowHeight) < 0.01 })
            XCTAssertEqual(Set(initial.map { $0.frame.width }).count, 1)
            XCTAssertLessThan(abs(panel.frame.width - AddressPanel.width), 0.01)
            let field = try XCTUnwrap(fields(content).first { $0.isEditable })
            let editor = NSTextView()
            XCTAssertTrue(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
            XCTAssertEqual(rows(content).map { $0.rootView.selected }, [true, false])
            XCTAssertTrue(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
            XCTAssertTrue(rows(content).allSatisfy { !$0.rootView.selected })
            XCTAssertTrue(app.allBrowsers.isEmpty)

            if let folder = ProcessInfo.processInfo.environment["BOBUKKIT_PREVIEW_DIR"] {
                let output = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: output.appendingPathComponent("lowkey-address.png"))
            }

            func query(_ text: String) {
                field.stringValue = text
                panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            }
            query("demo")
            XCTAssertEqual(rows(content).map { $0.rootView.suggestion }, [.history("https://example.com/demo")])
            query("")
            XCTAssertEqual(rows(content).map { $0.rootView.suggestion }, sites.map(Suggestion.site))
            query("demo")
            let history = try XCTUnwrap(rows(content).first { if case .history = $0.rootView.suggestion { return true }; return false })
            history.rootView.onRemove()
            XCTAssertTrue(rows(content).isEmpty)
            XCTAssertTrue(store.history.entries.isEmpty)
            XCTAssertEqual(store.config.sites, sites)
        }
    }
}
