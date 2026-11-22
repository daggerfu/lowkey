import AppKit
import os
import BobukCore
import LowkeyCore

/// lowkey's unified log (subsystem: the bundle identifier).
enum Log {
    static let app = BobukLog.logger("app")

    /// OSLog's Swift `.error` method needs macOS 11; `os_log` works since 10.12.
    static func error(_ message: String) {
        #if canImport(Darwin)
        os_log("%{public}@", log: app, type: .error, message)
        #else
        app.error(message)
        #endif
    }
}

/// Library entry point for the thin `Lowkey` executable (SwiftPM 5.3 cannot test
/// an executable target directly, so the app code lives in this library target).
public enum LowkeyLib {
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var controller: AppController!
    private var controlPort: ControlPort?
    private var localEventMonitor: Any?
    private var beforeActivation: ToggleWindowOrder?

    func applicationWillFinishLaunching(_ notification: Notification) {
        controller = AppController()
        controlPort = ControlPort(controller: controller)
        if controlPort == nil { Log.error("local control port unavailable") }
        NSApp.mainMenu = makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            if event.type == .flagsChanged {
                self?.controller.setCommandHeld(event.modifierFlags.contains(.command))
            } else {
                self?.beforeActivation = nil
            }
            return event
        }
        #if DEBUG
        // Development builds: LOWKEY_DEBUG_OPEN=settings opens Settings for visual checks.
        if ProcessInfo.processInfo.environment["LOWKEY_DEBUG_OPEN"] == "settings" {
            controller.showSettings()
        }
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let snapshot = ToggleWindowOrder.recentActivation(beforeActivation)
            beforeActivation = nil
            controller.handle(url: url, beforeActivation: snapshot)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        controller.allBrowsers.forEach { $0.savePlacement() }
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        beforeActivation = ToggleWindowOrder()
    }

    func applicationDidResignActive(_ notification: Notification) {
        beforeActivation = nil
        controller.setCommandHeld(false)
    }

    /// A Dock click opens the address prompt even when a site window is visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        controller.showPromptFromDock()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Actions

    @objc func showSettings(_ sender: Any?) { controller.showSettings() }
    @objc func openLocation(_ sender: Any?) { controller.showPrompt(target: controller.currentBrowser, newWindow: false) }
    @objc func newWindow(_ sender: Any?) { controller.showPrompt(target: controller.currentBrowser, newWindow: true) }
    @objc func openInProfile(_ sender: Any?) {
        controller.showPrompt(target: controller.currentWebWindow, newWindow: false, inCurrentProfile: true)
    }

    /// Fallback for windows without their own handler (About panel and others).
    @objc func lowkeyCloseWindow(_ sender: Any?) { NSApp.keyWindow?.performClose(sender) }
    @objc func lowkeyCloseSite(_ sender: Any?) { NSApp.keyWindow?.performClose(sender) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(openInProfile(_:)):
            return controller.currentWebWindow != nil
        case #selector(lowkeyCloseWindow(_:)):
            item.title = "Close Window"
            return NSApp.keyWindow != nil
        case #selector(lowkeyCloseSite(_:)):
            item.title = "Close Site"
            return false
        default:
            return true
        }
    }

    // MARK: Menu

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = submenu(in: main, title: "lowkey")
        app.addItem(withTitle: "About lowkey", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(showSettings(_:)), ",", target: self))
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        app.addItem(services)
        app.addItem(.separator())
        app.addItem(item("Hide lowkey", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        app.addItem(.separator())
        app.addItem(item("Quit lowkey", #selector(NSApplication.terminate(_:)), "q"))

        let file = submenu(in: main, title: "File")
        file.addItem(item("New Window…", #selector(newWindow(_:)), "n", target: self))
        file.addItem(item("Open Location…", #selector(openLocation(_:)), "l", target: self))
        file.addItem(item("Open Location in This Profile…", #selector(openInProfile(_:)), "l", [.command, .shift], target: self))
        file.addItem(.separator())
        file.addItem(item("Hide Window", #selector(LowkeyActions.lowkeyCloseWindow(_:)), "w"))
        file.addItem(item("Close Site", #selector(LowkeyActions.lowkeyCloseSite(_:)), "w", [.command, .shift]))

        let edit = submenu(in: main, title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        edit.addItem(item("Delete", #selector(NSText.delete(_:)), ""))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))

        let view = submenu(in: main, title: "View")
        view.addItem(item("Reload Page", #selector(LowkeyActions.lowkeyReload(_:)), "r"))
        view.addItem(item("Save as PDF…", #selector(LowkeyActions.lowkeySavePDF(_:)), "s", [.command, .shift]))
        view.addItem(.separator())
        view.addItem(item("Back", #selector(LowkeyActions.lowkeyBack(_:)), "["))
        view.addItem(item("Forward", #selector(LowkeyActions.lowkeyForward(_:)), "]"))
        view.addItem(item("Start Page", #selector(LowkeyActions.lowkeyStart(_:)), "h", [.command, .shift]))
        view.addItem(.separator())
        view.addItem(item("Actual Size", #selector(LowkeyActions.lowkeyActualSize(_:)), "0"))
        view.addItem(item("Zoom In", #selector(LowkeyActions.lowkeyZoomIn(_:)), "="))
        view.addItem(item("Zoom Out", #selector(LowkeyActions.lowkeyZoomOut(_:)), "-"))
        view.addItem(.separator())
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))

        let window = submenu(in: main, title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), ""))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""))
        NSApp.windowsMenu = window

        return main
    }

    private func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String,
                      _ modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
