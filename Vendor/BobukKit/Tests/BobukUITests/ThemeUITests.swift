#if canImport(AppKit)
import AppKit
import BobukCore
import BobukTestSupport
import SwiftUI
import XCTest
@testable import BobukUI

final class ThemeUITests: XCTestCase {
    func testThemeStorePersistsAppearanceAndPalettePerApp() {
        let (defaults, suite) = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(suite) }
        let keys = ThemeStore.StorageKeys(appearance: "appTheme", palette: "appThemePalette")

        let first = ThemeStore(defaults: defaults, keys: keys, defaultAppearance: .dark,
                               defaultPreset: .amber, appliesToApplication: false)
        XCTAssertEqual(first.appearance, .dark)
        XCTAssert(first.isDark)
        XCTAssertEqual(first.colors, ThemePreset.amber.colors(dark: true))
        XCTAssert(first.isDefaultPalette)

        first.applyPreset(ThemePreset.named("kanagawa")!)
        XCTAssert(!first.isDefaultPalette)
        XCTAssertEqual(first.colors.preset, "kanagawa")
        XCTAssertEqual(first.colors(dark: false).preset, "kanagawa")

        first.appearance = .light
        XCTAssert(!first.isDark)
        XCTAssertEqual(first.colors, ThemePreset.named("kanagawa")!.colors(dark: false))

        first.setAccent(RGB(hex: 0xC72566), dark: false)
        XCTAssertEqual(first.colors.preset, ThemeColors.customPresetID)
        XCTAssertEqual(first.colors.accent, "#c72566")

        // Reloading from the same defaults preserves both appearance and custom palette.
        let reloaded = ThemeStore(defaults: defaults, keys: keys, defaultAppearance: .dark,
                                  defaultPreset: .amber, appliesToApplication: false)
        XCTAssertEqual(reloaded.appearance, .light)
        XCTAssertEqual(reloaded.colors.preset, ThemeColors.customPresetID)
        XCTAssertEqual(reloaded.colors.accent, "#c72566")
        XCTAssertEqual(reloaded.colors(dark: true).preset, "kanagawa")

        reloaded.resetPalette()
        XCTAssert(reloaded.isDefaultPalette)
        XCTAssertEqual(reloaded.colors, ThemePreset.amber.colors(dark: false))
    }

    func testThemeStoreHonorsLegacyAppearanceKey() {
        let (defaults, suite) = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(suite) }
        defaults.set("light", forKey: "appTheme")
        let store = ThemeStore(defaults: defaults,
                               keys: .init(appearance: "appTheme", palette: "appThemePalette"),
                               defaultAppearance: .dark,
                               appliesToApplication: false)
        XCTAssertEqual(store.appearance, .light)
        XCTAssertEqual(store.colors, ThemePreset.amber.colors(dark: false))
    }

    func testChromeWindowAndPanelFollowLiveThemeChanges() {
        _ = NSApplication.shared
        let (defaults, suite) = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(suite) }
        let store = ThemeStore(defaults: defaults, defaultAppearance: .dark, appliesToApplication: false)
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), theme: store)
        let panel = BobukPanel(kind: .floating)
        panel.bindTheme(store)

        XCTAssertEqual(window.chromeStyle.accent.rgb, RGB(hex: 0xE7BB74))
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        XCTAssertEqual(panel.appearance?.name, .darkAqua)

        store.applyPreset(ThemePreset.named("catppuccin")!)
        XCTAssertEqual(window.chromeStyle.accent.rgb, RGB(hex: 0xCBA6F7))
        XCTAssertEqual(window.chromeStyle.panel.rgb, RGB(hex: 0x1E1E2E))

        store.appearance = .light
        XCTAssertEqual(window.chromeStyle.panel.rgb, RGB(hex: 0xEFF1F5))
        XCTAssertEqual(window.appearance?.name, .aqua)
        XCTAssertEqual(panel.appearance?.name, .aqua)

        // A dark custom panel in Light mode flips chromeAppearance to darkAqua so controls stay readable.
        store.setPanel(RGB(hex: 0x100F0F), dark: false)
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        XCTAssertEqual(panel.appearance?.name, .darkAqua)
    }

    func testThemeSettingsSectionHostsCleanly() {
        _ = NSApplication.shared
        let (defaults, suite) = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(suite) }
        let store = ThemeStore(defaults: defaults, defaultAppearance: .dark, appliesToApplication: false)
        let view = VStack {
            ThemeSettingsSection(theme: store)
        }
        .padding(16)
        .themedSurface(store)
        .frame(width: 440, height: 340)

        let host = ChromeWindow.hosting(view)
        host.setFrameSize(NSSize(width: 440, height: 340))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.frame.width, 440)
        XCTAssertEqual(host.frame.height, 340)
    }

    func testThemeStoreSetsExtendedColorRolesAndAutoResets() {
        let (defaults, suite) = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(suite) }
        let keys = ThemeStore.StorageKeys(appearance: "appTheme", palette: "appThemePalette")

        let store = ThemeStore(defaults: defaults, keys: keys, defaultAppearance: .dark,
                               defaultPreset: .amber, appliesToApplication: false)
        store.setColor(RGB(hex: 0xDDEEFF), for: .ink, dark: true)
        store.setColor(RGB(hex: 0x33AAFF), for: .link, dark: true)
        store.setColor(RGB(hex: 0x223344), for: .selection, dark: true)
        store.setColor(RGB(hex: 0xFF4466), for: .danger, dark: true)

        XCTAssertEqual(store.colors.preset, ThemeColors.customPresetID)
        XCTAssertEqual(store.tokens.ink, RGB(hex: 0xDDEEFF))
        XCTAssertEqual(store.tokens.link, RGB(hex: 0x33AAFF))
        XCTAssertEqual(store.tokens.selection, RGB(hex: 0x223344))
        XCTAssertEqual(store.tokens.danger, RGB(hex: 0xFF4466))
        XCTAssertEqual(store.pickerPalette.selection.rgb, RGB(hex: 0x223344))
        XCTAssertEqual(store.pickerPalette.link.rgb, RGB(hex: 0x33AAFF))
        XCTAssertEqual(store.chromeStyle.destructiveHover?.rgb, RGB(hex: 0xFF4466))

        let reloaded = ThemeStore(defaults: defaults, keys: keys, defaultAppearance: .dark,
                                  defaultPreset: .amber, appliesToApplication: false)
        XCTAssertEqual(reloaded.colors.link, "#33aaff")
        XCTAssertEqual(reloaded.colors.selection, "#223344")
        XCTAssertEqual(reloaded.tokens.danger, RGB(hex: 0xFF4466))

        // Resetting a role to nil clears the override and falls back to the auto-derived color.
        reloaded.setColor(nil, for: .link, dark: true)
        XCTAssertEqual(reloaded.colors.link, nil)
        XCTAssertEqual(reloaded.tokens.link, reloaded.tokens.accent)
    }

    func testThemeSettingsFormRowsHostsCleanly() {
        _ = NSApplication.shared
        let (defaults, suite) = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(suite) }
        let store = ThemeStore(defaults: defaults, defaultAppearance: .dark, appliesToApplication: false)
        // Form/Section are macOS 11; a plain VStack hosts the rows on Catalina too.
        let view = VStack {
            Text("Appearance")
            ThemeSettingsFormRows(theme: store)
        }
        .themedSurface(store)
        .frame(width: 480, height: 420)

        let host = ChromeWindow.hosting(view)
        host.setFrameSize(NSSize(width: 480, height: 420))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.frame.width, 480)
        XCTAssertEqual(host.frame.height, 420)
    }
}
#endif
