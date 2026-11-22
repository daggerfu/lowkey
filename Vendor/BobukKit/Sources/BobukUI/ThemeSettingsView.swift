#if canImport(AppKit)
// Reusable SwiftUI theming modifiers, section cards, rich preview swatch and Settings controls
// (both standalone cards and grouped Form rows) for bobuk-io apps.
import AppKit
import BobukCore
import SwiftUI

public extension View {
    /// Applies a theme's panel surface, primary text color and accent tint across the view hierarchy.
    func themedSurface(_ tokens: ThemeTokens) -> some View {
        self
            .foregroundColor(tokens.inkColor)
            .background(tokens.panelColor)
    }

    /// Convenience overload reading live tokens from a `ThemeStore`.
    func themedSurface(_ theme: ThemeStore) -> some View {
        themedSurface(theme.tokens)
    }
}

/// A themed settings/content card: tracked mono header over an elevated surface with a hairline border.
public struct ThemedSection<Content: View>: View {
    private let title: String?
    private let tokens: ThemeTokens
    private let content: Content

    public init(_ title: String? = nil, tokens: ThemeTokens, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tokens = tokens
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title, !title.isEmpty {
                MonoLabel(title, size: 10, tracking: 1.4)
                    .foregroundColor(tokens.mutedColor)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(tokens.elevatedColor))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.strokeColor, lineWidth: 1))
        }
    }
}

/// Compact 5-dot swatch strip visualizing a theme's panel, surface, accent, text and success colors.
public struct ThemeSwatchStrip: View {
    public let tokens: ThemeTokens

    public init(tokens: ThemeTokens) {
        self.tokens = tokens
    }

    public var body: some View {
        HStack(spacing: 4) {
            dot(tokens.panelColor)
            dot(tokens.elevatedColor)
            dot(tokens.accentColor)
            dot(tokens.linkColor)
            dot(tokens.successColor)
            dot(tokens.dangerColor)
        }
        .accessibility(hidden: true)
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(tokens.lineColor.opacity(0.75), lineWidth: 0.75))
    }
}

/// Rich swatch showing accent bar, panel, elevated card, selection row, text, muted, link and status dots.
public struct ThemePreview: View {
    public let tokens: ThemeTokens

    public init(tokens: ThemeTokens) {
        self.tokens = tokens
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(tokens.accentColor)
                .frame(height: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Title")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(tokens.inkColor)
                            Text("link")
                                .font(.system(size: 10, weight: .medium))
                                .underline()
                                .foregroundColor(tokens.linkColor)
                        }
                        Text("Secondary text")
                            .font(.system(size: 9))
                            .foregroundColor(tokens.mutedColor)
                    }
                    Spacer(minLength: 6)
                    Text("KEY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(tokens.keyInkColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(tokens.accentColor))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 5).fill(tokens.elevatedColor))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(tokens.strokeColor, lineWidth: 0.75))

                HStack(spacing: 6) {
                    Text("Selected row")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(tokens.inkColor)
                    Spacer(minLength: 4)
                    Circle().fill(tokens.successColor).frame(width: 6, height: 6)
                    Circle().fill(tokens.dangerColor).frame(width: 6, height: 6)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(tokens.selectionColor))
            }
            .padding(8)
            .background(tokens.panelColor)
        }
        .frame(width: 220)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(tokens.lineColor, lineWidth: 1))
        .accessibility(hidden: true)
    }
}

private struct ThemeRoleSpec: Identifiable {
    let role: ThemeColorRole
    let title: String
    var id: ThemeColorRole { role }

    static let core: [ThemeRoleSpec] = [
        .init(role: .panel, title: "Panel"),
        .init(role: .accent, title: "Accent"),
        .init(role: .ink, title: "Text"),
    ]

    static let advanced: [ThemeRoleSpec] = [
        .init(role: .surface, title: "Surface"),
        .init(role: .muted, title: "Muted text"),
        .init(role: .border, title: "Border"),
        .init(role: .selection, title: "Selection"),
        .init(role: .link, title: "Link"),
        .init(role: .success, title: "Success"),
        .init(role: .danger, title: "Danger"),
    ]
}

