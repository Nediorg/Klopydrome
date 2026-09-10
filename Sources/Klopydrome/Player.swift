// swiftlint:disable file_length
import Foundation
import AppKit
import NavidromeClient
import AVFoundation
import MediaPlayer
import Observation

/// Which audio suffixes AVPlayer can decode natively on macOS. Everything else
/// (ogg/vorbis, opus, ac3, ape, wma, wv, dsd, …) must be transcoded by the
/// server — we request that via the Subsonic `stream` `format` parameter.
enum PlaybackFormat {
    static let nativelyPlayable: Set<String> = [
        "mp3", "mp2", "m4a", "mp4", "m4b", "m4p", "aac", "alac",
        "flac", "wav", "wave", "aif", "aiff", "aifc", "caf", "amr",
        "mov", "m4v", "3gp", "3g2",
    ]

    /// Suffixes that indicate a lossless source (for UI badges).
    static let lossless: Set<String> = [
        "flac", "alac", "wav", "wave", "aiff", "aif", "aifc", "ape", "wv", "dsf", "dff",
    ]

    /// True when AVPlayer cannot play this suffix and the server must transcode.
    static func needsTranscode(_ suffix: String?) -> Bool {
        guard let suffix = suffix?.lowercased(), !suffix.isEmpty else { return false }
        return !nativelyPlayable.contains(suffix)
    }

    static func isLossless(_ suffix: String?) -> Bool {
        guard let suffix = suffix?.lowercased() else { return false }
        return lossless.contains(suffix)
    }
}

/// AVPlayer-based playback engine. Queue management, transport controls and
/// position tracking. Source resolution is delegated back to the app through
/// `onTrackRequest`.
@MainActor
@Observable
final class Player {
    enum RepeatMode: Equatable {
        case off
        case all
        case one
    }

    var queue: [SubsonicSong] = []
    var currentIndex = 0
    var isPlaying = false
    /// Observable UI state: true only while two MPV contexts overlap.
    var isCrossfading = false
    /// User preference for preparing the queue successor to eliminate the
    /// source-resolution pause at a natural track transition.
    var nextTrackPreloadingEnabled = true
    var isLoading = false
    /// True while AVPlayer is waiting for more data (actual buffering/stall),
    /// not while we merely cache ahead. Drives the mini-bar's loading sweep.
    var isBuffering = false
    var isCaching = false
    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Float = 1.0 {
        didSet {
            avPlayer.volume = outputGain
            mpvEngine.volume = outputGain
        }
    }
    var outputGain: Float { PlaybackVolume.outputGain(for: volume) }
    var lastError: String?

    var shuffle = false
    /// The user's shuffle choice persists across launches and is applied when
    /// the next non-empty queue is loaded.
    @ObservationIgnored var shufflePreferenceEnabled = false
    var repeatMode: RepeatMode = .off

    /// Tracks that have been started, most recent last (used by the queue panel History tab).
    var history: [SubsonicSong] = []

    /// Called when the player needs the app to resolve and start a track.
    var onTrackRequest: ((SubsonicSong) -> Void)?
    /// Notifies the app after a meaningful playback-state transition.
    @ObservationIgnored var onDiscordPresenceUpdate: (() -> Void)?
    /// Called when the current item finishes (for advancing the queue).
    var onTrackEnded: (() -> Void)?
    var onTrackCrossfaded: ((SubsonicSong) -> Void)?
    var onStreamRecordFinished: ((URL) -> Void)?

    /// The shared playback engine. Internal so the seek/formatting
    /// extensions (in separate files) can drive it.
    let avPlayer = AVPlayer()
    /// Active playback engine. MPV by default (every format, sample-accurate
    /// HTTP seeks — libmpv reads the seektable and range-requests the exact
    /// byte offset); AVPlayer when the user opts out in Settings.
    enum EngineKind { case avPlayer, mpv }
    private(set) var engineKind: EngineKind = .avPlayer
    var mpvEngine = MPVPlaybackEngine()
    @ObservationIgnored var mpvFailureFallback = MPVFailureFallback()
    let automix = AutomixPreparation()
    let shuffleState = ShuffleState()
    nonisolated(unsafe) var timeObserverToken: Any?
    nonisolated(unsafe) var endObserver: NSObjectProtocol?
    nonisolated(unsafe) var statusObserver: NSKeyValueObservation?
    nonisolated(unsafe) var itemStatusObserver: NSKeyValueObservation?
    var lastInfoSecond = -1
    @ObservationIgnored var nowPlayingArtworkTask: Task<Void, Never>?
    @ObservationIgnored var systemMediaActivationObserver: NSObjectProtocol?
    var hasReportedFailure = false

