# AGENTS.md

## What this is
- A macOS SwiftUI client for the Navidrome / Subsonic API, built as a Swift Package. It is NOT the Navidrome server.
- Four targets in `Package.swift`: `NavidromeClient` (library: HTTP client, API models, cache) and `Klopydrome` (executable SwiftUI app, macOS 14.4+) plus `NavidromeClientTests` / `KlopydromeTests`. `Klopydrome` depends on `NavidromeClient`.
- Do not edit `docs/` (upstream Navidrome server docs, reference only). Ignore `.build/` (artifacts), `dist/` (release zips), and `vendor/` (the audio engine fork).

## Setup (first checkout)
- Run `./scripts/build-mpvkit-audio.sh` once: it builds the audio-only MPVKit fork in `vendor/MPVKit-Audio` into `vendor/MPVKit-Audio/dist/libmpv/macos/Libmpv.framework` and `dist/release/xcframework/Libmpv.xcframework` (30–60 min, needs Homebrew tools: nasm, meson, ninja, cmake, pkg-config, wget, git, plus Xcode tools: xcodebuild, xcrun, zip). Without it `swift build` cannot link `import Libmpv` in `MPVPlaybackEngine.swift`.
- `swift test` needs **full Xcode** — the CommandLineTools toolchain ships no XCTest. `build-app.sh` and `lint.sh` auto-switch `DEVELOPER_DIR` to `/Applications/Xcode.app/Contents/Developer` when CommandLineTools is active.

## Delegate research to subagents
- Delegate self-contained research and analysis to subagents (`explore`, `general`, `swift-expert`, `swiftui-expert`) instead of doing it in the main thread: file hunts, cross-file impact analysis, and evaluating options/tradeoffs.
- Keep work in the main thread only when the full context matters (editing, deciding the final shape of a change, synthesizing results).
- Ask a subagent to return a concise, actionable summary — then verify its key claims yourself before acting.

## Visual bugs and screenshots
- **NEVER take screenshots of the app for my own analysis. I have no vision — a screenshot tells me nothing.**
- Screenshots are allowed ONLY to show to the user. In all other cases, do NOT capture them.
- When you need to run the app (bug repro, verification), build the bundle and hand it to the user to check (`./scripts/build-app.sh --no-test`, then the user opens `.build/app/Klopydrome.app`). Ask the user what they see.
- If you can't reproduce a visual bug yourself and the user has reported it, ask the user directly what they observe — don't guess from code or dump diagnostics the user can't see.
- For layout geometry questions, prefer on-screen debugging overlays that the USER can read and report back, over logs/stdout that never reach you in a headless run.

