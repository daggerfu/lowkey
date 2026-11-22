import AppKit
import BobukUI
import LowkeyCore
import WebKit

enum WindowKind: Equatable {
    /// A site from Settings: own profile; the cross hides the window.
    case saved(UUID)
    /// Opened with ⌘N or a typed address: shared `default` profile; the cross closes it.
    case ordinary
}

/// Menu commands handled by web windows through the responder chain.
@objc protocol LowkeyActions {
    func lowkeySavePDF(_ sender: Any?)
    func lowkeyReload(_ sender: Any?)
    func lowkeyBack(_ sender: Any?)
    func lowkeyForward(_ sender: Any?)
    func lowkeyStart(_ sender: Any?)
    func lowkeyCloseWindow(_ sender: Any?)
    func lowkeyCloseSite(_ sender: Any?)
    func lowkeyZoomIn(_ sender: Any?)
    func lowkeyZoomOut(_ sender: Any?)
    func lowkeyActualSize(_ sender: Any?)
}

/// Shared behavior of site windows and sign-in/popup windows.
class WebWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let webView: LowkeyWebView
    unowned let app: AppController
    var chrome: LowkeyWindow { window as! LowkeyWindow }
    var popups: [PopupWindowController] = []
    /// The address that failed to load, so ⌘R retries it rather than the error page.
    var failedURL: URL?
    /// One explicit location from ⌘⇧L, not a permanent change to the site's link policy.
    private var profileLocation: URL?
    private var observations: [NSKeyValueObservation] = []
    private var pageColorReady = false
    /// Latest colors reported by the page script (see `EditingReporter`).
    private var pageBackgroundColor: PageColor?
    private var pageThemeColor: PageColor?
    private var appearanceWork: DispatchWorkItem?

    init(window: LowkeyWindow, webView: LowkeyWebView, app: AppController) {
        self.webView = webView
        self.app = app
        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.pinEdges(to: window.body)
        observations = [
            watch(\.title), watch(\.url), watch(\.canGoBack), watch(\.canGoForward),
            watch(\.estimatedProgress), watch(\.isLoading),
        ]
        window.strip.closeButton.onPress = { [weak self] flags in self?.closeButtonPressed(flags) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func watch<Value>(_ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        (webView as WKWebView).observe(keyPath) { [weak self] _, _ in
            // KVO for these keys is delivered on the main thread.
            self?.updateChrome()
        }
    }

    /// Called by `EditingReporter` when the page's background or theme-color changed.
    func pageColors(background: PageColor?, theme: PageColor?) {
        pageBackgroundColor = background
        pageThemeColor = theme
        schedulePageAppearance()
    }

    /// Classify per window, not for the entire application; debounce rendering/animation updates.
    private func schedulePageAppearance() {
        guard pageColorReady else { return }
        appearanceWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.pageColorReady else { return }
            let background = self.pageBackgroundColor
            let hint = self.pageThemeColor
            let color = [background, hint].compactMap { $0 }.first { $0.isUsable }
            self.chrome.pageIsDark = color.map {
                PageAppearance.isDark(background: $0.rgb, previous: self.chrome.pageIsDark)
            }
            // Tint, in every mode so a switch in Settings shows at once: theme-color first.
            // With no usable color the previous one stays; navigation never clears it.
            self.chrome.tint = PageAppearance.tint(themeColor: hint, background: background,
                                                   previous: self.chrome.tint)
        }
        appearanceWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: item)
    }

    /// The saved site whose rules apply here; nil for ordinary windows.
    var site: Site? { nil }

    func updateChrome() {
        let title = webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? webView.url?.host ?? "Lowkey"
        window?.title = title
        chrome.accentBar.progress = webView.isLoading ? webView.estimatedProgress : nil
    }

    func closeButtonPressed(_ flags: NSEvent.ModifierFlags) { window?.close() }

    func load(_ url: URL) {
        profileLocation = nil
        failedURL = nil
        webView.load(URLRequest(url: url))
    }

    /// Reuse this exact web view and its data store, even for a different site's alias or an
    /// authentication-provider URL. Do not turn that origin into an allowed site permanently.
    func loadInCurrentProfile(_ url: URL) {
        failedURL = nil
        profileLocation = url
        webView.load(URLRequest(url: url))
    }

    /// Only the explicitly requested initial navigation bypasses site/sign-in routing.
    func consumeProfileLocation(_ url: URL) -> Bool {
        guard profileLocation == url else { return false }
        profileLocation = nil
        return true
    }

    func reloadPage() {
        if let failedURL = failedURL { load(failedURL) } else { webView.reload() }
    }

    /// Handles a main-frame navigation before WebKit loads it. Return true when it was handled elsewhere.
    func intercept(_ action: WKNavigationAction, url: URL) -> Bool {
        if action.navigationType == .linkActivated, action.modifierFlags.contains(.command) {
            app.openOrdinary(url, near: window)
            return true
        }
        return false
    }

    // MARK: Menu actions (responder chain)

    @objc func lowkeySavePDF(_ sender: Any?) {
        guard let window = window else { return }
        PagePDF.chooseDestination(for: webView, in: window)
    }
    @objc func lowkeyReload(_ sender: Any?) { reloadPage() }
    @objc func lowkeyBack(_ sender: Any?) { webView.goBack() }
    @objc func lowkeyForward(_ sender: Any?) { webView.goForward() }
    @objc func lowkeyCloseWindow(_ sender: Any?) { window?.close() }
    @objc func lowkeyCloseSite(_ sender: Any?) { window?.close() }
    @objc func lowkeyZoomIn(_ sender: Any?) { webView.magnification = min(3, webView.magnification + 0.1) }
    @objc func lowkeyZoomOut(_ sender: Any?) { webView.magnification = max(0.5, webView.magnification - 0.1) }
    @objc func lowkeyActualSize(_ sender: Any?) { webView.magnification = 1 }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(lowkeySavePDF(_:)): return webView.url != nil && !webView.isLoading
        case #selector(lowkeyBack(_:)): return webView.canGoBack
        case #selector(lowkeyForward(_:)): return webView.canGoForward
        default: return true
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        for popup in popups { popup.close() }
        popups.removeAll()
        appearanceWork?.cancel()
        webView.stopLoading()
        app.windowDidClose(self)
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return decisionHandler(.allow) }
        if scheme != "http" && scheme != "https" {
            if LinkPolicy.isEmbeddedScheme(scheme) { return decisionHandler(.allow) }
            // mailto:, tel:, app links: hand to the registered app.
            if action.targetFrame?.isMainFrame != false || action.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
            }
            return decisionHandler(.cancel)
        }
        guard action.targetFrame?.isMainFrame ?? true else { return decisionHandler(.allow) }
        if action.navigationType == .other, consumeProfileLocation(url) {
            return decisionHandler(.allow)
        }
        decisionHandler(intercept(action, url: url) ? .cancel : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if response.isForMainFrame && (!response.canShowMIMEType || disposition.lowercased().hasPrefix("attachment")) {
            // WKDownload needs the macOS 11 SDK; Catalina WebKit downloads on its own after .cancel.
            #if compiler(>=5.4)
            if #available(macOS 11.3, *) {
                decisionHandler(.download)
            } else {
                decisionHandler(.cancel)
            }
            #else
            decisionHandler(.cancel)
            #endif
        } else {
            decisionHandler(.allow)
        }
    }

    #if compiler(>=5.4)
    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }
    #endif

    private(set) var pendingDocument = false

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pendingDocument = true
        pageColorReady = false
        appearanceWork?.cancel()
        pageBackgroundColor = nil
        pageThemeColor = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageColorReady = true
        schedulePageAppearance()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pendingDocument = false
        profileLocation = nil
        pageColorReady = true
        schedulePageAppearance()
        self.webView.isEditingText = false
        if webView.url?.scheme != "about" { failedURL = nil }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pendingDocument = false
        let error = error as NSError
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        // 102: the load turned into a download or was cancelled by policy.
        if error.domain == "WebKitErrorDomain" && (error.code == 102 || error.code == 101) { return }
        let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? webView.url
        profileLocation = nil
        failedURL = url
        webView.loadHTMLString(WebKitSupport.errorPage(url: url, error: error, dark: ThemeCenter.shared.systemIsDark),
                               baseURL: nil)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest else {
            return completionHandler(.performDefaultHandling, nil)
        }
        guard challenge.previousFailureCount < 3 else { return completionHandler(.cancelAuthenticationChallenge, nil) }
        PageDialogs.credentials(host: challenge.protectionSpace.host, in: window) { credential in
            if let credential = credential { completionHandler(.useCredential, credential) }
            else { completionHandler(.cancelAuthenticationChallenge, nil) }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: UI

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = action.request.url
        let blank = url == nil || url!.absoluteString.isEmpty || url!.absoluteString == "about:blank"
        let sized = windowFeatures.width != nil || windowFeatures.height != nil
        if let url = url, !blank, !sized, !AuthProviders.isSignIn(url) {
            // target=_blank or window.open without a size. No tabs: open it here, outside, or (⌘) in a new window.
            openLink(url, request: action.request, newWindow: action.modifierFlags.contains(.command))
            return nil
        }
        // A real popup (sign-in, payment): its own window, same profile, keeps window.opener.
        let popup = PopupWindowController(configuration: configuration, owner: self, features: windowFeatures,
                                          returnsToSite: false, app: app)
        popups.append(popup)
        popup.present()
        return popup.webView
    }

    func openLink(_ url: URL, request: URLRequest, newWindow: Bool) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            NSWorkspace.shared.open(url)
            return
        }
        if LinkPolicy.decide(linkTo: url, site: site) == .openExternally {
            NSWorkspace.shared.open(url)
        } else if newWindow {
            app.openOrdinary(url, near: window)
        } else {
            failedURL = nil
            webView.load(request)
        }
    }

    func popupClosed(_ popup: PopupWindowController) {
        popups.removeAll { $0 === popup }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        PageDialogs.alert(message, in: window, completion: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        PageDialogs.confirm(message, in: window, completion: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        PageDialogs.prompt(prompt, defaultText: defaultText, in: window, completion: completionHandler)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        PageDialogs.openFiles(allowsMultiple: parameters.allowsMultipleSelection, directories: parameters.allowsDirectories,
                              in: window, completion: completionHandler)
    }
}

/// A site window: a saved site (by alias) or an ordinary window.
final class BrowserWindowController: WebWindowController {
    let kind: WindowKind
    /// The first page of an ordinary window; saved sites use their configured start URL.
    private let initialURL: URL
    private let placement: SiteWindowPlacement?
    private let backButton = StripButton(glyph: .back, label: "Back · ⌘←")
    private let forwardButton = StripButton(glyph: .forward, label: "Forward · ⌘→")
    private let startButton = StripButton(glyph: .start, label: "Open start page · ⇧⌘H")

    init(kind: WindowKind, startURL: URL, dataStore: WKWebsiteDataStore, app: AppController) {
        self.kind = kind
        if case .saved(let id) = kind { placement = SiteWindowPlacement(siteID: id) }
        else { placement = nil }
        initialURL = startURL
        let window = LowkeyWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                                  trailing: [backButton, startButton, forwardButton])
        window.minSize = NSSize(width: 360, height: 240)
        let webView = WebKitSupport.makeWebView(configuration: WebKitSupport.configuration(dataStore: dataStore))
        super.init(window: window, webView: webView, app: app)

        backButton.onPress = { [weak self] _ in self?.webView.goBack() }
        forwardButton.onPress = { [weak self] _ in self?.webView.goForward() }
        startButton.onPress = { [weak self] _ in self?.goToStart() }

        if let placement = placement {
            placement.restore(window)
        } else if let key = NSApp.keyWindow as? LowkeyWindow, key.isVisible {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: key.frame.minX, y: key.frame.maxY)))
        } else {
            window.center()
        }
        updateCloseGlyph(commandHeld: false)
        updateChrome()
    }

    override var site: Site? {
        guard case .saved(let id) = kind else { return nil }
        return app.store.config.site(id: id)
    }

    var startURL: URL { site?.url ?? initialURL }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func goToStart() { load(startURL) }

    func perform(_ command: SiteCommand, beforeActivation: ToggleWindowOrder?) {
        switch command {
        case .open: show()
        case .rewind:
            goToStart()
            if window?.isMiniaturized == true { window?.deminiaturize(nil) }
            show()
        case .toggle:
            guard let window = window else { return }
            let order = beforeActivation ?? ToggleWindowOrder()
            switch WindowToggle.action(isVisible: window.isVisible, isMiniaturized: window.isMiniaturized,
                                       isFrontmost: beforeActivation == nil && order.isFrontmost(window)) {
            case .hide:
                order.hide(window) { self.hide() }
            case .show:
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                    show()
                } else if !order.raiseOnly(window) {
                    show()
                }
                order.restoreBackgroundWindows(except: window)
            }
        case .reload: reloadPage()
        case .back: webView.goBack()
        case .forward: webView.goForward()
        case .start: goToStart()
        case .hide: hide()
        case .close: window?.close()
        }
    }

    func hide() {
        savePlacement()
        window?.orderOut(nil)
        app.windowDidHide(self)
    }

    // MARK: Saved-site window geometry

    func savePlacement() {
        guard let window = window else { return }
        placement?.save(window)
    }

    func windowDidMove(_ notification: Notification) { savePlacement() }
    func windowDidResize(_ notification: Notification) { savePlacement() }
    func windowWillEnterFullScreen(_ notification: Notification) { placement?.willEnterFullScreen() }
    func windowWillExitFullScreen(_ notification: Notification) { placement?.willExitFullScreen() }
    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = window else { return }
        placement?.didExitFullScreen(window)
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { placement?.didFailToEnterFullScreen(window) }

    override func windowWillClose(_ notification: Notification) {
        savePlacement()
        super.windowWillClose(notification)
    }

    /// Saved sites hide on the cross and close on ⌘-click; ordinary windows always close.
    override func closeButtonPressed(_ flags: NSEvent.ModifierFlags) {
        if case .saved = kind, !flags.contains(.command) { hide() } else { window?.close() }
    }

    func updateCloseGlyph(commandHeld: Bool) {
        let closes = kind == .ordinary || commandHeld
        let button = chrome.strip.closeButton
        button.glyph = closes ? .terminate : .close
        button.label = closes
            ? (kind == .ordinary ? "Close · ⌘W" : "Close site, keep sign-in · ⇧⌘W")
            : "Hide window · ⌘W  (⌘-click: close site)"
    }

    override func updateChrome() {
        super.updateChrome()
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }

    override func intercept(_ action: WKNavigationAction, url: URL) -> Bool {
        if super.intercept(action, url: url) { return true }
        guard let site = site else { return false }
        if AuthProviders.isSignIn(url) && !LinkPolicy.isPartOfSite(url, site: site) {
            openSignIn(action.request)
            return true
        }
        if action.navigationType == .linkActivated && LinkPolicy.decide(linkTo: url, site: site) == .openExternally {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }

    /// Sign-in pages of a saved site open in a separate window with the same profile.
    /// When the provider sends the browser back to the site, the site window loads that address.
    private func openSignIn(_ request: URLRequest) {
        let popup = PopupWindowController(configuration: webView.configuration, owner: self, features: nil,
                                          returnsToSite: true, app: app)
        popups.append(popup)
        popup.present()
        popup.webView.load(request)
    }

    @objc func lowkeyStart(_ sender: Any?) { goToStart() }

    @objc override func lowkeyCloseWindow(_ sender: Any?) {
        if case .saved = kind { hide() } else { window?.close() }
    }

    @objc override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(lowkeyCloseWindow(_:)) {
            item.title = kind == .ordinary ? "Close Window" : "Hide Window"
        }
        if item.action == #selector(lowkeyCloseSite(_:)) {
            item.title = kind == .ordinary ? "Close Window" : "Close Site"
        }
        return super.validateMenuItem(item)
    }
}

