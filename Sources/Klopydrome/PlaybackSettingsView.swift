import SwiftUI
import NavidromeClient

struct PlaybackSettingsView: View {
    @Environment(AppState.self) private var app

    private var crossfadeDuration: Binding<Double> {
        Binding(
            get: { app.serverConfig.effectiveAutomixFadeDuration },
            set: { app.serverConfig.automixFadeDuration = $0.rounded() }
        )
    }

    private var replayGainPreamp: Binding<Float> {
        Binding(
            get: { app.serverConfig.effectiveReplayGainPreampDB },
            set: { app.serverConfig.replayGainPreampDB = $0.rounded() }
        )
    }

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Picker("Engine".localized, selection: $app.serverConfig.playbackEngine.default(.mpv)) {
                    ForEach(PlaybackEngine.allCases) { engine in
                        Text(engine.label.localized).tag(engine)
                    }
                }
            } header: {
                Text("Player".localized)
            } footer: {
                if app.serverConfig.effectivePlaybackEngine == .avFoundation {
                    Text("Some playback features are unavailable with AVFoundation.".localized)
                }
            }

            Section {
                Picker("Codec".localized, selection: $app.serverConfig.format) {
                    Text("Original".localized).tag(String?.none)
                    Text("Opus").tag(String?.some("opus"))
                    Text("MP3").tag(String?.some("mp3"))
                    Text("M4A (AAC)").tag(String?.some("m4a"))
                    Text("FLAC").tag(String?.some("flac"))
                }

                Picker("Bitrate".localized, selection: $app.serverConfig.maxBitRate) {
                    Text("Original".localized).tag(0)
                    Text("320 kbps").tag(320)
                    Text("256 kbps").tag(256)
                    Text("192 kbps").tag(192)
                    Text("128 kbps").tag(128)
                    Text("64 kbps").tag(64)
                }

                Toggle(
                    "Cache transcoded tracks".localized,
                    isOn: $app.serverConfig.downloadTranscoded.orTrue
                )
            } header: {
                Text("Streaming".localized)
            } footer: {
                Text("Server-side transcoding parameters for streaming.".localized)
            }

            Section {
                Toggle(
                    "Preload next song".localized,
                    isOn: $app.serverConfig.nextTrackPreloadingEnabled.orTrue
                )
            } header: {
                Text("Preloading".localized)
            } footer: {
                Text("Pre-opens the next track to eliminate pauses between songs.".localized)
            }
            .disabled(app.serverConfig.effectivePlaybackEngine != .mpv)

            Section {
                Toggle("Auto-scrobbling".localized, isOn: $app.scrobblingEnabled)
                Toggle("Remember queue".localized, isOn: $app.queuePersistenceEnabled)
            } header: {
                Text("Look and Feel".localized)
            } footer: {
                Text("Saves playback position and queue across app launches.".localized)
            }

            Section {
                Toggle("Enable Crossfade".localized, isOn: $app.serverConfig.automixEnabled.orFalse)
                Toggle("Enable in Albums".localized, isOn: $app.serverConfig.automixApplyToAlbums.orFalse)
                    .disabled(!app.serverConfig.effectiveAutomixEnabled)
                HStack {
                    Text("Duration".localized)
                    Slider(value: crossfadeDuration, in: 1...12)
                    Text(L10n.format("format.duration.seconds", Int(app.serverConfig.effectiveAutomixFadeDuration)))
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                .disabled(!app.serverConfig.effectiveAutomixEnabled)
            } header: {
                Text("Crossfade".localized)
            } footer: {
                Text("Fades into the next song before the current one ends.".localized)
            }
            .disabled(app.serverConfig.effectivePlaybackEngine != .mpv)

            Section {
                Picker(
                    "Volume Correction (ReplayGain)".localized,
                    selection: $app.serverConfig.replayGainMode.default(.off)
                ) {
                    ForEach(ReplayGainMode.allCases) { mode in
                        Text(mode.label.localized).tag(mode)
                    }
                }
                HStack {
                    Text("Preamp".localized)
                    Slider(value: replayGainPreamp, in: AutomixLoudness.preampRange)
                    Text(L10n.format("format.gain.decibels", Double(app.serverConfig.effectiveReplayGainPreampDB)))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                .disabled(app.serverConfig.effectiveReplayGainMode == .off)
                Picker("Trim Trailing Silence".localized, selection: $app.serverConfig.silenceTrimMode.default(.off)) {
                    ForEach(SilenceTrimMode.allCases) { mode in
                        Text(mode.label.localized).tag(mode)
                    }
                }
            } header: {
                Text("Audio Processing".localized)
            } footer: {
                Text("Normalizes playback volume using ReplayGain tags.".localized)
            }
            .disabled(app.serverConfig.effectivePlaybackEngine != .mpv)

            Section {
                HStack {
                    Text("Time Offset".localized)
                    Spacer()
                    let currentOffsetMs = Int((app.serverConfig.effectiveLyricsDefaultOffset * 1000).rounded())
                    Text(String(format: "%+d ms".localized, currentOffsetMs))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Stepper("", onIncrement: {
                        let offsetMilliseconds = currentOffsetMs + 50
                        app.serverConfig.lyricsDefaultOffset = Double(offsetMilliseconds) / 1000.0
                    }, onDecrement: {
                        let offsetMilliseconds = currentOffsetMs - 50
                        app.serverConfig.lyricsDefaultOffset = Double(offsetMilliseconds) / 1000.0
                    })
                    .labelsHidden()
                }

                if app.serverConfig.effectiveLyricsDefaultOffset != 0 {
                    Button("Reset Offset".localized) {
                        app.serverConfig.lyricsDefaultOffset = nil
                    }
                }
            } header: {
                Text("Synchronization".localized)
            } footer: {
                Text("Applied to all songs to compensate for audio latency.".localized)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: app.serverConfig) { _, config in
            app.player.configureAutomix(
                enabled: config.effectiveAutomixEnabled,
                fadeDuration: config.effectiveAutomixFadeDuration,
                applyToAlbums: config.effectiveAutomixApplyToAlbums
            )
            app.player.configureReplayGain(
                mode: config.effectiveReplayGainMode,
                preampDB: config.effectiveReplayGainPreampDB
            )
            app.player.configureSilenceTrim(mode: config.effectiveSilenceTrimMode)
            app.player.configureNextTrackPreloading(
                enabled: config.effectiveNextTrackPreloadingEnabled
            )
            app.saveSettings()
        }
    }
}
