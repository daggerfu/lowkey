import SwiftUI
import LowkeyCore
import BobukUI

/// Native actions around BobukKit's shared layout; search and deletion stay in Lowkey.
/// Uses only the SwiftUI subset available on macOS 10.15.
struct SuggestionRow: View {
    let suggestion: Suggestion
    let selected: Bool
    let badgeWidth: CGFloat
    let palette: PickerPalette
    let onChoose: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        PickerRow(selected: selected, palette: palette) {
            HStack(spacing: PickerMetrics.columnSpacing) {
                Button(action: onChoose) {
                    HStack(spacing: PickerMetrics.columnSpacing) {
                        PickerBadge(badge, width: badgeWidth, palette: palette, emphasized: !isHistory)
                        Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                            .foregroundColor(Color(palette.text))
                        Spacer(minLength: 0)
                        if let detail = detail {
                            Text(detail).font(.system(size: 10.5)).lineLimit(1).truncationMode(.middle)
                                .foregroundColor(Color(palette.secondary))
                                .layoutPriority(-1)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: PickerMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibility(label: Text(isHistory ? "History \(title)" : "Site \(badge), \(title)"))
                .accessibility(addTraits: selected ? .isSelected : [])
                if isHistory {
                    // BobukKit's close glyph; it brightens on hover like other row actions.
                    GlyphButton(.close, label: "Remove \(title) from history", help: "Remove from history",
                                palette: palette, width: 18, height: 22, glyphSize: 11, hoverFill: false,
                                action: onRemove)
                    .opacity(selected || hovering ? 1 : 0)
                    .allowsHitTesting(selected || hovering)
                    .accessibility(hidden: !(selected || hovering))
                } else {
                    Color.clear.frame(width: 18, height: 22).accessibility(hidden: true)
                }
            }
        }
        .onHover { hovering = $0 }
    }

    private var isHistory: Bool { if case .history = suggestion { return true }; return false }
    private var badge: String { if case .site(let site) = suggestion { return site.alias.uppercased() }; return "↺" }
    private var title: String { if case .site(let site) = suggestion { return site.displayTitle }; return suggestion.text }
    private var detail: String? { if case .site(let site) = suggestion { return site.url?.host ?? site.startURL }; return nil }
}