/// A popup (`window.open` with a size) or a sign-in window. Shares the owner's profile.
final class PopupWindowController: WebWindowController {
    private weak var opener: WebWindowController?
    /// Sign-in mode: navigation back into the site goes to the owner window and this window closes.
    private let returnsToSite: Bool
    private let originBar = OriginBar()

    init(configuration: WKWebViewConfiguration, owner: WebWindowController, features: WKWindowFeatures?,
         returnsToSite: Bool, app: AppController) {
        self.opener = owner
        self.returnsToSite = returnsToSite
        let width = features?.width.map { CGFloat($0.doubleValue) } ?? 520
        let height = features?.height.map { CGFloat($0.doubleValue) } ?? 680
        let window = LowkeyWindow(contentRect: NSRect(x: 0, y: 0, width: max(320, width), height: max(240, height) + 34))
        window.minSize = NSSize(width: 320, height: 240)
        let webView = WebKitSupport.makeWebView(configuration: configuration)
        originBar.translatesAutoresizingMaskIntoConstraints = false
        window.body.addSubview(originBar)
        NSLayoutConstraint.activate([
            originBar.topAnchor.constraint(equalTo: window.body.topAnchor),
            originBar.leadingAnchor.constraint(equalTo: window.body.leadingAnchor),
            originBar.trailingAnchor.constraint(equalTo: window.body.trailingAnchor),
            originBar.heightAnchor.constraint(equalToConstant: 22),
        ])
        super.init(window: window, webView: webView, app: app)
        // Re-pin the web view below the origin bar.
        webView.removeFromSuperview()
        webView.pinEdges(to: window.body, top: originBar.bottomAnchor)
        updateChrome()
    }

