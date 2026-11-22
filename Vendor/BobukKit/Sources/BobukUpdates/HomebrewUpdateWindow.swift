#if canImport(AppKit)
// The progress window of a Homebrew update: the command, the live output of brew and the result.
// A `ChromeWindow` in the app's palette, from Ting and Splash Finish.
import AppKit
import BobukCore
import BobukUI
import SwiftUI
import Combine

public final class HomebrewUpdateModel: ObservableObject {
    public enum Phase: Equatable {
        case running
        case finished(HomebrewUpdateOutcome)
    }

    public let appName: String
    @Published public var command: String = ""
    @Published public var output: String = ""
    @Published public var phase: Phase = .running
    /// True after a success, while the app quits so that the helper starts the new copy.
    @Published public var restarting: Bool = false
    @Published public var title: String = ""

    public init(appName: String) {
        self.appName = appName
        updateTitle()
    }

    private func updateTitle() {
        switch phase {
        case .running:
            title = "Updating \(appName) via Homebrew…"
        case .finished(let outcome):
            switch outcome {
            case .upgraded:
                title = restarting ? "\(appName) was updated. Restarting…" : "\(appName) was updated."
            case .upToDate:
                title = "\(appName) is already up to date."
            case .failed(let code, _):
                title = "The update failed (brew exit code \(code))."
            case .cancelled:
                title = "The update was cancelled."
            }
        }
    }

    public var succeeded: Bool {
        switch phase {
        case .finished(let outcome):
            switch outcome {
            case .upgraded, .upToDate: return true
            default: return false
            }
        case .running:
            return false
        }
    }

    /// Shows the result. A failure or cancel shows the text it carries: the whole brew output, or
    /// the reason why the run could not start when there is no log at all.
    public func finish(_ outcome: HomebrewUpdateOutcome, log: String?) {
        switch outcome {
        case .failed(_, let text), .cancelled(let text):
            if text.isEmpty {
                output = log ?? output
            } else {
                output = text
            }
        case .upgraded, .upToDate:
            output = log ?? output
        }
        phase = .finished(outcome)
        updateTitle()
    }

    public func setRestarting(_ value: Bool) {
        restarting = value
        updateTitle()
    }
}

public final class HomebrewUpdateWindowController: NSObject, NSWindowDelegate, ObservableObject {
    private static var controllers: [String: HomebrewUpdateWindowController] = [:]

    /// One controller per app in a process.
    public static func shared(for app: AppUpdateIdentity, palette: PickerPalette = .system,
                              theme: ThemeStore? = nil) -> HomebrewUpdateWindowController {
        if let existing = controllers[app.bundleIdentifier] { return existing }
        let controller = HomebrewUpdateWindowController(app: app, palette: palette, theme: theme)
        controllers[app.bundleIdentifier] = controller
        return controller
    }

    public let app: AppUpdateIdentity
    public let model: HomebrewUpdateModel
    private let palette: PickerPalette
    private let theme: ThemeStore?
    private var window: ChromeWindow?
    private var runner: HomebrewUpdateRunner?
    private var role: HomebrewUpdateRole = .owner
    /// Replaced by tests; quits the app so the helper can start the installed copy.
    public var terminate: () -> Void = { NSApp.terminate(nil) }

    public init(app: AppUpdateIdentity, palette: PickerPalette = .system, theme: ThemeStore? = nil) {
        self.app = app
        self.palette = palette
        self.theme = theme
        model = HomebrewUpdateModel(appName: app.displayName)
    }

    @Published public var isRunning: Bool = false

    /// Starts the update, or brings the running one to the front: a second start is refused.
    public func start(_ install: HomebrewInstall) {
        // A run in progress, or a success while the app quits to restart: show it, start nothing.
        if model.restarting || runner?.isRunning == true { show(); return }
        let runner = HomebrewUpdateRunner(app: app, install: install)
        self.runner = runner
        role = .owner
        model.command = HomebrewUpdate.commandLine(for: install)
        model.output = ""
        model.phase = .running
        model.setRestarting(false)
        isRunning = true
        show()
        runner.start(onOutput: { [weak self] output in
            self?.model.output = output
        }, onFinish: { [weak self] outcome in
            self?.finish(outcome)
        })
    }

    /// Shows a run that the helper started this process for. The role comes from the argument the
    /// helper used, never from the timing of the status file: `.viewer` is the recovery window
    /// (a copy of the app in the run folder) while the installed app is gone, `.final` the
    /// installed app started after brew.
    public func showRun(_ directory: URL, role: HomebrewUpdateRole) {
        if runner?.isRunning == true { show(); return }
        self.role = role
        let cmdPath = directory.appendingPathComponent("command")
        if let cmd = try? String(contentsOf: cmdPath, encoding: .utf8) {
            model.command = cmd
        } else {
            model.command = HomebrewUpdate.arguments(for: app.cask).joined(separator: " ")
        }
        model.output = HomebrewUpdateRunner.output(in: directory)
        model.phase = .running
        model.setRestarting(false)
        let runner = HomebrewUpdateRunner(app: app, install: nil)
        self.runner = runner
        isRunning = true
        show()
        runner.watch(directory, onOutput: { [weak self] output in
            self?.model.output = output
        }, onFinish: { [weak self] outcome in
            self?.finish(outcome)
        })
    }

