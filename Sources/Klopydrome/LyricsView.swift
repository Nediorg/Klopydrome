import SwiftUI
import NavidromeClient

/// Apple Music-style karaoke lyrics, driven by the native `ScrollView` +
/// `scrollPosition(id:anchor:)` (macOS 14+): auto-follows the active line with
/// a spring, scrolling freely pauses auto-follow and reveals a Sync button,
/// tapping a line seeks to its timestamp.
struct LyricsView: View {
    private struct RenderState {
        let activeIndex: Int?
        let scrollDirection: Int
    }

    @Environment(AppState.self) var app
    /// When the user scrolls the lyrics manually, auto-follow disables and a
    /// Sync button appears; tapping it re-enables auto-follow for this song.
    @State private var autoScrollEnabled = true
    @State private var isUserScrolling = false
    private var isBrowsing: Bool { !autoScrollEnabled || isUserScrolling }
    /// The lyric line currently centered in the viewport.
    @State private var scrollTargetID: Int?
    @State private var lastFollowDate = Date.distantPast
    /// Line frames measured in the scroll content's own coordinate space
    /// (`LyricsLineFrameKey`): the follow centers `lineFrames[index].midY`.
    @State private var lineFrames: [Int: CGRect] = [:]
    /// The animator that glides the backing `NSScrollView` (see
    /// `LyricsScrollAnimator`), handed over once the scroll hierarchy lays out.
    @State private var scrollCoordinator: LyricsScrollAnimator.Coordinator?
    @State private var lyricRenderClock = LyricsRenderClock()
    /// Active line resolved from the INTERPOLATED render clock (driver below),
    /// not the coarse 4 Hz player ticks — so highlight and follow agree with
    /// the word coloring between samples.
    @State private var clockActiveIndex: Int?
    @State private var scrollDirection: Int = 1
    /// Post-seek guard: after a tap-seek the driver still sees pre-seek
    /// samples for a beat; without this it yanks the viewport back to the
    /// old line (reads as "jumped to the nearest"). Index writes disagreeing
    /// with the seek target are skipped until landing or 1 s timeout.
    @State private var seekGuardIndex: Int?
    @State private var seekGuardUntil = Date.distantPast
    private let lyricSpacing: CGFloat = 4
    private let lyricHorizontalPadding: CGFloat = 40
    /// Step of the sync-correction buttons, in seconds.
    let syncStep: Double = 0.25

    /// How long a follow glide's `scrollTargetID` writes are ignored after a
    /// programmatic follow. Must exceed the follow glide (see
    /// `followDuration`) with margin — and be well below the line cadence
    /// (2–3s) so a genuine user scroll within the next line still disables
    /// auto-follow.
    private let followLockout: TimeInterval = 1.2
    /// Follow glide duration: a bounded ease-in-out (no spring overshoot/ring),
    /// long enough that the step between lines reads as motion, not a teleport,
    /// yet short enough that the centered line still settles within the current
    /// line's airtime. Static so the glide test drives the exact app value.
    static let followDuration: TimeInterval = 0.4
    /// Coordinate space name for measuring line frames in scroll-content space.
    private static let lyricsScrollSpace = "lyricsScrollSpace"
    /// Early-activation lead: the highlight turns on a hair BEFORE the recorded
    /// timestamp, matching the LRC `SYNC_TIMING_OFFSET_MS` convention.
    /// Word-level (rich) cues need a touch more than plain line-level lyrics.
    private static let lineLead: Double = 0.115
    private static let richLineLead: Double = 0.150
    /// The viewport follows the same effective clock as word coloring and the
    /// active line. It never preselects a future row; this prevents the list
    /// from drifting independently while the current words are still singing.
    var body: some View {
        Group {
            if app.lyrics.isLoading && app.lyrics.syncedLines.isEmpty && app.lyrics.plainText == nil {
                ProgressView("Загрузка текста…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !app.lyrics.syncedLines.isEmpty {
                syncedLyrics
            } else if let text = app.lyrics.plainText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(.title3, design: .default))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            } else {
                Text("Текст песни не найден.".localized)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            refreshClockAndIndex()
        }
        // Self-healing fetch: preloaded MPV transitions skip Player's
        // onTrackRequest hook, so the store can keep a previous song's text
        // until something re-requests it. Re-run on appear and on every song
        // change while visible; the store deduplicates by song id.
        .task(id: app.player.displaySong?.id) {
            guard let client = app.client, let song = app.player.displaySong else { return }
            await app.lyrics.load(song: song, client: client)
        }
        .background {
            LyricsClockSynchronizer(onSync: refreshClockAndIndex)
        }
        // New song → re-enable auto-scroll so the next track starts following.
        .onChange(of: app.lyrics.loadedForSongID) { _, _ in
            autoScrollEnabled = true
            refreshClockAndIndex()
        }
    }

