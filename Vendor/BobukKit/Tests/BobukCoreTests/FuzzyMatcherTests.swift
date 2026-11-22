import XCTest
@testable import BobukCore

final class FuzzyMatcherTests: XCTestCase {
    private func kind(_ query: String, _ text: String) -> FuzzyMatchKind? { FuzzyMatcher.match(query, in: text)?.kind }

    func testContiguousKinds() {
        XCTAssertEqual(kind("safari", "Safari"), .exact)
        XCTAssertEqual(kind("SAF", "Safari"), .prefix)
        XCTAssertEqual(kind("visual studio code", "Visual Studio Code"), .exact)
        XCTAssertEqual(kind("visualstu", "Visual Studio Code"), .prefix)
        XCTAssertEqual(kind("code", "Visual Studio Code"), .wordStart)
        XCTAssertEqual(kind("studio co", "Visual Studio Code"), .wordStart)
        XCTAssertEqual(kind("vis co", "Visual Studio Code"), .wordStart)
        XCTAssertEqual(kind("vsc", "Visual Studio Code"), .initials)
        XCTAssertEqual(kind("udi", "Visual Studio Code"), .substring)
        XCTAssertEqual(kind("time", "FaceTime"), .wordStart)
        XCTAssertEqual(kind("ft", "FaceTime"), .initials)
        XCTAssertEqual(kind("node.js", "Node.js"), .exact)
        XCTAssertEqual(kind("7", "1Password 7"), .wordStart)
    }

    func testScatteredLetters() {
        XCTAssertEqual(kind("1pwd", "1Password"), .scattered)
        XCTAssertEqual(kind("terminl", "Terminal"), .scattered)
        XCTAssertEqual(kind("xcd", "Xcode"), .scattered)
        XCTAssertEqual(kind("code vis", "Visual Studio Code"), nil)
        XCTAssertEqual(kind("xyz", "Visual Studio Code"), nil)
    }

    func testTypos() {
        let wrong = FuzzyMatcher.match("1pvd", in: "1Password")
        XCTAssertEqual(wrong?.kind, .typo)
        XCTAssertEqual(wrong?.typos, 1)
        XCTAssertEqual(kind("1pasxsword", "1Password"), .typo)
        XCTAssertEqual(kind("setigns", "System Settings"), .typo)
        // Short queries get no typos; the first letter never is one.
        XCTAssertEqual(kind("1pv", "1Password"), nil)
        XCTAssertEqual(kind("xpwd", "1Password"), nil)
        // Two typos only from eight letters.
        XCTAssertEqual(kind("1pazzwrd", "1Password") , .typo)
        XCTAssertEqual(kind("1pzzd", "1Password"), nil)
        XCTAssertEqual(FuzzyMatcher.match("1pvd", in: "1Password", typos: false), nil)
    }

    func testFallbackTypoForThreeLetters() {
        let query = FuzzyQuery("1pv")
        XCTAssert(query.hasFallback)
        XCTAssertEqual(query.match("1Password"), nil)
        XCTAssertEqual(query.match("1Password", fallback: true)?.kind, .typo)
        XCTAssert(!FuzzyQuery("1p").hasFallback)
        XCTAssert(!FuzzyQuery("1pwd").hasFallback)
        XCTAssert(!FuzzyQuery("1pv", typos: false).hasFallback)
        XCTAssertEqual(FuzzyQuery("xpv").match("1Password", fallback: true), nil)
        // The filter falls back only when the normal pass matched nothing.
        let apps = ["1Password", "Safari", "Spotify", "Slack"]
        XCTAssertEqual(FuzzyMatcher.filter(apps, matching: "1pv", texts: { [$0] }), ["1Password"])
        XCTAssertEqual(FuzzyMatcher.filter(apps, matching: "saf", texts: { [$0] }), ["Safari"])
    }

