# Clipboard Cleaner

A tiny native macOS menu-bar app that watches the clipboard and, when you
copy a URL, cleans it — strips tracking/analytics query parameters,
unwraps a small set of known redirect links, and rewrites a handful of
well-known product-page URLs (AliExpress, Amazon, Best Buy, Walmart) to
their minimal canonical form, and does the same for MakerWorld model pages —
while leaving legitimate parameters and non-URL text untouched. Everything
runs locally — no network access at runtime.

## Project layout

- `Sources/ClipboardCleanerCore` — pure Swift URL-cleaning logic (no AppKit).
  - `URLCleaner.swift` — orchestrates the three cleaning layers (see below).
  - `RedirectUnwrapper.swift` — layer 1: local redirect/wrapper unwrapping.
  - `CanonicalURLRules.swift` — layer 2: explicit per-site canonical-form rules.
  - `TrackingRuleCatalog.swift` — layer 3: loads and matches the tracking-parameter blocklist.
  - `HostMatching.swift` — shared host/domain matching used by all three layers.
  - `StatisticsStore.swift` — the two aggregate usage counters (see below).
  - `Resources/tracking-rules.json` — the blocklist rule data (see below).
- `Sources/ClipboardCleaner` — the menu-bar app (AppKit: status item, clipboard polling).
- `Tests/ClipboardCleanerCoreTests` — unit and regression tests for the cleaning logic.
- `Tests/ClipboardCleanerTests` — menu-bar app, clipboard-monitor, and menu-layout tests.
- `Tests/UpdaterTests` — tests for the tracking-rule updater script.
- `scripts/update_tracking_rules.py` — maintainer tool to refresh the blocklist catalog.

## Three-layer cleaning pipeline

`URLCleaner.clean(_:)` runs input through three layers, in order:

1. **Redirect unwrapping** (`RedirectUnwrapper`) — a small, explicit list of
   known wrapper links whose destination is embedded directly in one of
   their own query parameters (Facebook's `l.facebook.com/l.php?u=`,
   Google's `/url?q=`/`?url=` on an explicit allowlist of reviewed Google-owned
   domains). Purely local string extraction —
   never an HTTP request. Opaque shorteners (bit.ly, t.co, tinyurl, …) are
   deliberately **not** handled: their destination only exists on the
   shortener's server, and resolving it would require a network request,
   which this app will never make.
