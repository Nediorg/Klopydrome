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
            avPlayer?.volume = outputGain
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

    /// Originating playlist, album, or general context for playback.
    var playbackContext: PlaybackContext?

    var currentPlaylist: PlaylistSummary? {
        if case .playlist(let summary) = playbackContext { return summary }
        return nil
    }

    /// Originating playlist or album title for contextual display.
    var queueContextTitle: String? {
        get {
            switch playbackContext {
            case .playlist(let summary):
                return summary.displayName
            case .smartPlaylist(let smart):
                return smart.name
            case .album(let album):
                return album.name
            case .artist(let artist):
                return artist.name
            case .general(let title):
                return title
            case nil:
                return nil
            }
        }
        set {
            if let newValue {
                playbackContext = .general(title: newValue)
            } else {
                playbackContext = nil
            }
        }
    }

    /// Formatted subtitle describing the originating playback source (only album or playlist).
    var queueContextSubtitle: String? {
        guard !queue.isEmpty else { return nil }
        switch playbackContext {
        case .album(let album):
            return String(format: "From %@".localized, album.displayName)
        case .playlist(let summary):
            return String(format: "From %@".localized, summary.displayName)
        case .smartPlaylist(let smart):
            return String(format: "From %@".localized, smart.name)
        default:
            return nil
        }
    }

    /// Called when the player needs the app to resolve and start a track.
    var onTrackRequest: ((SubsonicSong) -> Void)?
    /// Notifies the app after a meaningful playback-state transition.
    @ObservationIgnored var onDiscordPresenceUpdate: (() -> Void)?
    /// Called when the current item finishes (for advancing the queue).
    var onTrackEnded: (() -> Void)?
    var onTrackCrossfaded: ((SubsonicSong) -> Void)?
    var onStreamRecordFinished: ((URL) -> Void)?

    /// The shared playback engine, lazily initialized on demand when
    /// the user chooses AVPlayer or MPV falls back to it.
    @ObservationIgnored nonisolated(unsafe) var avPlayer: AVPlayer?
    /// Active playback engine. MPV by default (every format, sample-accurate
    /// HTTP seeks — libmpv reads the seektable and range-requests the exact
    /// byte offset); AVPlayer when the user opts out in Settings.
    enum EngineKind { case avPlayer, mpv }
    var engineKind: EngineKind = .mpv
    var mpvEngine = MPVPlaybackEngine()
    @ObservationIgnored var mpvFailureFallback = MPVFailureFallback()
    let automix = AutomixPreparation()
    let shuffleState = ShuffleState()
    @ObservationIgnored var timeObserverToken: Any?
    @ObservationIgnored var endObserver: NSObjectProtocol?
    @ObservationIgnored var statusObserver: NSKeyValueObservation?
    @ObservationIgnored var itemStatusObserver: NSKeyValueObservation?
    @ObservationIgnored var timeControlStatusObserver: NSKeyValueObservation?
    @ObservationIgnored var heldSeekTargetTimestamp: CFAbsoluteTime = 0
    var lastInfoSecond = -1
    @ObservationIgnored var nowPlayingArtworkTask: Task<Void, Never>?
    @ObservationIgnored var systemMediaActivationObserver: NSObjectProtocol?
    var hasReportedFailure = false

    /// True once the current track has been loaded into the active engine, so
    /// Play can resume it directly instead of re-resolving the source.
    var hasLoadedItem: Bool {
        engineKind == .mpv ? mpvEngine.isLoaded : avPlayer?.currentItem != nil
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
        // The MPV engine drives its own clock; the AVPlayer time observer
        // must not overwrite `currentTime`/`duration` while it's running.
        setUpMPVEngine()

        setupRemoteCommands()
        setupSystemMediaLifecycle()
    }

    deinit {
        if let token = timeObserverToken, let avPlayer = self.avPlayer {
            avPlayer.removeTimeObserver(token)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = systemMediaActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statusObserver?.invalidate()
        itemStatusObserver?.invalidate()
        timeControlStatusObserver?.invalidate()

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
    }

    // MARK: Queue

    func setQueue(
        _ songs: [SubsonicSong],
        startAt index: Int = 0,
        autoPlay: Bool = true,
        recordHistory: Bool = true,
        context: PlaybackContext? = nil
    ) {
        resetPreloadedNext()
        guard !songs.isEmpty else {
            stop()
            queue = []
            currentIndex = 0
            shuffleState.originalQueue = []
            shuffleState.shuffledQueue = []
            shuffle = false
            shufflePreferenceEnabled = false
            playbackContext = nil
            return
        }
        playbackContext = context
        let shouldShuffle = shufflePreferenceEnabled
        shuffleState.originalQueue = []
        shuffleState.shuffledQueue = []
        shuffle = false
        queue = songs
        currentIndex = min(max(index, 0), songs.count - 1)
        if shouldShuffle { setShuffleEnabled(true) }
        startCurrent(autoPlay: autoPlay, recordHistory: recordHistory)
    }

    func play(
        _ songs: [SubsonicSong],
        startAt index: Int = 0,
        recordHistory: Bool = true,
        context: PlaybackContext? = nil
    ) {
        setQueue(songs, startAt: index, autoPlay: true, recordHistory: recordHistory, context: context)
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
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
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
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        lastError = nil
        hasReportedFailure = false
        isBuffering = true
        duration = 0
        let targetSeek = pendingSeekTime ?? (currentTime > 0 ? currentTime : nil)
        currentTime = targetSeek ?? 0
        pendingSeekTime = targetSeek
        heldSeekTarget = targetSeek
        if targetSeek != nil { heldSeekTargetTimestamp = CFAbsoluteTimeGetCurrent() }
        transcodeRestartResidual = nil
        mpvStreamOffset = 0
        mpvSeekRestartActive = false
        mpvRestartStepped = false
        // Note: isPlaying is NOT set here. It stays in its previous state — false
        // during a paused queue restore, true when the user hits play. The async
        // task below only calls mpvEngine.play() when isPlaying is still true.
        loadMPVStream(url: url, streamRecordURL: streamRecordURL)
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
