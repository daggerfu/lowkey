#if canImport(AppKit)
import AppKit
import SwiftUI

public struct ShortcutHint: Hashable, Identifiable {
    public let keys: String
    public let action: String
    public var id: Self { self }
    public init(_ keys: String, _ action: String) { self.keys = keys; self.action = action }
}

/// Each shortcut and its caption stay together; complete groups wrap onto another line.
/// These are hints, never hidden keyboard handlers. Apps own all actual commands.
/// Pass `onSettings` to show a trailing settings gear button in the footer bar.
public struct ShortcutFooter: View {
    private let hints: [ShortcutHint]
    private let palette: PickerPalette
    private let settingsLabel: String
    private let settingsHelp: String
    private let onSettings: (() -> Void)?
    @State private var availableWidth: CGFloat = 0

    public init(_ hints: [ShortcutHint],
                palette: PickerPalette,
                settingsLabel: String = "Settings",
                settingsHelp: String = "Settings",
                onSettings: (() -> Void)? = nil) {
        self.hints = hints
        self.palette = palette
        self.settingsLabel = settingsLabel
        self.settingsHelp = settingsHelp
        self.onSettings = onSettings
    }

    private var resolvedWidth: CGFloat { availableWidth > 0 ? availableWidth : .infinity }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .topLeading) {
                GeometryReader { geometry in
                    Color.clear.preference(key: HintWidthKey.self, value: geometry.size.width)
                }
                hintStack(width: resolvedWidth)
            }
            .frame(height: stackHeight(width: resolvedWidth))
            .onPreferenceChange(HintWidthKey.self) { width in availableWidth = width }
            .accessibilityElement(children: .contain)

            if let onSettings = onSettings {
                GlyphButton(.settings, label: settingsLabel, help: settingsHelp, palette: palette,
                            width: 22, height: 22, glyphSize: 13, action: onSettings)
            }
        }
    }

    private func hintStack(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(placements(width: width)) { placement in
                hintView(placement.hint)
                    .frame(width: placement.size.width, height: placement.size.height, alignment: .topLeading)
                    .offset(x: placement.frame.minX, y: placement.frame.minY)
            }
        }
    }

    private func hintView(_ hint: ShortcutHint) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(hint.keys)
                .font(.system(size: PickerMetrics.footerFontSize, weight: .medium, design: .monospaced))
                .fixedSize()
                .foregroundColor(Color(palette.text))
            Text(hint.action)
                .font(.system(size: PickerMetrics.footerFontSize, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(Color(palette.secondary))
        }
        .accessibilityElement(children: .ignore)
        .accessibility(label: Text("\(hint.keys): \(hint.action)"))
    }

    private func placements(width: CGFloat) -> [HintPlacement] {
        let sizes = hints.map { HintPacking.size(for: $0) }
        let frames = HintPacking.frames(sizes: sizes, width: width)
        var result: [HintPlacement] = []
        for (index, hint) in hints.enumerated() {
            result.append(HintPlacement(index: index, hint: hint, size: sizes[index], frame: frames[index]))
        }
        return result
    }

    private func stackHeight(width: CGFloat) -> CGFloat {
        placements(width: width).map { $0.frame.maxY }.max() ?? 0
    }
}

private struct HintPlacement: Identifiable {
    let index: Int
    let hint: ShortcutHint
    let size: CGSize
    let frame: CGRect
    var id: Int { index }
}

private struct HintWidthKey: PreferenceKey {
    typealias Value = CGFloat
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Deterministic geometry, also used by tests without presenting a window.
enum HintPacking {
    static func frames(sizes: [CGSize], width: CGFloat) -> [CGRect] {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        return sizes.map { size in
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + PickerMetrics.footerLineSpacing
                lineHeight = 0
            }
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            x += size.width + PickerMetrics.footerSpacing
            lineHeight = max(lineHeight, size.height)
            return frame
        }
    }

    /// Ideal size of one shortcut group at the footer's monospaced font.
    static func size(for hint: ShortcutHint) -> CGSize {
        let medium = NSFont.monospacedSystemFont(ofSize: PickerMetrics.footerFontSize, weight: .medium)
        let regular = NSFont.monospacedSystemFont(ofSize: PickerMetrics.footerFontSize, weight: .regular)
        let keysWidth = ceil((hint.keys as NSString).size(withAttributes: [.font: medium]).width)
        let actionWidth = ceil((hint.action as NSString).size(withAttributes: [.font: regular]).width)
        let lineHeight = ceil(max(medium.boundingRectForFont.height, regular.boundingRectForFont.height))
        return CGSize(width: keysWidth + 4 + actionWidth, height: lineHeight)
    }
}
#endif