private struct ThemeBindings {
    let theme: ThemeStore
    let presets: [ThemePreset]
    let editingDark: Bool

    var colors: ThemeColors { theme.colors(dark: editingDark) }
    var tokens: ThemeTokens { theme.tokens(dark: editingDark) }

    var presetSelection: Binding<String> {
        Binding(
            get: {
                let id = colors.preset
                return presets.contains(where: { $0.id == id }) ? id : ThemeColors.customPresetID
            },
            set: { id in
                guard id != ThemeColors.customPresetID else { return }
                theme.applyPreset(id: id, in: presets)
            }
        )
    }

    func colorBinding(for role: ThemeColorRole) -> Binding<NSColor> {
        Binding(
            get: { NSColor(tokens.color(for: role)) },
            set: { color in
                guard let rgb = color.rgb else { return }
                theme.setColor(rgb, for: role, dark: editingDark)
            }
        )
    }

    func canResetToAuto(_ role: ThemeColorRole) -> Bool {
        guard role != .panel && role != .accent else { return false }
        return colors.preset == ThemeColors.customPresetID && colors.hex(for: role) != nil
    }

    func resetToAuto(_ role: ThemeColorRole) {
        theme.setColor(nil, for: role, dark: editingDark)
    }
}

/// Native color control (macOS 10.15): the modern SwiftUI `ColorPicker` is not available here.
private struct ColorWell: NSViewRepresentable {
    @Binding var color: NSColor
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(frame: .zero)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.controlSize = .small
        well.setAccessibilityLabel(accessibilityLabel)
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.parent = self
        well.color = color
        well.setAccessibilityLabel(accessibilityLabel)
    }

    final class Coordinator: NSObject {
        var parent: ColorWell
        init(_ parent: ColorWell) { self.parent = parent }

        @objc func colorChanged(_ well: NSColorWell) { parent.color = well.color }
    }
}

/// Form rows for apps that embed theme controls inside a native macOS grouped `Form` `Section`.
/// Shows Mode, Theme (with palette swatches), core colors (`Panel`, `Accent`, `Text`), an expandable
/// `More colors` disclosure (`Surface`, `Muted text`, `Border`, `Selection`, `Link`, `Success`,
/// `Danger`), rich live preview, WCAG contrast warnings and Reset.
public struct ThemeSettingsFormRows: View {
    @ObservedObject private var theme: ThemeStore
    private let offeredAppearances: [AppearanceChoice]
    private let presets: [ThemePreset]
    private let showsCustomColors: Bool
    @State private var editingDark: Bool
    @State private var showMoreColors = false

    public init(theme: ThemeStore,
                offeredAppearances: [AppearanceChoice] = AppearanceChoice.allCases,
                presets: [ThemePreset] = ThemePreset.all,
                showsCustomColors: Bool = true) {
        self.theme = theme
        self.offeredAppearances = offeredAppearances
        self.presets = presets
        self.showsCustomColors = showsCustomColors
        _editingDark = State(initialValue: theme.isDark)
    }

    private var activeEditingDark: Bool {
        switch theme.appearance {
        case .light: return false
        case .dark: return true
        case .system: return editingDark
        }
    }

    private var bindings: ThemeBindings {
        ThemeBindings(theme: theme, presets: presets, editingDark: activeEditingDark)
    }

