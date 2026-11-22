import Foundation

/// Where a link that leaves a saved site opens.
public enum ExternalLinkPolicy: String, Codable, CaseIterable {
    case defaultBrowser
    case lowkey
}

/// A saved site: an alias, a start page and its own website-data profile.
/// `id` names the profile, so renaming the alias keeps cookies and logins.
public struct Site: Codable, Identifiable, Equatable {
    public var id: UUID
    public var alias: String
    public var title: String
    public var startURL: String
    public var externalLinks: ExternalLinkPolicy
    /// Extra origins that count as part of the site: `https://ha.example.com`, `*.nabu.casa`.
    public var extraOrigins: [String]
    /// Name of the SOCKS proxy this site always opens through; nil falls back to `Config.proxyDomains` rules.
    public var proxy: String?

    public init(id: UUID = UUID(), alias: String, title: String = "", startURL: String,
                externalLinks: ExternalLinkPolicy = .defaultBrowser, extraOrigins: [String] = [],
                proxy: String? = nil) {
        self.id = id
        self.alias = alias
        self.title = title
        self.startURL = startURL
        self.externalLinks = externalLinks
        self.extraOrigins = extraOrigins
        self.proxy = proxy
    }

    enum CodingKeys: String, CodingKey { case id, alias, title, startURL, externalLinks, extraOrigins, proxy }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        alias = try c.decode(String.self, forKey: .alias)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startURL = try c.decode(String.self, forKey: .startURL)
        externalLinks = try c.decodeIfPresent(ExternalLinkPolicy.self, forKey: .externalLinks) ?? .defaultBrowser
        extraOrigins = try c.decodeIfPresent([String].self, forKey: .extraOrigins) ?? []
        proxy = try c.decodeIfPresent(String.self, forKey: .proxy)
    }

    public var displayTitle: String { title.isEmpty ? alias : title }
    public var url: URL? { AddressResolver.webURL(startURL) }

    /// Aliases are the host part of `lowkey://ALIAS/open`: letters, digits, `-` and `_`.
    public static func isValidAlias(_ alias: String) -> Bool {
        guard let first = alias.unicodeScalars.first, alias.count <= 32,
              CharacterSet.alphanumerics.contains(first), first.isASCII else { return false }
        return alias.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }
}

/// How lowkey's chrome picks its colors.
/// - `tint` (default): the window strip takes the page color: the site's `theme-color` first,
///   then the page background; the last usable color is kept. The rest of the chrome uses the
///   light or dark palette picked from that color, or from the system before the first color.
/// - `page`: follow each page's background (then `theme-color`) to pick the light or dark palette;
///   use System when no page color is available.
/// - `system`, `light`, `dark`: the palette by the system, or always light or dark.
public enum ThemeMode: String, Codable, CaseIterable {
    case tint, page, system, light, dark
}

public struct AppearanceConfig: Codable, Equatable {
    public var mode: ThemeMode
    public var light: ThemeColors
    public var dark: ThemeColors

    public init(mode: ThemeMode = .tint, light: ThemeColors = ThemePreset.amber.colors(dark: false),
                dark: ThemeColors = ThemePreset.amber.colors(dark: true)) {
        self.mode = mode
        self.light = light
        self.dark = dark
    }

    enum CodingKeys: String, CodingKey { case mode, light, dark }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(ThemeMode.self, forKey: .mode) ?? .tint
        light = Self.valid(try c.decodeIfPresent(ThemeColors.self, forKey: .light)) ?? ThemePreset.amber.colors(dark: false)
        dark = Self.valid(try c.decodeIfPresent(ThemeColors.self, forKey: .dark)) ?? ThemePreset.amber.colors(dark: true)
    }

    private static func valid(_ colors: ThemeColors?) -> ThemeColors? {
        guard let colors = colors, colors.isValid else { return nil }
        return colors
    }

    public func colors(dark isDark: Bool) -> ThemeColors { isDark ? dark : light }
}

public struct Config: Codable, Equatable {
    public var sites: [Site]
    public var appearance: AppearanceConfig
    /// Named SOCKS proxies that sites and rules can reference.
    public var proxies: [SocksProxy]
    /// Hosts that always open through the named proxy.
    public var proxyDomains: [ProxyRule]

    public init(sites: [Site] = [], appearance: AppearanceConfig = AppearanceConfig(),
                proxies: [SocksProxy] = [], proxyDomains: [ProxyRule] = []) {
        self.sites = sites
        self.appearance = appearance
        self.proxies = proxies
        self.proxyDomains = proxyDomains
    }

    /// Version 2 added the Tint mode; older files move a saved Page mode to Tint once.
    public static let version = 2

    enum CodingKeys: String, CodingKey { case version, sites, appearance, proxies, proxyDomains }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        sites = try c.decodeIfPresent([Site].self, forKey: .sites) ?? []
        appearance = try c.decodeIfPresent(AppearanceConfig.self, forKey: .appearance) ?? AppearanceConfig()
        proxies = try c.decodeIfPresent([SocksProxy].self, forKey: .proxies) ?? []
        proxyDomains = try c.decodeIfPresent([ProxyRule].self, forKey: .proxyDomains) ?? []
        if version < 2 && appearance.mode == .page { appearance.mode = .tint }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.version, forKey: .version)
        try c.encode(sites, forKey: .sites)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(proxies, forKey: .proxies)
        try c.encode(proxyDomains, forKey: .proxyDomains)
    }

    public func site(alias: String) -> Site? {
        sites.first { $0.alias.caseInsensitiveCompare(alias) == .orderedSame }
    }

    public func site(id: UUID) -> Site? { sites.first { $0.id == id } }

    /// Problems that block saving: invalid or duplicate aliases, bad start URLs.
    public func problems() -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for site in sites {
            let name = site.alias.isEmpty ? "(empty)" : site.alias
            if !Site.isValidAlias(site.alias) {
                result.append("Alias “\(name)”: use letters, digits, - and _ (up to 32).")
            } else if !seen.insert(site.alias.lowercased()).inserted {
                result.append("Alias “\(name)” is used twice.")
            }
            if site.url == nil { result.append("“\(name)”: the start URL must be an http or https address.") }
        }
        result.append(contentsOf: proxyProblems())
        return result
    }

    public static func load(from url: URL) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
