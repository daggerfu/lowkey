import AppKit
import CoreGraphics
import LowkeyCore

/// Launch Services can activate lowkey before delivering a URL, raising the previous key window.
/// Keep other windows behind the same apps when a single saved-site window is toggled.
struct ToggleWindowOrder {
    private let stack = Self.visibleNormalWindows()
    private let timestamp = Date()

    // The URL can arrive just after activation, on a later run-loop turn. Don't reuse a
    // snapshot from an unrelated activation (such as switching to lowkey via the Dock).
    static func recentActivation(_ snapshot: Self?) -> Self? {
        guard let snapshot = snapshot, Date().timeIntervalSince(snapshot.timestamp) < 0.25 else { return nil }
        return snapshot
    }

    func isFrontmost(_ window: NSWindow) -> Bool {
        guard NSApp.isActive && window.isKeyWindow else { return false }
        // An active key window can still be behind another app. Key status alone isn't enough.
        guard let index = stack.firstIndex(where: { $0.number == window.windowNumber }),
              let bounds = stack[index].bounds else { return true }
        return !stack[..<index].contains { !$0.isOwned && $0.bounds?.intersects(bounds) == true }
    }

    /// `orderOut` searches for a replacement key/main window synchronously. Windows
    /// behind another app must not participate, or AppKit may visibly raise them.
    func hide(_ target: NSWindow, perform: () -> Void) {
        let background = WindowToggle.backgroundWindows(in: stack.map(\.number),
                                                        owned: Set(stack.filter(\.isOwned).map(\.number)))
        let blocked = NSApp.windows.compactMap { $0 as? LowkeyWindow }.filter {
            $0 !== target && $0.allowsFocus && background.contains($0.windowNumber)
        }
        for window in blocked { window.allowsFocus = false }
        defer { for window in blocked { window.allowsFocus = true } }
        perform()
    }

    /// Use a relative order while active; makeKeyAndOrderFront can pull other
    /// windows in front of the app they were behind.
    func raiseOnly(_ target: NSWindow) -> Bool {
        guard NSApp.isActive, target.isOnActiveSpace, target.level == .normal,
              target.attachedSheet == nil, !target.isMiniaturized,
              let first = Self.visibleNormalWindows().first else { return false }
        if first.number != target.windowNumber {
            target.order(.above, relativeTo: first.number)
        }
        target.makeKey()
        return true
    }

    func restoreBackgroundWindows(except target: NSWindow) {
        let windows = Dictionary(uniqueKeysWithValues: NSApp.windows.filter { $0.windowNumber > 0 }
            .map { ($0.windowNumber, $0) })
        let moves = WindowToggle.backgroundRestoration(before: stack.map(\.number),
                                                        after: Self.visibleNormalWindows().map(\.number),
                                                        owned: Set(stack.filter(\.isOwned).map(\.number)),
                                                        target: target.windowNumber)
        for move in moves {
            windows[move.window]?.order(.below, relativeTo: move.anchor)
        }
    }

    private static func visibleNormalWindows() -> [(number: Int, isOwned: Bool, bounds: CGRect?)] {
        let pid = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return (list as? [[String: Any]] ?? []).compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == NSWindow.Level.normal.rawValue,
                  let number = info[kCGWindowNumber as String] as? Int else { return nil }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) }
            return (number, info[kCGWindowOwnerPID as String] as? Int32 == pid, bounds)
        }
    }
}
