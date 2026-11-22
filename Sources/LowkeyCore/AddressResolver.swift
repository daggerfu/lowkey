import BobukCore
import Foundation

/// What the address prompt opens for a line of input.
public enum AddressTarget: Equatable {
    case site(Site)
    case url(URL)
    case invalid
}

public enum AddressResolver {
    /// An alias wins over an address. Bare hosts get `https://`, local hosts `http://`.
    public static func resolve(_ input: String, sites: [Site]) -> AddressTarget {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .invalid }
        // Try the original spelling first, then the same keys in another layout.
        for variant in KeyboardLayoutSwap.variants(of: text) {
            if let site = sites.first(where: { $0.alias.caseInsensitiveCompare(variant) == .orderedSame }) {
                return .site(site)
            }
        }
        guard let url = webURL(text) else { return .invalid }
        return .url(url)
    }

    /// Parses an http(s) address, adding a scheme to bare hosts such as `example.com` or `nas.local:5000`.
    public static func webURL(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if let schemeEnd = text.range(of: "://") {
            let scheme = text[..<schemeEnd.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https", let url = URL(string: text),
                  let host = url.host, !host.isEmpty else { return nil }
            return url
        }
        guard let host = URL(string: "http://" + text)?.host, !host.isEmpty else { return nil }
        let looksLikeHost = host.contains(".") || host == "localhost" || host.contains(":")
            || text.dropFirst(host.count).hasPrefix(":")
        guard looksLikeHost else { return nil }
        let scheme = isLoopback(host) ? "http" : "https"
        return URL(string: "\(scheme)://\(text)")
    }

    static func isLoopback(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return host == "localhost" || host.hasSuffix(".localhost") || host.hasPrefix("127.") || host == "::1"
    }
}
