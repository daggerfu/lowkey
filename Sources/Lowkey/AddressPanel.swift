import AppKit
import SwiftUI
import LowkeyCore
import BobukCore
import BobukUI

/// The ⌘L prompt: an alias or an address, with suggestions from saved sites and input history.
final class AddressPanel: BobukPanel, NSTextFieldDelegate, PageThemeProviding {
    private unowned let app: AppController
    private weak var target: WebWindowController?
    private var newWindow = false
    private var inCurrentProfile = false
    private var suggestions: [Suggestion] = []
    /// nil until the user picks a row with the arrow keys or the mouse.
    private var selected: Int?

    private let background = PickerSurfaceView(palette: ThemeCenter.shared.tokens.pickerPalette())
    private let accent = NSView()
    private let infoRow = NSStackView()
    private let infoGlyph = GlyphView(glyph: .lock)
    private let infoLabel = NSTextField(labelWithString: "")
    private let arrow = NSTextField(labelWithString: "→")
    private let field = NSTextField()
    private let list = NSStackView()
    private let footer = NSHostingView(rootView: ShortcutFooter([], palette: ThemeCenter.shared.tokens.pickerPalette()))
    private let infoSeparator = Separator()
    private let listSeparator = Separator()
    private let footerSeparator = Separator()
    /// Palette colors only: light or dark by the target's page, never its Tint color as panel.
    var pageTheme: PageTheme { target?.chrome.pageTheme ?? PageTheme() }
    private var themeTokens: ThemeTokens { ThemeCenter.shared.tokens(page: pageTheme) }

    static let width: CGFloat = 560

