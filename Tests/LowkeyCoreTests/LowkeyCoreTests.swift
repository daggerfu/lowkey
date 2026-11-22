import Foundation
import XCTest
@testable import LowkeyCore

private let ha = Site(alias: "HA", title: "Home Assistant", startURL: "https://homeassistant.local",
                      extraOrigins: ["*.nabu.casa", "http://ha.lan:8123"])

final class DeepLinkTests: XCTestCase {
    func testParsesSiteCommands() throws {
        XCTAssertEqual(try DeepLink.parse(URL(string: "lowkey://HA/open")!).get(), .site(alias: "HA", command: .open))
        XCTAssertEqual(try DeepLink.parse(URL(string: "lowkey://ha/Reload")!).get(), .site(alias: "ha", command: .reload))
        XCTAssertEqual(try DeepLink.parse(URL(string: "lowkey://HA")!).get(), .site(alias: "HA", command: .open))
        XCTAssertEqual(try DeepLink.parse(URL(string: "lowkey://HA/")!).get(), .site(alias: "HA", command: .open))
        XCTAssertEqual(try DeepLink.parse(URL(string: "LOWKEY://my_site/close")!).get(), .site(alias: "my_site", command: .close))
    }

    func testEmptyAliasShowsPrompt() throws {
        XCTAssertEqual(try DeepLink.parse(URL(string: "lowkey://")!).get(), .prompt)
    }

    func testRejectsUnknownCommandsAndSchemes() {
        XCTAssertEqual(DeepLink.parse(URL(string: "lowkey://HA/eval")!), .failure(.unknownCommand("eval")))
        XCTAssertEqual(DeepLink.parse(URL(string: "lowkey://HA/open/extra")!), .failure(.unknownCommand("open/extra")))
        XCTAssertEqual(DeepLink.parse(URL(string: "https://HA/open")!), .failure(.notLowkey))
    }
}

final class AddressTests: XCTestCase {
    func testAliasWinsCaseInsensitively() {
        XCTAssertEqual(AddressResolver.resolve("ha", sites: [ha]), .site(ha))
    }

    func testBareHostsGetHTTPS() {
        XCTAssertEqual(AddressResolver.resolve("google.com", sites: [ha]), .url(URL(string: "https://google.com")!))
        XCTAssertEqual(AddressResolver.resolve("nas.local:5000/x", sites: []), .url(URL(string: "https://nas.local:5000/x")!))
    }

    func testLoopbackGetsHTTP() {
        XCTAssertEqual(AddressResolver.resolve("localhost:3000", sites: []), .url(URL(string: "http://localhost:3000")!))
        XCTAssertEqual(AddressResolver.resolve("127.0.0.1:8080", sites: []), .url(URL(string: "http://127.0.0.1:8080")!))
    }

    func testKeepsExplicitWebSchemes() {
        XCTAssertEqual(AddressResolver.resolve("http://ha.lan:8123", sites: []), .url(URL(string: "http://ha.lan:8123")!))
    }

    func testRejectsWordsAndOtherSchemes() {
        XCTAssertEqual(AddressResolver.resolve("unknown", sites: [ha]), .invalid)
        XCTAssertEqual(AddressResolver.resolve("two words.com", sites: []), .invalid)
        XCTAssertEqual(AddressResolver.resolve("file:///etc/passwd", sites: []), .invalid)
        XCTAssertEqual(AddressResolver.resolve("javascript://x.com", sites: []), .invalid)
        XCTAssertEqual(AddressResolver.resolve("   ", sites: []), .invalid)
    }
}

final class HistoryTests: XCTestCase {
    func testRecordsNewestFirstWithoutDuplicates() {
        var history = InputHistory()
        history.record("a.com")
        history.record("b.com")
        history.record("A.com")
        XCTAssertEqual(history.entries, ["A.com", "b.com"])
    }

    func testKeepsLastThousand() {
        var history = InputHistory()
        for i in 0..<1005 { history.record("site\(i).com") }
        XCTAssertEqual(history.entries.count, 1000)
        XCTAssertEqual(history.entries.first, "site1004.com")
        XCTAssertEqual(history.entries.last, "site5.com")
    }

    func testRemovedEntryReturnsWhenSubmitted() {
        var history = InputHistory(entries: ["a.com", "b.com"])
        history.remove("A.COM")
        XCTAssertEqual(history.entries, ["b.com"])
        history.record("a.com")
        XCTAssertEqual(history.entries, ["a.com", "b.com"])
    }

