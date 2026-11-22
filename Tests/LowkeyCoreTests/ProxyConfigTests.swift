import Foundation
import XCTest
@testable import LowkeyCore

final class ProxyTests: XCTestCase {
    private let tor = SocksProxy(name: "tor", host: "127.0.0.1", port: 9050)
    private let remote = SocksProxy(name: "remote", host: "proxy.example.com", port: 1080,
                                    username: "u", password: "p")

    private func config(sites: [Site] = [], rules: [ProxyRule] = []) -> Config {
        Config(sites: sites, proxies: [tor, remote], proxyDomains: rules)
    }

    func testSiteProxyBindingWins() {
        let site = Site(alias: "A", startURL: "https://a.example.com", proxy: "remote")
        XCTAssertEqual(config().proxy(for: site), remote)
    }

    func testRuleMatchesHostAndSubdomains() {
        let site = Site(alias: "B", startURL: "https://b.onion")
        XCTAssertEqual(config(rules: [ProxyRule(proxy: "tor", hosts: ["onion"])]).proxy(for: site), tor)
        XCTAssertEqual(config(rules: [ProxyRule(proxy: "tor", hosts: ["*.onion"])]).proxy(for: site), tor)
    }

    func testWildcardExcludesBareHost() {
        let bare = Site(alias: "C", startURL: "https://example.com")
        let rule = ProxyRule(proxy: "tor", hosts: ["*.example.com"])
        XCTAssertNil(config(rules: [rule]).proxy(for: bare))
        XCTAssertTrue(rule.matches(host: "a.b.example.com"))
    }

    func testPlainEntryIncludesSubdomains() {
        let rule = ProxyRule(proxy: "tor", hosts: ["example.com"])
        XCTAssertTrue(rule.matches(host: "example.com"))
        XCTAssertTrue(rule.matches(host: "a.example.com"))
        XCTAssertFalse(rule.matches(host: "notexample.com"))
    }

    func testSiteBindingBeatsRule() {
        let site = Site(alias: "D", startURL: "https://d.onion", proxy: "remote")
        let rules = [ProxyRule(proxy: "tor", hosts: ["onion"])]
        XCTAssertEqual(config(sites: [site], rules: rules).proxy(for: site), remote)
    }

    func testNoProxyWithoutBindingOrRule() {
        let site = Site(alias: "E", startURL: "https://e.example.com")
        XCTAssertNil(config(sites: [site]).proxy(for: site))
    }

    func testProblemsCatchUnknownProxyNames() {
        let site = Site(alias: "A", startURL: "https://a.example.com", proxy: "missing")
        let config = Config(sites: [site], proxies: [tor],
                            proxyDomains: [ProxyRule(proxy: "gone", hosts: ["x.com"])])
        let problems = config.problems()
        XCTAssertTrue(problems.contains { $0.contains("unknown proxy “missing”") })
        XCTAssertTrue(problems.contains { $0.contains("unknown proxy “gone”") })
    }

    func testProblemsCatchBadPortsAndDuplicates() {
        let bad = SocksProxy(name: "tor", host: "127.0.0.1", port: 70000)
        let dup = SocksProxy(name: "TOR", host: "h", port: 1)
        let config = Config(proxies: [bad, dup, tor])
        let problems = config.problems()
        XCTAssertTrue(problems.contains { $0.contains("between 1 and 65535") })
        XCTAssertTrue(problems.contains { $0.contains("used twice") })
    }

    func testPasswordNeedsUserName() {
        let proxy = SocksProxy(name: "x", host: "h", port: 1080, password: "p")
        XCTAssertTrue(Config(proxies: [proxy]).problems().contains { $0.contains("needs a user name") })
    }

    func testEmptyConfigHasNoProblems() {
        XCTAssertTrue(Config().problems().isEmpty)
    }

    func testConfigRoundTripsProxies() throws {
        let config = self.config(sites: [Site(alias: "A", startURL: "https://a.example.com", proxy: "tor")],
                                 rules: [ProxyRule(proxy: "tor", hosts: ["onion"])])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowkey-proxy-test.json")
        try config.save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try Config.load(from: url), config)
    }

    func testOldConfigWithoutProxiesLoads() throws {
        let json = #"{"sites":[{"alias":"HA","startURL":"https://homeassistant.local"}]}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(Config.self, from: json)
        // A config without ids gets fresh ones per site; compare the stable fields.
        XCTAssertEqual(config.sites.map { [$0.alias, $0.startURL] }, [["HA", "https://homeassistant.local"]])
        XCTAssertTrue(config.proxies.isEmpty)
        XCTAssertTrue(config.proxyDomains.isEmpty)
        XCTAssertNil(config.sites[0].proxy)
    }
}
