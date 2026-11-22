import AVFoundation
import Foundation
import MediaPlayer
import NavidromeClient

extension Player {
    @discardableResult
    func ensureAVPlayer() -> AVPlayer {
        if let existing = avPlayer { return existing }
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = outputGain

        timeObserverToken = player.addPeriodicTimeObserver(
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
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let finishedItem = notification.object as? AVPlayerItem,
                      finishedItem == self.avPlayer?.currentItem else { return }
                self.onTrackEnded?()
            }
        }

        statusObserver = player.observe(\.status, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if observedPlayer.status == .failed {
                    self.handleFailure(observedPlayer.error ?? observedPlayer.currentItem?.error)
                }
            }
        }

        timeControlStatusObserver = player.observe(
            \.timeControlStatus,
            options: [.new]
        ) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self, self.engineKind == .avPlayer else { return }
                self.isBuffering = observedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if observedPlayer.timeControlStatus == .playing { self.isLoading = false }
            }
        }

        avPlayer = player
        return player
    }

    func playURL(_ url: URL) {
        currentSourceURL = url
        engineKind = .avPlayer
        mpvStreamOffset = 0
        resetSeekState(keepPendingSeek: true)
        isLoading = true
        isBuffering = true
        isCaching = false
        lastError = nil
        hasReportedFailure = false
        let player = ensureAVPlayer()
        let item = AVPlayerItem(url: url)
        observeItemStatus(item)
        player.replaceCurrentItem(with: item)
        updateNowPlayingInfo()
    }

    func observeItemStatus(_ item: AVPlayerItem) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .readyToPlay {
                    self.isLoading = false
                    self.isBuffering = false
                    self.applyPendingSeekIfNeeded()
                    if self.isPlaying {
                        self.avPlayer?.play()
                    }
                }
                if item.status == .failed {
                    self.handleFailure(item.error)
                }
            }
        }
    }

    private static func avErrorCodeName(_ code: Int) -> String? {
        switch AVError.Code(rawValue: code) {
        case .unknown: return "AVErrorUnknown"
        case .fileFormatNotRecognized: return "AVErrorFileFormatNotRecognized"
        case .serverIncorrectlyConfigured: return "AVErrorServerIncorrectlyConfigured"
        case .failedToParse: return "AVErrorFailedToParse"
        case .undecodableMediaData: return "AVErrorUndecodableMediaData"
        case .contentIsNotAuthorized: return "AVErrorContentIsNotAuthorized"
        case .operationNotSupportedForAsset: return "AVErrorOperationNotSupportedForAsset"
        case .decoderNotFound: return "AVErrorDecoderNotFound"
        default: return nil
        }
    }

    static func formatAVPlayerError(_ error: Error?) -> String {
        guard let error else {
            return L10n.text("format.player.unavailable")
        }
        let nsError = error as NSError
        let errorIdentifier: String
        if nsError.domain == AVFoundationErrorDomain, let name = avErrorCodeName(nsError.code) {
            errorIdentifier = "\(name), \(nsError.code)"
        } else {
            errorIdentifier = "\(nsError.domain), \(nsError.code)"
        }

        let fullCode: String
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            fullCode = "(\(errorIdentifier), \(underlying.domain) \(underlying.code))"
        } else {
            fullCode = "(\(errorIdentifier))"
        }

        return L10n.format("format.player.failure", fullCode)
    }

    func handleFailure(_ error: Error?) {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        lastError = Self.formatAVPlayerError(error)
        isPlaying = false
        isLoading = false
        isBuffering = false
        updateNowPlayingInfo()
    }

    func handleAVPPeriodicUpdate(_ time: CMTime) {
        if engineKind == .mpv { return }
        guard let avPlayer else { return }
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
            duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 0
        }
        isBuffering = avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if avPlayer.timeControlStatus == .playing { isLoading = false }
        if avPlayer.status == .failed || avPlayer.currentItem?.status == .failed {
            handleFailure(avPlayer.error ?? avPlayer.currentItem?.error)
        }
        reportNowPlayingSecond(display)
    }
}