    /// True once the current track has been loaded into the active engine, so
    /// Play can resume it directly instead of re-resolving the source.
    var hasLoadedItem: Bool {
        engineKind == .mpv ? mpvEngine.isLoaded : avPlayer.currentItem != nil
    }

    /// True while the user is actively scrubbing. The periodic time observer
    /// is suspended during the scrub so it can't fight the drag preview.
    @ObservationIgnored var isScrubbing = false

    /// Seek position requested before the current item is seekable (track
    /// still loading/transcoding). Applied once the item is actually loaded,
    /// so a lyric tap or scrubber drag during load is not lost. Also reused to
    /// coalesce rapid seeks while a transcode-restart pipe is settling.
    @ObservationIgnored var pendingSeekTime: Double?

    /// Absolute start time of the current MPV stream (seconds). Zero for local
    /// files and range-seekable streams; after a live-transcode restart it
    /// holds the `timeOffset` the server started from, mapping mpv's
    /// pipe-relative clock back to the real track position everywhere (timers,
    /// lyrics, scrubber, preload/crossfade triggers).
    @ObservationIgnored var mpvStreamOffset: Double = 0

    /// Intended position of the most recent seek, held on screen until the
    /// engine's real position actually catches up. Prevents the timeline from
    /// snapping back to 0 (or the pre-seek position) while a fresh load or a
    /// transcode restart is still landing.
    @ObservationIgnored var heldSeekTarget: Double?

    /// Fractional remainder of a transcode-restart target (seconds past the
    /// integer `timeOffset` the server starts from). Applied as a small
    /// in-pipe seek once the fresh pipe is loaded, so playback resumes at the
    /// exact position the user asked for.
    @ObservationIgnored var transcodeRestartResidual: Double?

    /// True once a restart's fresh pipe has actually been loaded and stepped
    /// onto its target (residual seek applied, play/pause restored). Ticks
    /// before that point carry either the old pipe's pre-restart position or
    /// the newborn pipe's 0 — with the wrong offset added they look like a
    /// target that's already been reached (or far beyond it) and would release
    /// the held clock and roll the marker back. Suppressed until this flips.
    @ObservationIgnored var mpvRestartStepped = false

    /// True while the current MPV stream is a server-restarted live transcode
    /// (a non-seekable pipe). Every later big seek restarts the stream instead
    /// of relying on libmpv, even if a duration eventually appears.
    @ObservationIgnored var mpvSeekRestartActive = false

    /// Bumped for each MPV load; a stale load's completion must not clobber
    /// the state of a newer request (rapid seeks, track changes).
    @ObservationIgnored var mpvLoadGeneration = 0

    /// True while a precise seek is still landing (AVPlayer seek is
    /// asynchronous). The time observer leaves `currentTime` alone then, so
    /// the lyrics/scrubber don't jump back to the old position mid-flight.
    @ObservationIgnored var isSeekInFlight = false

    /// Monotonic counter so an outdated seek's completion can't clear the
    /// in-flight flag belonging to a newer seek.
    @ObservationIgnored var seekRequestID = 0

    /// Track length usable before the engine reports one, and as a guard
    /// against a transcoded stream's under-reported demuxer duration (VBR or
    /// `estimateContentLength` mismatch). The server's `song.duration` is the
    /// authoritative length — the scrubber and timers always show the larger
    /// of the two so a 0:29 / -0:10 negative-remaining glitch can't happen.
    var trackDuration: Double {
        let meta = Double(currentSong?.duration ?? 0)
        if duration > 0 { return max(duration, meta) }
        return meta
    }

