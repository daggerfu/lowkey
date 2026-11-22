import WebKit
import LowkeyCore
import XCTest
@testable import LowkeyLib

final class PageControlsTests: XCTestCase {
    func testFormCommands() {
        UITest.onMain {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 480, height: 300), configuration: config)
            let url = URL(string: "https://demo.invalid")!
            UITest.loadPage(view, html: """
            <input aria-label="Comment" id="t" value="private-content"><label>Period<select id="s"><option>One</option><option>Two</option></select></label>
            <button disabled>Send</button><input type="password" value="another-secret">
            """, baseURL: url)
            func run(_ cmd: PageCommand, _ args: [String] = []) -> String {
                var output = ""
                var done = false
                PageControls.run(cmd, args: args, view: view, site: url) { result in
                    output = result
                    done = true
                }
                UITest.pump(until: { done })
                return output
            }
            XCTAssertEqual(run(.wait), "ok")
            XCTAssertEqual(run(.wait, ["Send"]), "pending")
            let raw = run(.inspect, ["--json"])
            XCTAssertTrue(raw.hasPrefix("output:"))
            let rows = try? JSONSerialization.jsonObject(with: Data(raw.dropFirst(7).utf8)) as? [[String: Any]]
            XCTAssertEqual(rows?.count, 3)
            XCTAssertFalse(raw.contains("secret"))
            XCTAssertFalse(raw.contains("private-content"))
            XCTAssertEqual(run(.fill, ["Comment", "a ' quote"]), "ok")
            XCTAssertEqual(run(.select, ["Period", "Two"]), "ok")
            XCTAssertEqual(try? UITest.evaluate(view, "[t.value,s.value]") as? [String], ["a ' quote", "Two"])
            XCTAssertEqual(run(.select, ["Period", "Three"]), "option not found")
            _ = try? UITest.evaluate(view, "document.querySelector('button').disabled=false;t.after(t.cloneNode());void 0")
            XCTAssertEqual(run(.wait, ["Send"]), "ok")
            XCTAssertEqual(run(.fill, ["Comment", "other"]), "ambiguous label")
            var wrongOrigin = ""
            var done = false
            PageControls.run(.inspect, args: [], view: view, site: URL(string: "https://another.invalid")!) { result in
                wrongOrigin = result
                done = true
            }
            UITest.pump(until: { done })
            XCTAssertEqual(wrongOrigin, "wrong site origin")
        }
    }
}
