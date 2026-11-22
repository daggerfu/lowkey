import AppKit
import XCTest
@testable import LowkeyLib

/// No visible windows, synthetic keypresses, real aliases or real website profiles.
final class SiteWindowPlacementTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 600, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    func testRestoresSizeAndPositionForTheSameSite() {
        UITest.onMain {
            let siteID = UUID()
            let placement = SiteWindowPlacement(siteID: siteID)
            defer { NSWindow.removeFrame(usingName: placement.name) }
            let first = self.makeWindow()
            placement.restore(first)
            let frame = NSRect(x: 220, y: 180, width: 700, height: 460)
            first.setFrame(frame, display: false)
            placement.save(first)
            first.close()

            let reopened = self.makeWindow()
            // A new persistence object models a recreated controller or a fresh app process.
            SiteWindowPlacement(siteID: siteID).restore(reopened)
            XCTAssertEqual(reopened.frame, frame)
            reopened.close()
        }
    }

    func testDifferentSitesKeepIndependentFrames() {
        UITest.onMain {
            let a = SiteWindowPlacement(siteID: UUID())
            let b = SiteWindowPlacement(siteID: UUID())
            defer { NSWindow.removeFrame(usingName: a.name); NSWindow.removeFrame(usingName: b.name) }
            let window = self.makeWindow()
            a.restore(window)
            let frameA = NSRect(x: 120, y: 150, width: 600, height: 400)
            window.setFrame(frameA, display: false)
            a.save(window)
            b.restore(window)
            let frameB = NSRect(x: 260, y: 200, width: 800, height: 500)
            window.setFrame(frameB, display: false)
            b.save(window)

            a.restore(window)
            XCTAssertEqual(window.frame, frameA)
            b.restore(window)
            XCTAssertEqual(window.frame, frameB)
            window.close()
        }
    }

    func testFullScreenTransitionDoesNotReplaceNormalFrame() {
        UITest.onMain {
            let siteID = UUID()
            let placement = SiteWindowPlacement(siteID: siteID)
            defer { NSWindow.removeFrame(usingName: placement.name) }
            let window = self.makeWindow()
            placement.restore(window)
            let normal = NSRect(x: 160, y: 160, width: 640, height: 440)
            window.setFrame(normal, display: false)
            placement.save(window)
            placement.willEnterFullScreen()
            window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
            placement.save(window)

            let check = self.makeWindow()
            SiteWindowPlacement(siteID: siteID).restore(check)
            XCTAssertEqual(check.frame, normal)
            check.close()

            placement.willExitFullScreen()
            window.setFrame(normal, display: false)
            placement.didExitFullScreen(window)
            let changed = NSRect(x: 180, y: 180, width: 680, height: 450)
            window.setFrame(changed, display: false)
            placement.save(window)
            placement.restore(window)
            XCTAssertEqual(window.frame, changed)
            window.close()
        }
    }
}