    func testRoundTripsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowkey-history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try InputHistory(entries: ["x.com", "y.com"]).save(to: url)
        XCTAssertEqual(InputHistory.load(from: url).entries, ["x.com", "y.com"])
        // The file format is a plain JSON array without escaped slashes.
        try InputHistory(entries: ["https://a.example/x"]).save(to: url)
        XCTAssertEqual(String(decoding: try Data(contentsOf: url), as: UTF8.self), #"["https://a.example/x"]"#)
        // Codable keeps its `entries` key and drops nothing.
        let coded = try JSONEncoder().encode(InputHistory(entries: ["b.com"]))
        XCTAssertEqual(String(decoding: coded, as: UTF8.self), #"{"entries":["b.com"]}"#)
        XCTAssertEqual(try JSONDecoder().decode(InputHistory.self, from: coded), InputHistory(entries: ["b.com"]))
    }
}

final class SuggestionTests: XCTestCase {
    let grafana = Site(alias: "GRAF", title: "Grafana", startURL: "https://grafana.lan:3000")

    func testSitesComeFirstThenHistory() {
        let history = InputHistory(entries: ["https://github.com", "https://graphql.org", "HA"])
        let result = Suggestions.make(query: "gr", sites: [ha, grafana], history: history)
        XCTAssertEqual(result, [.site(grafana), .history("https://graphql.org")])
    }

    func testBlankQueryListsOnlySavedSites() {
        let history = InputHistory(entries: ["https://github.com"])
        for query in ["", "  \t"] {
            XCTAssertEqual(Suggestions.make(query: query, sites: [ha, grafana], history: history), [.site(ha), .site(grafana)])
            XCTAssertTrue(Suggestions.make(query: query, sites: [], history: history).isEmpty)
        }
    }

    func testHistoryPrefixBeatsContains() {
        let history = InputHistory(entries: ["https://maps.google.com", "https://google.com"])
        let result = Suggestions.make(query: "goo", sites: [], history: history)
        XCTAssertEqual(result, [.history("https://google.com"), .history("https://maps.google.com")])
    }
}

final class LinkPolicyTests: XCTestCase {
    func testOriginsNormalizeDefaultPorts() {
        XCTAssertEqual(Origin(URL(string: "https://A.com")!), Origin(URL(string: "https://a.com:443/x")!))
        XCTAssertNotEqual(Origin(URL(string: "https://a.com")!), Origin(URL(string: "http://a.com")!))
    }

    func testSiteOriginsAndPatterns() {
        XCTAssertTrue(LinkPolicy.isPartOfSite(URL(string: "https://homeassistant.local/lovelace")!, site: ha))
        XCTAssertFalse(LinkPolicy.isPartOfSite(URL(string: "https://sub.homeassistant.local/")!, site: ha))
        XCTAssertTrue(LinkPolicy.isPartOfSite(URL(string: "https://abc.ui.nabu.casa/")!, site: ha))
        XCTAssertFalse(LinkPolicy.isPartOfSite(URL(string: "https://nabu.casa/")!, site: ha))
        XCTAssertTrue(LinkPolicy.isPartOfSite(URL(string: "http://ha.lan:8123/")!, site: ha))
        XCTAssertFalse(LinkPolicy.isPartOfSite(URL(string: "https://ha.lan:8123/")!, site: ha))
    }

    func testExternalLinksFollowSitePolicy() {
        let external = URL(string: "https://example.com")!
        XCTAssertEqual(LinkPolicy.decide(linkTo: external, site: ha), .openExternally)
        var inside = ha
        inside.externalLinks = .lowkey
        XCTAssertEqual(LinkPolicy.decide(linkTo: external, site: inside), .stay)
        XCTAssertEqual(LinkPolicy.decide(linkTo: external, site: nil), .stay)
        XCTAssertEqual(LinkPolicy.decide(linkTo: URL(string: "https://homeassistant.local/x")!, site: ha), .stay)
    }

    func testSignInPagesStay() {
        XCTAssertEqual(LinkPolicy.decide(linkTo: URL(string: "https://accounts.google.com/o/oauth2/auth")!, site: ha), .stay)
        XCTAssertTrue(AuthProviders.isSignIn(URL(string: "https://github.com/login/oauth/authorize")!))
        XCTAssertFalse(AuthProviders.isSignIn(URL(string: "https://github.com/bobuk")!))
        XCTAssertTrue(AuthProviders.isSignIn(URL(string: "https://dev-x.eu.auth0.com/authorize")!))
    }

