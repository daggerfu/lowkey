import Foundation

/// Scheme, host and port. Default ports are made explicit, so `https://a` equals `https://a:443`.
public struct Origin: Hashable, CustomStringConvertible {
    public let scheme: String
    public let host: String
    public let port: Int

    public init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        guard let port = url.port ?? Self.defaultPort(scheme) else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = port
    }

    static func defaultPort(_ scheme: String) -> Int? {
        switch scheme {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    public var description: String {
        Self.defaultPort(scheme) == port ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
    }
}

/// One entry of "own origins": `https://ha.example.com`, `ha.example.com:8123` or `*.nabu.casa`.
public struct OriginPattern: Equatable {
    /// `nil` accepts http and https.
    let scheme: String?
    let host: String
    let wildcard: Bool
    let port: Int?

    public init?(_ pattern: String) {
        var text = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        var scheme: String?
        if let range = text.range(of: "://") {
            scheme = String(text[..<range.lowerBound])
            guard scheme == "http" || scheme == "https" else { return nil }
            text = String(text[range.upperBound...])
        }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        var wildcard = false
        if text.hasPrefix("*.") {
            wildcard = true
            text.removeFirst(2)
        }
        var port: Int?
        if let colon = text.lastIndex(of: ":"), !text.hasSuffix("]") {
            guard let value = Int(text[text.index(after: colon)...]) else { return nil }
            port = value
            text = String(text[..<colon])
        }
        guard !text.isEmpty, !text.contains("*") else { return nil }
        self.scheme = scheme
        self.host = text
        self.wildcard = wildcard
        self.port = port
    }

    public func matches(_ origin: Origin) -> Bool {
        if let scheme = scheme { guard origin.scheme == scheme else { return false } }
        else { guard origin.scheme == "http" || origin.scheme == "https" else { return false } }
        // `*.example.com` covers subdomains only, as in certificates.
        let hostMatches = wildcard ? origin.host.hasSuffix("." + host) : origin.host == host
        guard hostMatches else { return false }
        let expected = port ?? (scheme.flatMap(Origin.defaultPort) ?? Origin.defaultPort(origin.scheme))
        return origin.port == expected
    }
}

public enum LinkDecision: Equatable {
    /// Load in this Lowkey window.
    case stay
    /// Hand off to the default browser (or the app registered for the scheme).
    case openExternally
}

public enum LinkPolicy {
    public static func isPartOfSite(_ url: URL, site: Site) -> Bool {
        guard let origin = Origin(url) else { return false }
        if let start = site.url.flatMap(Origin.init), start == origin { return true }
        return site.extraOrigins.compactMap(OriginPattern.init).contains { $0.matches(origin) }
    }

    /// Decides a link the user clicked. Redirects and script navigations stay, so sign-in flows keep working.
    /// `site` is nil for ordinary windows: every web link stays there.
    public static func decide(linkTo url: URL, site: Site?) -> LinkDecision {
        guard let scheme = url.scheme?.lowercased() else { return .stay }
        if scheme != "http" && scheme != "https" { return isEmbeddedScheme(scheme) ? .stay : .openExternally }
        guard let site = site, site.externalLinks == .defaultBrowser else { return .stay }
        if isPartOfSite(url, site: site) || AuthProviders.isSignIn(url) { return .stay }
        return .openExternally
    }

    /// Schemes the web view shows itself rather than handing them to another app.
    public static func isEmbeddedScheme(_ scheme: String) -> Bool {
        ["http", "https", "about", "blob", "data", "javascript"].contains(scheme.lowercased())
    }
}

/// Well-known sign-in pages. In a saved-site window they open in a separate sign-in window
/// that shares the site's profile; the result returns to the site window.
public enum AuthProviders {
    static let hosts: Set<String> = [
        "accounts.google.com", "appleid.apple.com", "login.microsoftonline.com", "login.live.com",
        "login.microsoft.com", "id.atlassian.com", "auth.atlassian.com", "accounts.zoho.com",
    ]
    static let hostSuffixes = [".auth0.com", ".okta.com", ".onelogin.com"]
    /// Hosts where only the sign-in paths count.
    static let pathPrefixes: [String: [String]] = [
        "github.com": ["/login", "/session", "/sessions/"],
        "gitlab.com": ["/oauth/", "/users/sign_in", "/users/auth/"],
        "slack.com": ["/openid/", "/oauth/", "/signin"],
    ]

    public static func isSignIn(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        if hosts.contains(host) || hostSuffixes.contains(where: { host.hasSuffix($0) }) { return true }
        guard let prefixes = pathPrefixes[host] else { return false }
        let path = url.path
        return prefixes.contains { path.hasPrefix($0) }
    }
}
