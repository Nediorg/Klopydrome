# AGENTS.md

## What this is
- A macOS SwiftUI client for the Navidrome / Subsonic API, built as a Swift Package. It is NOT the Navidrome server.
- Four targets in `Package.swift`: `NavidromeClient` (library: HTTP client, API models, cache) and `Klopydrome` (executable SwiftUI app, macOS 14.4+) plus `NavidromeClientTests` / `KlopydromeTests`. `Klopydrome` depends on `NavidromeClient`.
- Do not edit `docs/` (upstream Navidrome server docs, reference only). Ignore `.build/` (artifacts), `dist/` (release zips), and `vendor/` (audio engine fork).

## Project Structure & Core Subsystems
- **`Sources/NavidromeClient/`**: Subsonic/Navidrome API client library (decoupled from SwiftUI).
  - Networking & Endpoints: `SubsonicClient.swift`, `Endpoints.swift`, `NavidromeAPI.swift`.
  - API Models: `Models.swift`, `PlaylistModels.swift`, `LyricsModels.swift`, `SubsonicError.swift`.
  - HTTP & Disk Cache: `CacheManager.swift` (`~/Library/Caches/NavidromeSwift`), ETag/SWR caching.
- **`Sources/Klopydrome/`**: Main macOS SwiftUI client application (macOS 14.4+).
  - **State Orchestrator (`AppState`)**: Central `@Observable` environment object. Domain logic is split into focused extensions (`AppState+Playback`, `AppState+TrackDownload`, `AppState+Offline`, `AppState+OfflineCaching`, `AppState+LibraryWarmup`, `AppState+PlaylistDuplicates`, etc.).
  - **Audio Engine (`Player`)**: Coordinates queue, track transitions, crossfade, and seek via `MPVPlaybackEngine` (wrapping Libmpv). Automix transition analysis in `AutomixTransitionAnalysis.swift`.
  - **Navigation & Shell**: `MainView`, `SidebarView`, `DetailColumn`. History routes through in-memory `app.nav.history: [Destination]`.
  - **Key Screens**:
    - Home & Shelves: `HomeView.swift`, `HomeQuickAccessSection.swift`, `OfflineHomeView.swift`.
    - Detail views: `AlbumDetailView.swift`, `ArtistDetailView.swift`, `PlaylistDetailView.swift`, `GenreDetailView.swift`, `SmartPlaylistDetailView.swift`.
    - Browsers: `SongsView.swift`, `SongTable.swift`, `PlaylistsView.swift`, `ArtistsView.swift`, `GenresView.swift`.
    - Playback UI & Lyrics: `MiniPlayerView.swift`, `PlayerLCDView.swift`, `LyricsView.swift`, `KaraokeLineView.swift`.
    - Settings: `AppSettingsView.swift` (`GeneralSettingsView`, `PlaybackSettingsView`, `CacheSettingsView`, `AppearanceSettingsView`).
  - **Smart Playlists**: `SmartQuery.swift`, `SmartFields.swift`, `SmartPlaylistEngine.swift`, `SmartPlaylistEditorView.swift`.
  - **Offline & Persistence**: `OfflineRepository.swift`, `SwiftDataOfflineRepository.swift`, `OfflineMutationQueue.swift`, `KeychainStore.swift`, `ServerConfig.swift`.
  - **Design System & Artwork**: `CoverArtView.swift`, `CoverArtStore.swift`, `SongTable.swift`, `SongRow.swift`, `AlbumGridView.swift`, `CompactSongsGrid.swift`, `ContentPillCard.swift`, `SkeletonKit.swift`, `DetailScaffoldKit.swift`, `Components.swift`, `Theme.swift`.
- **`Tests/`**: `NavidromeClientTests/` (API and URL building tests) and `KlopydromeTests/` (player, offline, cache, UI logic tests).
- **`scripts/`**: Toolchain for Libmpv build (`build-mpvkit-audio.sh`), app packaging (`build-app.sh`), linting (`lint.sh`), and releases (`package-release.sh`).