    override var site: Site? { opener?.site }

    func present() {
        guard let window = window else { return }
        if let parent = opener?.window, parent.isVisible {
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: parent.frame.midX - frame.width / 2,
                                          y: max(parent.frame.minY, parent.frame.maxY - frame.height - 40)))
            parent.addChildWindow(window, ordered: .above)
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    override func updateChrome() {
        super.updateChrome()
        let url = webView.url
        originBar.update(host: url?.host ?? "", secure: url?.scheme == "https" && webView.hasOnlySecureContent)
    }

    override func intercept(_ action: WKNavigationAction, url: URL) -> Bool {
        if super.intercept(action, url: url) { return true }
        if returnsToSite, let owner = opener, let site = site, LinkPolicy.isPartOfSite(url, site: site), !AuthProviders.isSignIn(url) {
            owner.failedURL = nil
            owner.webView.load(action.request)
            window?.close()
            return true
        }
        return false
    }

    func webViewDidClose(_ webView: WKWebView) {
        window?.close()
    }

    override func windowWillClose(_ notification: Notification) {
        for popup in popups { popup.close() }
        popups.removeAll()
        webView.stopLoading()
        if let parent = window?.parent { parent.removeChildWindow(window!) }
        opener?.popupClosed(self)
    }
}

/// The address line of a popup or sign-in window: who is asking for the password.
final class OriginBar: NSView {
    private let label = NSTextField(labelWithString: "")
    private let lock = GlyphView(glyph: .lock)

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        lock.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lock)
        addSubview(label)
        NSLayoutConstraint.activate([
            lock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            lock.centerYAnchor.constraint(equalTo: centerYAnchor),
            lock.widthAnchor.constraint(equalToConstant: 10),
            lock.heightAnchor.constraint(equalToConstant: 10),
            label.leadingAnchor.constraint(equalTo: lock.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func update(host: String, secure: Bool) {
        label.stringValue = host.isEmpty ? "…" : host
        lock.isHidden = !secure
        themeDidChange()
    }

    /// The window's chrome colors changed (or the bar moved to a window).
    func themeDidChange() {
        let tokens = lowkeyTokens
        label.textColor = NSColor(tokens.muted)
        lock.color = NSColor(tokens.muted)
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        themeDidChange()
    }

    override func draw(_ dirtyRect: NSRect) {
        let tokens = lowkeyTokens
        NSColor(tokens.panel).setFill()
        bounds.fill()
        NSColor(tokens.stroke).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}
