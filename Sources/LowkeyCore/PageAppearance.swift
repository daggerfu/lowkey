import Foundation

/// Light/dark classification for a page's background, not its `prefers-color-scheme` preference.
/// A small dead band prevents switching repeatedly when the page animates through mid-gray.
public enum PageAppearance {
    public static func isDark(background: RGB, previous: Bool? = nil) -> Bool {
        switch previous {
        case .some(true): return background.luminance < 0.22
        case .some(false): return background.luminance < 0.15
        case .none: return background.luminance < 0.18
        }
    }

    /// Colors with less alpha are not usable: the page shows something else through them.
    public static let minimumAlpha = 0.9

    /// The Tint color of a window: the site's `theme-color`, then the page background,
    /// then the previous Tint color; nil before the first usable color.
    public static func tint(themeColor: PageColor?, background: PageColor?, previous: RGB?) -> RGB? {
        [themeColor, background].compactMap { $0 }.first { $0.isUsable }?.rgb ?? previous
    }
}

/// A color read from the page, with its alpha.
public struct PageColor: Equatable {
    public var rgb: RGB
    public var alpha: Double

    public init(rgb: RGB, alpha: Double) {
        self.rgb = rgb
        self.alpha = alpha
    }

    public var isUsable: Bool { alpha >= PageAppearance.minimumAlpha }
}
