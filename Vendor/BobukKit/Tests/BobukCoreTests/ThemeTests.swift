import Foundation
import XCTest
@testable import BobukCore

final class ThemeCoreTests: XCTestCase {
    func testRgbParsesFormatsMixesAndMeasuresContrast() {
        XCTAssertEqual(RGB(hex: "#f7f8f5"), RGB(hex: 0xF7F8F5))
        XCTAssertEqual(RGB(hex: " #222A2E \n")?.hex, "#222a2e")
        XCTAssertEqual(RGB(hex: "222a2e"), nil)
        XCTAssertEqual(RGB(hex: "#fff"), nil)
        XCTAssertEqual(RGB(hex: "#gggggg"), nil)

        let white = RGB(hex: 0xFFFFFF)
        let black = RGB(hex: 0x000000)
        XCTAssert(abs(white.contrast(with: black) - 21) < 0.01)
        XCTAssertEqual(white.mixed(with: black, 0.5).hex, "#808080")
        XCTAssertEqual(white.mixed(with: black, -1), white)
        XCTAssertEqual(white.mixed(with: black, 2), black)
    }

    func testEveryBuiltinPresetIsUniqueValidAndHighContrast() {
        XCTAssertEqual(ThemePreset.all.first, .amber)
        XCTAssertEqual(ThemePreset.all.count, 18)

        let ids = ThemePreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)

        for preset in ThemePreset.all {
            XCTAssertEqual(ThemePreset.named(preset.id), preset)
            for isDark in [false, true] {
                let colors = preset.colors(dark: isDark)
                XCTAssert(colors.isValid, "\(preset.id) dark=\(isDark)")
                // Every curated preset supplies its full authentic palette.
                for role in ThemeColorRole.allCases {
                    XCTAssertNotEqual(colors.hex(for: role), nil, "\(preset.id) dark=\(isDark) missing \(role)")
                }
                let tokens = ThemeTokens(colors: colors)
                XCTAssertEqual(tokens.isDark, isDark, "\(preset.id) dark=\(isDark)")
                XCTAssert(!tokens.lowAccentContrast, "\(preset.id) dark=\(isDark) accent contrast \(tokens.panel.contrast(with: tokens.accent))")
                XCTAssert(!tokens.lowInkContrast, "\(preset.id) dark=\(isDark) ink contrast \(tokens.panel.contrast(with: tokens.ink))")
                XCTAssert(tokens.panel.contrast(with: tokens.ink) >= 7.0, "\(preset.id) dark=\(isDark) ink contrast \(tokens.panel.contrast(with: tokens.ink))")
                XCTAssert(tokens.panel.contrast(with: tokens.muted) >= 4.5, "\(preset.id) dark=\(isDark) muted contrast \(tokens.panel.contrast(with: tokens.muted))")
                XCTAssert(tokens.panel.contrast(with: tokens.link) >= 3.5, "\(preset.id) dark=\(isDark) link contrast \(tokens.panel.contrast(with: tokens.link))")
                XCTAssert(tokens.panel.contrast(with: tokens.success) >= 4.5, "\(preset.id) dark=\(isDark) success contrast \(tokens.panel.contrast(with: tokens.success))")
                XCTAssert(tokens.panel.contrast(with: tokens.danger) >= 4.5, "\(preset.id) dark=\(isDark) danger contrast \(tokens.panel.contrast(with: tokens.danger))")
                XCTAssert(tokens.accent.contrast(with: tokens.keyInk) >= 3.0, "\(preset.id) dark=\(isDark) keyInk contrast \(tokens.accent.contrast(with: tokens.keyInk))")
                XCTAssertNotEqual(tokens.selection, tokens.panel, "\(preset.id) dark=\(isDark) selection distinct")
                XCTAssertNotEqual(tokens.elevated, tokens.panel, "\(preset.id) dark=\(isDark) surface distinct")
            }
        }
    }

    func testTokensDetectLowContrastAndSupportAutoFallback() {
        let low = ThemeTokens(panel: RGB(hex: 0x222A2E), accent: RGB(hex: 0x2B3338), ink: RGB(hex: 0x333C40))
        XCTAssert(low.lowAccentContrast)
        XCTAssert(low.lowInkContrast)
        XCTAssert(low.isDark)
        XCTAssert(!low.isTinted)

        let tinted = ThemeTokens(tint: RGB(hex: 0xFFFFFF), colors: ThemePreset.amber.colors(dark: true))
        XCTAssert(tinted.isTinted)
        XCTAssert(!tinted.isDark)
        XCTAssertEqual(tinted.accent, RGB(hex: 0xE7BB74))
        XCTAssert(tinted.panel.contrast(with: tinted.border(increasedContrast: true))
                > tinted.panel.contrast(with: tinted.border(increasedContrast: false)))
    }

    func testPaletteConfigPersistsAllRolesAndRemainsBackwardCompatible() throws {
        var config = ThemePaletteConfig(preset: ThemePreset.named("kanagawa")!)
        XCTAssertEqual(config.dark.ink, "#dcd7ba")
        XCTAssertEqual(config.dark.link, "#7fb4ca")

        // Editing a single role marks that side as custom without losing other roles.
        config.set("#ff5500", for: .link, dark: true)
        XCTAssertEqual(config.dark.preset, ThemeColors.customPresetID)
        XCTAssertEqual(config.dark.link, "#ff5500")
        XCTAssertEqual(config.dark.ink, "#dcd7ba")
        XCTAssertEqual(config.light.preset, "kanagawa")

        // Resetting an optional role to nil falls back to auto derivation.
        config.set(nil, for: .link, dark: true)
        XCTAssertEqual(config.dark.link, nil)
        XCTAssertEqual(config.tokens(dark: true).link, config.tokens(dark: true).accent)

        // Invalid hex is ignored.
        config.set("not-a-color", for: .surface, dark: true)
        XCTAssertEqual(config.dark.surface, "#2a2a37")

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ThemePaletteConfig.self, from: data)
        XCTAssertEqual(decoded, config)

        // Legacy 2-color JSON (without ink/surface/muted/etc.) decodes cleanly and derives all tokens.
        let legacy = Data(##"{"light":{"preset":"custom","panel":"#f7f8f5","accent":"#885500"},"dark":{"preset":"nord","panel":"#2e3440","accent":"#88c0d0"}}"##.utf8)
        let fromLegacy = try JSONDecoder().decode(ThemePaletteConfig.self, from: legacy)
        XCTAssertEqual(fromLegacy.dark.panel, "#2e3440")
        XCTAssertEqual(fromLegacy.dark.ink, nil)
        XCTAssertEqual(fromLegacy.tokens(dark: true).ink, ThemeTokens.lightInk)

        // Corrupt colors fall back to Amber without throwing.
        let corrupt = Data(##"{"light":{"preset":"bad","panel":"nope","accent":"#123"},"dark":{"preset":"nord","panel":"#2e3440","accent":"#88c0d0","ink":"bad"}}"##.utf8)
        let recovered = try JSONDecoder().decode(ThemePaletteConfig.self, from: corrupt)
        XCTAssertEqual(recovered.light, ThemePreset.amber.colors(dark: false))
        XCTAssertEqual(recovered.dark, ThemePreset.amber.colors(dark: true))
    }
}
