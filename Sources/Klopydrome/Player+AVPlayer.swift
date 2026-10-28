import AVFoundation
import Foundation
import MediaPlayer
import NavidromeClient

// MARK: AVPlayer Management & Observation

extension Player {
    @discardableResult
    func ensureAVPlayer() -> AVPlayer {
        if let existing = underlyingAVPlayer { return existing }
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
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
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onTrackEnded?()
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

        underlyingAVPlayer = player
        return player
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
        let player = ensureAVPlayer()
        let item = AVPlayerItem(url: url)
        observeItemStatus(item)
        player.replaceCurrentItem(with: item)
        // Don't start playing until the item is ready — observeItemStatus fires
        // applyPendingSeekIfNeeded(), which can begin playback if needed.
        updateNowPlayingInfo()
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
                        self.avPlayer?.play()
                    }
                }
                if item.status == .failed {
                    self.handleFailure(item.error)
                }
            }
        }
    }

    func handleFailure(_ error: Error?) {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        lastError = L10n.text("format.player.unavailable")
        isPlaying = false
        isLoading = false
        updateNowPlayingInfo()
    }

    func handleAVPPeriodicUpdate(_ time: CMTime) {
        // The MPV engine ticks its own clock via onTimeUpdate.
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
