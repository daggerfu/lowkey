import AppKit
import LowkeyCore
import BobukUI

extension NSColor {
    var pageColor: PageColor? {
        guard let rgb = rgb, let color = usingColorSpace(.sRGB) else { return nil }
        return PageColor(rgb: rgb, alpha: Double(color.alphaComponent))
    }
}

/// What a window knows about its page colors, kept per window so different pages can differ.
struct PageTheme: Equatable {
    /// Page mode: the background first, theme-color second; nil without a usable color.
    var isDark: Bool?
    /// Tint mode: theme-color first, background second, the last color kept; nil before the first.
    var tint: RGB?
    /// Light/dark of `tint`, with the dead band of `PageAppearance.isDark`.
    var tintIsDark: Bool?
}

/// Windows supply their own page classification so different pages can use different chrome modes.
protocol PageThemeProviding: AnyObject {
    var pageTheme: PageTheme { get }
}

extension NSView {
    var pageTheme: PageTheme { (window as? PageThemeProviding)?.pageTheme ?? PageTheme() }

    /// Palette tokens: for everything but the window strip.
    var lowkeyTokens: ThemeTokens { ThemeCenter.shared.tokens(page: pageTheme) }

    /// Tokens of the window strip: tinted with the page color in Tint mode.
    var lowkeyStripTokens: ThemeTokens { ThemeCenter.shared.stripTokens(page: pageTheme) }
}

/// Lowkey's chrome theme. Web pages keep the system appearance and their own colors.
final class ThemeCenter {
    static let shared = ThemeCenter()
    static let didChange = Notification.Name("LowkeyThemeDidChange")

    private var systemObservation: NSKeyValueObservation?

    var appearance = AppearanceConfig() {
        didSet { if appearance != oldValue { notify() } }
    }

    private init() {
        // Lowkey never sets NSApp.appearance, so this follows System Settings.
        systemObservation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
            DispatchQueue.main.async { ThemeCenter.shared.notify() }
        }
    }

    var systemIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    var isDark: Bool { isDark(page: PageTheme()) }

    func isDark(page: PageTheme) -> Bool {
        switch appearance.mode {
        case .tint: return page.tintIsDark ?? systemIsDark
        case .page: return page.isDark ?? systemIsDark
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        }
    }

    var tokens: ThemeTokens { tokens(page: PageTheme()) }

    /// Palette tokens, light or dark by the mode. Never tinted.
    func tokens(page: PageTheme) -> ThemeTokens {
        ThemeTokens(colors: appearance.colors(dark: isDark(page: page)))
    }

    /// Tokens of the window strip: in Tint mode the panel is the page color once there is one.
    func stripTokens(page: PageTheme) -> ThemeTokens {
        let colors = appearance.colors(dark: isDark(page: page))
        if appearance.mode == .tint, let tint = page.tint { return ThemeTokens(tint: tint, colors: colors) }
        return ThemeTokens(colors: colors)
    }

    /// Appearance for views drawn on the themed panel (tooltips, text fields, menus).
    var chromeAppearance: NSAppearance? { chromeAppearance(page: PageTheme()) }

    func chromeAppearance(page: PageTheme) -> NSAppearance? {
        NSAppearance(named: tokens(page: page).isDark ? .darkAqua : .aqua)
    }

    /// Appearance for the controls of the window strip. In Tint mode it follows the tint
    /// (with its dead band, or the system before the first tint), not the palette panel.
    func stripAppearance(page: PageTheme) -> NSAppearance? {
        guard appearance.mode == .tint else { return chromeAppearance(page: page) }
        return NSAppearance(named: isDark(page: page) ? .darkAqua : .aqua)
    }

    /// Appearance for the Settings window: the chosen mode, or the system one.
    var windowAppearance: NSAppearance? {
        [.tint, .page, .system].contains(appearance.mode) ? nil : NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