    func testOtherSchemesLeaveEvenInOrdinaryWindows() {
        XCTAssertEqual(LinkPolicy.decide(linkTo: URL(string: "mailto:a@b.c")!, site: nil), .openExternally)
        XCTAssertEqual(LinkPolicy.decide(linkTo: URL(string: "about:blank")!, site: ha), .stay)
    }

    func testRejectsBadPatterns() {
        XCTAssertNil(OriginPattern("ftp://x.com"))
        XCTAssertNil(OriginPattern("a.*.com"))
        XCTAssertNil(OriginPattern(""))
    }
}

final class ConfigTests: XCTestCase {
    func testValidatesAliasesAndURLs() {
        XCTAssertTrue(Site.isValidAlias("HA"))
        XCTAssertTrue(Site.isValidAlias("my-site_2"))
        XCTAssertFalse(Site.isValidAlias("-x"))
        XCTAssertFalse(Site.isValidAlias("a.b"))
        XCTAssertFalse(Site.isValidAlias("сайт"))
        let config = Config(sites: [ha, Site(alias: "ha", startURL: "ftp://x"), Site(alias: "bad alias", startURL: "x.com")])
        XCTAssertEqual(config.problems().count, 3)
    }

    func testToleratesMissingFields() throws {
        let json = #"{"sites":[{"alias":"HA","startURL":"https://homeassistant.local"}]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.site(alias: "ha")?.externalLinks, .defaultBrowser)
        XCTAssertEqual(config.appearance.mode, .tint)
    }

    func testRoundTripsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowkey-config-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let config = Config(sites: [ha], appearance: AppearanceConfig(mode: .dark))
        try config.save(to: url)
        XCTAssertEqual(try Config.load(from: url), config)
    }

    func testInvalidThemeColorsFallBack() throws {
        let json = ##"{"appearance":{"mode":"light","light":{"preset":"x","panel":"red","accent":"#000000"}}}"##
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.appearance.light, ThemePreset.amber.colors(dark: false))
    }
}

final class ThemeTests: XCTestCase {
    func testInkFollowsPanelBrightness() {
        XCTAssertFalse(ThemeTokens(colors: ThemePreset.amber.colors(dark: false)).isDark)
        XCTAssertTrue(ThemeTokens(colors: ThemePreset.amber.colors(dark: true)).isDark)
    }

    func testPresetsAreValidHex() {
        XCTAssertEqual(ThemePreset.all.count, 18)
        for preset in ThemePreset.all {
            for dark in [false, true] {
                let colors = preset.colors(dark: dark)
                XCTAssertTrue(colors.isValid, "\(preset.id)")
            }
        }
        XCTAssertEqual(Set(ThemePreset.all.map(\.id)).count, ThemePreset.all.count)
    }

    func testFlagsLowContrastAccent() {
        XCTAssertTrue(ThemeTokens(colors: ThemeColors(preset: "custom", panel: "#222222", accent: "#2a2a2a")).lowAccentContrast)
        XCTAssertEqual(RGB(hex: "#885500")?.hex, "#885500")
    }

    func testFullPaletteRoundTripsAndRemainsBackwardCompatible() throws {
        // Legacy 2-color JSON still decodes cleanly with auto-derived semantic tokens.
        let legacyJSON = ##"{"version":2,"appearance":{"mode":"dark","dark":{"preset":"catppuccin","panel":"#1e1e2e","accent":"#cba6f7"}}}"##
        let legacy = try JSONDecoder().decode(Config.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacy.appearance.dark.preset, "catppuccin")
        XCTAssertNil(legacy.appearance.dark.link)

        // Full 10-color preset round-trips every role.
        let full = Config(appearance: AppearanceConfig(mode: .dark,
                                                       light: ThemePreset.named("kanagawa")!.colors(dark: false),
                                                       dark: ThemePreset.named("catppuccin")!.colors(dark: true)))
        let encoded = try JSONEncoder().encode(full)
        let decoded = try JSONDecoder().decode(Config.self, from: encoded)
        XCTAssertEqual(decoded, full)
        XCTAssertEqual(decoded.appearance.dark.link, "#89b4fa")
        XCTAssertEqual(decoded.appearance.light.selection, "#d8d6b2")
    }
}
