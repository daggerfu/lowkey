import Foundation
import XCTest
@testable import LowkeyCore

final class ControlRequestTests: XCTestCase {
    func testRoundTrip() throws {
        for command in ["open", "hide", "toggle"] {
            let request = try XCTUnwrap(ControlRequest(["HA-1", command]))
            let decoded = try XCTUnwrap(ControlRequest(payload: request.payload))
            XCTAssertEqual(decoded.command, request.command)
            XCTAssertEqual(decoded.alias, "HA-1")
        }
    }

    func testPortNameKeepsTheV1Format() {
        XCTAssertEqual(ControlRequest.portName(pid: 4242), "io.bobuk.lowkey.control.v1.4242")
    }

    func testPdfRoundTrip() throws {
        let request = try XCTUnwrap(ControlRequest(["HA", "save-pdf", "/tmp/Full page.pdf"]))
        XCTAssertTrue(request.command.isPDFExport)
        XCTAssertEqual(ControlRequest(payload: request.payload)?.command, request.command)
        for args in [[], ["relative.pdf"], ["/tmp/page.txt"], ["/tmp/page.pdf", "extra"], ["/tmp/bad\0.pdf"]] {
            XCTAssertNil(ControlRequest(["HA", "save-pdf"] + args))
        }
    }

    func testUploadRoundTrip() throws {
        let file = Data([0, 255, 10, 0])
        let request = try XCTUnwrap(ControlRequest(alias: "HA", filename: "Файл 1.pdf", bytes: file))
        XCTAssertEqual(ControlRequest(payload: request.payload)?.command, .upload(name: "Файл 1.pdf", bytes: file))
        XCTAssertNil(ControlRequest(payload: Data("upload HA /tmp/private.pdf".utf8)))
        XCTAssertNil(ControlRequest(alias: "HA", filename: "../test.pdf", bytes: file))
        XCTAssertEqual(ControlRequest(["HA", "click", "Обновить"])?.command, .click("Обновить"))
    }

    func testRejectsInvalidInput() {
        for text in ["toggle", "toggle *", "open https://example.org", "reload HA", "open HA extra", "toggle HA\n"] {
            XCTAssertNil(ControlRequest(payload: Data(text.utf8)), text)
        }
    }
}
