/*
 * lowkey for Ubuntu: GTK 4 + WebKitGTK 6.0.
 *
 * Same model as the macOS app: one window per saved site, each site with its own
 * persistent profile, ordinary windows sharing a default profile, an alias/address
 * prompt, and the lowkeyctl control port. Window commands work; page automation
 * (inspect/wait/fill/select/click/upload/save-pdf) answers "unsupported on linux".
 *
 * Profiles live in ~/.local/share/lowkey; configuration in ~/.config/lowkey/config.json
 * (LOWKEY_CONFIG overrides it, like on macOS). Per-site SOCKS proxies from the config
 * use WebKitGTK's public network-proxy API.
 *
 * NOTE: written without a local build (no toolchain in the authoring environment);
 * first build on Ubuntu is expected to surface small API/typing fixes.
 */

import CGTK
import Foundation
import LowkeyCore

// Swift cannot pass closures as C function pointers: every trampoline is a global
// function whose user data is an Unmanaged box of the value it needs.
private final class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}

private func box<T>(_ value: T) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(Box(value)).toOpaque()
}

private func unbox<T>(_ pointer: UnsafeMutableRawPointer) -> T {
    Unmanaged<Box<T>>.fromOpaque(pointer).takeRetainedValue().value
}

/// Runs `body` on the GTK main thread and waits for the result, mirroring the
/// macOS ControlPort contract: the IPC queue blocks, GTK keeps running.
private final class MainWork {
    let body: () -> String
    private let condition = NSCondition()
    private var result: String?
    private var finished = false

    init(_ body: @escaping () -> String) { self.body = body }

    func run() {
        let value = body()
        condition.lock()
        result = value
        finished = true
        condition.signal()
        condition.unlock()
    }

    func wait(deadline: Date) -> String? {
        condition.lock()
        while !finished, Date() < deadline {
            condition.wait(until: deadline)
        }
        condition.unlock()
        return result
    }
}

private func idleTrampoline(_ pointer: UnsafeMutableRawPointer?) -> Int32 {
    guard let pointer = pointer else { return 0 }
    let work: MainWork = unbox(pointer)
    work.run()
    return 0 // G_SOURCE_REMOVE
}

final class LinuxApp {
    private struct WindowEntry {
        let window: UnsafeMutablePointer<GtkWidget>
        let webView: UnsafeMutablePointer<WebKitWebView>
        let site: Site?
    }

    private let gtkApp: UnsafeMutablePointer<GtkApplication>
    private let stateURL: URL
    private let historyURL: URL
    private let profilesRoot: URL
    private var config: Config
    private var history: InputHistory

    /// Saved-site windows by profile UUID.
    private var windows: [UUID: WindowEntry] = [:]
    private var ordinary: [WindowEntry] = []
    private var controlPort: MessagePortServer?

    static func main() {
        LinuxApp().run()
    }

    init() {
        gtkApp = cgtk_application_new("io.bobuk.lowkey")

        // Same layout as the macOS Store: LOWKEY_CONFIG moves config and history aside.
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dataHome = environment["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/share")
        profilesRoot = dataHome.appendingPathComponent("lowkey")
        if let path = environment["LOWKEY_CONFIG"], !path.isEmpty {
            stateURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            historyURL = URL(fileURLWithPath: stateURL.path + ".history.json")
        } else {
            stateURL = home.appendingPathComponent(".config/lowkey/config.json")
            historyURL = profilesRoot.appendingPathComponent("history.json")
        }

        do {
            config = try Config.load(from: stateURL)
        } catch {
            config = Config()
            LogError("can’t read \(stateURL.path): \(error.localizedDescription)")
        }
        history = InputHistory.load(from: historyURL)

        writePidFile()
        openControlPort()

        cgtk_application_on_activate(gtkApp, { instance, userdata in
            let app: LinuxApp = unbox(userdata)
            app.showPrompt()
        }, box(self))
        cgtk_application_on_shutdown(gtkApp, { instance, userdata in
            let app: LinuxApp = unbox(userdata)
            app.shutdown()
        }, box(self))
    }

    // MARK: - Lifetime

