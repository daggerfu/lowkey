import WebKit
import XCTest
@testable import LowkeyLib

final class PageUploadTests: XCTestCase {
    func testAttachesBytesToUniqueInputWithoutSubmitting() {
        UITest.onMain {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: .zero, configuration: config)
            let url = URL(string: "https://upload-test.invalid/")!
            UITest.loadPage(view, html: """
            <form onsubmit="event.preventDefault();document.title='submitted'"><input id=f type=file accept='.pdf' hidden></form>
            <script>f.onchange=()=>document.title='selected'</script>
            """, baseURL: url)
            func attach(_ name: String, _ field: String?, _ startURL: URL) -> String {
                var output = ""
                var done = false
                PageUpload.attach(in: view, startURL: startURL, name: name, bytes: Data([0, 255, 13]), field: field) { result in
                    output = result
                    done = true
                }
                UITest.pump(until: { done })
                return output
            }
            XCTAssertEqual(attach("a.pdf", nil, URL(string: "https://other.invalid")!), "wrong site origin")
            XCTAssertEqual(attach("a.png", nil, url), "file type not accepted")
            XCTAssertEqual(try? UITest.evaluate(view, "f.files.length") as? Int, 0)
            XCTAssertEqual(attach("a b.pdf", nil, url), "ok")
            XCTAssertEqual(try? UITest.evaluate(view, "[document.title,f.files[0].name,f.files[0].type]") as? [String],
                           ["selected", "a b.pdf", "application/pdf"])
            // callAsyncJavaScript (await inside JS) is macOS 12; read the bytes via a callback instead.
            _ = try? UITest.evaluate(view, """
            f.files[0].arrayBuffer().then(b => { window.__bytes = Array.from(new Uint8Array(b)); }); void 0
            """)
            UITest.pump(until: { (try? UITest.evaluate(view, "window.__bytes !== undefined")) as? Bool == true }, timeout: 5)
            XCTAssertEqual(try? UITest.evaluate(view, "window.__bytes") as? [Int], [0, 255, 13])
            _ = try? UITest.evaluate(view, "f.after(f.cloneNode());void 0")
            XCTAssertEqual(attach("a.pdf", nil, url), "multiple file inputs")
            _ = try? UITest.evaluate(view, """
            document.body.innerHTML='<label>Avatar<input type=file></label><label for="doc">Документ</label><input id="doc" type=file>';
            void 0
            """)
            XCTAssertEqual(attach("b.pdf", "Документ", url), "ok")
            XCTAssertEqual(try? UITest.evaluate(view, "[...document.querySelectorAll('input')].map(i=>i.files.length)") as? [Int], [0, 1])
            XCTAssertEqual(attach("c.pdf", "Missing", url), "field not found")
            _ = try? UITest.evaluate(view, "document.querySelector('input').setAttribute('aria-label','Документ');void 0")
            XCTAssertEqual(attach("c.pdf", "Документ", url), "ambiguous field")
        }
    }
}