## Setup & Toolchain
- Run `./scripts/build-mpvkit-audio.sh` once on checkout to build the Libmpv framework for the audio engine fork in `vendor/MPVKit-Audio`.
- `swift test` needs **full Xcode** (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`). `build-app.sh` and `lint.sh` handle this automatically.
- Note on sandboxed CLI: SwiftPM module caching in `/var/folders` and `.git/index.lock` creation may require bypassing the sandbox (`BypassSandbox: true`) when building, testing, or committing via tool commands.

## Delegate research to subagents
- Delegate self-contained research and analysis to subagents instead of doing it in the main thread: file hunts, cross-file impact analysis, and evaluating options/tradeoffs.
- Keep work in the main thread only when the full context matters (editing, deciding the final shape of a change, synthesizing results).
- Ask a subagent to return a concise, actionable summary — then verify its key claims yourself before acting.

## Surgical diffs & codebase footprint (No refactor sprawl)
- **Fix strictly the reported defect**: Make the smallest possible surgical intervention. Target the 1–3 files directly responsible for the symptom. Never patch symptoms in multiple caller files when fixing a bug.
- **Zero opportunistic refactoring**: Never rewrite neighboring methods, change unrelated architecture, add unprompted background tasks/prefetchers, or "clean up" adjacent code while fixing a bug.
- **Do not alter cross-module contracts unless unavoidable**: If a defect is reported in the app UI, solve it in `Klopydrome`. Do not touch `NavidromeClient` (changing public APIs, actor isolation, or model protocols) unless the client library itself is demonstrably broken.
- **Question expanding diffs immediately**: If a bugfix starts touching 4+ files or cascading across layers, stop: you are likely addressing symptoms in multiple downstream places instead of fixing the root cause locally.
- **Distinguish bug fixes from system unification**: While bug fixes must remain strictly localized to 1–3 files at the root cause, systemic improvements and architectural unifications must be applied cohesively across all consumer screens at the shared-entity level (see Deep system unification below).

## Root cause first, workarounds last
- Diagnose the root cause first and fix the cause. Never layer a behavior-changing wrapper over the UI to mask a bug.
- Workarounds only when the user explicitly allows them: small, tightly scoped, documented inline with why the root fix isn't possible, and re-applied on cadence if the system undoes it.

## Rely on native API (API-first consistency)
- **Prioritize native Subsonic/Navidrome API endpoints**: Never build client-side synthetic workarounds or multi-request cascades (e.g. querying search to reconstruct discographies or assembling shelves piecemeal) when the server provides a dedicated endpoint (`getStarred2`, `getAlbumList2`, `getTopSongs`, `getArtistInfo`).
- **Minimize request bursts**: Avoid issuing cascades of round-trips to replicate server logic locally. Group or reuse existing payloads wherever possible.
- **Client-side fallbacks only for genuine QoL features**: Custom local processing or fallback requests are allowed ONLY when the server API genuinely lacks the capability and the feature is an explicit user-facing QoL requirement (e.g. offline synthesis, duplicate addition protection, client-side sort preferences).

## Build, test, run
- `swift build` — compile check; run after any change.
- `swift test` — XCTest suite. Filter a single test: `swift test --filter <TestCase>`.
- `./scripts/build-app.sh [--release]` — builds via Xcode into `.build/app/Klopydrome.app` (ad-hoc signed without hardened runtime, hand-embeds `NavidromeClient.framework`). Prefer over bare `swift run` so macOS activates the app properly.

## Version control & release
- **All changes to the working tree must be committed.** When completing any unit of work, commit it before moving on. There should be no uncommitted changes left behind.
- **Commit hygiene**: Intermediate commits exist for local rollback during active exploration. Before completing a task or submitting for review, squash and rebase unpushed fixup/revert commits into clean, logical conventional commits.
- Write concise, conventional commit messages. Do not push unless explicitly asked.
- Release flow: Makefile `make package` / `make dist` (`scripts/package-release.sh`). Releases are cut by bumping `VERSION`, committing, tagging `vX.Y.Z`, and pushing branch + tag to trigger CI.
- Pre-release commit hygiene: audit commit history since last tag, clean up throwaway fixups/reverts, and get explicit user approval before shipping.

## Cross-module gotchas
- Shared types (`AuthMode`, `SubsonicConfig`, `SubsonicSong`, `SubsonicEnvelope`, `CacheManager`, `CacheKind`) live in `NavidromeClient`. Every file in `Sources/Klopydrome/` MUST `import NavidromeClient`.
- Client internal helpers (`buildURL`, `authQueryItems`, `md5Hex`, `randomSalt`) are accessible to tests via `@testable import NavidromeClient`.

## Language / architecture
- Package uses `swiftLanguageModes: [.v5]`. Shared state uses `@Observable` + `@MainActor` (macOS 14), view-local state uses `@State`/`@Bindable`. Do not introduce strict-concurrency-only APIs.
- `AppState` is injected via `.environment()`. `ServerConfig` is persisted; passwords live in Keychain via `KeychainStore`.
- Caching has two layers: `CacheManager` (disk, `~/Library/Caches/NavidromeSwift` legacy root) and `CoverArtStore` (in-memory).
- **NavigationSplitView detail navigation must use in-memory history**: Never nest a `NavigationStack` inside the `NavigationSplitView` detail column. All detail sub-pages route through `app.nav.history: [Destination]` and `app.navigateBack()`.
- **Detail views must fill all space**: Every detail view inside `DetailColumn` must specify `.frame(maxWidth: .infinity, maxHeight: .infinity)` before `.safeAreaInset` is applied.
- Automix transitions are analysis-only (`Player+TransitionAnalysis.swift`); rendering stays on the established MPV crossfade.

## Code comments & readability (Zero comment bloat)
- **Code must be self-documenting**: Express intent through clear, concise naming of types, variables, and functions. Do NOT add docstrings (`///`) or inline comments (`//`) that simply restate what the code already says.
- **Forbidden**:
  - Tautological comments on properties (e.g. `/// Track duration`, `/// User preference for shuffle`).
  - Obvious step comments (e.g. `// Set up player`, `// Remove track`).
  - Gratuitous `// MARK: - ...` separators for 2–3 line sections or self-evident properties.
- **Allowed only by exception**:
  - Non-obvious C-interop caveats or unsafe pointer lifecycles (e.g. Libmpv C API specifics).
  - Mathematical and audio formulas (e.g. ReplayGain / Automix equal-power crossfade math).
  - Low-level system workarounds (e.g. AppKit event tap quirks, pipe-offset audio seek limitations).

## Architectural discipline (KISS & DRY)
- **Single source of truth for core flows**:
  - All playback initiation must route through a single authoritative entry point in `AppState` (`app.play(...)`), which handles offline filtering, starting index resolution, and player state dispatch. Individual views and menus MUST NOT duplicate offline filtering or index recalculation.
  - Queue operations (`playNext`, `playLater`, `remove`, `clear`) must have unified implementations without diverging overloads for single vs. collection items.
  - Playback source context is restricted strictly to `.album`, `.playlist`, and `.smartPlaylist`. Do not re-introduce synthetic or ad-hoc source types.
- **No overengineered crutches**: Avoid multi-timer cascades, synthetic data reconstruction, or speculative fallback logic. Keep the control flow direct, linear, and predictable.
- **Auto Layout & NSHostingView Container Geometry**:
  - When hosting scrollable SwiftUI views (`ScrollView`, `List`, `LazyVStack`) in an `NSHostingView` inside an AppKit clipping container or drawer:
    1. **Never leave `NSHostingView` unconstrained in the scroll axis**: An unconstrained height (`bottomAnchor >= clipHost.bottomAnchor` without an explicit upper bound) causes SwiftUI to report its entire content height (e.g. 20,000+ pt for 400+ rows) as fitting size. This causes `ScrollView.bounds.height == content.height`, completely breaking `LazyVStack` virtualization (eagerly realizing all rows) and destroying scrollability (rubber-banding at 0 without scrolling).
    2. **Never tie `NSHostingView.bottomAnchor` to `clipHost.bottomAnchor` with `.required` equality during resize animations**: An equality constraint steals space from sibling views. If siblings have 1:1 aspect ratio constraints (such as square artwork), Auto Layout shrinks their width, collapsing the window into an un-resizable miniature pill.
    3. **The established drawer pattern**: Bound the hosted view's height to the intended target height (`heightAnchor.constraint(equalToConstant: targetHeight)` at priority 999) with `bottomAnchor.constraint(greaterThanOrEqualTo: clipHost.bottomAnchor)`. The clipping host masks content during transitions without squeezing adjacent views or allowing unbounded height growth.
- **Scroll Virtualization & Large Collection Performance**:
  - In `ScrollView` + `LazyVStack`, avoid allocating temporary enumerated arrays (`ForEach(Array(list.enumerated()), id: \.offset)`). Use index ranges (`ForEach(0..<list.count, id: \.self)`) or stable identifiers (`id: \.id`).
  - Never attach `NotificationCenter` listeners (e.g. `ScrollGate` observers) or allocate class-based hover trackers inside individual row views (`QueueTrackRow`, `SongRow`). Hover state must remain strictly view-local (`.onHover { hovering = $0 }`).
  - **Streaming API Ingestion & Table Virtualization**: During background streaming or incremental search ingestion (`search3`, library sync), throttle UI table view updates to at most once per second (1 Hz) to prevent layout thrashing and continuous cell mounting during user scrolling. Fast-path cache/download checks with O(1) lookups before touching disk.

## UI conventions & Design System
- **Mandatory reuse of core UI assets — never invent custom duplicates:**
  - `SongTable`: full tabular song list with sorting and columns (used in Songs browser).
  - `SongRow`: standard track row for detail lists (Album, Playlist, Artist, Favorites, Downloads).
  - `CompactSongsSection` / `CompactSongsGrid`: 3-row Apple Music-style compact song blocks/shelves.
  - `AlbumGridView` / `AlbumCard`: standard square album artwork tiles with hover play/actions.
  - `ContentPillCard`: 8pt continuous radius, 40pt artwork thumbnail. Search "Top Results" MUST reuse this canonical pill component from Home Quick Access rather than inventing divergent search cards.
  - `SkeletonKit`: unified shimmer loading skeletons (`SkeletonSongRow`, `SkeletonSongList`, `SkeletonCardGrid`).
- **Context actions have ONE source of truth:**
  - Playlist actions: `PlaylistContextMenuItems` in `PlaylistMenu.swift`.
  - Song actions: `SongActionItems` in `SongMenu.swift`.
  - Album actions: `AlbumContextMenuItems` in `AlbumMenu.swift`.
  - Artist actions: `ArtistContextMenuItems` in `ArtistMenu.swift`.
- **Hit targets are larger than visual glyphs:** Keep padding inside the label and add `.contentShape(Rectangle())`. Action buttons and ellipsis menus must have square, generous hit targets (24–28pt), never restricted to the tiny glyph bounds.
- **No verbose text clutter (self-sufficient, concise UI copy):** Feature names, buttons, menu items, and toggles must be strictly concise and explain their intent on their own. Longer wording is only acceptable when it directly removes ambiguity. Avoid explanatory subtitles under checkboxes/toggles, prose descriptions, and gratuitous hover text (`.help(...)`) on labeled controls — they create visual noise that degrades interface readability. Use standard macOS nouns over verbs ("Offline Mode", "Network"). Standard, concise tooltips remain appropriate only for icon-only controls where meaning is not self-evident.
- **Deep system unification (component coherence):** Ensure components operate collectively through shared sources of truth. Architectural and visual improvements must apply across all related screens at the shared-entity level, rather than being patched ad-hoc in isolated views. Fragmented logic, duplicate components, and divergent user flows are unacceptable.
- **Typography & Font Hierarchy in Track Rows & Applets:**
  - In track rows (`QueueTrackRow`, `CompactSongRow`, `SongRow`, popover lists), Title and Subtitle share equal base font size (`.callout` or 12pt). Visual hierarchy MUST be expressed through font weight (Title: `.medium` or `.semibold` vs Subtitle: `.regular`) and color contrast (`.primary` vs `AMColor.secondaryText`), NEVER by shrinking the subtitle to miniature `.caption` or `.caption2`.
  - **Header Action Buttons (Play / Shuffle pills)**: Action buttons in Album/Playlist detail headers must strictly use `AMFont.actionPill` (14pt, `.semibold`) and icon `AMFont.actionPillIcon` (13pt). Never shrink action button labels to miniature body or caption sizes.
  - **Tile & Count Metadata**: Subtitles displaying item counts (e.g. "%d albums", "%d songs") in Artists and Genres tiles must strictly use `AMFont.rowSubtitle` with `AMColor.secondaryText`. Arbitrary hardcoded point sizes (`9pt`, `10.5pt`) are forbidden.
  - All typography styles must reference semantic styles (`AMFont`) or standard dynamic type scales rather than arbitrary hardcoded point sizes.
- **Consistent Active Track & Hover Presentation:**
  - Active playing track state must be uniform across all row components:
    1. Title text tinted with `AMColor.accent`.
    2. Artwork shows speaker/playing badge overlay.
    3. Row selection / hover uses neutral translucent highlight (`Color.primary.opacity(0.08)` or `AMColor.sidebarSelection`), NEVER a solid full-row colored accent fill that clashes with surrounding rows.
    4. Subtitle remains neutral secondary text (`AMColor.secondaryText`).
- **Card Container & Skeleton Unification:**
  - Standard media cards (Album, Playlist, Smart Playlist) must use the shared card container: 6pt continuous corner radius, 1:1 aspect ratio artwork, 2-line title limit with line reservation, and secondary owner/artist line.
  - Skeletons and loading states must exclusively use `SkeletonKit` (`SkeletonCard`, `SkeletonSongRow`). Private placeholder structs with static non-shimmer rectangles are forbidden.
- **Low Power Mode & Energy Conservation**:
  - Disable infinite decorative animations (such as continuous shimmer sweeps in `Shimmer.swift` and `Components.swift`) when `ProcessInfo.processInfo.isLowPowerModeEnabled`.
  - In Low Power Mode, cap cover art loading resolution to `.low` (240px) to prevent memory and GPU spikes during rapid scrolling.
- `Build`/`lint` gate: `./scripts/lint.sh` enforces code-size thresholds and quality rules. If an edit nears a size limit, extract new code into an extension file rather than raising thresholds.

## Localization & Branding
- Every user-visible string MUST be localized (`Localizable.strings` in `en.lproj` and `ru.lproj`). Flag hard-coded strings.
- **English canonical keys only**: All localization keys in Swift code MUST be in English (e.g. `"Show".localized`, `"Quick Access".localized`). Never write Russian string literals as localization keys in Swift source files (e.g. forbidden: `"Показать".localized`).
- **1:1 key parity**: `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings` must maintain exact 1:1 key parity. `en.lproj` must never contain Cyrillic keys.
- Do not use the app brand name in locale strings. Use generic wording ("Кэш приложения" / "Application cache", not "Кэш Klopydrome").

## Deterministic & locale-agnostic testing
- Tests must be deterministic regardless of system language or region settings.
- **Never assert on localized UI string literals**:
  - Assert underlying domain state, enums, or numeric values instead of formatted strings (e.g. assert `player.isCrossfading == true` and `player.crossfadeRemainingTime == 3.0` rather than checking formatted `"Crossfade · 3 s"`).
  - When testing error dispatch, assert that the error exists or match against the localized format function (`L10n.format(...)`).