## Root cause first, workarounds last
- Diagnose the root cause first and fix the cause. Never layer a behavior-changing wrapper over the UI to mask a bug (lesson: the reverted mini-player traffic-lights resync — it didn't fix the disappearance and added new misbehavior; it was reverted instead of patched forward).
- Workarounds only when the user explicitly allows them.
- An allowed workaround must be small, tightly scoped, documented inline with WHY the root fix isn't possible — and must not be a "temporary fix" (no TODO-vapor that rots). If the system undoes it, re-apply on redraw/cadence rather than one-shot: e.g. hiding the sidebar menu is acceptable as a small workaround that tears itself down and re-applies every N time instead of pretending to hold once.

## Build, test, run
- `swift build` — compile check; run after any change.
- `swift test` — XCTest suite: `NavidromeClientTests` (client/API logic) and `KlopydromeTests` (pixel-level cover-render tests via `ImageRenderer`). Filter a single test: `swift test --filter <TestCase>/<testMethod>` or `swift test --filter <TestCase>`. Note: `ImageRenderer` needs a main-actor + run-loop tick (`renderPNG` helper).
- `./scripts/build-app.sh [--release]` builds via the **Xcode project** (`Klopydrome.xcodeproj`, not `swift build`) into `.build/app/Klopydrome.app`. Gates before packaging: SwiftLint (new violations only) + `swift test --filter PlaylistCoverPresetTests`; skip with `--no-lint` / `--no-test`.
- The bundle is signed ad-hoc **without the hardened runtime** — the stock LuaJIT crashes with EXC_BAD_ACCESS under the hardened runtime. The script also hand-embeds `NavidromeClient.framework` into the bundle and rewrites its install name to `@rpath` (Xcode does not auto-embed local framework targets; without this the app fails to launch).
- Prefer `build-app.sh` over `swift run`: a bare executable is not activated as an app, so text fields may not receive keyboard input. The app itself calls `NSApp.activate` on launch to compensate.

## Version control
- **All changes to the working tree must be committed.** When you complete any unit of work (a task, feature, or fix), commit it before moving on. There should be no uncommitted changes left behind.
- Write a concise, conventional commit message describing the change. Do not push unless explicitly asked.

## Release flow
- Makefile targets: `make package`/`make dist` → `scripts/package-release.sh` (zip into `dist/`). There are no local publish scripts: releases are cut by pushing a `v*` tag (see below).
- Release flow: bump `VERSION`, commit, tag `vX.Y.Z`, push branch + tag. CI (`.github/workflows/build.yml`, GitHub Actions, macOS 26) builds the release bundle, zips it, and publishes a GitHub Release with the zip. No `.env`/tokens needed.

## Cross-module gotchas
- Shared types (`AuthMode`, `SubsonicConfig`, `SubsonicSong`, `SubsonicEnvelope`, `CacheManager`, `CacheKind`) are defined in the `NavidromeClient` module. Every file in `Sources/Klopydrome/` MUST `import NavidromeClient` to use them — otherwise you get "cannot find type in scope" (`LoginView.swift` was previously broken for exactly this reason).
- `buildURL`, `authQueryItems`, `md5Hex`, `randomSalt` on `NavidromeClient` are `internal` (not `public`); tests access them via `@testable import NavidromeClient`.

## Language / architecture
- Package is tools-version 6.0 but uses `swiftLanguageModes: [.v5]`. App code relies on `@Observable` + `@MainActor` (macOS 14) for shared state and `@State`/`@Bindable` for view-local state; do not introduce strict-concurrency-only APIs.
- `AppState` is an `@Observable` class injected via `.environment()`. `ServerConfig` (Codable) is persisted; the password lives in the Keychain via `KeychainStore`.
- Caching has two layers: `CacheManager` (disk, stores for covers/streams/metadata under `~/Library/Caches/NavidromeSwift`) and `CoverArtStore` (in-memory). AppState exposes `isCached(_:)` / `cacheSongs(_:)`.
- **Automix transitions are analysis-only.** Per-pair edge analysis (energy, beat/downbeat, vocal risk) runs on real decoded audio in the background (`Player+TransitionAnalysis.swift`); `AutomixProfileRecommender` picks an explainable `TransitionProfile` through hard gates (readiness/rhythm/meter/spectrum/vocal/energy). The decision never changes audio output — rendering stays on the established MPV crossfade until a profile's renderer is validated; the selected profile surfaces in `crossfadeStatusText`. Remote streams get the conservative fallback immediately.
- Views use `NavigationSplitView` with explicit `navigationSplitViewColumnWidth`, `.help()` tooltips on icon-only buttons, `@FocusState` for text-field focus, and `LazyVStack` for long lists. Prefer standard HIG components over custom chrome.

## UI conventions
- **Context actions have ONE source of truth.** Playlist actions come from `PlaylistContextMenuItems` (rename / play / follow / make public / duplicate / delete) — sidebar rows, playlists-grid tiles, and the detail-window «…» button all build from it; the public/private toggle goes through `app.togglePlaylistVisibility(_:)`. Song actions come from `SongActionItems` — every list row's right-click and hover «…», the Songs-table selection menu, and the now-playing menu all build from it (play / play next / queue later / add to playlist / favorite / download / rate). Both components and their helpers live in `Sources/Klopydrome/PlaylistMenu.swift` and `Sources/Klopydrome/SongMenu.swift`. Never hand-roll a parallel list of actions on a surface — that is how the four different song menus and three different playlist menus appeared.
- `Build`/`lint` gate: `./scripts/lint.sh` uses a SwiftLint baseline, so **adding lines to a file near a size limit flags the WHOLE file.** When a lint error appears after a small edit, prefer moving the new code into an extension in another file (e.g. `AppState` methods as `extension AppState`) over raising the threshold — it keeps the baseline intact.
- **Hit targets are larger than the visual object.** When building pill/menu/button labels, the whole padded background must be clickable — never leave dead space around the text or icon. Plain `Button`/`Menu` hit areas are exactly the label content, so padding added OUTSIDE the label expands the background but not the click area. Fix: keep the padding inside the label and add `.contentShape(Rectangle())` to it (this bit us in the artist-page sort pill: only the text and the arrow were clickable, the rounded background around them was dead).

## Localization
- Every user-visible string MUST be localized. If you add new strings, add the English localization in `Resources/en.lproj/Localizable.strings` (and update `ru.lproj` if you touch Russian). When analyzing code, flag any hard-coded UI string without a `L10n`/`LocalizedStringKey`/`String(localized:)` lookup and translate it.
- For code analysis, delegate to `explore`/`general` subagents to sweep for unlocalized strings across the codebase.

## Branding in locales
- Do not use the app brand name in locale strings. Use generic wording: e.g. "Кэш приложения" / "Application cache", not "Кэш Klopydrome" / "Klopydrome cache". Klopydrome is just one client for the Subsonic/Navidrome API — locales must not be tied to a specific client name.

## Pre-release commit hygiene
- Before any release (bumping `VERSION`/pushing a `v*` tag), audit the commit log since the last tag/release: look for duplicate commits, probable regressions, and throwaway fixup commits (especially `Revert` commits that just undo a previous attempt). Use `explore`/`general` subagents to help with the audit when the history is long.
- Report all findings to the user and get explicit approval before proceeding — either "ship as-is" or "clean up first". Remember: intermediate commits exist only for local rollback; the history pushed to remote must be clean (squashed/fixup-ed, no revert-noise).

## User reference materials
- Treat `misc/` as the user-maintained workspace for reference files and supporting documentation. Before work that could be informed by existing research, product notes, design reviews, API references or source material, inspect the relevant contents of `misc/`.
- Store agent-produced research and technical feasibility notes in `misc/research/`.
- Do not move, edit or delete user-maintained files under `misc/` unless the user explicitly requests it.
