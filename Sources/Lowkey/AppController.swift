import AppKit
import LowkeyCore
import WebKit

/// Configuration and input history on disk.
/// `LOWKEY_CONFIG=/tmp/x.json` moves both files for manual checks (history: `/tmp/x.json.history.json`).
final class Store: ObservableObject {
    @Published private(set) var config: Config
    @Published private(set) var history: InputHistory
    /// The last load or save problem, shown in Settings.
    @Published var problem: String?

    let configURL: URL
    let historyURL: URL

    init(configURL customConfigURL: URL? = nil) {
        let environment = ProcessInfo.processInfo.environment
        if let customConfigURL = customConfigURL {
            configURL = customConfigURL
            historyURL = URL(fileURLWithPath: customConfigURL.path + ".history.json")
        } else if let path = environment["LOWKEY_CONFIG"], !path.isEmpty {
            configURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            historyURL = URL(fileURLWithPath: configURL.path + ".history.json")
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            configURL = home.appendingPathComponent(".config/lowkey/config.json")
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            historyURL = support.appendingPathComponent("Lowkey/history.json")
        }
        do {
            config = try Config.load(from: configURL)
        } catch {
            config = Config()
            problem = "Can’t read \(configURL.path): \(error.localizedDescription). lowkey will not overwrite it until you change a setting."
        }
        history = InputHistory.load(from: historyURL)
    }

    /// Saves a valid configuration. Returns the problems that block saving.
    @discardableResult func update(_ new: Config) -> [String] {
        let problems = new.problems()
        guard problems.isEmpty else { return problems }
        guard new != config else { return [] }
        do {
            try new.save(to: configURL)
            config = new
            problem = nil
        } catch {
            problem = "Can’t save settings: \(error.localizedDescription)"
            return [problem!]
        }
        return []
    }

    func record(_ text: String) {
        history.record(text)
        saveHistory()
    }

    func removeHistory(_ text: String) {
        history.remove(text)
        saveHistory()
    }

    func clearHistory() {
        history.clear()
        saveHistory()
    }

    private func saveHistory() {
        do { try history.save(to: historyURL) } catch { Log.error("can’t save history: \(error.localizedDescription)") }
    }
}

/// Owns the windows and runs commands from deep links, menus and the address prompt.
final class AppController {
    let store: Store
    private(set) var siteWindows: [UUID: BrowserWindowController] = [:]
    private(set) var ordinaryWindows: [BrowserWindowController] = []
    private lazy var prompt = AddressPanel(app: self)
    private var settings: SettingsWindowController?
    private(set) var commandHeld = false

    init(store: Store? = nil) {
        self.store = store ?? Store()
        ThemeCenter.shared.appearance = self.store.config.appearance
    }

    var allBrowsers: [BrowserWindowController] { Array(siteWindows.values) + ordinaryWindows }

    /// The site window the user works in, if any.
    var currentBrowser: BrowserWindowController? {
        if let controller = NSApp.keyWindow?.windowController as? BrowserWindowController { return controller }
        if let controller = NSApp.mainWindow?.windowController as? BrowserWindowController { return controller }
        return nil
    }

    /// Includes sign-in/popup windows: the shortcut must use the profile in front.
    var currentWebWindow: WebWindowController? {
        (NSApp.keyWindow?.windowController as? WebWindowController)
            ?? (NSApp.mainWindow?.windowController as? WebWindowController)
    }

    // MARK: Deep links

    func handle(url: URL, beforeActivation: ToggleWindowOrder? = nil) {
        switch DeepLink.parse(url) {
        case .success(.prompt):
            showPrompt(target: currentBrowser, newWindow: false)
        case .success(.site(let alias, let command)):
            if alias == "*", command == .toggle {
                toggleSavedWindows()
                return
            }
            guard let site = store.config.site(alias: alias) else {
                showPrompt(target: currentBrowser, newWindow: false, prefill: alias,
                           message: "No site named “\(alias)”. Add it in Settings (⌘,).")
                return
            }
            run(command, on: site, beforeActivation: beforeActivation)
        case .failure(.unknownCommand(let name)):
            let known = SiteCommand.allCases.map(\.rawValue).joined(separator: ", ")
            showPrompt(target: currentBrowser, newWindow: false, message: "Unknown command “\(name)”. Use: \(known).")
        case .failure(.notLowkey):
            break
        }
    }