    func testFoldingAndLayouts() {
        XCTAssertEqual(kind("cafe", "Café Racer"), .prefix)
        XCTAssertEqual(kind("CAFÉ", "cafe"), .exact)
        XCTAssertEqual(kind("елка", "Ёлка"), .exact)
        XCTAssertEqual(kind("ыфафкш", "Safari"), .exact)
        XCTAssertEqual(kind("ntktuhfv", "Телеграм"), .exact)
        XCTAssertEqual(kind("ьуыыфпуы", "Messages"), .exact)
        XCTAssertEqual(FuzzyMatcher.match("ыфафкш", in: "Safari", layoutSwap: false), nil)
        XCTAssertEqual(kind("strasse", "Straße"), .exact)
    }

    func testEmptyInputs() {
        XCTAssertEqual(FuzzyMatcher.match("", in: "Safari"), nil)
        XCTAssertEqual(FuzzyMatcher.match("  -", in: "Safari"), nil)
        XCTAssertEqual(FuzzyMatcher.match("a", in: ""), nil)
        XCTAssert(FuzzyQuery(" - ").isEmpty)
    }

    func testPositionsForHighlighting() {
        XCTAssertEqual(FuzzyMatcher.match("1pwd", in: "1Password")?.positions, [0, 1, 5, 8])
        XCTAssertEqual(FuzzyMatcher.match("vsc", in: "Visual Studio Code")?.positions, [0, 7, 14])
        XCTAssertEqual(FuzzyMatcher.match("saf", in: "Safari")?.positions, [0, 1, 2])
        // Wrong and extra letters are not highlighted.
        XCTAssertEqual(FuzzyMatcher.match("1pvd", in: "1Password")?.positions.count, 3)
        // Offsets are characters of the original text, also after "ß" folds to "ss".
        XCTAssertEqual(FuzzyMatcher.match("ae", in: "Straße")?.positions, [3, 5])
    }

    func testScoresPreferWordStartsAndRuns() {
        let boundary = FuzzyMatcher.match("bm", in: "BatMan")!
        let inside = FuzzyMatcher.match("bm", in: "Batman")!
        XCTAssert(boundary.score > inside.score)
        let safari = FuzzyMatcher.match("sfri", in: "Safari")!
        let info = FuzzyMatcher.match("sfri", in: "System Information")!
        XCTAssert(safari.isBetter(than: info))
    }

    func testFilterOrdersByKindThenScoreThenInput() {
        let records = ["A", "AAAA", "CNAME", "MX", "TXT"]
        XCTAssertEqual(FuzzyMatcher.filter(records, matching: "", texts: { [$0] }), records)
        XCTAssertEqual(FuzzyMatcher.filter(records, matching: "m", texts: { [$0] }), ["MX", "CNAME"])
        XCTAssertEqual(FuzzyMatcher.filter(records, matching: "x", texts: { [$0] }), ["MX", "TXT"])
        XCTAssert(FuzzyMatcher.filter(records, matching: "q", texts: { [$0] }).isEmpty)
        let apps = ["System Information", "Safari", "Screen Sharing", "Terminal"]
        XCTAssertEqual(FuzzyMatcher.filter(apps, matching: "sfri", texts: { [$0] }).first, "Safari")
        XCTAssertEqual(FuzzyMatcher.filter(apps, matching: "term", texts: { [$0] }), ["Terminal", "System Information"])
        // Any of the item's texts may match.
        let pairs = [("one", "alpha"), ("two", "beta")]
        XCTAssertEqual(FuzzyMatcher.filter(pairs, matching: "bet", texts: { [$0.0, $0.1] }).map(\.0), ["two"])
    }

    func testLongTextsGetContiguousMatchesOnly() {
        let long = String(repeating: "lorem ipsum ", count: 60) + "needle"
        XCTAssertEqual(FuzzyMatcher.match("needle", in: long)?.kind, .wordStart)
        XCTAssertEqual(FuzzyMatcher.match("ndl", in: long), nil)
    }
}