    private func finish(_ outcome: HomebrewUpdateOutcome) {
        let logText: String?
        if let dir = runner?.directory {
            logText = HomebrewUpdateRunner.output(in: dir)
        } else {
            logText = nil
        }
        model.finish(outcome, log: logText)
        isRunning = false
        // The viewer exists only to show this result: bring its window back if it was closed.
        if role == .viewer { show() }
        let shouldQuit: Bool
        if let r = runner {
            shouldQuit = r.conclude(outcome, role: role)
        } else {
            shouldQuit = false
        }
        if shouldQuit {
            // Quit so that the helper starts the installed app, which shows this result again.
            model.setRestarting(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.terminate()
            }
        }
    }

    private func cancel() {
        if let r = runner {
            r.cancel()
        }
    }

    private func show() {
        let window: ChromeWindow
        if let w = self.window {
            window = w
        } else {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        // Closing the window does not stop brew; the menu action shows it again. The recovery
        // viewer is nothing but this window: closing it after the result quits it, and the helper
        // then starts the installed app again.
        window = nil
        if role == .viewer, runner?.isRunning != true { terminate() }
    }

    private func makeWindow() -> ChromeWindow {
        let initialStyle = theme?.chromeStyle ?? palette.chromeStyle
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                                  style: initialStyle, showsTitle: true)
        if let theme = theme { window.bindTheme(theme) }
        window.title = "Update \(app.displayName) via Homebrew"
        window.minSize = NSSize(width: 520, height: 340)
        window.delegate = self
        window.setContent(HomebrewUpdateView(model: model, notice: app.keptNotice, palette: palette, theme: theme,
                                             cancel: { [weak self] in self?.cancel() },
                                             close: { [weak window] in window?.performClose(nil) }))
        self.window = window
        return window
    }
}

private struct HomebrewUpdateView: View {
    @ObservedObject var model: HomebrewUpdateModel
    let notice: String
    let palette: PickerPalette
    let theme: ThemeStore?
    let cancel: () -> Void
    let close: () -> Void

    private var activePalette: PickerPalette {
        if let t = theme {
            return t.pickerPalette
        }
        return palette
    }

    var body: AnyView {
        // `.accentColor` needs macOS 11; Catalina keeps the default accent.
        let view = root
        if #available(macOS 11, *) {
            return AnyView(view.accentColor(Color(current.accent)))
        }
        return AnyView(view)
    }

    private var current: PickerPalette { activePalette }

    private var root: some View {
        let current = activePalette
        let logBackground: Color = {
            if let t = theme { return t.tokens.fieldColor }
            return Color(NSColor.textBackgroundColor)
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if model.phase == .running || model.restarting {
                    Text("…")
                }
                let titleColor: NSColor = {
                    switch model.phase {
                    case .running:
                        return current.text
                    case .finished:
                        if model.succeeded {
                            return current.text
                        }
                        return current.accent
                    }
                }()
                Text(model.title).font(.headline)
                    .foregroundColor(Color(titleColor))
            }
            Text(model.command)
                .font(.system(size: 11, design: .monospaced))
                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(current.text).opacity(0.07)))
            ScrollView {
                let outText = model.output.isEmpty ? "Waiting for brew…" : model.output
                let outColor: NSColor = model.output.isEmpty ? current.secondary : current.text
                Text(outText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(outColor))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            .background(RoundedRectangle(cornerRadius: 4).fill(logBackground))
            HStack {
                Text("Only \(model.appName) is updated. \(notice)")
                    .font(.caption).foregroundColor(Color(current.secondary))
                Spacer()
                if model.phase == .running {
                    Button("Cancel", action: cancel)
                } else if !model.restarting {
                    Button("Close", action: close)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 300)
        .foregroundColor(Color(current.text))
        .background(Color(current.surface))
    }
}

/// The recovery viewer: the copy of the app in the run folder, started by the helper with
/// `--homebrew-update-viewer <run folder>` while the installed app is gone. It runs only this
/// window: no menu-bar icon, no hotkey, no configuration, no Sparkle.
public enum HomebrewUpdateViewer {
    public static func run(_ directory: URL, app: AppUpdateIdentity, palette: PickerPalette = .system,
                           theme: ThemeStore? = nil) -> Never {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        theme?.apply()
        HomebrewUpdateWindowController.shared(for: app, palette: palette, theme: theme).showRun(directory, role: .viewer)
        application.run()
        exit(0)
    }
}
#endif
