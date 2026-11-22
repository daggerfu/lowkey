import Foundation

/// A SOCKS proxy that saved-site profiles can be routed through.
/// Authentication is passed for SOCKS5; without credentials SOCKS4 is used.
public struct SocksProxy: Codable, Equatable, Identifiable {
    public var name: String
    public var host: String
    public var port: Int
    public var username: String?
    public var password: String?

    public var id: String { name }

    public init(name: String, host: String, port: Int, username: String? = nil, password: String? = nil) {
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    /// Names share the alias rules: letters, digits, `-` and `_`, up to 32.
    public static func isValidName(_ name: String) -> Bool { Site.isValidAlias(name) }
}

/// Hosts (and, with `*.`, their subdomains only) that always open through the named proxy,
/// even when the site itself does not name one. Only saved sites can be routed: an ordinary
/// window shares the default WebKit store, which has no per-window proxy.
public struct ProxyRule: Codable, Equatable {
    public var proxy: String
    public var hosts: [String]

    public init(proxy: String, hosts: [String]) {
        self.proxy = proxy
        self.hosts = hosts
    }

    /// Mirrors `LinkPolicy` origin patterns: `example.com` matches the host and its subdomains,
    /// `*.example.com` matches subdomains only.
    public func matches(host: String) -> Bool {
        hosts.contains { entry in
            if entry.hasPrefix("*.") {
                let suffix = String(entry.dropFirst(2))
                return host.hasSuffix("." + suffix)
            }
            return host == entry || host.hasSuffix("." + entry)
        }
    }
}

extension Config {
    /// The proxy a saved site opens through: its own binding wins, then the first matching rule.
    public func proxy(for site: Site) -> SocksProxy? {
        if let name = site.proxy {
            return proxies.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        guard let host = site.url?.host?.lowercased() else { return nil }
        for rule in proxyDomains {
            guard rule.matches(host: host), let proxy = proxies.first(where: { $0.name.caseInsensitiveCompare(rule.proxy) == .orderedSame }) else { continue }
            return proxy
        }
        return nil
    }

    /// Proxy problems that block saving: unknown names, bad hosts and ports.
    public func proxyProblems() -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for proxy in proxies {
            if !SocksProxy.isValidName(proxy.name) {
                result.append("Proxy “\(proxy.name.isEmpty ? "(empty)" : proxy.name)”: use letters, digits, - and _ (up to 32).")
            } else if !seen.insert(proxy.name.lowercased()).inserted {
                result.append("Proxy “\(proxy.name)” is used twice.")
            }
            if proxy.host.isEmpty || proxy.host.contains(where: { $0.isWhitespace }) {
                result.append("Proxy “\(proxy.name)”: the host must not be empty or contain spaces.")
            }
            if !(1...65_535).contains(proxy.port) {
                result.append("Proxy “\(proxy.name)”: the port must be between 1 and 65535.")
            }
            if proxy.password?.isEmpty == false && proxy.username?.isEmpty != false {
                result.append("Proxy “\(proxy.name)”: a password needs a user name.")
            }
        }
        let names = Set(proxies.map { $0.name.lowercased() })
        for site in sites {
            if let name = site.proxy, !names.contains(name.lowercased()) {
                result.append("“\(site.alias.isEmpty ? "(empty)" : site.alias)”: unknown proxy “\(name)”.")
            }
        }
        for rule in proxyDomains {
            if !names.contains(rule.proxy.lowercased()) {
                result.append("Proxy rule: unknown proxy “\(rule.proxy)”.")
            }
            for host in rule.hosts where host.isEmpty || host.contains(where: { $0.isWhitespace }) {
                result.append("Proxy rule for “\(rule.proxy)”: “\(host)” is not a valid host.")
            }
        }
        return result
    }
}
