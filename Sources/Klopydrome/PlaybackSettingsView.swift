import SwiftUI
import NavidromeClient

/// Playback preferences separated from general server and appearance settings.
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
                Picker("Движок".localized, selection: $app.serverConfig.playbackEngine.default(.mpv)) {
                    ForEach(PlaybackEngine.allCases) { engine in
                        Text(engine.label.localized).tag(engine)
                    }
                }
            } header: {
                Text("Плеер".localized)
            } footer: {
                if app.serverConfig.effectivePlaybackEngine == .avFoundation {
                    Text("В режиме AVFoundation часть функций воспроизведения недоступна.".localized)
                }
            }

            Section {
                Picker("Кодек".localized, selection: $app.serverConfig.format) {
                    Text("Оригинал".localized).tag(String?.none)
                    Text("Opus").tag(String?.some("opus"))
                    Text("MP3").tag(String?.some("mp3"))
                    Text("M4A (AAC)").tag(String?.some("m4a"))
                    Text("FLAC").tag(String?.some("flac"))
                }

                Picker("Битрейт".localized, selection: $app.serverConfig.maxBitRate) {
                    Text("Оригинал".localized).tag(0)
                    Text("320 kbps").tag(320)
                    Text("256 kbps").tag(256)
                    Text("192 kbps").tag(192)
                    Text("128 kbps").tag(128)
                    Text("64 kbps").tag(64)
                }

                Toggle(
                    "Кэшировать транскодированные треки".localized,
                    isOn: $app.serverConfig.downloadTranscoded.orTrue
                )
            } header: {
                Text("Стриминг".localized)
            } footer: {
                Text("Параметры транскодирования на стороне сервера для стриминга.".localized)
            }

            Section {
                Toggle(
                    "Предзагружать следующую песню".localized,
                    isOn: $app.serverConfig.nextTrackPreloadingEnabled.orTrue
                )
            } header: {
                Text("Предзагрузка".localized)
            } footer: {
                Text("Заранее открывает следующий трек для воспроизведения без задержки.".localized)
            }
            .disabled(app.serverConfig.effectivePlaybackEngine != .mpv)

            Section {
                Toggle("Авто-скробблинг".localized, isOn: $app.scrobblingEnabled)
                Toggle("Запоминать очередь".localized, isOn: $app.queuePersistenceEnabled)
            } header: {
                Text("Поведение".localized)
            } footer: {
                Text("Сохраняет позицию и список воспроизведения между запусками приложения.".localized)
            }

            Section {
                Toggle("Включить плавный переход".localized, isOn: $app.serverConfig.automixEnabled.orFalse)
                Toggle("Включать в альбомах".localized, isOn: $app.serverConfig.automixApplyToAlbums.orFalse)
                    .disabled(!app.serverConfig.effectiveAutomixEnabled)
                HStack {
                    Text("Длительность".localized)
                    Slider(value: crossfadeDuration, in: 1...12)
                    Text(L10n.format("format.duration.seconds", Int(app.serverConfig.effectiveAutomixFadeDuration)))
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                .disabled(!app.serverConfig.effectiveAutomixEnabled)
            } header: {
                Text("Плавный переход".localized)
            } footer: {
                Text("Следующая песня начинает звучать до окончания текущей.".localized)
            }
            .disabled(app.serverConfig.effectivePlaybackEngine != .mpv)

            Section {
                Picker(
                    "Коррекция громкости (ReplayGain)".localized,
                    selection: $app.serverConfig.replayGainMode.default(.off)
                ) {
                    ForEach(ReplayGainMode.allCases) { mode in
                        Text(mode.label.localized).tag(mode)
                    }
                }
                HStack {
                    Text("Предусиление".localized)
                    Slider(value: replayGainPreamp, in: AutomixLoudness.preampRange)
                    Text(L10n.format("format.gain.decibels", Double(app.serverConfig.effectiveReplayGainPreampDB)))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                .disabled(app.serverConfig.effectiveReplayGainMode == .off)
                Picker("Обрезка тишины в конце".localized, selection: $app.serverConfig.silenceTrimMode.default(.off)) {
                    ForEach(SilenceTrimMode.allCases) { mode in
                        Text(mode.label.localized).tag(mode)
                    }
                }
            } header: {
                Text("Обработка звука".localized)
            } footer: {
                Text("Выравнивание громкости приводит треки с тегами ReplayGain к единому уровню.".localized)
            }
            .disabled(app.serverConfig.effectivePlaybackEngine != .mpv)

            Section {
                HStack {
                    Text("Смещение времени".localized)
                    Spacer()
                    let currentOffsetMs = Int((app.serverConfig.effectiveLyricsDefaultOffset * 1000).rounded())
                    Text(String(format: "%+d мс".localized, currentOffsetMs))
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
                    Button("Сбросить смещение".localized) {
                        app.serverConfig.lyricsDefaultOffset = nil
                    }
                }
            } header: {
                Text("Синхронизация".localized)
            } footer: {
                Text("Смещение применяется ко всем песням для компенсации задержки звука.".localized)
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