    /// Playback time shifted by the user's sync correction, global calibration,
    /// and the early activation lead.
    private var effectivePlaybackTime: Double {
        (app.player.currentTime * app.lyrics.timeRate)
            + app.lyrics.timeOffsetSeconds
            + app.serverConfig.effectiveLyricsDefaultOffset
            + leadSeconds
    }

    /// Follow and word coloring share one temporal source: a line becomes the
    /// scroll target only when it is the active lyric line on the effective
    /// playback clock. Each line reports its frame in the scroll content's own
    /// coordinate space (`LyricsLineFrameKey`); the follow glides the backing
    /// `NSScrollView` clip bounds to center that frame, animated with an
    /// explicit duration via `LyricsScrollAnimator` — SwiftUI's own programmatic
    /// scroll paths all snap (their scroll animation is a fixed fast glide,
    /// regardless of the requested animation). The `scrollPosition` binding is
    /// kept purely as the user-scroll detector: it reports the centered line
    /// while the user scrolls, and a value that arrives after the follow
    /// animation has settled (see `followLockout`) disables auto-follow.
    /// Transparent half-viewport edge zones keep the first and last lyric lines
    /// able to reach the visual center.
    private var syncedLyrics: some View {
        let renderState = RenderState(
            activeIndex: clockActiveIndex,
            scrollDirection: scrollDirection
        )
        return GeometryReader { geo in
            let lineWrapWidth = Self.lineWrapWidth(
                viewportWidth: geo.size.width,
                horizontalPadding: lyricHorizontalPadding
            )
            ScrollView {
                VStack(spacing: lyricSpacing) {
                    Color.clear
                        .frame(height: Self.edgeInset(for: geo.size.height))
                        .accessibilityHidden(true)

                    ForEach(app.lyrics.syncedLines.indices, id: \.self) { index in
                        staggeredLyricLine(
                            line: app.lyrics.syncedLines[index],
                            index: index,
                            words: app.lyrics.cachedDisplayWords(for: index),
                            renderState: renderState,
                            wrapWidth: lineWrapWidth
                        )
                        .id(index)
                        .background(GeometryReader { lineGeo in
                            Color.clear.preference(
                                key: LyricsLineFrameKey.self,
                                value: [index: lineGeo.frame(in: .named(Self.lyricsScrollSpace))]
                            )
                        })
                    }

                    Color.clear
                        .frame(height: Self.edgeInset(for: geo.size.height))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, lyricHorizontalPadding)
                .scrollTargetLayout()
                .coordinateSpace(name: Self.lyricsScrollSpace)
                .onPreferenceChange(LyricsLineFrameKey.self) { newFrames in
                    scrollCoordinator?.lineFrames = newFrames
                    if lineFrames != newFrames { lineFrames = newFrames }
                }
                .background(alignment: .top) {
                    LyricsScrollAnimator(coordinator: $scrollCoordinator) { isScrolling in
                        isUserScrolling = isScrolling
                        if isScrolling && autoScrollEnabled {
                            autoScrollEnabled = false
                        }
                    }
                    .frame(width: 0, height: 0)
                }
            }
            .scrollPosition(id: $scrollTargetID, anchor: .center)
            .scrollIndicators(.hidden)
            .background { clockIndexDriver }
            .overlay(alignment: .bottom) {
                if !autoScrollEnabled {
                    Button(action: resumeFollowing) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 11, weight: .semibold))
                            Text("К текущей строке".localized)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.20), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.32, dampingFraction: 0.88), value: autoScrollEnabled)
                }
            }

            .onChange(of: clockActiveIndex, initial: true) { oldIndex, newIndex in
                if let old = oldIndex, let new = newIndex, new != old {
                    scrollDirection = new >= old ? 1 : -1
                }
                guard autoScrollEnabled, let index = newIndex else { return }
                follow(to: index)
            }
            .onAppear {
                centerInitialLine()
            }
        }
        // The `scrollPosition` binding reports the centered line as the user
        // scrolls; a value that arrives after the follow animation has settled
        // (see `followLockout`) is a real user scroll.
        .onChange(of: scrollTargetID) { _, newID in
            guard autoScrollEnabled, newID != clockActiveIndex else { return }
            guard Date.now.timeIntervalSince(lastFollowDate) > followLockout else { return }
            autoScrollEnabled = false
        }
    }
}

// MARK: - Subviews & Scrolling

