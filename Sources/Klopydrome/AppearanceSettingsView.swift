import SwiftUI
import NavidromeClient

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
            Picker("Theme".localized, selection: Bindable(app).serverConfig.theme) {
                Text("System Default".localized).tag(AppTheme?.none)
                ForEach([AppTheme.dark, AppTheme.light]) { theme in
                    Text(theme.label.localized).tag(AppTheme?.some(theme))
                }
            }

            Picker("Cover resolution".localized, selection: Binding<CoverResolution>(
                get: { app.serverConfig.coverResolution ?? .high },
                set: { app.serverConfig.coverResolution = $0 }
            )) {
                ForEach(CoverResolution.allCases) { resolution in
                    Text(resolution.label).tag(resolution)
                }
            }

            Toggle(
                "Conserve data on mobile networks".localized,
                isOn: Bindable(app).serverConfig.adaptiveCellularDataEnabled.orTrue
            )
        } header: {
            Text("Appearance".localized)
        }
    }

    private var playlistsSection: some View {
        Section {
            Picker("Duplicates in Playlists".localized, selection: Bindable(app).duplicatePlaylistAction) {
                ForEach(DuplicatePlaylistAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
        } header: {
            Text("Playlists".localized)
        }
    }

    private var lyricsSection: some View {
        Section {
            Picker("Font Size".localized, selection: Bindable(app).serverConfig.lyricsFontSize) {
                Text("Standard".localized).tag(LyricsFontSize?.none)
                ForEach(LyricsFontSize.allCases.filter { $0 != .standard }) { size in
                    Text(size.label.localized).tag(LyricsFontSize?.some(size))
                }
            }

            Picker("Animation Style".localized, selection: Bindable(app).serverConfig.lyricsAnimationMotion) {
                Text("Smooth".localized).tag(LyricsAnimationMotion?.none)
                ForEach(LyricsAnimationMotion.allCases.filter { $0 != .smooth }) { motion in
                    Text(motion.label.localized).tag(LyricsAnimationMotion?.some(motion))
                }
            }

            Toggle(
                "Blur Inactive Lines".localized,
                isOn: Bindable(app).serverConfig.lyricsBlurEnabled.orTrue
            )
        } header: {
            Text("Lyrics".localized)
        }
    }
}
