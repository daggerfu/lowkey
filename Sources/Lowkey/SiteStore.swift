import CFNetwork
import Foundation
import LowkeyCore
import WebKit

/// Per-site profile stores. WKWebView has no public proxy API, so a proxy is applied
/// through WebKit's private `_WKWebsiteDataStoreConfiguration` when the OS provides it;
/// otherwise the site opens without a proxy and the fallback is logged.
enum SiteStoreFactory {
    static func make(id: UUID, proxy: SocksProxy?) -> WKWebsiteDataStore {
        if let proxy = proxy {
            if let store = proxiedStore(id: id, proxy: proxy) { return store }
            Log.error("proxy “\(proxy.name)” needs a newer WebKit; the site opens without a proxy")
        }
        return plainStore(id: id)
    }

    /// Whether this macOS/WebKit accepts a proxy configuration at all; Settings explains
    /// the fallback before a site silently opens without a proxy.
    static var supportsProxy: Bool {
        NSClassFromString("_WKWebsiteDataStoreConfiguration") != nil
            && WKWebsiteDataStore.responds(to: NSSelectorFromString("_dataStoreWithConfiguration:"))
    }

    private static func plainStore(id: UUID) -> WKWebsiteDataStore {
        #if compiler(>=5.9)
        if #available(macOS 14, *) {
            return WKWebsiteDataStore(forIdentifier: id)
        }
        #endif
        if #available(macOS 12, *), let store = configuredStore(id: id, proxy: nil) {
            return store
        }
        return .default()
    }

    /// The private configuration needs the public `identifier` API (macOS 12) for the same
    /// persistent profile paths that `WKWebsiteDataStore(forIdentifier:)` uses.
    private static func proxiedStore(id: UUID, proxy: SocksProxy) -> WKWebsiteDataStore? {
        configuredStore(id: id, proxy: proxyDictionary(proxy) as NSDictionary)
    }

    private static func configuredStore(id: UUID, proxy: NSDictionary?) -> WKWebsiteDataStore? {
        guard #available(macOS 12, *),
              let configClass = NSClassFromString("_WKWebsiteDataStoreConfiguration") as? NSObject.Type,
              WKWebsiteDataStore.responds(to: NSSelectorFromString("_dataStoreWithConfiguration:"))
        else { return nil }
        let config = configClass.init()
        let setIdentifier = NSSelectorFromString("setIdentifier:")
        guard config.responds(to: setIdentifier) else { return nil }
        config.perform(setIdentifier, with: id)
        if let proxy = proxy {
            let setProxy = NSSelectorFromString("setProxyConfiguration:")
            guard config.responds(to: setProxy) else { return nil }
            config.perform(setProxy, with: proxy)
        }
        let result = WKWebsiteDataStore.perform(NSSelectorFromString("_dataStoreWithConfiguration:"), with: config)
        return result?.takeUnretainedValue() as? WKWebsiteDataStore
    }

    /// The dictionary format is the one `CFNetworkCopySystemProxySettings` uses.
    /// `SOCKSUser`/`SOCKSPassword` are the CFNetwork keys for SOCKS authentication;
    /// older CFNetwork ignores unknown keys and connects without credentials.
    static func proxyDictionary(_ proxy: SocksProxy) -> [AnyHashable: Any] {
        var dict: [AnyHashable: Any] = [
            kCFNetworkProxiesSOCKSEnable: NSNumber(value: 1),
            kCFNetworkProxiesSOCKSProxy: proxy.host,
            kCFNetworkProxiesSOCKSPort: NSNumber(value: proxy.port),
        ]
        if let username = proxy.username, !username.isEmpty { dict["SOCKSUser" as AnyHashable] = username }
        if let password = proxy.password, !password.isEmpty { dict["SOCKSPassword" as AnyHashable] = password }
        return dict
    }
}
