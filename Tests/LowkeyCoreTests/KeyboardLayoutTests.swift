import Foundation
import XCTest
@testable import LowkeyCore

final class KeyboardLayoutTests: XCTestCase {
    private let ha = Site(alias: "HA", title: "Home Assistant", startURL: "https://homeassistant.local")

    // BobukCore's KeyboardLayoutSwap tests cover the variants themselves; these cover lowkey's use.
    func testOpensAnExactAliasInAnotherLayout() {
        XCTAssertEqual(AddressResolver.resolve("рф", sites: [ha]), .site(ha))
        XCTAssertEqual(AddressResolver.resolve("  РФ  ", sites: [ha]), .site(ha))
    }

    func testSearchesAliasesTitlesAndHistory() {
        let telegram = Site(alias: "TG", title: "Телеграм", startURL: "https://web.telegram.org")
        let history = InputHistory(entries: ["https://google.com", "https://github.com"])
        XCTAssertEqual(Suggestions.make(query: "рф", sites: [ha], history: history), [.site(ha)])
        XCTAssertEqual(Suggestions.make(query: "пщщпду", sites: [], history: history), [.history("https://google.com")])
        XCTAssertEqual(Suggestions.make(query: "ntktuhfv", sites: [telegram], history: history), [.site(telegram)])
        XCTAssertEqual(Suggestions.make(query: "пше", sites: [], history: history), [.history("https://github.com")])
    }

    func testDirectSpellingRanksBeforeLayoutAlternativesAndNeverDuplicates() {
        let latin = Site(alias: "A", title: "Figma", startURL: "https://a.example")
        let cyrillic = Site(alias: "B", title: "Альфа", startURL: "https://b.example")
        let result = Suggestions.make(query: "а", sites: [latin, cyrillic], history: InputHistory())
        XCTAssertEqual(result.first, .site(cyrillic))
        XCTAssertEqual(result.count, 2)
        let history = InputHistory(entries: ["https://aa.example"])
        XCTAssertEqual(Suggestions.make(query: "a", sites: [], history: history).count, 1)
    }

    func testValidURLsAndPathCaseAreNotRewritten() {
        // macOS 10.15's Foundation only parses ASCII hosts: use punycode and a percent-encoded query.
        let address = "https://xn--e1afmkfd.xn--p1ag/CaseSensitive?Q=%D0%A2%D0%B5%D1%81%D1%82"
        XCTAssertEqual(AddressResolver.resolve(address, sites: [ha]), .url(URL(string: address)!))
        XCTAssertEqual(AddressResolver.resolve("https://google.com/CaseSensitive", sites: []), .url(URL(string: "https://google.com/CaseSensitive")!))
    }
}
