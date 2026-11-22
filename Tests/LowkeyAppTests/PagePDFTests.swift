import PDFKit
import WebKit
import XCTest
@testable import LowkeyLib

final class PagePDFTests: XCTestCase {
    /// Full print pagination with print CSS needs `WKWebView.printOperation(with:)`, macOS 11.
    /// On Catalina printing falls back to the plain view, which neither paginates nor
    /// applies print styles, so the content assertions cannot run there.
    func testPrintsEntireDocumentAndPrintStyles() throws {
        #if compiler(>=5.4)
        if #available(macOS 11, *) {
            try runAssertions()
        } else {
            throw XCTSkip("WKWebView.printOperation(with:) requires macOS 11")
        }
        #else
        throw XCTSkip("WKWebView.printOperation(with:) requires macOS 11")
        #endif
    }

    #if compiler(>=5.4)
    @available(macOS 11, *)
    private func runAssertions() throws {
        try UITest.onMain {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 480, height: 300), configuration: configuration)
            let origin = URL(string: "https://pdf-demo.invalid")!
            UITest.loadPage(view, html: """
            <style>@media print { .screen { display: none } } section { height: 1800px }</style>
            <div class="screen">SCREENONLY</div><section>FIRSTMARKER</section><p>LASTMARKER</p>
            """, baseURL: origin)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let destination = directory.appendingPathComponent("whole page.pdf")
            func run(_ site: URL) -> String {
                var output = ""
                var done = false
                PageControls.run(.savePDF, args: [destination.path], view: view, site: site) { result in
                    output = result
                    done = true
                }
                UITest.pump(until: { done }, timeout: 70)
                return output
            }
            XCTAssertEqual(run(origin), "ok")
            let document = try XCTUnwrap(PDFDocument(url: destination))
            XCTAssertGreaterThan(document.pageCount, 1)
            let text = try XCTUnwrap(document.string)
            XCTAssertTrue(text.contains("FIRSTMARKER"))
            XCTAssertTrue(text.contains("LASTMARKER"))
            XCTAssertFalse(text.contains("SCREENONLY"))
            let original = try Data(contentsOf: destination)
            XCTAssertTrue(run(origin).hasPrefix("PDF export failed:"))
            XCTAssertEqual(try Data(contentsOf: destination), original)
            XCTAssertEqual(run(URL(string: "https://other.invalid")!), "wrong site origin")
        }
    }
    #endif
}
