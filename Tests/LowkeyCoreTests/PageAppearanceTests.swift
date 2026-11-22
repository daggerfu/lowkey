import Foundation
import XCTest
@testable import LowkeyCore

final class PageAppearanceTests: XCTestCase {
    func testDetectsCommonBackgrounds() {
        for hex in ["#282a36", "#2e3440", "#1e1e2e", "#002b36", "#000000"] {
            XCTAssertTrue(PageAppearance.isDark(background: RGB(hex: hex)!))
        }
        for hex in ["#ffffff", "#eff1f5", "#faf4ed", "#fdf6e3", "#eceff4"] {
            XCTAssertFalse(PageAppearance.isDark(background: RGB(hex: hex)!))
        }
    }

    func testDeadBandKeepsPreviousMode() {
        let gray = RGB(r: 0.47, g: 0.47, b: 0.47)
        XCTAssertTrue(PageAppearance.isDark(background: gray, previous: true))
        XCTAssertFalse(PageAppearance.isDark(background: gray, previous: false))
        XCTAssertFalse(PageAppearance.isDark(background: RGB(hex: "#ffffff")!, previous: true))
        XCTAssertTrue(PageAppearance.isDark(background: RGB(hex: "#222222")!, previous: false))
    }

    func testNewConfigsTintWhileExplicitModesArePreserved() throws {
        XCTAssertEqual(AppearanceConfig().mode, .tint)
        for mode in ["tint", "system", "light", "dark"] {
            let data = Data("{\"appearance\":{\"mode\":\"\(mode)\"}}".utf8)
            let config = try JSONDecoder().decode(Config.self, from: data)
            XCTAssertEqual(config.appearance.mode.rawValue, mode)
        }
    }

    func testMissingModeDecodesToTint() throws {
        for json in [#"{}"#, #"{"appearance":{}}"#, ##"{"version":2,"appearance":{"light":{"preset":"amber","panel":"#f7f8f5","accent":"#885500"}}}"##] {
            XCTAssertEqual(try JSONDecoder().decode(Config.self, from: Data(json.utf8)).appearance.mode, .tint)
        }
        XCTAssertEqual(try JSONDecoder().decode(AppearanceConfig.self, from: Data("{}".utf8)).mode, .tint)
    }

    func testSavedPageModeMovesToTintOnce() throws {
        func mode(_ json: String) throws -> ThemeMode {
            try JSONDecoder().decode(Config.self, from: Data(json.utf8)).appearance.mode
        }
        XCTAssertEqual(try mode(#"{"appearance":{"mode":"page"}}"#), .tint)
        XCTAssertEqual(try mode(#"{"version":1,"appearance":{"mode":"page"}}"#), .tint)
        XCTAssertEqual(try mode(#"{"version":2,"appearance":{"mode":"page"}}"#), .page)
        for kept in ["system", "light", "dark"] {
            for version in ["", #""version":1,"#, #""version":2,"#] {
                XCTAssertEqual(try mode("{\(version)\"appearance\":{\"mode\":\"\(kept)\"}}").rawValue, kept)
            }
        }
    }

    func testEncodedConfigHasVersion2AndKeepsPage() throws {
        let data = try JSONEncoder().encode(Config(appearance: AppearanceConfig(mode: .page)))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["version"] as? Int, 2)
        XCTAssertEqual(try JSONDecoder().decode(Config.self, from: data).appearance.mode, .page)
    }

    func testTintRoundTripsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowkey-config-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let config = Config(appearance: AppearanceConfig(mode: .tint))
        try config.save(to: url)
        XCTAssertEqual(try Config.load(from: url), config)
        XCTAssertEqual(try Config.load(from: url).appearance.mode, .tint)
    }

    func testTintPrefersThemeColorThenBackgroundThenPrevious() {
        let theme = RGB(hex: "#336699")!, background = RGB(hex: "#ffffff")!, previous = RGB(hex: "#111111")!
        let usable = { (rgb: RGB) in PageColor(rgb: rgb, alpha: 1) }
        XCTAssertEqual(PageAppearance.tint(themeColor: usable(theme), background: usable(background), previous: previous), theme)
        XCTAssertEqual(PageAppearance.tint(themeColor: nil, background: usable(background), previous: previous), background)
        XCTAssertEqual(PageAppearance.tint(themeColor: PageColor(rgb: theme, alpha: 0.89), background: usable(background),
                                          previous: previous), background)
        XCTAssertEqual(PageAppearance.tint(themeColor: PageColor(rgb: theme, alpha: 0.9), background: usable(background),
                                          previous: nil), theme)
        XCTAssertEqual(PageAppearance.tint(themeColor: PageColor(rgb: theme, alpha: 0.5), background: PageColor(rgb: background, alpha: 0),
                                          previous: previous), previous)
        XCTAssertEqual(PageAppearance.tint(themeColor: nil, background: nil, previous: previous), previous)
        XCTAssertNil(PageAppearance.tint(themeColor: nil, background: nil, previous: nil))
        XCTAssertNil(PageAppearance.tint(themeColor: PageColor(rgb: theme, alpha: 0.2), background: nil, previous: nil))
    }

    func testTintedTokensTakeInkFromTintAndAccentFromPalette() {
        let palette = ThemePreset.amber.colors(dark: false)
        let accent = ThemeTokens(colors: palette).accent
        let light = RGB(hex: "#ffd700")!, dark = RGB(hex: "#1a237e")!
        let onLight = ThemeTokens(tint: light, colors: palette)
        XCTAssertEqual(onLight.panel, light)
        XCTAssertEqual(onLight.ink, ThemeTokens.darkInk)
        XCTAssertEqual(onLight.accent, accent)
        XCTAssertEqual(onLight.muted, light.mixed(with: ThemeTokens.darkInk, 0.72))
        let onDark = ThemeTokens(tint: dark, colors: palette)
        XCTAssertEqual(onDark.panel, dark)
        XCTAssertEqual(onDark.ink, ThemeTokens.lightInk)
        XCTAssertEqual(onDark.accent, accent)
        XCTAssertEqual(onDark.hover, dark.mixed(with: ThemeTokens.lightInk, 0.07))
        XCTAssertTrue(onLight.isTinted && onDark.isTinted)
        XCTAssertFalse(ThemeTokens(colors: palette).isTinted)
    }
}
