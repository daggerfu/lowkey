import AppKit

/// Native window geometry, keyed by the site's stable profile ID rather than its editable alias.
/// Uses AppKit's frame format, including screen geometry, so restore can adapt to display changes.
final class SiteWindowPlacement {
    let name: NSWindow.FrameAutosaveName
    private var ready = false
    private var inFullScreenTransition = false

    init(siteID: UUID) {
        // Keep the original autosave key so existing saved positions still restore.
        name = "LowkeySite-\(siteID.uuidString)"
    }

    func restore(_ window: NSWindow) {
        ready = false
        if !window.setFrameUsingName(name) { window.center() }
        ready = true
    }

    func save(_ window: NSWindow) {
        guard ready, !inFullScreenTransition, !window.styleMask.contains(.fullScreen) else { return }
        window.saveFrame(usingName: name)
    }

    /// Fullscreen is temporary geometry. Never replace the normal window's saved rectangle with it.
    func willEnterFullScreen() { inFullScreenTransition = true }
    func willExitFullScreen() { inFullScreenTransition = true }
    func didExitFullScreen(_ window: NSWindow) {
        inFullScreenTransition = false
        save(window)
    }

    func didFailToEnterFullScreen(_ window: NSWindow) {
        inFullScreenTransition = false
        save(window)
    }
}
