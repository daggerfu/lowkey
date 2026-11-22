#if canImport(AppKit)
import AppKit
import XCTest
import BobukUI

/// Subclasses in app modules capture `[weak self]` in notification blocks without warnings.
final class ProbeWindow: ChromeWindow {
    var observer: NSObjectProtocol?
    func observe() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            _ = self?.title
        }
    }
}

final class ProbePanel: BobukPanel {
    var observer: NSObjectProtocol?
    func observe() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            _ = self?.title
        }
    }
}

final class SubclassSendableTests: XCTestCase {
    func testSubclassesCompile() {
        let window = ProbeWindow(contentRect: .zero)
        let panel = ProbePanel(kind: .floating)
        window.observe()
        panel.observe()
        XCTAssertNotNil(window.observer)
        XCTAssertNotNil(panel.observer)
    }
}
#endif
