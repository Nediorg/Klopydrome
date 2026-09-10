import SwiftUI
import NavidromeClient

/// Playback preferences separated from general server and appearance settings.
struct PlaybackSettingsView: View {
    @Environment(AppState.self) private var app

    /// A nil value means the default MPV engine; writing the resolved value
    /// makes the user’s choice explicit in the persisted server configuration.
    private var playbackEngineBinding: Binding<PlaybackEngine> {
        Binding(
            get: { app.serverConfig.effectivePlaybackEngine },
            set: { app.serverConfig.playbackEngine = $0 }
        )
    }

    private var crossfadeEnabled: Binding<Bool> {
        Binding(
            get: { app.serverConfig.effectiveAutomixEnabled },
            set: { app.serverConfig.automixEnabled = $0 }
        )
    }

    private var crossfadeDuration: Binding<Double> {
        Binding(
            get: { app.serverConfig.effectiveAutomixFadeDuration },
            set: { app.serverConfig.automixFadeDuration = $0 }
        )
    }

    private var replayGainMode: Binding<ReplayGainMode> {
        Binding(
            get: { app.serverConfig.effectiveReplayGainMode },
            set: { app.serverConfig.replayGainMode = $0 }
        )
    }

    private var replayGainPreamp: Binding<Float> {
        Binding(
            get: { app.serverConfig.effectiveReplayGainPreampDB },
            set: { app.serverConfig.replayGainPreampDB = $0 }
        )
    }

    private var silenceTrimMode: Binding<SilenceTrimMode> {
        Binding(
            get: { app.serverConfig.effectiveSilenceTrimMode },
            set: { app.serverConfig.silenceTrimMode = $0 }
        )
    }

    private var nextTrackPreloadingEnabled: Binding<Bool> {
        Binding(
            get: { app.serverConfig.effectiveNextTrackPreloadingEnabled },
            set: { app.serverConfig.nextTrackPreloadingEnabled = $0 }
        )
    }

    var body: some View {
        Form {
            Section("Плеер") {
                Picker("Движок", selection: playbackEngineBinding) {
                    ForEach(PlaybackEngine.allCases) { engine in
                        Text(engine.label.localized).tag(engine)
                    }
                }
                .help("MPV: точный поиск и любые форматы. AVFoundation: системный плеер.")
            }

            Section {
                Toggle("Предзагружать следующую песню", isOn: nextTrackPreloadingEnabled)
            } header: {
                Text("Предзагрузка".localized)
            } footer: {
                Text(
                    "Заранее открывает следующий трек, чтобы уменьшить паузу между " +
                        "песнями."
                )
            }
            .disabled(app.serverConfig.effectivePlaybackEngine != .mpv)

            Section("Поведение") {
                Toggle("Авто-скробблинг", isOn: Binding(
                    get: { app.scrobblingEnabled },
                    set: { app.scrobblingEnabled = $0 }
                ))
                Toggle("Запоминать очередь", isOn: Binding(
                    get: { app.queuePersistenceEnabled },
                    set: { app.queuePersistenceEnabled = $0 }
                ))
                .help(
                    "Очередь воспроизведения и позиция сохраняются на сервере " +
                        "и восстанавливаются при следующем запуске."
                )
            }

            Section {
                Toggle("Включить плавный переход", isOn: crossfadeEnabled)
                HStack {
                    Text("Длительность".localized)
                    Slider(value: crossfadeDuration, in: 1...12, step: 1)
                    Text(L10n.format("format.duration.seconds", Int(crossfadeDuration.wrappedValue)))
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                .disabled(!crossfadeEnabled.wrappedValue)
            } header: {
                Text("Плавный переход".localized)
            } footer: {
                Text(
                    "Следующая песня начинает звучать до конца текущей. " +
                        "Работает при непрерывном воспроизведении очереди через MPV."
                )
            }

            Section {
                Picker("Коррекция громкости (ReplayGain)", selection: replayGainMode) {
                    ForEach(ReplayGainMode.allCases) { mode in
                        Text(mode.label.localized).tag(mode)
                    }
                }
                .help("Выравнивает громкость песен по тегам ReplayGain.")
                HStack {
                    Text("Предусиление".localized)
                    Slider(value: replayGainPreamp, in: AutomixLoudness.preampRange, step: 1)
                    Text(L10n.format("format.gain.decibels", Double(replayGainPreamp.wrappedValue)))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                .disabled(replayGainMode.wrappedValue == .off)
                Picker("Обрезка тишины в конце", selection: silenceTrimMode) {
                    ForEach(SilenceTrimMode.allCases) { mode in
                        Text(mode.label.localized).tag(mode)
                    }
                }
                .help("Убирает долгую паузу в конце дорожки.")
            } header: {
                Text("Обработка звука".localized)
            } footer: {
                Text(
                    "Коррекция громкости делает уровень песен ровнее независимо от " +
                        "плавного перехода. Обрезка тишины и ReplayGain работают только через MPV."
                )
            }
            .disabled(app.serverConfig.effectivePlaybackEngine != .mpv)
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: app.serverConfig) { _, config in
            app.player.configureAutomix(
                enabled: config.effectiveAutomixEnabled,
                fadeDuration: config.effectiveAutomixFadeDuration
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
