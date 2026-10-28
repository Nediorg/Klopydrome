import Foundation
import AppKit
import NavidromeClient
import AVFoundation
import MediaPlayer
import Observation

enum PlaybackFormat {
    static let nativelyPlayable: Set<String> = [
        "mp3", "mp2", "m4a", "mp4", "m4b", "m4p", "aac", "alac",
        "flac", "wav", "wave", "aif", "aiff", "aifc", "caf", "amr",
        "mov", "m4v", "3gp", "3g2",
    ]

    static let lossless: Set<String> = [
        "flac", "alac", "wav", "wave", "aiff", "aif", "aifc", "ape", "wv", "dsf", "dff",
    ]

    static func needsTranscode(_ suffix: String?) -> Bool {
        guard let suffix = suffix?.lowercased(), !suffix.isEmpty else { return false }
        return !nativelyPlayable.contains(suffix)
    }

    static func isLossless(_ suffix: String?) -> Bool {
        guard let suffix = suffix?.lowercased() else { return false }
        return lossless.contains(suffix)
    }
}

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
    var isCrossfading = false
    var nextTrackPreloadingEnabled = true
    var isLoading = false
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
    @ObservationIgnored var shufflePreferenceEnabled = false
    var repeatMode: RepeatMode = .off

    var history: [SubsonicSong] = []

    var playbackContext: PlaybackContext?

    var currentPlaylist: PlaylistSummary? {
        if case .playlist(let summary) = playbackContext { return summary }
        return nil
    }

    var queueContextTitle: String? {
        switch playbackContext {
        case .playlist(let summary):
            return summary.displayName
        case .smartPlaylist(let smart):
            return smart.name
        case .album(let album):
            return album.displayName
        case nil:
            return nil
        }
    }

    var queueContextSubtitle: String? {
        guard !queue.isEmpty else { return nil }
        switch playbackContext {
        case .album(let album):
            return String(format: "From %@".localized, album.displayName)
        case .playlist(let summary):
            return String(format: "From %@".localized, summary.displayName)
        case .smartPlaylist(let smart):
            return String(format: "From %@".localized, smart.name)
        case nil:
            return nil
        }
    }

    var onTrackRequest: ((SubsonicSong) -> Void)?
    @ObservationIgnored var onDiscordPresenceUpdate: (() -> Void)?
    var onTrackEnded: (() -> Void)?
    var onTrackCrossfaded: ((SubsonicSong) -> Void)?
    var onStreamRecordFinished: ((URL) -> Void)?

    @ObservationIgnored nonisolated(unsafe) var avPlayer: AVPlayer?
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

    var hasLoadedItem: Bool {
        engineKind == .mpv ? mpvEngine.isLoaded : avPlayer?.currentItem != nil
    }

    @ObservationIgnored var isScrubbing = false

    @ObservationIgnored var pendingSeekTime: Double?

    @ObservationIgnored var mpvStreamOffset: Double = 0

    @ObservationIgnored var heldSeekTarget: Double?

    @ObservationIgnored var transcodeRestartResidual: Double?

    @ObservationIgnored var mpvRestartStepped = false

    @ObservationIgnored var mpvSeekRestartActive = false

    @ObservationIgnored var mpvLoadGeneration = 0

    @ObservationIgnored var isSeekInFlight = false

    @ObservationIgnored var seekRequestID = 0

    var trackDuration: Double {
        let meta = Double(currentSong?.duration ?? 0)
        if duration > 0 { return max(duration, meta) }
        return meta
    }

    init() {
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

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        startCurrent()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        resetPreloadedNext()
        updateNowPlayingInfo()
    }

    func startCurrent(autoPlay: Bool = true, recordHistory: Bool = true) {
        automix.currentSourceURL = nil
        guard let song = currentSong else { return }
        mpvFailureFallback.clear()
        mpvLoadGeneration += 1
        if promotePreloadedMPVTrack(for: song, autoPlay: autoPlay, recordHistory: recordHistory) { return }
        resetPreloadedNext()
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
        pendingSeekTime = nil
        if recordHistory {
            history.append(song)
            if history.count > 500 { history.removeFirst(history.count - 500) }
        }
        updateNowPlayingInfo()
        onTrackRequest?(song)
    }

    func clearHistory() {
        history = []
    }

    func cancelStreamRecord() {
        mpvEngine.cancelStreamRecord()
    }

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
        loadMPVStream(url: url, streamRecordURL: streamRecordURL)
    }
}

extension Player {
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
