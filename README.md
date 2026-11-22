# lowkey

A minimal macOS browser built with AppKit and the system WebKit. No tabs, no
permanent address bar. Saved sites open by alias, each with its own persistent profile.

**macOS 10.15 or later · Intel · 0BSD.** Official release ZIPs are
Developer ID signed, notarized and stapled. The public product name is always
**lowkey**, in lowercase; historical Swift identifiers and storage paths are unchanged.

## Install

Download the universal ZIP from [GitHub Releases](https://github.com/bobuk-io/lowkey/releases/latest),
unzip it and move **lowkey.app** to `/Applications`. Open the app and press ⌘L
to enter an address, or press ⌘, to add saved sites in Settings. Releases include a
SHA-256 checksum. Do not disable Gatekeeper to install an unknown binary.

There is no automatic updater, Sparkle integration or Homebrew cask. To update,
quit lowkey, download the new release and replace only the app. Settings, history,
profiles and sign-ins are retained. Launching does not open any windows. Click the
Dock icon again to open the address prompt, even when a site window is visible.

## Windows and keyboard

One live window per saved site. Reopening an alias brings back its current page,
including a hidden window. Each site remembers its normal window position and size,
keyed by its stable UUID; renaming an alias keeps its profile and geometry.

| Shortcut | Action |
| --- | --- |
| ⌘L | Address or alias prompt |
| ⌘⇧L | Open a URL or alias in this window's exact current profile |
| ⌘N | Prompt for a new ordinary window |
| ⌘← / ⌘→ | Back / forward, except while editing text |
| ⌘[ / ⌘] | Back / forward menu commands |
| ⇧⌘H | Configured start page; initial URL for an ordinary window |
| ⌘R | Reload; retry a failed address |
| ⌘W | Hide a saved-site window; close an ordinary window |
| ⇧⌘W | Close the window, retaining its profile |
| ⌘, | Settings |
| ⌘Q | Quit lowkey and stop all pages |

The window strip is 20 pt high with a 2 pt accent line and back/start/forward controls.
Drag it to move the window; resize normally. View or ⌃⌘F enters system fullscreen.
⌘-clicking a site's left control closes it; a normal click hides it. Closing a window
never clears its cookies. The site's cross changes to a Q-like glyph while ⌘ is held;
ordinary windows show Q by default.

An alias activates its saved window. A raw URL entered with ⌘L in a saved-site
window opens a new ordinary window. In an ordinary window it replaces that page;
⌘Return requests a new ordinary window.

**⌘⇧L — Open Location in This Profile…** instead loads a URL or the resolved
address of an alias into the exact current web view, preserving its profile,
cookies and sign-in state. It also works in sign-in/popup windows. It never switches
to the alias's profile or creates an ordinary window, even with ⌘Return. The explicit
navigation bypasses external-link/sign-in routing once; later links use the normal
site policy. This is useful for authentication that needs a URL in an existing profile,
but does not guarantee that an identity provider supports embedded browsers.

## Addresses and suggestions

The prompt accepts HTTP(S) URLs and bare hosts. Bare hosts use HTTPS; loopback uses
HTTP. There is no search-engine fallback. An empty prompt lists only configured sites.
Once you type, suggestions come from aliases and the last
**1,000 unique submitted entries**, not every visited page. Russian/Ukrainian ↔ US
keyboard-layout variants also match: `рф` can find `HA`. Original-spelling matches
come first; valid typed URLs and the field text are never silently rewritten.

Use arrows and Return to choose. Hover a history entry and click × to forget it;
entering it again restores it as newest. Remove aliases in Settings, not history.
The picker uses shared BobukKit rows, equal-width centered badges, a rounded frame
and wrapping shortcut hints. Its colors follow the current window's theme.

## Settings, profiles and privacy

Settings contains saved sites, appearance and history controls. A site has an alias,
optional title, start URL, external-link policy and extra origins. Valid changes save
automatically. Alias matching ignores case; a stable UUID identifies the profile.

- Every saved site has its own persistent `WKWebsiteDataStore` identified by UUID.
- Ordinary windows share the default persistent store. Popups share their opener's store.
- Removing a saved site confirms and deletes its profile; closing it does not.
- Configuration: `~/.config/lowkey/config.json`.
- Submitted-input history: `~/Library/Application Support/Lowkey/history.json`.
  This historical directory spelling is retained for compatibility.
- No analytics, application account or backend. Websites receive ordinary WebKit traffic.
- Camera/microphone access is requested for website requests; uploads/downloads use
  native dialogs. No Accessibility or Input Monitoring permission is needed.

```json
{
  "sites": [{
    "id": "B943B7D1-190E-43CB-AFAE-4058D93274E3",
    "alias": "HA", "title": "Home Assistant",
    "startURL": "https://homeassistant.local",
    "externalLinks": "defaultBrowser",
    "extraOrigins": ["https://ha.example.com", "*.nabu.casa"]
  }],
  "appearance": { "mode": "tint" }
}
```

The start origin (scheme, host, port) and extra origins count as internal. Subdomains
are external unless allowed; `*.example.com` excludes the bare host. Clicked external
links stay in lowkey or open in the default browser, according to the site's setting.
Redirects and script navigation are not automatically sent outside, to avoid breaking
sign-in. Ordinary `target="_blank"` links do not create tabs.

Appearance modes: Tint (default), Page, System, Light and Dark. In Tint mode the window
strip takes the page color: the site's `theme-color` first, then the page background
(colors with alpha below 0.9 do not count). When the page gives no usable color, for
example while a new page loads, the window keeps its last color; before the first one the
strip uses the palette panel. No line shows under the strip, its icons are derived from
the tint, and a color change animates briefly. The accent line, the address prompt and
popup origin bars keep the palette, light or dark by the tint. Page mode reads each page's
WebKit background, with `theme-color` as a fallback, and chooses the light/dark palette
per window. System is used without a usable color. A debounce/dead band reduces
flicker. A config saved before Tint existed with mode `page` moves to Tint once. Image/video/canvas-heavy pages may look different from their detected background;
this is not screenshot analysis. lowkey never recolors site content or forces its CSS.

Light/dark palettes are independent, with editable panel/accent colors. Presets include
Amber, Sage, Ocean, Terracotta, Dracula, Nord, Catppuccin, Gruvbox, Solarized, Tokyo Night,
One Light/Dark and Rosé Pine. Settings uses System in Tint and Page modes.

## Command line

To use `lowkeyctl` by name in Terminal, follow the [PATH setup and command reference](https://bobuk.io/apps/lowkey/lowkeyctl/). The setup links the helper from `/Applications/lowkey.app` into a user bin directory; it does not require sudo or modify shell startup files.

Alternatively, run the helper directly (not via `open`) to address a saved site without opening a URL:

```sh
/Applications/lowkey.app/Contents/Helpers/lowkeyctl HA toggle
```

To click a button or link in an already-open site window, pass its exact label as one argument:

```sh
/Applications/lowkey.app/Contents/Helpers/lowkeyctl HA click 'Refresh list'
```

`click` does not open or raise the window. It matches rendered text or `aria-label`
(case-sensitive, whitespace normalized) in the main document, including open shadow roots,
not iframes. It requires the saved start URL's origin. No match, multiple matches or a
disabled control return an error without clicking. Exit status 0 means the click was
dispatched, not that the website completed the action. This is a local CLI command,
not a `lowkey://` link.

Starting with lowkey 0.1.2, use **Save as PDF…** in the page context menu,
**View → Save as PDF…** (⌘⇧S), and:

```sh
/Applications/lowkey.app/Contents/Helpers/lowkeyctl HA save-pdf ~/Desktop/page.pdf
```

This prints the entire current document to an A4 PDF, including content below the viewport,
using the site's print styles. It does not scroll to load lazy content or expand virtualized lists.
The menu opens a save dialog. The helper accepts a `.pdf` path (relative paths work), requires
an open page on the saved origin, and refuses to overwrite an existing file. No print dialog appears.

To attach one file to an already-open page:

```sh
/Applications/lowkey.app/Contents/Helpers/lowkeyctl HA upload 'file name.pdf'
```

The helper reads one regular file (up to 8 MiB) and passes its basename and bytes,
not its local path. The page must be on the saved origin. By default it must have exactly one file
input in the main document or its open shadow roots. Add `--field 'Document'`
to select one input by its exact HTML or ARIA label instead. A hidden input is supported;
ambiguous matches, a disabled input, directories and incompatible file types are rejected.
This replaces the current file selection and fires `input` and `change`. It doesn't
submit the form, but the site can read or send the file immediately. No `lowkey://`
upload commands are supported.

Other local commands (prefix each with `lowkeyctl HA`):

| Command | Result |
|---|---|
| `inspect [--json]` | List controls with their types and labels, not current field values. |
| `status [--json]` | Report window visibility, focus, minimization and loading without raising the window. |
| `wait [label] [--timeout seconds]` | Wait for DOM readiness, optionally for one visible, enabled control with an exact label. Defaults to 10 seconds (1–300). Does not wait for network idle or click. |
| `fill 'Comment' 'Hello'` | Set a labelled text input or textarea; no password fields. |
| `select 'Period' 'This month'` | Select an option by display text in a labelled native single-select. |

Page commands only work in the saved origin, main document and open shadow roots. `fill` and
`select` fire input/change events, not a submit; the site's own handlers may save changes.

Window commands: `toggle`, `open`, `hide`, `rewind`, each preceded by one saved alias.
`lowkeyctl HA rewind` shows HA and navigates back to its configured start URL, not the previous history entry. `open` and
`toggle` start the containing app if necessary; `hide` does nothing if it isn't
running. The helper uses local IPC, not a network service. For a toggle, lowkey
selects the target window before the helper requests focus. Existing URL bindings
still work. macOS delivers `open 'lowkey://…'` as a URL; it does not call `lowkeyctl`.
Ting builds with helper support translate single-site open, toggle, hide and rewind bindings
into helper arguments. For page actions, use a [Ting `lowkey` step](https://github.com/bobuk-io/ting/blob/main/docs/micro-apps/FORMAT.md#lowkey-steps), not a URL binding.

For example, to find a control before automating it:

```sh
ctl=/Applications/lowkey.app/Contents/Helpers/lowkeyctl
"$ctl" HA status --json
"$ctl" HA inspect --json
```

`status` reports `alias`, `open`, `visible`, `minimized`, `focused` and `loading`.
`inspect` needs an open window; each result has `type`, `labels`, `disabled` and `visible`.
Use a label from that output with `wait`, `fill`, `select` or `click`. Match failures
return a nonzero exit status; do not retry a click or upload automatically.

## Deep links

```sh
open 'lowkey://HA/open'       # create or bring back a saved-site window
open 'lowkey://HA/toggle'     # frontmost → hide; background/hidden/minimized → show; unopened → create
open 'lowkey://*/toggle'      # frontmost saved site → hide all; otherwise raise existing saved-site windows
open 'lowkey://HA/reload'
open 'lowkey://HA/back'
open 'lowkey://HA/forward'
open 'lowkey://HA/start'
open 'lowkey://HA/hide'
open 'lowkey://HA/close'      # release live page, retain profile
```

Toggling a single alias brings only that site's window forward. The wildcard hides
existing saved-site windows if one has focus, or shows them otherwise. It does not
open unused sites or touch ordinary windows.
`lowkey://` opens the prompt; unknown aliases appear there. Names are case-insensitive.
Deep links intentionally expose no JavaScript, clicks, shell or page automation.

## Sign-in and limits

Sign-in windows share the parent profile and show the provider host. WebKit-created
popups retain opener/window-close behavior. Recognized provider navigation may open
separately and return a callback to the site window.

**Google and other identity providers may reject embedded user agents.** Real-provider
sign-in and complex callbacks have not been fully validated. lowkey does not impersonate
Safari, bypass certificate validation or transfer another browser's cookies.
Basic downloads, uploads, JavaScript dialogs and HTTP authentication are implemented.
There are no extensions or password-manager integration. See [SECURITY.md](SECURITY.md).

## Build and develop

Swift 6.2 / Xcode 26 or later, on macOS:

```sh
git clone https://github.com/bobuk-io/lowkey.git
cd lowkey
swift test
Scripts/run.sh                     # build and run the debug app
Scripts/package_app.sh release      # release build, ad-hoc signed by default
```

Below 0.5.0, `Scripts/run.sh` builds the app, stops running lowkey copies,
replaces `/Applications/lowkey.app`, and starts the new build. From 0.5.0,
it uses `build/lowkey.app` instead; quit that copy before rebuilding its bundle.
For isolated manual checks without replacing the installed app or stopping other copies:

```sh
LOWKEY_CONFIG=/tmp/lowkey-test.json Scripts/run.sh
```

This isolates configuration/history, **not the default WebKit store**. Use random
site UUIDs, nonpersistent stores or a local mock page; never use real accounts for tests/screenshots.

`Sources/LowkeyCore` is pure logic; `Sources/Lowkey` holds AppKit/WebKit/SwiftUI.
The self-contained BobukKit package is in `Vendor/BobukKit`. Windows are `LowkeyWindow`,
a BobukUI `ChromeWindow` that takes its `ChromeStyle` from lowkey's theme; the ⌘L prompt
is a BobukUI `BobukPanel(kind: .prompt)`. Layout variants and the history list come from
BobukCore (`KeyboardLayoutSwap`, `RecentList`), and `lowkeyctl` talks to the app through
BobukCore's `MessagePortServer`/`MessagePortClient`. Edit shared UI only in
`~/GitHub/bobuk.io/BobukKit`, then run its `Scripts/sync.sh` and `--check` for all
registered consumers. Release EXTRA_TESTS verifies snapshot hashes and tests the kit.

Releases use the shared kit in `Scripts/release/`, configured by `release.env` and
`version.env`. Prepare English notes in `docs/releases/v<version>.md` and the landing
page in all three locales; run `Scripts/release/doctor.sh` with `APP_IDENTITY` and
`NOTARY_PROFILE`, then `Scripts/release_next.sh`. That command makes a real signed,
notarized universal release, installs `/Applications/lowkey.app`, restarts it, publishes
GitHub assets/checksums and deploys the landing site. Test the kit only with the offline
`Scripts/release/test_kit.sh`; never run publication commands as a check.

## Support and removal

Report problems through [GitHub Issues](https://github.com/bobuk-io/lowkey/issues).
Include versions and a minimal local reproduction, not cookies, credentials, private
URLs or configuration.

To uninstall, remove saved sites in Settings first if you want their website data
deleted, quit lowkey and delete lowkey.app. Configuration and input history remain
at the paths above. Removing the app does not erase WebKit data, including the ordinary
profile. Never delete unrelated WebKit data or another browser's profiles.

## License

Original code is [0BSD](LICENSE). Adapted release scripts retain MIT attribution;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