2. **Canonical URL rules** (`CanonicalURLRules`) — explicit, opt-in
   rewrites to a minimal canonical form for a small set of well-known,
   heavily-parameterized product pages (AliExpress, Amazon, Best Buy,
   Walmart). Each rule requires both the host *and* the path to confidently
   match a known shape (e.g. Amazon's `/dp/<ASIN>`) before it rewrites
   anything; there is no generic "strip all query parameters" rule. If a
   URL doesn't match, this layer does nothing and the URL falls through to
   layer 3 unchanged.
3. **Tracking-parameter blocklist** (`TrackingRuleCatalog`) — the default,
   always-on fallback described below. Removes known tracking parameters
   by name; every other parameter, on every domain without a layer-2 rule,
   is left untouched. This is what keeps the app safe for the long tail of
   sites nobody has specifically reviewed.

Layers 1 and 2 were designed by studying the *behavior* of
[corbindavenport/link-cleaner](https://github.com/corbindavenport/link-cleaner)
(GPL-3.0) — an allowlist/canonical-rewrite browser extension — as a design
reference. No code from that project was read, copied, or incorporated;
the Swift implementation here is independent.

## The tracking-parameter catalog

`tracking-rules.json` is generated from the [ClearURLs/Rules](https://github.com/ClearURLs/Rules)
catalog (LGPL-3.0) plus a small hand-maintained list of additions. It has
two kinds of rules:

- **Global** — stripped from any URL (e.g. `utm_*`, `fbclid`, `gclid`).
- **Domain-scoped** — stripped only on specific domains and their
  subdomains, because the parameter name isn't unambiguous elsewhere (e.g.
  `si` only on `youtube.com`/`youtu.be`, `igshid` only on `instagram.com`,
  `ved`/`gs_*` only on `google.*`).

Only the "which query parameters are tracking" data is used — not
ClearURLs' redirector-unwrapping, exception lists, or URL-blocking
features. See [THIRD_PARTY_LICENSES/README.md](THIRD_PARTY_LICENSES/README.md)
for the full license/attribution details and exactly what was excluded and why.

To refresh the catalog from upstream (a manual, offline step — never run by
the app itself):

```bash
python3 scripts/update_tracking_rules.py
```

The updater resolves the upstream `master` commit first and downloads the
catalog by immutable commit SHA. It rejects unexpected schema changes and any
change to the explicitly reviewed set of skipped providers instead of silently
producing different rules.

## Running during development

```bash
swift run
```

The status item (clipboard icon) appears in the menu bar. Use **Clean Current
Clipboard** for a one-off cleanup, view recent cleaned links under **History**,
and manage preferences from **Settings**. Settings contains monitoring,
in-memory History, statistics visibility, and (on macOS 13+) Launch at Login.
History is off by default and its entries are discarded when the app quits.

## Running the tests

```bash
./test.sh
```

This wraps `swift test`. On a machine with only Command Line Tools
installed (no full Xcode), it adds the flags needed to locate the
swift-testing framework; with a full Xcode toolchain selected it just runs
`swift test` directly.

## Building a double-clickable app

```bash
./scripts/build_app.sh
```

This produces `build/Clipboard Cleaner.app` — an ad-hoc-signed, sandboxed,
launchable macOS app bundle (menu-bar only, no Dock icon, via
`LSUIElement`). `tracking-rules.json` is placed in the standard
`Contents/Resources` location (not SwiftPM's raw generated resource
bundle) so the whole bundle lives under `Contents/` and can be properly
sealed by codesign. Open it with:

```bash
open "build/Clipboard Cleaner.app"
```

## Packaging a shareable DMG

```bash
./scripts/package_dmg.sh
```

This builds the app and writes `dist/Clipboard-Cleaner-<version>.dmg`. The
disk image contains the app and an **Applications** shortcut for drag-to-install
in Finder. It is suitable for sharing directly with friends, but the app is
only ad-hoc signed, so Gatekeeper will require them to right-click the app and
choose **Open** the first time. Developer ID signing and notarization are
needed for a warning-free public distribution. The latest public build is
[Clipboard Cleaner v1.0.1](https://github.com/thetoadsage/clipboard-cleaner-public/releases/tag/v1.0.1).

On macOS 13 or later, use the menu's **Launch at Login** toggle. It is backed
by Apple's `SMAppService`; macOS 12 users can still add the app manually in
**System Settings → General → Login Items**. The monitoring-enabled setting is
also persisted, so relaunching does not unexpectedly turn monitoring back on.

## How it works

- `ClipboardMonitor` polls `NSPasteboard.general.changeCount` on a timer
  (every 0.5s while monitoring is enabled). It only reacts when the change
  count changes. Disabling monitoring stops the timer; re-enabling starts
  watching from the current clipboard state.
- When new text is detected and monitoring is enabled, it's passed to
  `URLCleaner.clean(_:)`. If the text isn't a recognizable `http`/`https`
  URL, or has no tracking parameters, it's returned unchanged and the
  clipboard is left alone.
- If the cleaned string differs, it's written back to the pasteboard, and
  `lastChangeCount` is updated immediately from the post-write value — this
  is what prevents the monitor from reprocessing its own write on the next
  poll (an infinite loop). The change count is checked again immediately
  before writing to minimize the risk of replacing a newer copy. AppKit does
  not offer an atomic compare-and-swap for the pasteboard, so a very small
  time-of-check/time-of-use window remains.
- "Clean Current Clipboard" runs the same cleaning logic once, immediately,
  regardless of whether monitoring is enabled.

## Statistics

Two aggregate counters, "Links cleaned" and "Parameters removed", shown in
the menu bar and persisted across launches via `UserDefaults`
(`StatisticsStore`). Nothing else is ever recorded:

- Only recorded when a URL is *actually* changed (a redirect unwrap and/or
  a parameter actually stripped) — not for non-URLs, already-clean URLs, or
  anything that fails to parse — and only after the pasteboard write
  actually succeeds (an aborted write, per the race guard in
  `ClipboardMonitor`, is never counted).
- "Parameters removed" counts query parameters stripped by any of the
  three cleaning layers: redirect-unwrapping (every query parameter on a
  wrapper URL that got replaced by its destination, e.g. Facebook's `u=`
  and `h=`), canonical rewriting, and blocklist filtering — all added
  together for one cleaning operation.
- `StatisticsStore`'s entire public API is two `Int` getters, a
  `recordCleanedLink(parametersRemoved: Int)` method, and `reset()` —
  there's no parameter through which a URL, domain, or parameter name
  could reach it, by construction.
- "Show Statistics" (in the menu) only controls whether the two counters
  are *displayed*; they keep accumulating either way. "Reset Statistics…"
  requires confirming an alert before zeroing both counters.

## Privacy & security

This is a first-class design requirement, not an afterthought. See the
project's audit history for the full account; summary:

- **No network access, anywhere in the app.** Verified by grep (no
  `URLSession`/`Network`/socket APIs anywhere in `Sources/`) and by
  empirically confirming (via a disposable sandboxed probe binary) that the
  App Sandbox entitlement blocks network access at the OS level, not just
  by code review. The only networked code in this repository is
  `scripts/update_tracking_rules.py`, a manual, offline, maintainer-only
  tool that is never bundled into the app and never run by it.
- **App Sandbox is enabled** (`com.apple.security.app-sandbox`, no other
  entitlements) on the built `.app`. This is a deny-by-default,
  kernel-enforced boundary: no network, no filesystem access outside the
  app's own container, no camera/microphone/etc. General pasteboard
  read/write (what this app actually needs) is unaffected.
- **No clipboard content or URL metadata is logged or persisted.** No
  `print`/`NSLog`/logging calls touch clipboard content anywhere in the
  codebase. No clipboard contents, URLs, domains, parameter names, or values
  are stored. Only aggregate counters and UI preferences are persisted in
  `UserDefaults`. Non-matching (non-URL) clipboard content is never even
  written back to the pasteboard — the monitor only touches the pasteboard
  when `URLCleaner.clean` actually changed something.
- **The tracking-rules catalog is data, not code.** It's parsed with
  `JSONDecoder` into plain `[String]` arrays; rule strings are only ever
  used as exact-match `Set` lookups or `NSRegularExpression` patterns,
  never executed. Loading validates the file's size and shape
  (`TrackingRuleCatalog.isCatalogWithinSafeBounds`) and fails safely to an
  empty catalog — never a crash — on anything malformed or oversized.
- **Defense-in-depth against pathological input**: clipboard content over
  8KB, and query parameter names over 512 characters, are never parsed or
  regex-matched at all (see `URLCleaner.maxInputLengthBytes` /
  `TrackingRuleCatalog.maxParameterNameLength`). Redirect unwrapping is
  capped at 3 hops. These are backed by regression tests in
  `Tests/ClipboardCleanerCoreTests/SecurityRegressionTests.swift`,
  including empirical timing assertions against adversarial inputs, not
  just code review.
- **Clipboard formats**: automatic cleaning accepts only a single item
  containing plain text, optionally accompanied by `public.url` and URL
  metadata that browsers or macOS add when copying a link. It skips rich text,
  HTML, images, files, unknown representations without `public.url`, and
  multi-item copies to avoid discarding accompanying content. The explicit
  **Clean Current Clipboard** action still replaces a changed URL with plain
  text, discarding other representations of that clipboard content.

## Continuous integration and releases

The macOS GitHub Actions workflow runs the complete Swift tests, a release
build, updater syntax/unit checks, app-bundle construction, strict ad-hoc
signature verification, resource validation, and checksum verification.

App versions come from numeric `v` tags such as `v1.2.3`; untagged development
builds use `0.0.0`. Use `package_dmg.sh` above for the Finder-friendly artifact
shared with users. To create a local maintainer archive and checksum:

```bash
./scripts/package_release.sh
```

This writes a versioned ZIP and `SHA256SUMS` to `dist/`. Builds are currently
ad-hoc signed. Developer ID signing and notarization are intentionally deferred
until release credentials and that distribution workflow are configured.

Clipboard Cleaner's own source is available under the [MIT License](LICENSE).
The generated tracking catalog retains its separate ClearURLs LGPL-3.0 terms;
see [THIRD_PARTY_LICENSES/README.md](THIRD_PARTY_LICENSES/README.md).

## Support

If Clipboard Cleaner is useful to you, you can [support it on Ko-fi](https://ko-fi.com/kingtoad).
