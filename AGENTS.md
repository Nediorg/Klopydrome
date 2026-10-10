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
    - Detail views: `AlbumDetailView.swift`, `ArtistDetailView.swift`, `PlaylistDetailView.swift`.
    - Browsers: `SongsView.swift`, `SongTable.swift`, `PlaylistsView.swift`, `ArtistsView.swift`.
    - Playback UI & Lyrics: `MiniPlayerView.swift`, `PlayerLCDView.swift`, `LyricsView.swift`, `KaraokeLineView.swift`.
    - Settings: `AppSettingsView.swift` (`PlaybackSettingsView`, `CacheSettingsView`, `AppearanceSettingsView`).
  - **Smart Playlists**: `SmartQuery.swift`, `SmartFields.swift`, `SmartPlaylistEngine.swift`, `SmartPlaylistEditorView.swift`.
  - **Offline & Persistence**: `OfflineRepository.swift`, `SwiftDataOfflineRepository.swift`, `OfflineMutationQueue.swift`, `KeychainStore.swift`, `ServerConfig.swift`.
  - **Design System & Artwork**: `CoverArtView.swift`, `CoverArtStore.swift`, `SongTable.swift`, `AlbumGridView.swift`, `CompactSongsGrid.swift`, `ContentPillCard.swift`, `Components.swift`, `Theme.swift`.
- **`Tests/`**: `NavidromeClientTests/` (API and URL building tests) and `KlopydromeTests/` (player, offline, cache, UI logic tests).
- **`scripts/`**: Toolchain for Libmpv build (`build-mpvkit-audio.sh`), app packaging (`build-app.sh`), linting (`lint.sh`), and releases (`package-release.sh`).

## Setup & Toolchain
- Run `./scripts/build-mpvkit-audio.sh` once on checkout to build the Libmpv framework for the audio engine fork in `vendor/MPVKit-Audio`.
- `swift test` needs **full Xcode** (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`). `build-app.sh` and `lint.sh` handle this automatically.

## Delegate research to subagents
- Delegate self-contained research and analysis to subagents (`explore`, `general`, `swift-expert`, `swiftui-expert`) instead of doing it in the main thread: file hunts, cross-file impact analysis, and evaluating options/tradeoffs.
- Keep work in the main thread only when the full context matters (editing, deciding the final shape of a change, synthesizing results).
- Ask a subagent to return a concise, actionable summary — then verify its key claims yourself before acting.

## Surgical diffs & codebase footprint (No refactor sprawl)
- **Fix strictly the reported defect**: Make the smallest possible surgical intervention. Target the 1–3 files directly responsible for the symptom.
- **Zero opportunistic refactoring**: Never rewrite neighboring methods, change unrelated architecture, add unprompted background tasks/prefetchers, or "clean up" adjacent code while fixing a bug.
- **Do not alter cross-module contracts unless unavoidable**: If a defect is reported in the app UI, solve it in `Klopydrome`. Do not touch `NavidromeClient` (changing public APIs, actor isolation, or model protocols) unless the client library itself is demonstrably broken.
- **Question expanding diffs immediately**: If a bugfix starts touching 4+ files or cascading across layers, stop: you are likely addressing symptoms in multiple downstream places instead of fixing the root cause locally.

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
- Write concise, conventional commit messages. Do not push unless explicitly asked.
- Release flow: Makefile `make package` / `make dist` (`scripts/package-release.sh`). Releases are cut by bumping `VERSION`, committing, tagging `vX.Y.Z`, and pushing branch + tag to trigger CI.
- Pre-release commit hygiene: audit commit history since last tag, clean up throwaway fixups/reverts, and get explicit user approval before shipping.

## Cross-module gotchas
- Shared types (`AuthMode`, `SubsonicConfig`, `SubsonicSong`, `SubsonicEnvelope`, `CacheManager`, `CacheKind`) live in `NavidromeClient`. Every file in `Sources/Klopydrome/` MUST `import NavidromeClient`.
- Client internal helpers (`buildURL`, `authQueryItems`, `md5Hex`, `randomSalt`) are accessible to tests via `@testable import NavidromeClient`.

## Language / architecture
- Package uses `swiftLanguageModes: [.v5]`. Shared state uses `@Observable` + `@MainActor` (macOS 14), view-local state uses `@State`/`@Bindable`. Do not introduce strict-concurrency-only APIs.
- `AppState` is injected via `.environment()`. `ServerConfig` is persisted; passwords live in Keychain via `KeychainStore`.
- Caching has two layers: `CacheManager` (disk, `~/Library/Caches/NavidromeSwift`) and `CoverArtStore` (in-memory).
- **NavigationSplitView detail navigation must use in-memory history**: Never nest a `NavigationStack` inside the `NavigationSplitView` detail column. All detail sub-pages route through `app.nav.history: [Destination]` and `app.navigateBack()`.
- **Detail views must fill all space**: Every detail view inside `DetailColumn` must specify `.frame(maxWidth: .infinity, maxHeight: .infinity)` before `.safeAreaInset` is applied.
- Automix transitions are analysis-only (`Player+TransitionAnalysis.swift`); rendering stays on the established MPV crossfade.

## UI conventions & Design System
- **Mandatory reuse of core UI assets — never invent custom duplicates:**
  - `SongTable`: full tabular song list with sorting and columns.
  - `CompactSongsSection` / `CompactSongsGrid`: 3-row Apple Music-style compact song blocks/shelves.
  - `AlbumGridView` / `AlbumCard`: standard square album artwork tiles with hover play/actions.
  - Content pills (`TopResultSongCard`, `TopResultArtistCard`, `ContentPillCard`): 8pt continuous radius, 40pt artwork thumbnail.
- **Context actions have ONE source of truth:**
  - Playlist actions: `PlaylistContextMenuItems` in `PlaylistMenu.swift`.
  - Song actions: `SongActionItems` in `SongMenu.swift`.
- **Hit targets are larger than visual glyphs:** Keep padding inside the label and add `.contentShape(Rectangle())`. Action buttons and ellipsis menus must have square, generous hit targets (24–28pt), never restricted to the tiny glyph bounds.
- **No verbose text clutter & accurate terminology:** Use standard macOS nouns over verbs ("Офлайн-режим", "Сеть"). No explanatory text walls or redundant counters in persistent chrome.
- `Build`/`lint` gate: `./scripts/lint.sh` uses a baseline. If an edit nears a size limit, extract new code into an extension file rather than raising thresholds.

## Localization & Branding
- Every user-visible string MUST be localized (`Localizable.strings` in `en.lproj` and `ru.lproj`). Flag hard-coded strings.
- Do not use the app brand name in locale strings. Use generic wording ("Кэш приложения" / "Application cache", not "Кэш Klopydrome").