    private var editedTokens: ThemeTokens { bindings.tokens }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(theme.tokens.inkColor)
            Spacer(minLength: 12)
            control()
        }
    }

    public var body: some View {
        Group {
            Picker("Mode", selection: $theme.appearance) {
                ForEach(offeredAppearances) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            row("Theme") {
                HStack(spacing: 10) {
                    ThemeSwatchStrip(tokens: editedTokens)
                    Picker("Theme", selection: bindings.presetSelection) {
                        ForEach(presets) { preset in
                            Text(preset.title).tag(preset.id)
                        }
                        if bindings.colors.preset == ThemeColors.customPresetID {
                            Divider()
                            Text("Custom").tag(ThemeColors.customPresetID)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            if showsCustomColors {
                if theme.appearance == .system {
                    Picker("Customize", selection: $editingDark) {
                        Text("Light").tag(false)
                        Text("Dark").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                ForEach(ThemeRoleSpec.core) { spec in
                    colorRow(spec, bindings: bindings)
                }

                Button(action: { showMoreColors.toggle() }) {
                    Text(showMoreColors ? "▾ More colors" : "▸ More colors")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.tokens.mutedColor)
                }
                .buttonStyle(PlainButtonStyle())

                if showMoreColors {
                    ForEach(ThemeRoleSpec.advanced) { spec in
                        colorRow(spec, bindings: bindings)
                    }
                }
            }

            row("Preview") {
                ThemePreview(tokens: editedTokens)
            }

            if editedTokens.lowAccentContrast {
                // Text, not Label/SF Symbols: the kit stays on the macOS 10.15 SDK.
                Text("⚠ The accent color is hard to see on this panel.")
                    .font(.caption)
                    .foregroundColor(editedTokens.dangerColor)
            }

            if editedTokens.lowInkContrast {
                Text("⚠ The text color has low contrast on this panel.")
                    .font(.caption)
                    .foregroundColor(editedTokens.dangerColor)
            }

            HStack {
                Spacer()
                Button("Reset to \(theme.defaultPreset.title)") {
                    theme.resetPalette()
                }
                .disabled(theme.isDefaultPalette)
            }
        }
        .onReceive(theme.$appearance) { next in
            switch next {
            case .light: editingDark = false
            case .dark: editingDark = true
            case .system: editingDark = theme.isDark
            }
        }
    }

    private func colorRow(_ spec: ThemeRoleSpec, bindings: ThemeBindings) -> some View {
        row(spec.title) {
            HStack(spacing: 8) {
                if bindings.canResetToAuto(spec.role) {
                    Button("Auto") { bindings.resetToAuto(spec.role) }
                        .buttonStyle(BorderlessButtonStyle())
                        .font(.caption)
                        .foregroundColor(theme.tokens.mutedColor)
                        .accessibility(label: Text("Use automatic contrast-matched color"))
                }
                ColorWell(color: bindings.colorBinding(for: spec.role), accessibilityLabel: spec.title)
                    .frame(width: 32, height: 18)
            }
        }
    }
}

/// Drop-in Settings card for Appearance mode, Theme preset selection (with swatches), core colors,
/// expandable `More colors`, rich live preview, WCAG contrast warnings and Reset.
public struct ThemeSettingsSection: View {
    @ObservedObject private var theme: ThemeStore
    private let title: String
    private let offeredAppearances: [AppearanceChoice]
    private let presets: [ThemePreset]
    private let showsCustomColors: Bool
    @State private var editingDark: Bool
    @State private var showMoreColors = false

    public init(theme: ThemeStore,
                title: String = "Appearance",
                offeredAppearances: [AppearanceChoice] = AppearanceChoice.allCases,
                presets: [ThemePreset] = ThemePreset.all,
                showsCustomColors: Bool = true) {
        self.theme = theme
        self.title = title
        self.offeredAppearances = offeredAppearances
        self.presets = presets
        self.showsCustomColors = showsCustomColors
        _editingDark = State(initialValue: theme.isDark)
    }

    private var activeEditingDark: Bool {
        switch theme.appearance {
        case .light: return false
        case .dark: return true
        case .system: return editingDark
        }
    }

    private var tokens: ThemeTokens { theme.tokens }
    private var palette: PickerPalette { theme.pickerPalette }
    private var bindings: ThemeBindings {
        ThemeBindings(theme: theme, presets: presets, editingDark: activeEditingDark)
    }
    private var editedTokens: ThemeTokens { bindings.tokens }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(theme.tokens.inkColor)
            Spacer(minLength: 12)
            control()
        }
    }

    private func compactPicker(_ spec: ThemeRoleSpec, bindings: ThemeBindings) -> some View {
        HStack(spacing: 6) {
            Text(spec.title)
                .font(.system(size: 12.5))
                .foregroundColor(theme.tokens.inkColor)
            ColorWell(color: bindings.colorBinding(for: spec.role), accessibilityLabel: spec.title)
                .frame(width: 32, height: 18)
        }
    }

    private func detailColorRow(_ spec: ThemeRoleSpec, bindings: ThemeBindings) -> some View {
        HStack(spacing: 8) {
            Text(spec.title)
                .font(.system(size: 12.5))
                .foregroundColor(theme.tokens.inkColor)
            Spacer(minLength: 8)
            if bindings.canResetToAuto(spec.role) {
                Button("Auto") { bindings.resetToAuto(spec.role) }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 11))
                    .foregroundColor(theme.tokens.mutedColor)
                    .accessibility(label: Text("Use automatic contrast-matched color"))
            }
            ColorWell(color: bindings.colorBinding(for: spec.role), accessibilityLabel: spec.title)
                .frame(width: 32, height: 18)
        }
    }

    public var body: some View {
        ThemedSection(title, tokens: tokens) {
            row("Mode") {
                Picker("Mode", selection: $theme.appearance) {
                    ForEach(offeredAppearances) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 220)
            }

            Rectangle().fill(tokens.strokeColor).frame(height: 1)

            row("Theme") {
                HStack(spacing: 8) {
                    ThemeSwatchStrip(tokens: editedTokens)
                    Picker("Theme", selection: bindings.presetSelection) {
                        ForEach(presets) { preset in
                            Text(preset.title).tag(preset.id)
                        }
                        if bindings.colors.preset == ThemeColors.customPresetID {
                            Divider()
                            Text("Custom").tag(ThemeColors.customPresetID)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165, alignment: .trailing)
                }
            }

            if showsCustomColors {
                if theme.appearance == .system {
                    row("Customize") {
                        Picker("Customize", selection: $editingDark) {
                            Text("Light").tag(false)
                            Text("Dark").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 150)
                    }
                }

                Rectangle().fill(tokens.strokeColor).frame(height: 1)

                HStack(spacing: 12) {
                    compactPicker(ThemeRoleSpec.core[0], bindings: bindings)
                    Spacer(minLength: 4)
                    compactPicker(ThemeRoleSpec.core[1], bindings: bindings)
                    Spacer(minLength: 4)
                    compactPicker(ThemeRoleSpec.core[2], bindings: bindings)
                }

                Button(action: { showMoreColors.toggle() }) {
                    Text(showMoreColors ? "▾ More colors" : "▸ More colors")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(tokens.mutedColor)
                }
                .buttonStyle(PlainButtonStyle())

                if showMoreColors {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ThemeRoleSpec.advanced) { spec in
                            detailColorRow(spec, bindings: bindings)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            Rectangle().fill(tokens.strokeColor).frame(height: 1)

            row("Preview") {
                ThemePreview(tokens: editedTokens)
            }

            if editedTokens.lowAccentContrast {
                // Text, not Label/SF Symbols: the kit stays on the macOS 10.15 SDK.
                Text("⚠ The accent color is hard to see on this panel.")
                    .font(.caption)
                    .foregroundColor(editedTokens.dangerColor)
            }

            if editedTokens.lowInkContrast {
                Text("⚠ The text color has low contrast on this panel.")
                    .font(.caption)
                    .foregroundColor(editedTokens.dangerColor)
            }

            HStack {
                Spacer()
                Button("Reset to \(theme.defaultPreset.title)") {
                    theme.resetPalette()
                }
                .buttonStyle(QuietButtonStyle(palette: palette, height: 26))
                .disabled(theme.isDefaultPalette)
            }
        }
        .onReceive(theme.$appearance) { next in
            switch next {
            case .light: editingDark = false
            case .dark: editingDark = true
            case .system: editingDark = theme.isDark
            }
        }
    }
}
#endif
