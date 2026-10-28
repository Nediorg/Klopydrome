import SwiftUI
import NavidromeClient

struct LyricsView: View {
    private struct RenderState {
        let activeIndex: Int?
        let scrollDirection: Int
    }

    @Environment(AppState.self) var app
    @State private var autoScrollEnabled = true
    @State private var isUserScrolling = false
    private var isBrowsing: Bool { !autoScrollEnabled || isUserScrolling }
    @State private var scrollTargetID: Int?
    @State private var lastFollowDate = Date.distantPast
    @State private var lineFrames: [Int: CGRect] = [:]
    @State private var scrollCoordinator: LyricsScrollAnimator.Coordinator?
    @State private var lyricRenderClock = LyricsRenderClock()
    @State private var clockActiveIndex: Int?
    @State private var scrollDirection: Int = 1
    @State private var seekGuardIndex: Int?
    @State private var seekGuardUntil = Date.distantPast
    private let lyricSpacing: CGFloat = 4
    private let lyricHorizontalPadding: CGFloat = 40
    let syncStep: Double = 0.25

    private let followLockout: TimeInterval = 1.2
    static let followDuration: TimeInterval = 0.4
    private static let lyricsScrollSpace = "lyricsScrollSpace"
    private static let lineLead: Double = 0.115
    private static let richLineLead: Double = 0.150
    var body: some View {
        Group {
            if app.lyrics.isLoading && app.lyrics.syncedLines.isEmpty && app.lyrics.plainText == nil {
                ProgressView("Loading lyrics…".localized)
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
                Text("Lyrics not found.".localized)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            refreshClockAndIndex()
        }
        .task(id: app.player.displaySong?.id) {
            guard let song = app.player.displaySong else { return }
            await app.lyrics.load(song: song, client: app.client, cache: app.cache)
        }
        .background {
            LyricsClockSynchronizer(onSync: refreshClockAndIndex)
        }
        .onChange(of: app.lyrics.loadedForSongID) { _, _ in
            autoScrollEnabled = true
            refreshClockAndIndex()
        }
    }

    private var effectivePlaybackTime: Double {
        (app.player.currentTime * app.lyrics.timeRate)
            + app.lyrics.timeOffsetSeconds
            + app.serverConfig.effectiveLyricsDefaultOffset
            + leadSeconds
    }

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
                    lineFrames = newFrames
                    scrollCoordinator?.lineFrames = newFrames
                    if scrollTargetID == nil, let index = clockActiveIndex {
                        follow(to: index)
                    }
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
                            Text("To Current Line".localized)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(AMColor.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(AMColor.primaryText.opacity(0.18), lineWidth: 0.5)
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
            .onChange(of: scrollCoordinator) { _, coord in
                guard let coord else { return }
                coord.lineFrames = lineFrames
                if autoScrollEnabled, let index = clockActiveIndex {
                    follow(to: index)
                }
            }
        }
        .onChange(of: scrollTargetID) { _, newID in
            guard autoScrollEnabled, newID != clockActiveIndex else { return }
            guard Date.now.timeIntervalSince(lastFollowDate) > followLockout else { return }
            autoScrollEnabled = false
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
            let playing = app.player.isPlaying && !app.player.isBuffering && !app.player.isLoading
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
                fillLive: live && playing,
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

    private func lineText(at index: Int?) -> String? {
        guard let index, app.lyrics.syncedLines.indices.contains(index) else { return nil }
        return app.lyrics.syncedLines[index].value
    }

    private func follow(to index: Int) {
        lastFollowDate = Date.now
        guard let animator = scrollCoordinator,
              let scrollView = animator.scrollView,
              let frame = animator.lineFrames[index] ?? lineFrames[index] else { return }
        if animator.lineFrames.isEmpty && !lineFrames.isEmpty {
            animator.lineFrames = lineFrames
        }
        let viewport = scrollView.contentView.bounds.height
        let anchorY = viewport * 0.50
        let offset = max(0, frame.midY - anchorY)
        animator.animate(to: offset, duration: Self.followDuration)
    }

    private func resumeFollowing() {
        autoScrollEnabled = true
        guard let index = clockActiveIndex else { return }
        follow(to: index)
    }

    private func centerInitialLine() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard autoScrollEnabled, let index = clockActiveIndex else { return }
            follow(to: index)
        }
    }

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

    static func lineWrapWidth(viewportWidth: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
        max(0, (viewportWidth - horizontalPadding * 2) / KaraokeLine.maxLineScale)
    }

    func lyricState(index: Int, activeIndex: Int?) -> LyricLineState {
        guard let active = activeIndex else { return .future }
        if index < active { return .past }
        if index == active { return .now }
        return .future
    }

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
}
