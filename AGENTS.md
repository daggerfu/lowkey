# lowkey project rules

- Always write the public product name **lowkey**, in lowercase, including menus,
  titles, documentation, landing copy and release names. Preserve existing Swift
  module/type names, bundle ID and stored data paths for compatibility.

- Native macOS browser: AppKit, WebKit, SwiftUI settings. Bundle identifier
  `io.bobuk.lowkey`; use `io.bobuk` for new identifiers.
- Repository: `bobuk-io/lowkey`. Never publish browser profiles or website data.
- Shared UI and infrastructure come from BobukKit (`Vendor/BobukKit`); read
  `../BobukKit/README.md` before adding windows, panels, controls, hotkeys, file stores,
  processes or update code here, and follow `../AGENTS.md`. The release kit in
  `Scripts/release/` is a managed copy of `../BobukKit/ReleaseKit`; never edit it here.
- lowkey windows are `LowkeyWindow` subclasses of BobukKit's `ChromeWindow`; their ⌘W goes
  through lowkey's menu (hide vs close for saved sites), so they keep `closesOnCommandW` off.
- While `version.env` is below 0.5.0, run `Scripts/run.sh` after verified app changes. It stops running
  lowkey copies, replaces `/Applications/lowkey.app` with the development build,
  and starts it without asking again. At 0.5.0 and later, ask before restarting
  or replacing the installed bundle.
- Tests and screenshots use temporary configuration and random site UUIDs or
  nonpersistent WebKit stores. `LOWKEY_CONFIG` isolates config and input history,
  NOT the default WebKit store. Never use real accounts or pages for screenshots.
- Keep pure logic in LowkeyCore. Releases use the shared kit (`Scripts/release/README.md`);
  `Scripts/release_next.sh` makes a real release. Public binaries require Developer ID
  signing, notarization, stapling, local tests, a universal ZIP, checksums, GitHub publication, installation at
  /Applications/lowkey.app and restart, and landing deployment. No Sparkle or
  Homebrew support is currently shipped; do not claim it exists.
- Update the landing site in all three locales when a release needs it. See
  ../AGENTS.md and ../landing/docs/updating.md. Never announce an unpublished
  binary as available for download.