extension LyricsView {
    @ViewBuilder
    private func staggeredLyricLine(
        line: SyncedLine,
        index: Int,
        words: [SyncedWord]?,
        renderState: RenderState,
        wrapWidth: CGFloat
    ) -> some View {
        let text = line.value ?? ""
        let motion = app.serverConfig.effectiveLyricsAnimationMotion
        let blurEnabled = app.serverConfig.effectiveLyricsBlurEnabled
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let dist = index - (renderState.activeIndex ?? index)
            let playing = app.player.isPlaying && !app.player.isBuffering && !app.player.isLoading
            LyricsPauseMarker(
                progress: 0,
                renderClock: lyricRenderClock,
                pauseRange: pauseRange(at: index),
                index: index,
                activeLineIndex: renderState.activeIndex,
                scrollDirection: renderState.scrollDirection,
                lineDistance: dist,
                isBrowsing: isBrowsing,
                isPlaying: playing,
                motion: motion,
                blurEnabled: blurEnabled,
                countdownEnabled: true
            ) {
                seekToLine(index)
            }
            .equatable()
            .id(index)
        } else {
            let live = renderState.activeIndex == index
            let fontSize = app.serverConfig.effectiveLyricsFontSize
            KaraokeLine(
                text: text,
                lineStart: line.start.map { $0 / 1000 },
                currentTime: line.start.map { $0 / 1000 } ?? 0,
                renderClock: lyricRenderClock,
                state: lyricState(index: index, activeIndex: renderState.activeIndex),
                index: index,
                activeLineIndex: renderState.activeIndex,
                scrollDirection: renderState.scrollDirection,
                words: words,
                maxLayoutWidth: wrapWidth,
                fillLive: live,
                isBrowsing: isBrowsing,
                fontSize: fontSize,
                motion: motion,
                blurEnabled: blurEnabled
            ) {
                seekToLine(index)
            }
            .equatable()
            .id(index)
        }
    }

    /// The current lyric text for an index (nil for no/plain lyrics), so the
    /// debug audit shows WHICH line the highlight is on, not just the number.
    private func lineText(at index: Int?) -> String? {
        guard let index, app.lyrics.syncedLines.indices.contains(index) else { return nil }
        return app.lyrics.syncedLines[index].value
    }

    // MARK: Scrolling

    /// Animate the viewport so line `index` is centered. The glide runs on the
    /// backing `NSScrollView` with an explicit duration (SwiftUI's programmatic
    /// scroll paths all snap), eased in and out (no spring overshoot, which
    /// read as the lyrics "drifting" in time, and no ring when lines step every
    /// 2–3s). Marks `lastFollowDate` so the `scrollPosition` binding's writes
    /// during the glide are not mistaken for a user scroll.
    private func follow(to index: Int) {
        lastFollowDate = Date.now
        guard !app.player.isBuffering, !app.player.isLoading else { return }
        guard let animator = scrollCoordinator,
              let scrollView = animator.scrollView,
              let frame = animator.lineFrames[index] ?? lineFrames[index] else { return }
        let viewport = scrollView.contentView.bounds.height
        let anchorY = viewport * 0.50
        let offset = max(0, frame.midY - anchorY)
        animator.animate(to: offset, duration: Self.followDuration)
    }

    /// Re-enable auto-follow and glide back to the current line.
    private func resumeFollowing() {
        autoScrollEnabled = true
        guard let index = clockActiveIndex else { return }
        follow(to: index)
    }

    /// Center the first active line once the panel settles.
    private func centerInitialLine() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard autoScrollEnabled, !app.player.isBuffering, !app.player.isLoading,
                  let index = clockActiveIndex else { return }
            follow(to: index)
        }
    }

    /// Handoff driver: resolves the active line from the interpolated render clock.
    private var clockIndexDriver: some View {
        let paused = !app.player.isPlaying || app.player.isBuffering || app.player.isLoading
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { _ in
            let time = lyricRenderClock.currentTime
            if !app.player.isBuffering && !app.player.isLoading {
                let guardActive = seekGuardIndex != nil && Date.now < seekGuardUntil
                let index: Int? = guardActive
                    ? seekGuardIndex
                    : { seekGuardIndex = nil; return app.lyrics.activeLineIndex(at: time) }()
                Color.clear
                    .onChange(of: index, initial: true) { _, newIndex in
                        if newIndex != clockActiveIndex { clockActiveIndex = newIndex }
                    }
            }
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Seek to a tapped lyric line's timestamp and follow it.
    private func seekToLine(_ index: Int) {
        guard index >= 0, index < app.lyrics.syncedLines.count,
              let startMs = app.lyrics.syncedLines[index].start else { return }
        if let current = clockActiveIndex, index != current {
            scrollDirection = index >= current ? 1 : -1
        }
        let recorded = startMs / 1000
        let effectiveOffset = app.lyrics.timeOffsetSeconds + app.serverConfig.effectiveLyricsDefaultOffset
        let target = (recorded - effectiveOffset - leadSeconds) / app.lyrics.timeRate
        app.player.endScrub(at: max(0, target))
        synchronizeRenderClock()
        seekGuardIndex = index
        seekGuardUntil = Date.now.addingTimeInterval(1)
        clockActiveIndex = index
        autoScrollEnabled = true
        follow(to: index)
    }

    private static func edgeInset(for viewportHeight: CGFloat) -> CGFloat {
        max(0, viewportHeight * 0.50)
    }

    /// Width the unscaled lyric text may wrap at.
    static func lineWrapWidth(viewportWidth: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
        max(0, (viewportWidth - horizontalPadding * 2) / KaraokeLine.maxLineScale)
    }

    /// 0-, 3-state styling for a lyric line.
    func lyricState(index: Int, activeIndex: Int?) -> LyricLineState {
        guard let active = activeIndex else { return .future }
        if index < active { return .past }
        if index == active { return .now }
        return .future
    }

    /// Lead for the CURRENT lyrics: word-level (rich) cues get 150ms, plain
    /// line-level synced lyrics 115ms. Word timing may come from server
    /// `cueLine` blocks OR inline `<m:ss.xx>`
    /// markers (old Navidrome emits neither as structured cues; the active
    /// line is still word-synced when its parse splits into several chunks).
    ///
    /// Pure function of STATIC lyrics state (no `activeIndex`/probe — that
    /// would recurse through `effectivePlaybackTime`).
    private var leadSeconds: Double {
        if !app.lyrics.wordsByLine.isEmpty { return Self.richLineLead }
        let hasInlineMarkers = app.lyrics.syncedLines.contains {
            ($0.value ?? "").contains("<")
        }
        return hasInlineMarkers ? Self.richLineLead : Self.lineLead
    }

    private func synchronizeRenderClock() {
        let playing = app.player.isPlaying && !app.player.isBuffering && !app.player.isLoading
        lyricRenderClock.synchronize(
            time: effectivePlaybackTime,
            isPlaying: playing,
            rate: app.lyrics.timeRate
        )
    }

    /// Re-anchor the interpolation clock to the latest authoritative sample
    /// and refresh the handoff index immediately.
    private func refreshClockAndIndex() {
        synchronizeRenderClock()
        let time = lyricRenderClock.currentTime
        guard !app.player.isBuffering, !app.player.isLoading else {
            return
        }
        let index = app.lyrics.activeLineIndex(at: time)
        if let guardIndex = seekGuardIndex,
           Date.now < seekGuardUntil, index != guardIndex { return }
        seekGuardIndex = nil
        if index != clockActiveIndex { clockActiveIndex = index }
    }

    private func pauseRange(at index: Int) -> ClosedRange<Double>? {
        guard let pauseEnd = nextLyricStart(after: index),
              let pauseStart = pauseStart(at: index),
              pauseEnd > pauseStart else { return nil }
        return pauseStart...pauseEnd
    }

    private func pauseStart(at index: Int) -> Double? {
        guard let timestamp = app.lyrics.syncedLines[index].start.map({ $0 / 1000 }) else {
            return nil
        }
        guard let previousIndex = previousLyricIndex(before: index),
              let wordEnd = app.lyrics.wordsByLine[previousIndex]?.compactMap(\.end).max(),
              wordEnd >= 0, wordEnd <= timestamp else { return timestamp }
        return wordEnd
    }

    private func nextLyricStart(after index: Int) -> Double? {
        app.lyrics.syncedLines.indices.dropFirst(index + 1)
            .first { !isPause(app.lyrics.syncedLines[$0]) && app.lyrics.syncedLines[$0].start != nil }
            .flatMap { app.lyrics.syncedLines[$0].start.map { $0 / 1000 } }
    }

    private func previousLyricIndex(before index: Int) -> Int? {
        (0..<index).reversed().first { !isPause(app.lyrics.syncedLines[$0]) }
    }

    private func isPause(_ line: SyncedLine) -> Bool {
        (line.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Dedicated subview isolating high-frequency player clock observation so that
/// `LyricsView.body` does not re-evaluate on every playback tick (4 Hz / 60 Hz).
private struct LyricsClockSynchronizer: View {
    @Environment(AppState.self) private var app
    let onSync: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: app.player.currentTime) { _, _ in onSync() }
            .onChange(of: app.player.isPlaying) { _, _ in onSync() }
            .onChange(of: app.player.isBuffering) { _, _ in onSync() }
            .onChange(of: app.player.isLoading) { _, _ in onSync() }
            .onChange(of: app.lyrics.timeRate) { _, _ in onSync() }
            .onChange(of: app.lyrics.timeOffsetSeconds) { _, _ in onSync() }
            .onChange(of: app.serverConfig.lyricsDefaultOffset) { _, _ in onSync() }
    }
}
