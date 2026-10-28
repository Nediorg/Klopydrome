import SwiftUI
import NavidromeClient

/// Settings tab for visual appearance and lyrics personalization:
/// general theme, cover art resolution, lyrics typography, animation motion,
/// depth-of-field blur, and interlude countdown.
struct AppearanceSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Form {
            appearanceSection
            playlistsSection
            lyricsSection
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: app.serverConfig) { _, newConfig in
            app.saveSettings()
            CoverArtStore.shared.configure(
                client: app.client,
                cache: app.cache,
                coverResolution: newConfig.coverResolution ?? .high,
                adaptiveCellularDataEnabled: newConfig.effectiveAdaptiveCellularDataEnabled
            )
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Тема".localized, selection: Bindable(app).serverConfig.theme) {
                Text("Как в системе".localized).tag(AppTheme?.none)
                ForEach([AppTheme.dark, AppTheme.light]) { theme in
                    Text(theme.label.localized).tag(AppTheme?.some(theme))
                }
            }

            Picker("Разрешение обложек".localized, selection: Binding<CoverResolution>(
                get: { app.serverConfig.coverResolution ?? .high },
                set: { app.serverConfig.coverResolution = $0 }
            )) {
                ForEach(CoverResolution.allCases) { resolution in
                    Text(resolution.label).tag(resolution)
                }
            }

            Toggle(
                "Экономить трафик при мобильной сети".localized,
                isOn: Bindable(app).serverConfig.adaptiveCellularDataEnabled.orTrue
            )
        } header: {
            Text("Оформление".localized)
        }
    }

    private var playlistsSection: some View {
        Section {
            Picker("Дубликаты в плейлистах".localized, selection: Bindable(app).duplicatePlaylistAction) {
                ForEach(DuplicatePlaylistAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
        } header: {
            Text("Плейлисты".localized)
        }
    }

    private var lyricsSection: some View {
        Section {
            Picker("Размер шрифта".localized, selection: Bindable(app).serverConfig.lyricsFontSize) {
                Text("Обычный".localized).tag(LyricsFontSize?.none)
                ForEach(LyricsFontSize.allCases.filter { $0 != .standard }) { size in
                    Text(size.label.localized).tag(LyricsFontSize?.some(size))
                }
            }

            Picker("Стиль анимации".localized, selection: Bindable(app).serverConfig.lyricsAnimationMotion) {
                Text("Плавная".localized).tag(LyricsAnimationMotion?.none)
                ForEach(LyricsAnimationMotion.allCases.filter { $0 != .smooth }) { motion in
                    Text(motion.label.localized).tag(LyricsAnimationMotion?.some(motion))
                }
            }

            Toggle(
                "Размывать неактивные строки".localized,
                isOn: Bindable(app).serverConfig.lyricsBlurEnabled.orTrue
            )
        } header: {
            Text("Текст песен".localized)
        }
    }
}