    /// Unlike a URL open, the CLI request hasn't activated lowkey. Reply only after
    /// ordering the window so the caller may request activation without raising a stale key window.
    func handle(_ request: ControlRequest, completion: @escaping (String) -> Void) {
        guard let site = store.config.site(alias: request.alias) else { return completion("unknown site") }
        switch request.command {
        case .page(.status, let args):
            let browser = siteWindows[site.id], window = browser?.window
            let status = WindowStatus(alias: site.alias, open: window != nil, visible: window?.isVisible == true,
                                      minimized: window?.isMiniaturized == true, focused: NSApp.isActive && window?.isKeyWindow == true,
                                      loading: browser?.webView.isLoading == true)
            completion("output:" + status.output(json: args == ["--json"]))
        case .page(let command, let args):
            guard let browser = siteWindows[site.id], let url = site.url else { return completion("window not open") }
            if command == .wait && browser.pendingDocument { return completion("pending") }
            PageControls.run(command, args: args, view: browser.webView, site: url, completion: completion)
        case .click(let label):
            guard let browser = siteWindows[site.id], let url = site.url else { return completion("window not open") }
            guard !browser.webView.isLoading else { return completion("page loading") }
            PageClick.perform(in: browser.webView, startURL: url, label: label, completion: completion)
        case .upload(let name, let bytes, let field):
            guard let browser = siteWindows[site.id], let url = site.url else { return completion("window not open") }
            guard !browser.webView.isLoading else { return completion("page loading") }
            PageUpload.attach(in: browser.webView, startURL: url, name: name, bytes: bytes, field: field, completion: completion)
        case .window(let command):
            run(command, on: site, beforeActivation: nil)
            if command == .hide { return completion("ok") }
            guard let window = siteWindows[site.id]?.window else { return completion("cannot open site") }
            completion(window.isVisible && !window.isMiniaturized ? "focus" : "ok")
        }
    }

    private func run(_ command: SiteCommand, on site: Site, beforeActivation: ToggleWindowOrder?) {
        if let controller = siteWindows[site.id] {
            controller.perform(command, beforeActivation: beforeActivation)
            return
        }
        // hide/close on a site that is not open: nothing to do.
        guard command != .hide && command != .close else { return }
        let order = command == .toggle ? beforeActivation ?? ToggleWindowOrder() : nil
        if let window = openSite(site)?.window {
            order?.restoreBackgroundWindows(except: window)
        }
    }

    /// All existing saved-site windows move in one direction, rather than exchanging visibility.
    /// Unopened aliases and ordinary/default-profile windows are intentionally untouched.
    private func toggleSavedWindows() {
        let controllers = Array(siteWindows.values)
        let action = WindowToggle.groupAction(frontmostWindows: controllers.map {
            guard let window = $0.window else { return false }
            return NSApp.isActive && window.isKeyWindow && window.isVisible && !window.isMiniaturized
        })
        for controller in controllers {
            switch action {
            case .hide: controller.hide()
            case .show:
                if controller.window?.isMiniaturized == true { controller.window?.deminiaturize(nil) }
                controller.show()
            }
        }
    }

    // MARK: Windows

    @discardableResult func openSite(_ site: Site) -> BrowserWindowController? {
        if let controller = siteWindows[site.id] {
            controller.show()
            return controller
        }
        guard let url = site.url else { return nil }
        let controller = BrowserWindowController(kind: .saved(site.id), startURL: url,
                                                 dataStore: SiteStoreFactory.make(id: site.id, proxy: store.config.proxy(for: site)),
                                                 app: self)
        siteWindows[site.id] = controller
        controller.updateCloseGlyph(commandHeld: commandHeld)
        controller.load(url)
        controller.show()
        return controller
    }

    /// Persistent per-site profiles need `WKWebsiteDataStore(forIdentifier:)`, macOS 11 SDK.
    /// Catalina shares the default store: sites still get windows and link policy, but not
    /// separate cookies. The store comes from `SiteStoreFactory`, which can also route the
    /// profile through the site's SOCKS proxy.

