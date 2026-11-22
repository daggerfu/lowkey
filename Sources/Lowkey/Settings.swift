import AppKit
import BobukUI
import LowkeyCore
import SwiftUI

final class SettingsModel: ObservableObject {
    private unowned let app: AppController
    @Published var draft: Config { didSet { commit() } }
    @Published var selection: UUID?
    @Published var problems: [String] = []
    /// Which mode's colors the color pickers edit.
    @Published var editingDark: Bool

    init(app: AppController) {
        self.app = app
        draft = app.store.config
        selection = app.store.config.sites.first?.id
        editingDark = ThemeCenter.shared.isDark
    }

    var store: Store { app.store }

    /// Saves valid changes at once. With site problems, the appearance still saves and the sites wait.
    private func commit() {
        problems = draft.problems()
        if problems.isEmpty {
            problems = store.update(draft)
        } else {
            var config = store.config
            config.appearance = draft.appearance
            store.update(config)
        }
        app.applyAppearance(draft.appearance)
    }

    var selectedIndex: Int? { draft.sites.firstIndex { $0.id == selection } }

    func site<T>(_ keyPath: WritableKeyPath<Site, T>, default value: T) -> Binding<T> {
        Binding(get: { [weak self] in
            guard let self = self, let index = self.selectedIndex else { return value }
            return self.draft.sites[index][keyPath: keyPath]
        }, set: { [weak self] newValue in
            guard let self = self, let index = self.selectedIndex else { return }
            self.draft.sites[index][keyPath: keyPath] = newValue
        })
    }

    func addSite() {
        var number = draft.sites.count + 1
        while draft.site(alias: "SITE\(number)") != nil { number += 1 }
        let site = Site(alias: "SITE\(number)", title: "", startURL: "https://")
        draft.sites.append(site)
        selection = site.id
    }

    func removeSelected() {
        guard let index = selectedIndex else { return }
        let site = draft.sites[index]
        let alert = NSAlert()
        alert.messageText = "Remove “\(site.displayTitle)”?"
        alert.informativeText = "lowkey closes its window and deletes its profile: cookies, sign-ins and site data. This can’t be undone."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if #available(macOS 11, *) {
            alert.buttons.first?.hasDestructiveAction = true
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let wasSaved = store.config.site(id: site.id) != nil
        draft.sites.remove(at: index)
        selection = draft.sites.indices.contains(index) ? draft.sites[index].id : draft.sites.last?.id
        if wasSaved { app.removeSiteData(site.id) }
    }

    // MARK: Appearance

    var colors: ThemeColors {
        get { draft.appearance.colors(dark: editingDark) }
        set {
            if editingDark { draft.appearance.dark = newValue } else { draft.appearance.light = newValue }
        }
    }

    var isDefaultForEditingMode: Bool {
        colors == ThemePreset.amber.colors(dark: editingDark)
    }

    func applyPreset(_ id: String) {
        guard let preset = ThemePreset.named(id) else { return }
        colors = preset.colors(dark: editingDark)
    }

    /// Native color well binding; `ColorPicker` needs macOS 11.
    func nsColor(for role: ThemeColorRole) -> Binding<NSColor> {
        Binding(get: { [weak self] in
            NSColor(ThemeTokens(colors: self?.colors ?? ThemePreset.amber.colors(dark: false)).color(for: role))
        }, set: { [weak self] color in
            guard let self = self, let rgb = color.rgb else { return }
            let current = ThemeTokens(colors: self.colors).color(for: role)
            guard rgb.hex != current.hex else { return }
            var next = self.colors
            next.set(rgb.hex, for: role)
            self.colors = next
        })
    }

    func canResetToAuto(_ role: ThemeColorRole) -> Bool {
        guard role != .panel && role != .accent else { return false }
        return colors.preset == ThemeColors.customPresetID && colors.hex(for: role) != nil
    }