    init(app: AppController) {
        self.app = app
        // A prompt: floating, activating, on the active Space; it closes on focus loss, on app
        // deactivation, with Esc and with ⌘W (all by ordering out).
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120), kind: .prompt)
        onCommandKey = { [weak self] _, command in
            guard command == .text(#selector(NSText.copy(_:))) else { return false }
            return self?.copyPageAddress() ?? false
        }
        build()
        // Both are posted on the main thread.
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange),
                                               name: ThemeCenter.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange),
                                               name: LowkeyWindow.pageThemeDidChange, object: nil)
    }

    @objc private func themeDidChange() { applyTheme() }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        infoGlyph.translatesAutoresizingMaskIntoConstraints = false
        infoGlyph.widthAnchor.constraint(equalToConstant: 10).isActive = true
        infoGlyph.heightAnchor.constraint(equalToConstant: 10).isActive = true
        infoLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        infoLabel.lineBreakMode = .byTruncatingMiddle
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        infoRow.orientation = .horizontal
        infoRow.spacing = 7
        infoRow.edgeInsets = NSEdgeInsets(top: 9, left: 16, bottom: 9, right: 16)
        infoRow.addArrangedSubview(infoGlyph)
        infoRow.addArrangedSubview(infoLabel)

        arrow.font = .systemFont(ofSize: 17)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18)
        field.placeholderString = "Alias or address"
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel("Alias or address")
        let input = NSStackView(views: [arrow, field])
        input.orientation = .horizontal
        input.spacing = 10
        input.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        list.orientation = .vertical
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        let footerRow = NSStackView(views: [footer])
        footerRow.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 9, right: 16)

        for view in [accent, infoRow, infoSeparator, input, listSeparator, list, footerSeparator, footerRow] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        accent.heightAnchor.constraint(equalToConstant: PickerMetrics.accentHeight).isActive = true

        background.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            background.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        contentView = background
    }

    // MARK: Showing

    func show(target: WebWindowController?, newWindow: Bool, prefill: String?, message: String?,
              inCurrentProfile: Bool = false) {
        configure(target: target, newWindow: newWindow, prefill: prefill, message: message,
                  inCurrentProfile: inCurrentProfile)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// Populate and measure without activating the window; showing owns focus separately.
    func configure(target: WebWindowController?, newWindow: Bool, prefill: String?, message: String?,
                   inCurrentProfile: Bool = false) {
        self.target = target
        self.newWindow = newWindow
        self.inCurrentProfile = inCurrentProfile
        field.placeholderString = inCurrentProfile ? "Address in this profile" : "Alias or address"
        field.setAccessibilityLabel(inCurrentProfile ? "Address in this profile" : "Alias or address")
        field.stringValue = prefill ?? ""
        selected = nil
        setInfo(message: message)
        applyTheme()
        refresh()
        position()
    }

    /// The info row shows an error message, which keeps its own color on theme changes.
    private var infoShowsError = false

    private func setInfo(message: String?) {
        infoShowsError = message != nil
        if let message = message {
            infoGlyph.isHidden = true
            infoLabel.stringValue = message
            infoLabel.font = .systemFont(ofSize: 11.5)
            infoLabel.textColor = themeTokens.dangerNSColor
            infoRow.isHidden = false
        } else if let url = target?.webView.url, url.scheme != "about" {
            infoGlyph.isHidden = url.scheme != "https"
            infoLabel.stringValue = url.absoluteString
            infoLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            infoLabel.textColor = NSColor(themeTokens.muted)
            infoRow.isHidden = false
        } else {
            infoRow.isHidden = true
        }
        infoSeparator.isHidden = infoRow.isHidden
    }

    /// 56 points below the top of the target window, else in the upper part of the main screen.
    private func position() {
        layoutIfNeededForSize()
        let size = frame.size
        if let parent = target?.window, parent.isVisible, !parent.isMiniaturized {
            setFrameOrigin(PanelPlacement.over(parent: parent.frame, size: size, inset: 56).origin)
        } else if let screen = NSScreen.main {
            let frame = PanelPlacement.frame(size: size, in: screen.visibleFrame,
                                             anchor: .upper(fraction: 0.28, minimum: 0), margin: 0)
            setFrameOrigin(frame.origin)
        }
    }

    /// Fits the window to its content, keeping the top edge in place.
    private func layoutIfNeededForSize() {
        fitHeight(to: background, width: Self.width)
    }

    /// ⌘C with nothing selected copies the current page address.
    private func copyPageAddress() -> Bool {
        guard let editor = field.currentEditor(), editor.selectedRange.length == 0,
              let url = target?.webView.url, url.scheme != "about" else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        setInfo(message: nil)
        infoLabel.stringValue = "Copied: \(url.absoluteString)"
        return true
    }

    // MARK: Suggestions

    private func refresh() {
        suggestions = Suggestions.make(query: field.stringValue, sites: app.store.config.sites, history: app.store.history)
        if let index = selected, index >= suggestions.count { selected = suggestions.isEmpty ? nil : suggestions.count - 1 }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let badgeWidth = PickerMetrics.badgeWidth(for: suggestions.compactMap {
            if case .site(let site) = $0 { return site.alias.uppercased() }
            return nil
        })
        for (index, suggestion) in suggestions.enumerated() {
            let row = NSHostingView(rootView: SuggestionRow(suggestion: suggestion, selected: index == selected,
                badgeWidth: badgeWidth, palette: themeTokens.pickerPalette(),
                onChoose: { [weak self] in self?.submit(text: suggestion.text) },
                onRemove: { [weak self] in
                    self?.app.store.removeHistory(suggestion.text)
                    self?.refresh()
                }))
            row.translatesAutoresizingMaskIntoConstraints = false
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -12).isActive = true
            row.heightAnchor.constraint(equalToConstant: PickerMetrics.rowHeight).isActive = true
        }
        list.isHidden = suggestions.isEmpty
        listSeparator.isHidden = suggestions.isEmpty
        let browser = self.target as? BrowserWindowController
        let target = newWindow || browser?.kind != .ordinary ? "new window" : "this window"
        var hints: [ShortcutHint] = [.init("↩", inCurrentProfile ? "open in this profile" : "open (address: \(target))")]
        if !inCurrentProfile { hints.append(.init("⌘↩", "new window")) }
        hints += [.init("↑↓", "choose"), .init("⌘C", "copy URL"), .init("esc", "close")]
        footer.rootView = ShortcutFooter(hints, palette: themeTokens.pickerPalette(), onSettings: { [weak self] in
            self?.orderOut(nil)
            self?.app.showSettings()
        })
        if isVisible { layoutIfNeededForSize() }
    }

    func controlTextDidChange(_ obj: Notification) {
        selected = nil
        setInfo(message: nil)
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            guard !suggestions.isEmpty else { return true }
            selected = PickerSelection.move(selected, by: 1, count: suggestions.count, allowsEmpty: true)
            refresh()
            return true
        case #selector(NSResponder.moveUp(_:)):
            selected = PickerSelection.move(selected, by: -1, count: suggestions.count, allowsEmpty: true)
            refresh()
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            if let index = selected, suggestions.indices.contains(index) {
                submit(text: suggestions[index].text)
            } else {
                submitTyped()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            orderOut(nil)
            return true
        default:
            return false
        }
    }

    /// Typed text that is neither an alias nor an address falls back to the first suggestion.
    private func submitTyped() {
        let text = field.stringValue
        if case .invalid = AddressResolver.resolve(text, sites: app.store.config.sites), let first = suggestions.first {
            submit(text: first.text)
        } else {
            submit(text: text)
        }
    }

    private func submit(text: String) {
        let commandHeld = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        let target = self.target
        if let error = app.submit(text, target: target, newWindow: newWindow || commandHeld,
                                  inCurrentProfile: inCurrentProfile) {
            setInfo(message: error)
            layoutIfNeededForSize()
            NSSound.beep()
            return
        }
        orderOut(nil)
    }

    // MARK: Theme

    private func applyTheme() {
        let tokens = themeTokens
        appearance = ThemeCenter.shared.chromeAppearance(page: pageTheme)
        background.palette = tokens.pickerPalette()
        arrow.textColor = NSColor(tokens.accent)
        field.textColor = NSColor(tokens.ink)
        if !infoShowsError { infoLabel.textColor = NSColor(tokens.muted) }
        for separator in [infoSeparator, listSeparator, footerSeparator] { separator.needsDisplay = true }
        infoGlyph.color = NSColor(tokens.muted)
        if isVisible { refresh() }
    }
}

private final class Separator: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(lowkeyTokens.stroke).setFill()
        bounds.fill()
    }
}
