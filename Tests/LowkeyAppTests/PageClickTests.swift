import WebKit
import XCTest
@testable import LowkeyLib

final class PageClickTests: XCTestCase {
    func testOnlyClicksOneMatchingControlOnTheSavedOrigin() {
        UITest.onMain {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: config)
            let site = URL(string: "https://click-test.invalid/")!
            UITest.loadPage(view, html: """
            <meta charset="utf-8"><body onclick="document.body.dataset.hit=event.target.id">
            <button id="refresh">Обновить  список</button><a href="#next" id="go">Go</a>
            <button hidden>Go</button><button>Double</button><a href="#two">Double</a>
            <button disabled>Disabled</button><a href="javascript:void(0)">Script</a>
            """, baseURL: site)
            func perform(_ label: String, _ url: URL) -> String {
                var output = ""
                var done = false
                PageClick.perform(in: view, startURL: url, label: label) { result in
                    output = result
                    done = true
                }
                UITest.pump(until: { done })
                return output
            }
            XCTAssertEqual(perform("Обновить список", site), "ok")
            XCTAssertEqual(try? UITest.evaluate(view, "document.body.dataset.hit") as? String, "refresh")
            XCTAssertEqual(perform("Go", site), "ok")
            XCTAssertEqual(perform("Double", site), "ambiguous label")
            XCTAssertEqual(perform("Missing", site), "label not found")
            XCTAssertEqual(perform("Disabled", site), "control disabled")
            XCTAssertEqual(perform("Script", site), "unsupported link")
            XCTAssertEqual(perform("Обновить список", URL(string: "https://other.invalid")!), "wrong site origin")
            XCTAssertEqual(try? UITest.evaluate(view, "document.body.dataset.hit") as? String, "go")
        }
    }
}