    func resetToAuto(_ role: ThemeColorRole) {
        var next = colors
        next.set(nil, for: role)
        colors = next
    }

    func resetColors() { applyPreset(ThemePreset.amber.id) }

    func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear input history?"
        alert.informativeText = "lowkey forgets every address and alias you typed. Saved sites stay."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clearHistory()
        objectWillChange.send()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: Store

    var body: some View {
        return TabView {
            SitesPane(model: model)
                .tabItem { Text("Sites") }
            AppearancePane(model: model)
                .tabItem { Text("Appearance") }
            GeneralPane(model: model, store: store)
                .tabItem { Text("History") }
        }
        .padding(16)
        .frame(width: 680, height: 540)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).frame(width: 118, alignment: .leading)
            content
        }
    }
}

private struct SitesPane: View {
    @ObservedObject var model: SettingsModel
    @State private var originsText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    ForEach(model.draft.sites) { site in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.displayTitle).lineLimit(1)
                            Text(site.alias).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                        }
                        .tag(site.id)
                    }
                }
                .listStyle(PlainListStyle())
                HStack(spacing: 2) {
                    Button(action: model.addSite) { Image(nsImage: NSImage(named: NSImage.addTemplateName)!).frame(width: 18, height: 16) }
                        .accessibility(label: Text("Add a site"))
                    Button(action: model.removeSelected) { Image(nsImage: NSImage(named: NSImage.removeTemplateName)!).frame(width: 18, height: 16) }
                        .accessibility(label: Text("Remove the selected site"))
                        .disabled(model.selection == nil)
                    Spacer()
                }
                .buttonStyle(BorderlessButtonStyle())
                .padding(.top, 6)
            }
            .frame(width: 190)

            if model.selectedIndex != nil {
                detail
            } else {
                VStack(spacing: 8) {
                    Text("No sites yet").font(.headline)
                    Text("Add a site with +, give it an alias such as HA, and open it with lowkey://HA/open.")
                        .multilineTextAlignment(.center).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: loadOrigins)
        .onReceive(model.$selection) { _ in loadOrigins() }
    }

    private var detail: some View {
        let alias = model.site(\.alias, default: "")
        return Form {
            TextField("Alias", text: alias)
                .font(.system(.body, design: .monospaced))
            SettingsRow("Deep link") {
                HStack {
                    Text(DeepLink.url(alias: alias.wrappedValue)).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                        .lineLimit(1)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(DeepLink.url(alias: alias.wrappedValue), forType: .string)
                    }
                    .controlSize(.small)
                }
            }
            TextField("Title", text: model.site(\.title, default: ""))
            TextField("Start URL", text: model.site(\.startURL, default: ""))
                .font(.system(.body, design: .monospaced))
            Picker("Links to other sites", selection: model.site(\.externalLinks, default: .defaultBrowser)) {
                Text("Open in the default browser").tag(ExternalLinkPolicy.defaultBrowser)
                Text("Open in lowkey").tag(ExternalLinkPolicy.lowkey)
            }
            SettingsRow("Proxy") {
                Picker("", selection: proxyName) {
                    Text("None").tag("")
                    ForEach(model.draft.proxies) { proxy in Text(proxy.name).tag(proxy.name) }
                }
                .labelsHidden()
            }
            Group {
                if !SiteStoreFactory.supportsProxy {
                    Text("SOCKS proxies need a newer macOS; a site with a proxy opens without it.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Text("Addresses that count as this site, separated by commas. The start URL’s origin always counts. Sign-in pages (Google, Apple, Microsoft…) open in a separate window and return here.")
                    .font(.caption).foregroundColor(.secondary)
                Text("Named proxies and always-proxied hosts are set in config.json (“proxies”, “proxyDomains”). A proxy applies to site windows opened after saving.")
                    .font(.caption).foregroundColor(.secondary)
            }
            SettingsRow("Own origins") {
                TextField("", text: $originsText, onCommit: saveOrigins)
                    .font(.system(.body, design: .monospaced))
            }
            if !model.problems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.problems, id: \.self) { problem in
                        HStack(spacing: 4) {
                            Image(nsImage: NSImage(named: NSImage.cautionName)!)
                            Text(problem)
                        }
                        .foregroundColor(.red).font(.caption)
                    }
                    Text("Changes to sites are saved when these are fixed.").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private var proxyName: Binding<String> {
        Binding(get: { model.site(\.proxy, default: nil).wrappedValue ?? "" },
                set: { model.site(\.proxy, default: nil).wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func loadOrigins() {
        originsText = model.site(\.extraOrigins, default: []).wrappedValue.joined(separator: ", ")
    }

    private func saveOrigins() {
        let origins = originsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        model.site(\.extraOrigins, default: []).wrappedValue = origins
    }
}

struct AppearancePane: View {
    @ObservedObject var model: SettingsModel
    @State private var showMoreColors = false

    private static let coreRoles: [(ThemeColorRole, String)] = [
        (.panel, "Panel"),
        (.accent, "Accent"),
        (.ink, "Text"),
    ]

    private static let advancedRoles: [(ThemeColorRole, String)] = [
        (.surface, "Surface"),
        (.muted, "Muted text"),
        (.border, "Border"),
        (.selection, "Selection"),
        (.link, "Link"),
        (.success, "Success"),
        (.danger, "Danger"),
    ]

    /// Switching to Light/Dark edits that palette right away (macOS 10.15 has no `onChange`).
    private var mode: Binding<ThemeMode> {
        Binding(get: { self.model.draft.appearance.mode }, set: { mode in
            self.model.draft.appearance.mode = mode
            if mode == .light { self.model.editingDark = false }
            else if mode == .dark { self.model.editingDark = true }
        })
    }

    private func colorRow(_ role: ThemeColorRole, title: String) -> some View {
        SettingsRow(title) {
            HStack(spacing: 8) {
                if model.canResetToAuto(role) {
                    Button("Auto") { model.resetToAuto(role) }
                        .buttonStyle(BorderlessButtonStyle())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ColorWell(color: model.nsColor(for: role), accessibilityLabel: title)
            }
        }
    }

    var body: some View {
        let tokens = ThemeTokens(colors: model.colors)
        return Form {
            Section {
                Picker("Mode", selection: mode) {
                    Text("Tint").tag(ThemeMode.tint)
                    Text("Page").tag(ThemeMode.page)
                    Text("System").tag(ThemeMode.system)
                    Text("Light").tag(ThemeMode.light)
                    Text("Dark").tag(ThemeMode.dark)
                }
                .pickerStyle(SegmentedPickerStyle())
                Picker("Edit colors for", selection: $model.editingDark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                SettingsRow("Theme") {
                    HStack(spacing: 10) {
                        ThemeSwatchStrip(tokens: tokens)
                        Picker("Theme", selection: Binding(
                            get: {
                                let id = model.colors.preset
                                return ThemePreset.all.contains(where: { $0.id == id }) ? id : ThemeColors.customPresetID
                            },
                            set: { model.applyPreset($0) }
                        )) {
                            ForEach(ThemePreset.all) { preset in Text(preset.title).tag(preset.id) }
                            if model.colors.preset == ThemeColors.customPresetID {
                                Divider()
                                Text("Custom").tag(ThemeColors.customPresetID)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
                ForEach(Self.coreRoles, id: \.0) { role, title in
                    colorRow(role, title: title)
                }
                Group {
                    Toggle("More colors", isOn: $showMoreColors)
                    if showMoreColors {
                        ForEach(Self.advancedRoles, id: \.0) { role, title in
                            colorRow(role, title: title)
                        }
                    }
                }
                SettingsRow("Preview") {
                    HStack(alignment: .top, spacing: 10) {
                        StripPreview(tokens: tokens)
                        ThemePreview(tokens: tokens)
                    }
                }
                if tokens.lowAccentContrast {
                    HStack(spacing: 4) {
                        Image(nsImage: NSImage(named: NSImage.cautionName)!)
                        Text("The accent color is hard to see on this panel.")
                    }
                    .font(.caption).foregroundColor(tokens.dangerColor)
                }
                if tokens.lowInkContrast {
                    HStack(spacing: 4) {
                        Image(nsImage: NSImage(named: NSImage.cautionName)!)
                        Text("The text color has low contrast on this panel.")
                    }
                    .font(.caption).foregroundColor(tokens.dangerColor)
                }
                HStack {
                    Spacer()
                    Button("Reset to Amber", action: model.resetColors)
                        .disabled(model.isDefaultForEditingMode)
                }
                Text("Tint follows the page’s theme color or background on the window strip. Page follows each page’s light or dark background. Light and dark palettes keep their own colors; lowkey never recolors the page.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
/// Native color control (macOS 10.15): SwiftUI's `ColorPicker` needs macOS 11.
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

private struct StripPreview: View {
    let tokens: ThemeTokens

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(tokens.accentColor).frame(height: 3)
            HStack(spacing: 8) {
                Text("×")
                Spacer()
                Text("‹  ⇤  ›")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(tokens.mutedColor)
            .padding(.horizontal, 6)
            .frame(height: ChromeMetrics.stripHeight)
            .background(tokens.panelColor)
            Rectangle().fill(tokens.strokeColor).frame(height: 1)
            Rectangle().fill(Color(NSColor.textBackgroundColor)).frame(height: 55)
        }
        .frame(width: 170)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(tokens.lineColor, lineWidth: 1))
        .accessibility(hidden: true)
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: Store

    var body: some View {
        Form {
            Section(header: Text("Input history")) {
                SettingsRow("Saved entries") {
                    Spacer()
                    Text("\(store.history.entries.count) of \(InputHistory.limit)")
                }
                Text("Addresses and aliases you type in ⌘L. To forget one entry, point at it in the ⌘L list and click ×.")
                    .font(.caption).foregroundColor(.secondary)
                Button("Clear History…", action: model.clearHistory)
                    .disabled(store.history.entries.isEmpty)
            }
            Section(header: Text("Files")) {
                SettingsRow("Settings") {
                    Spacer()
                    Button(store.configURL.path) { NSWorkspace.shared.activateFileViewerSelecting([store.configURL]) }
                        .buttonStyle(PlainButtonStyle()).font(.system(.caption, design: .monospaced))
                }
                if let problem = store.problem {
                    HStack(spacing: 4) {
                        Image(nsImage: NSImage(named: NSImage.cautionName)!)
                        Text(problem)
                    }
                    .foregroundColor(.red).font(.caption)
                }
            }
        }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel
    private var themeObserver: NSObjectProtocol?

    init(app: AppController) {
        model = SettingsModel(app: app)
        let window = LowkeyWindow(contentRect: NSRect(x: 0, y: 0, width: 712, height: 586), resizable: false)
        window.title = "lowkey Settings"
        window.setContent(SettingsView(model: model, store: app.store))
        super.init(window: window)
        window.delegate = self
        window.closeButton.label = "Close · ⌘W"
        window.closeButton.glyph = .terminate
        window.closeButton.onPress = { [weak self] _ in self?.close() }
        window.setFrameAutosaveName("LowkeySettings")
        if !window.setFrameUsingName("LowkeySettings") { window.center() }
        applyTheme()
        themeObserver = NotificationCenter.default.addObserver(forName: ThemeCenter.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyTheme()
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func applyTheme() {
        window?.appearance = ThemeCenter.shared.windowAppearance
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func lowkeyCloseWindow(_ sender: Any?) { close() }
    @objc func lowkeyCloseSite(_ sender: Any?) { close() }
}