    func openOrdinary(_ url: URL, near window: NSWindow? = nil) {
        let controller = BrowserWindowController(kind: .ordinary, startURL: url, dataStore: .default(), app: self)
        ordinaryWindows.append(controller)
        controller.load(url)
        controller.show()
    }

    func windowDidClose(_ controller: WebWindowController) {
        guard let browser = controller as? BrowserWindowController else { return }
        if case .saved(let id) = browser.kind, siteWindows[id] === browser { siteWindows[id] = nil }
        ordinaryWindows.removeAll { $0 === browser }
    }

    func windowDidHide(_ controller: BrowserWindowController) {}

    func setCommandHeld(_ held: Bool) {
        guard held != commandHeld else { return }
        commandHeld = held
        for controller in siteWindows.values { controller.updateCloseGlyph(commandHeld: held) }
    }

    // MARK: Address prompt

    func showPromptFromDock() {
        if prompt.isVisible {
            prompt.makeKeyAndOrderFront(nil) // Preserve text and the original navigation target.
        } else {
            showPrompt(target: currentBrowser, newWindow: false)
        }
    }

    func showPrompt(target: WebWindowController?, newWindow: Bool, prefill: String? = nil,
                    message: String? = nil, inCurrentProfile: Bool = false) {
        prompt.show(target: target, newWindow: newWindow, prefill: prefill, message: message,
                    inCurrentProfile: inCurrentProfile)
    }

    /// Opens what the user typed. Returns an error message to show in the prompt.
    func submit(_ text: String, target: WebWindowController?, newWindow: Bool,
                inCurrentProfile: Bool = false) -> String? {
        let resolved = AddressResolver.resolve(text, sites: store.config.sites)
        if inCurrentProfile {
            guard let target = target, target.window != nil else { return "The profile window is no longer open." }
            let address: URL?
            switch resolved {
            case .site(let site): address = site.url
            case .url(let url): address = url
            case .invalid: address = nil
            }
            guard let openURL = address else { return "Enter a site alias or a web address." }
            store.record(openURL.absoluteString)
            target.loadInCurrentProfile(openURL)
            target.window?.makeKeyAndOrderFront(nil)
            return nil
        }
        switch resolved {
        case .site(let site):
            store.record(site.alias)
            openSite(site)
        case .url(let url):
            store.record(url.absoluteString)
            // A typed address never replaces a saved site; it gets an ordinary window.
            if !newWindow, let target = target as? BrowserWindowController, target.kind == .ordinary {
                target.load(url)
                target.show()
            } else {
                openOrdinary(url, near: target?.window)
            }
        case .invalid:
            return "“\(text.trimmingCharacters(in: .whitespaces))” is not a site alias or a web address."
        }
        return nil
    }

    // MARK: Settings

    func showSettings() {
        if settings == nil { settings = SettingsWindowController(app: self) }
        settings?.show()
    }

    func applyAppearance(_ appearance: AppearanceConfig) {
        ThemeCenter.shared.appearance = appearance
    }

    /// Closes the window of a removed site and deletes its profile (cookies, storage, logins).
    func removeSiteData(_ id: UUID) {
        siteWindows[id]?.window?.close()
        siteWindows[id] = nil
        // Give WebKit a moment to release the store of the closed window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            #if compiler(>=5.4)
            if #available(macOS 11, *) {
                WKWebsiteDataStore.remove(forIdentifier: id) { error in
                    if let error = error {
                        Log.error("can’t remove the profile of a deleted site: \(error.localizedDescription)")
                    }
                }
            } else {
                Self.removeProfileDirectory(id)
            }
            #else
            Self.removeProfileDirectory(id)
            #endif
        }
    }

    /// Catalina has no `WKWebsiteDataStore.remove`; delete the on-disk profile directly.
    private static func removeProfileDirectory(_ id: UUID) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/WebKit/\(bundleID)/WebsiteData/Profiles/\(id.uuidString)"),
            home.appendingPathComponent("Library/WebKit/\(bundleID)/WebsiteData/\(id.uuidString)"),
            home.appendingPathComponent("Library/Caches/\(bundleID)/WebKit/\(id.uuidString)"),
        ]
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do { try FileManager.default.removeItem(at: url) }
            catch {
                Log.error("can’t remove the profile of a deleted site: \(error.localizedDescription)")
            }
        }
    }
}