    init() {
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        avPlayer.volume = outputGain

        timeObserverToken = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.handleAVPPeriodicUpdate(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onTrackEnded?()
            }
        }

        statusObserver = avPlayer.observe(\.status, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if player.status == .failed {
                    self.handleFailure(player.error ?? player.currentItem?.error)
                }
            }
        }

        // The MPV engine drives its own clock; the AVPlayer time observer
        // must not overwrite `currentTime`/`duration` while it's running.
        setUpMPVEngine()
        setUpMPVPreloader()

        setupRemoteCommands()
        setupSystemMediaLifecycle()
    }

    deinit {
        if let token = timeObserverToken {
            avPlayer.removeTimeObserver(token)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statusObserver?.invalidate()
        itemStatusObserver?.invalidate()
    }

    // MARK: Queue

    func setQueue(_ songs: [SubsonicSong], startAt index: Int = 0, autoPlay: Bool = true, recordHistory: Bool = true) {
        resetPreloadedNext()
        guard !songs.isEmpty else {
            queue = []
            currentIndex = 0
            shuffleState.originalQueue = []
            shuffleState.shuffledQueue = []
            shuffle = false
            shufflePreferenceEnabled = false
            return
        }
        let shouldShuffle = shufflePreferenceEnabled
        shuffleState.originalQueue = []
        shuffleState.shuffledQueue = []
        shuffle = false
        queue = songs
        currentIndex = min(max(index, 0), songs.count - 1)
        if shouldShuffle { setShuffleEnabled(true) }
        startCurrent(autoPlay: autoPlay, recordHistory: recordHistory)
    }

    func play(_ songs: [SubsonicSong], startAt index: Int = 0, recordHistory: Bool = true) {
        setQueue(songs, startAt: index, recordHistory: recordHistory)
    }

    /// Jump to a specific position within the existing queue (Up Next list).
    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        startCurrent()
    }

    // MARK: Shuffle / repeat

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        resetPreloadedNext()
        updateNowPlayingInfo()
    }

    // MARK: Source resolution

    func startCurrent(autoPlay: Bool = true, recordHistory: Bool = true) {
        automix.currentSourceURL = nil
        guard let song = currentSong else { return }
        mpvFailureFallback.clear()
        mpvLoadGeneration += 1
        if promotePreloadedMPVTrack(for: song, autoPlay: autoPlay, recordHistory: recordHistory) { return }
        resetPreloadedNext()
        // Stop the current item immediately. If the next track isn't ready yet
        // (stream resolve / transcode), the previous one must not keep playing.
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        mpvEngine.stop()
        isPlaying = autoPlay
        lastError = nil
        hasReportedFailure = false
        isLoading = true
        isBuffering = false
        currentTime = 0
        duration = 0
        pendingSeekTime = nil
        heldSeekTarget = nil
        transcodeRestartResidual = nil
        mpvStreamOffset = 0
        mpvSeekRestartActive = false
        mpvRestartStepped = false
        engineKind = .avPlayer
        // A seek requested for the PREVIOUS track must not land on this one.
        pendingSeekTime = nil
        if recordHistory {
            history.append(song)
            if history.count > 500 { history.removeFirst(history.count - 500) }
        }
        // Publish synchronously while stream resolution is still in flight so
        // Control Center and media keys do not retain the previous track.
        updateNowPlayingInfo()
        onTrackRequest?(song)
    }

    func clearHistory() {
        history = []
    }

    /// Loads `url` into AVPlayer and starts playback.
    func playURL(_ url: URL) {
        mpvFailureFallback.clear()
        automix.currentSourceURL = url
        engineKind = .avPlayer
        mpvStreamOffset = 0
        mpvSeekRestartActive = false
        mpvRestartStepped = false
        heldSeekTarget = nil
        transcodeRestartResidual = nil
        isLoading = false
        isCaching = false
        lastError = nil
        hasReportedFailure = false
        let item = AVPlayerItem(url: url)
        observeItemStatus(item)
        avPlayer.replaceCurrentItem(with: item)
        // Don't start playing until the item is ready — observeItemStatus fires
        // applyPendingSeekIfNeeded(), which can begin playback if needed.
        updateNowPlayingInfo()
    }

    /// Plays `url` through libmpv (via MPVKit). The default engine: mpv owns
    /// demuxing, decoding and HTTP-range seeking, so streams and local files
    /// seek sample-accurately without the hand-rolled decode feeder that
    /// stuttered under load.
    func cancelStreamRecord() {
        mpvEngine.cancelStreamRecord()
    }

    /// Plays `url` through libmpv (via MPVKit). The default engine: mpv owns
    /// demuxing, decoding and HTTP-range seeking, so streams and local files
    /// seek sample-accurately without the hand-rolled decode feeder that
    /// stuttered under load.
    func playMPV(_ url: URL, streamRecordURL: URL? = nil) {
        mpvFailureFallback.arm(for: url)
        automix.currentSourceURL = url
        engineKind = .mpv
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        lastError = nil
        hasReportedFailure = false
        isBuffering = true
        duration = 0
        currentTime = 0
        pendingSeekTime = nil
        heldSeekTarget = nil
        transcodeRestartResidual = nil
        mpvStreamOffset = 0
        mpvSeekRestartActive = false
        mpvRestartStepped = false
        // Note: isPlaying is NOT set here. It stays in its previous state — false
        // during a paused queue restore, true when the user hits play. The async
        // task below only calls mpvEngine.play() when isPlaying is still true.
        loadMPVStream(url: url, streamRecordURL: streamRecordURL)
    }

    func observeItemStatus(_ item: AVPlayerItem) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .readyToPlay {
                    self.applyPendingSeekIfNeeded()
                    // Start playback only when ready — avoids audio bursts
                    // during queue restoration (playURL → pause → no audio).
                    if self.isPlaying {
                        self.avPlayer.play()
                    }
                }
                if item.status == .failed {
                    self.handleFailure(item.error)
                }
            }
        }
    }

    private func handleFailure(_ error: Error?) {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        lastError = L10n.text("format.player.unavailable")
        isPlaying = false
        isLoading = false
        updateNowPlayingInfo()
    }

    private func handleAVPPeriodicUpdate(_ time: CMTime) {
        // The MPV engine ticks its own clock via onTimeUpdate.
        if engineKind == .mpv { return }
        let pipeSeconds = time.seconds.isFinite ? time.seconds : 0
        let display = pipeSeconds + mpvStreamOffset
        if !isScrubbing && !isSeekInFlight {
            if mpvSeekRestartActive && !mpvRestartStepped {
                // New pipe not yet stepped — keep held target.
            } else if let held = heldSeekTarget {
                if display >= held - 0.25 {
                    heldSeekTarget = nil
                    currentTime = display
                } else if currentTime < held {
                    currentTime = held
                }
            } else {
                currentTime = display
            }
        }
        if let item = avPlayer.currentItem, item.duration.isNumeric {
            let rawDuration = item.duration.seconds
            duration = rawDuration.isFinite && rawDuration > 0
                ? rawDuration + mpvStreamOffset
                : 0
        }
        isBuffering = avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if avPlayer.timeControlStatus == .playing { isLoading = false }
        if avPlayer.status == .failed || avPlayer.currentItem?.status == .failed {
            handleFailure(avPlayer.error ?? avPlayer.currentItem?.error)
        }
        reportNowPlayingSecond(display)
    }
}

// MARK: Remote commands / media keys

extension Player {
    /// Wires media-key (remote-command) handling into the player. Called once
    /// from `init()`.
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        enableRemoteCommands(in: center)
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func setupSystemMediaLifecycle() {
        systemMediaActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreSystemMediaControls()
            }
        }
    }

    func restoreSystemMediaControls() {
        enableRemoteCommands(in: MPRemoteCommandCenter.shared())
        updateNowPlayingInfo()
    }

    private func enableRemoteCommands(in center: MPRemoteCommandCenter) {
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
    }
}
