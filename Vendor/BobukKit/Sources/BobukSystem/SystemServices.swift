#if canImport(ServiceManagement)
// Small system services every menu-bar app needs: launch at login, the Accessibility permission
// and making an accessory app frontmost. Use these instead of calling the frameworks directly.
import AppKit
import ApplicationServices
import ServiceManagement

public enum LoginItemError: LocalizedError, Equatable {
    /// The app has not supplied the bundle identifier of its login helper.
    case notConfigured
    /// `SMLoginItemSetEnabled` refused the change (helper missing, or the app is not signed).
    case refused

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Launch at login is not configured for this app."
        case .refused:
            return "macOS refused to change the login item. Check the helper app in Contents/Library/LoginItems."
        }
    }
}

public enum LoginItem {
    /// State of the login helper. macOS 10.15 applies changes immediately, so there is no
    /// approval step; `.requiresApproval` and `.unsupported` remain only for source compatibility.
    public enum Status: Equatable {
        case notRegistered
        case enabled
        case requiresApproval
        case unsupported
    }

    /// Apps call once at startup with the bundle identifier of the helper app in
    /// `Contents/Library/LoginItems`. Kit code never hard-codes an app's identifier.
    public static func configure(helperBundleID: String) {
        self.helperBundleID = helperBundleID
    }

    private static var helperBundleID: String?
    private static var defaultsKey: String? {
        guard let helperBundleID = helperBundleID else { return nil }
        return "BobukKit.LoginItem.\(helperBundleID)"
    }

    public static var status: Status {
        guard let helperBundleID = helperBundleID else { return .notRegistered }
        if let key = defaultsKey, UserDefaults.standard.bool(forKey: key) { return .enabled }
        // launchd starts the helper at login, so a running helper is an enabled item too.
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == helperBundleID }) {
            return .enabled
        }
        return .notRegistered
    }

    public static var isEnabled: Bool { status == .enabled }

    /// macOS 10.15 has no approval step; kept for callers written against newer SDKs.
    public static var needsApproval: Bool { false }

    /// Registers or unregisters the helper. `openSettingsIfNeeded` is accepted for source
    /// compatibility and does nothing: 10.15 applies the change without opening settings.
    public static func set(_ enabled: Bool, openSettingsIfNeeded: Bool = true) throws {
        guard let helperBundleID = helperBundleID, let key = defaultsKey else { throw LoginItemError.notConfigured }
        guard enabled != isEnabled else { return }
        guard SMLoginItemSetEnabled(helperBundleID as CFString, enabled) else { throw LoginItemError.refused }
        UserDefaults.standard.set(enabled, forKey: key)
        _ = openSettingsIfNeeded
    }

    /// `set` with the error as a short message for the UI, or nil on success.
    public static func setReportingError(_ enabled: Bool, openSettingsIfNeeded: Bool = true) -> String? {
        do {
            try set(enabled, openSettingsIfNeeded: openSettingsIfNeeded)
            return nil
        } catch {
            return "Launch at login: \(error.localizedDescription)"
        }
    }
}

public enum AccessibilityPermission {
    /// True when the app may read other apps' UI and post events (pasting into the front app).
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once; returns the current state.
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

public enum AppActivation {
    /// Brings the app (usually an `LSUIElement` accessory) to the front before showing a window.
    /// Uses `NSApp.activate(ignoringOtherApps:)`, available since macOS 10.6.
    public static func activate() { NSApp.activate(ignoringOtherApps: true) }

    /// `.accessory`: no Dock icon and no menu bar while a window is open.
    public static func becomeAccessory() { NSApp.setActivationPolicy(.accessory) }
}
#endif
