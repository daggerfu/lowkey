import AppKit
import BobukUI
import LowkeyCore

/// A lowkey window: BobukKit's `ChromeWindow` (accent line, strip, `body`) in lowkey's theme.
/// It keeps the page classification of its page for Page and Tint modes and recolors the
/// chrome from `ThemeCenter`'s strip tokens.
class LowkeyWindow: ChromeWindow, PageThemeProviding {
    static let pageThemeDidChange = Notification.Name("LowkeyPageThemeDidChange")
    var pageIsDark: Bool? {
        didSet {
            guard pageIsDark != oldValue else { return }
            applyTheme()
            NotificationCenter.default.post(name: Self.pageThemeDidChange, object: self)
        }
    }

    /// The page color for Tint mode; kept across navigations, nil before the first page color.
    var tint: RGB? {
        didSet {
            guard tint != oldValue else { return }
            tintIsDark = tint.map { PageAppearance.isDark(background: $0, previous: tintIsDark) }
            applyTheme(animated: ThemeCenter.shared.appearance.mode == .tint)
            NotificationCenter.default.post(name: Self.pageThemeDidChange, object: self)
        }
    }
    private var tintIsDark: Bool?

    var pageTheme: PageTheme { PageTheme(isDark: pageIsDark, tint: tint, tintIsDark: tintIsDark) }

    init(contentRect: NSRect, trailing: [StripButton] = [], resizable: Bool = true) {
        super.init(contentRect: contentRect, style: LowkeyWindow.chromeStyle(page: PageTheme()),
                   trailing: trailing, resizable: resizable)
        // The File menu owns ⌘W: it hides saved sites and closes other windows.
        closesOnCommandW = false
        // lowkey has a live Edit menu, and a web view must see ⌘C/⌘V/⌘X/⌘A/⌘Z first: WKWebView
        // hands ⌘ keys to the page (editors handle undo and select-all in keydown) before
        // the menu runs the native action.
        routesEditCommands = false
        // Posted on the main thread by ThemeCenter.
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange),
                                               name: ThemeCenter.didChange, object: nil)
    }

    @objc private func themeDidChange() { applyTheme() }

    /// Chrome colors from the strip tokens: in Tint mode the strip and its separator take the
    /// page color, and the close cross keeps the computed ink instead of a red that can match it.
    static func chromeStyle(page: PageTheme) -> ChromeStyle {
        let center = ThemeCenter.shared
        let tokens = center.stripTokens(page: page)
        let tinted = center.appearance.mode == .tint
        return ChromeStyle(panel: NSColor(tokens.panel), ink: NSColor(tokens.ink), muted: NSColor(tokens.muted),
                           accent: NSColor(tokens.accent),
                           separator: NSColor(tinted ? tokens.panel : tokens.stroke),
                           destructiveHover: tokens.isTinted ? nil : tokens.dangerNSColor,
                           appearance: center.stripAppearance(page: page))
    }

    func applyTheme(animated: Bool = false) {
        setChromeStyle(Self.chromeStyle(page: pageTheme), animated: animated)
    }

    /// Popup origin bars are chrome too; leave the WKWebView's appearance alone.
    override func chromeStyleDidChange(animated: Bool) {
        for origin in body.subviews.compactMap({ $0 as? OriginBar }) { origin.themeDidChange() }
    }
}
