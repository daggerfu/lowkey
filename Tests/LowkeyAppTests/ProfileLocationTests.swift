import AppKit
import WebKit
import LowkeyCore
import XCTest
@testable import LowkeyLib

/// No windows are shown, no real profiles/config are used, and no key presses are sent.
final class ProfileLocationTests: XCTestCase {
    private func fixture() throws -> (AppController, BrowserWindowController, URL) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lowkey-profile-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = AppController(store: Store(configURL: folder.appendingPathComponent("config.json")))
        let browser = BrowserWindowController(kind: .ordinary,
                                              startURL: URL(string: "http://127.0.0.1:1/")!,
                                              dataStore: .nonPersistent(), app: app)
        return (app, browser, folder)
    }

    func testForcedLocationKeepsTheExactWebViewAndProfileAndIsOneShot() throws {
        try UITest.onMain {
            let (app, browser, folder) = try self.fixture()
            defer { browser.close(); try? FileManager.default.removeItem(at: folder); withExtendedLifetime(app) {} }
            let webView = browser.webView
            let dataStore = webView.configuration.websiteDataStore
            let address = URL(string: "http://127.0.0.1:1/sign-in")!
            browser.loadInCurrentProfile(address)
            XCTAssertTrue(browser.webView === webView)
            XCTAssertTrue(browser.webView.configuration.websiteDataStore === dataStore)
            XCTAssertFalse(browser.consumeProfileLocation(URL(string: "http://127.0.0.1:1/other")!))
            XCTAssertTrue(browser.consumeProfileLocation(address))
            XCTAssertFalse(browser.consumeProfileLocation(address))
            XCTAssertTrue(app.ordinaryWindows.isEmpty)
            XCTAssertTrue(app.siteWindows.isEmpty)
            XCTAssertTrue(browser.popups.isEmpty)
        }
    }

    func testSavedSiteKeepsItsProfileAndRulesForAnExternalLocation() throws {
        try UITest.onMain {
            let (app, unused, folder) = try self.fixture()
            defer { unused.close(); try? FileManager.default.removeItem(at: folder) }
            let site = Site(alias: "demo", startURL: "http://localhost:1/")
            var config = app.store.config
            config.sites = [site]
            XCTAssertTrue(app.store.update(config).isEmpty)
            let browser = BrowserWindowController(kind: .saved(site.id), startURL: site.url!,
                                                  dataStore: .nonPersistent(), app: app)
            defer { browser.close(); NSWindow.removeFrame(usingName: SiteWindowPlacement(siteID: site.id).name) }
            let dataStore = browser.webView.configuration.websiteDataStore
            let address = URL(string: "http://127.0.0.1:1/sign-in")!
            XCTAssertEqual(LinkPolicy.decide(linkTo: address, site: browser.site), .openExternally)
            browser.loadInCurrentProfile(address)
            XCTAssertTrue(browser.consumeProfileLocation(address))
            XCTAssertTrue(browser.webView.configuration.websiteDataStore === dataStore)
            XCTAssertEqual(app.store.config.sites, [site])
            XCTAssertEqual(LinkPolicy.decide(linkTo: address, site: browser.site), .openExternally)
            XCTAssertTrue(browser.popups.isEmpty)
            XCTAssertTrue(app.ordinaryWindows.isEmpty)
        }
    }

    func testRegularLoadClearsTheOverride() throws {
        try UITest.onMain {
            let (app, browser, folder) = try self.fixture()
            defer { browser.close(); try? FileManager.default.removeItem(at: folder); withExtendedLifetime(app) {} }
            let address = URL(string: "http://127.0.0.1:1/sign-in")!
            browser.loadInCurrentProfile(address)
            browser.load(URL(string: "http://127.0.0.1:1/home")!)
            XCTAssertFalse(browser.consumeProfileLocation(address))
        }
    }

    func testMissingTargetNeverFallsBackToAnotherProfile() throws {
        try UITest.onMain {
            let (app, browser, folder) = try self.fixture()
            defer { browser.close(); try? FileManager.default.removeItem(at: folder) }
            XCTAssertNotNil(app.submit("http://127.0.0.1:1/sign-in", target: nil, newWindow: true,
                                       inCurrentProfile: true))
            XCTAssertTrue(app.ordinaryWindows.isEmpty)
            XCTAssertTrue(app.store.history.entries.isEmpty)
        }
    }

    func testInvalidLocationDoesNotLoadOrRecordAnything() throws {
        try UITest.onMain {
            let (app, browser, folder) = try self.fixture()
            defer { browser.close(); try? FileManager.default.removeItem(at: folder) }
            XCTAssertNotNil(app.submit("not a web address", target: browser, newWindow: false,
                                       inCurrentProfile: true))
            XCTAssertNil(browser.webView.url)
            XCTAssertTrue(app.store.history.entries.isEmpty)
        }
    }
}