    private var pidFile: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("io.bobuk.lowkey.pid")
    }

    private func writePidFile() {
        try? String(getpid()).write(to: pidFile, atomically: true, encoding: .utf8)
    }

    private func shutdown() {
        try? FileManager.default.removeItem(at: pidFile)
    }

    func run() {
        let argc = Int32(CommandLine.argc)
        var argv = CommandLine.unsafeArgv
        _ = cgtk_application_run(gtkApp, argc, &argv)
    }

    // MARK: - Prompt

    func showPrompt() {
        cgtk_prompt(nil, "lowkey", nil, { text, userdata in
            let app: LinuxApp = unbox(userdata)
            guard let text = text else { return }
            app.submit(text)
        }, box(self))
    }

    /// Mirrors AppController.submit: an alias opens the site window; an address opens
    /// an ordinary window. ⌘L-style replacement of the current page is not needed here
    /// (the prompt is not attached to a window's profile).
    func submit(_ text: String) {
        switch AddressResolver.resolve(text, sites: config.sites) {
        case .site(let site):
            record(site.alias)
            openSite(site)
        case .url(let url):
            record(url.absoluteString)
            openOrdinary(url)
        case .invalid:
            showPrompt()
        }
    }

    private func record(_ text: String) {
        history.record(text)
        do { try history.save(to: historyURL) }
        catch { LogError("can’t save history: \(error.localizedDescription)") }
    }

    // MARK: - Windows

    @discardableResult
    private func openSite(_ site: Site) -> WindowEntry? {
        if let existing = windows[site.id] {
            cgtk_window_present(existing.window)
            return existing
        }
        guard let url = site.url else { return nil }
        let entry = makeWindow(site: site, url: url)
        windows[site.id] = entry
        return entry
    }

    private func openOrdinary(_ url: URL) {
        ordinary.append(makeWindow(site: nil, url: url))
    }

    private func makeWindow(site: Site?, url: URL) -> WindowEntry {
        let window = cgtk_window_new(gtkApp, site?.displayTitle ?? "lowkey")
        let dataDir: URL
        let socks5: String?
        if let site = site {
            dataDir = profilesRoot.appendingPathComponent("profiles/\(site.id.uuidString)")
            socks5 = config.proxy(for: site).map { "\($0.host):\($0.port)" }
        } else {
            dataDir = profilesRoot.appendingPathComponent("default")
            socks5 = nil
        }
        let socks5Pointer = socks5.flatMap { strdup($0) }
        let webView = cgtk_webview_new_in_window(window, dataDir.path, socks5Pointer)
        if let socks5Pointer = socks5Pointer { free(socks5Pointer) }

        let entry = WindowEntry(window: window, webView: webView, site: site)
        // The close-request handler receives the window as the first argument,
        // so no user data is needed; the destroy notification carries the app.
        cgtk_window_on_close_request(window, { instance, userdata in
            let app: LinuxApp = unbox(userdata)
            app.noteClosed(UnsafeMutablePointer<GtkWidget>(instance))
            return 0 // allow the close
        }, box(self))
        cgtk_webview_load(webView, url.absoluteString)
        cgtk_window_present(window)
        return entry
    }

    private func noteClosed(_ window: UnsafeMutablePointer<GtkWidget>) {
        if let (id, _) = windows.first(where: { $0.value.window == window }) {
            windows.removeValue(forKey: id)
        }
        ordinary.removeAll { $0.window == window }
    }

    // MARK: - Control port

    private func openControlPort() {
        let name = ControlRequest.portName(pid: getpid())
        let handler: MessagePortServer.Handler = { [weak self] _, payload in
            guard let self = self,
                  let request = ControlRequest(payload: payload) else { return Data("invalid".utf8) }
            let deadline = Date().addingTimeInterval(request.command.isPDFExport ? 60 : 4)
            let work = MainWork { self.handle(request) }
            let pointer = box(work)
            cgtk_invoke_on_main(idleTrampoline, pointer)
            return work.wait(deadline: deadline) ?? "result unknown"
        }
        controlPort = MessagePortServer(name: name, queueLabel: "io.bobuk.lowkey.control", handler: handler)
        if controlPort == nil {
            LogError("control port name is taken; another copy of lowkey is running")
        }
    }

    /// Runs on the GTK main thread (dispatched through MainWork).
    private func handle(_ request: ControlRequest) -> String {
        guard let site = config.site(alias: request.alias) else { return "unknown site" }
        switch request.command {
        case .window(let command):
            return performWindowCommand(command, on: site)
        case .page(.status, let params):
            return status(of: site, json: params == ["--json"])
        case .page, .click, .upload:
            return "unsupported on linux"
        }
    }

    private func performWindowCommand(_ command: SiteCommand, on site: Site) -> String {
        switch command {
        case .open, .toggle, .rewind:
            if command == .toggle, let entry = windows[site.id], cgtk_window_visible(entry.window) == 1 {
                cgtk_window_hide(entry.window)
                return "ok"
            }
            guard let entry = openSite(site) else { return "cannot open site" }
            if command == .rewind, let url = site.url { cgtk_webview_load(entry.webView, url.absoluteString) }
            cgtk_window_present(entry.window)
            return "focus"
        case .hide:
            if let entry = windows[site.id] { cgtk_window_hide(entry.window) }
            return "ok"
        case .close:
            if let entry = windows[site.id] {
                cgtk_window_destroy(entry.window)
                windows.removeValue(forKey: site.id)
            }
            return "ok"
        case .reload:
            windows[site.id].map { cgtk_webview_reload($0.webView) }
            return "ok"
        case .back:
            windows[site.id].map { cgtk_webview_back($0.webView) }
            return "ok"
        case .forward:
            windows[site.id].map { cgtk_webview_forward($0.webView) }
            return "ok"
        case .start:
            guard let url = site.url else { return "cannot open site" }
            windows[site.id].map { cgtk_webview_load($0.webView, url.absoluteString) }
            return "ok"
        }
    }

    /// `lowkeyctl HA status` without raising the window.
    private func status(of site: Site, json: Bool) -> String {
        guard let entry = windows[site.id] else {
            return WindowStatus(alias: site.alias).output(json: json)
        }
        return WindowStatus(
            alias: site.alias,
            open: true,
            visible: cgtk_window_visible(entry.window) == 1,
            minimized: false, // iconification is not surfaced separately on this port
            focused: cgtk_window_active(entry.window) == 1,
            loading: cgtk_webview_loading(entry.webView) == 1
        ).output(json: json)
    }
}

// Linux has no OSLog; stderr keeps messages visible from a terminal or journal.
func LogError(_ message: String) {
    FileHandle.standardError.write(Data("lowkey: \(message)\n".utf8))
}

LinuxApp.main()
