import SwiftUI
import NavidromeClient

/// The Cmd+, Settings window: General (streaming/playback) and Cache.
struct AppSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Общие", systemImage: "gearshape") }
            PlaybackSettingsView()
                .tabItem { Label("Воспроизведение", systemImage: "play.circle") }
            CacheSettingsView()
                .tabItem { Label("Кэш", systemImage: "internaldrive") }
            AdvancedSettingsView()
                .tabItem { Label("Расширенные", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 520, height: 460)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var showLogout = false

    var body: some View {
        Form {
            Section("Потоковая передача") {
                Picker("Кодек", selection: Bindable(app).serverConfig.format) {
                    Text("Оригинальный (решает сервер)".localized).tag(String?.none)
                    Text("Opus").tag(String?.some("opus"))
                    Text("MP3").tag(String?.some("mp3"))
                    Text("M4A (AAC)").tag(String?.some("m4a"))
                    Text("FLAC").tag(String?.some("flac"))
                }
                .help("Формат, в который сервер будет транскодировать потоки и загрузки. «Оригинальный» сохраняет исходный файл.")

                Picker("Битрейт транскодинга", selection: Bindable(app).serverConfig.maxBitRate) {
                    Text("Оригинал".localized).tag(0)
                    Text("320 kbps").tag(320)
                    Text("256 kbps").tag(256)
                    Text("192 kbps").tag(192)
                    Text("128 kbps").tag(128)
                    Text("64 kbps").tag(64)
                }
                // swiftlint:disable:next line_length
                Text("Применяется к потокам и загруженному кэшу. Кодек и битрейт требуют поддержки транскодирования на сервере.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Внешний вид") {
                Picker("Тема", selection: Bindable(app).serverConfig.theme) {
                    Text("Как в системе".localized).tag(AppTheme?.none)
                    ForEach([AppTheme.dark, AppTheme.light]) { theme in
                        Text(theme.label.localized).tag(AppTheme?.some(theme))
                    }
                }
                .help("Принудительно включает тёмную или светлую тему; по умолчанию следует системной.")
                Picker("Разрешение обложек", selection: Bindable(app).serverConfig.coverResolution) {
                    Text("Высокое (по умолчанию)".localized).tag(CoverResolution?.none)
                    ForEach(CoverResolution.allCases.filter { $0 != .high }) { resolution in
                        Text(resolution.label.localized).tag(CoverResolution?.some(resolution))
                    }
                }
                .help(
                    "Высокое — до 1000px, чётко на Retina без лишнего трафика. " +
                        "«Оригинал» — полное разрешение; низкие значения экономят кэш и трафик."
                )
            }
            Section("Аккаунт") {
                LabeledContent("Сервер") { Text(app.serverConfig.url).foregroundStyle(.secondary) }
                Button("Выйти из аккаунта", role: .destructive) {
                    showLogout = true
                }
                .confirmationDialog("Выйти из аккаунта?",
                                    isPresented: $showLogout,
                                    titleVisibility: .visible) {
                    Button("Выйти", role: .destructive) { app.disconnect() }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    // swiftlint:disable:next line_length
                    Text("Очередь, кэш и сохранённый пароль будут очищены. Вы сможете подключиться к другому серверу.".localized)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: app.serverConfig) { _, _ in
            app.saveSettings()
            app.refreshDiscordRichPresence()
        }
    }
}

private struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var app

    private var isDiscordPresenceEnabled: Bool {
        app.serverConfig.effectiveDiscordRichPresenceEnabled
    }

    var body: some View {
        Form {
            Section("Discord Rich Presence") {
                Toggle(
                    "Показывать текущий трек в Discord",
                    isOn: Bindable(app).serverConfig.discordRichPresenceEnabled.orFalse
                )
                Toggle(
                    "Показывать трек на паузе",
                    isOn: Bindable(app).serverConfig.discordShowPaused.orTrue
                )
                .disabled(!isDiscordPresenceEnabled)
                TextField(
                    "Discord Application ID",
                    text: Bindable(app).serverConfig.discordApplicationID.orEmpty,
                    prompt: Text("123456789012345678")
                )
                .textContentType(.none)
                .help("Создайте application в Discord Developer Portal и вставьте его числовой ID.")
                DiscordStatusRow()
            }

            DebugSettingsSection()
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: app.serverConfig) { _, _ in
            app.saveSettings()
            app.refreshDiscordRichPresence()
        }
    }
}

private struct CacheSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var showConfirmation = false
    @State private var usedStreams = 0
    @State private var usedTotal = 0
    @State private var usedCovers = 0
    @State private var usedMetadata = 0
    /// Bumped after a background cache clear, so usage refreshes without
    /// blocking the settings surface.
    @State private var reloadToken = 0
    private let megabyte = 1024 * 1024
    private let defaultStreamLimit = 1_500
    private let defaultTotalLimit = 2_000
    private var defaultStreamBytes: Int { defaultStreamLimit * megabyte }
    private var defaultTotalBytes: Int { defaultTotalLimit * megabyte }
    private var configuredStreamLimit: Int? {
        app.serverConfig.streamCacheLimitBytes
    }
    private var configuredTotalLimit: Int? {
        app.serverConfig.totalCacheLimitBytes
    }
    private var effectiveTotalLimit: Int {
        max(configuredTotalLimit ?? defaultTotalBytes, configuredStreamLimit ?? 0)
    }
    private var effectiveStreamLimit: Int {
        min(configuredStreamLimit ?? defaultStreamBytes, effectiveTotalLimit)
    }
    var body: some View {
        Form {
            Section("Офлайн-кэш") {
                Toggle(
                    "Сохранять полностью прослушанные песни",
                    isOn: Bindable(app).serverConfig.cacheEnabled
                )
                Text("Пропущенные песни не загружаются. Для полной загрузки используйте «Загрузить».".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Использование кэша") {
                CacheUsageOverview(
                    usedStreams: usedStreams,
                    usedCovers: usedCovers,
                    usedMetadata: usedMetadata,
                    usedTotal: usedTotal,
                    totalLimit: effectiveTotalLimit
                )

                Button("Очистить кэш…", role: .destructive) {
                    showConfirmation = true
                }
            }

            Section("Лимиты кэша") {
                CacheBudgetSection(
                    title: "Аудиокэш",
                    details: "Скачанные песни входят в общий кэш.",
                    selectedLimit: configuredStreamLimit,
                    automaticValue: effectiveStreamLimit,
                    choices: CacheLimitPreset.all,
                    onSelect: selectStreamLimit
                )
                CacheBudgetSection(
                    title: "Общий кэш",
                    details: "Включает аудио, обложки и метаданные.",
                    selectedLimit: configuredTotalLimit,
                    automaticValue: effectiveTotalLimit,
                    choices: CacheLimitPreset.all,
                    onSelect: selectTotalLimit
                )
            }
        }
        .formStyle(.grouped)
        .onChange(of: app.serverConfig) { _, _ in
            if !app.serverConfig.cacheEnabled { app.cancelAutomaticPlaybackCache() }
            Task { await app.applyCacheLimits() }
            app.saveSettings()
        }
        .task(id: reloadToken) {
            normalizeCacheLimits()
            await reloadUsage()
        }
        .confirmationDialog(
            "Очистить весь кэш?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Очистить", role: .destructive) {
                Task {
                    await app.clearCache()
                    try? await Task.sleep(for: .milliseconds(400))
                    reloadToken &+= 1
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все кэшированные песни, обложки и метаданные будут удалены.".localized)
        }
    }

    private func selectStreamLimit(_ limit: Int?) {
        app.serverConfig.streamCacheLimitBytes = limit
        guard let limit else { return }
        let total = app.serverConfig.totalCacheLimitBytes ?? defaultTotalBytes
        if total < limit { app.serverConfig.totalCacheLimitBytes = limit }
    }

    private func selectTotalLimit(_ limit: Int?) {
        let total = limit ?? defaultTotalBytes
        app.serverConfig.totalCacheLimitBytes = limit
        guard let streamLimit = app.serverConfig.streamCacheLimitBytes,
              streamLimit > total else { return }
        app.serverConfig.streamCacheLimitBytes = total
    }

    private func normalizeCacheLimits() {
        guard let streamLimit = app.serverConfig.streamCacheLimitBytes else { return }
        guard let total = app.serverConfig.totalCacheLimitBytes else {
            if streamLimit > defaultTotalBytes {
                app.serverConfig.streamCacheLimitBytes = defaultTotalBytes
            }
            return
        }
        if streamLimit > total { app.serverConfig.streamCacheLimitBytes = total }
    }

    private func reloadUsage() async {
        guard let cache = app.cache else { return }
        usedStreams = await cache.bytesAsync(for: .streams)
        usedTotal = await cache.totalBytesAsync()
        usedCovers = await cache.bytesAsync(for: .covers)
        usedMetadata = await cache.bytesAsync(for: .metadata)
    }
}

/// A compact storage summary that turns the cache categories into a single
/// readable surface, separate from the policy controls below it.
private struct CacheUsageOverview: View {
    let usedStreams: Int
    let usedCovers: Int
    let usedMetadata: Int
    let usedTotal: Int
    let totalLimit: Int?

    private let megabyte = 1024 * 1024

    private var effectiveLimit: Int {
        totalLimit ?? 2_000 * megabyte
    }

    private var knownUsage: Int {
        usedStreams + usedCovers + usedMetadata
    }

    private var unclassifiedUsage: Int {
        max(usedTotal - knownUsage, 0)
    }

    private var scaleBytes: Double {
        Double(max(effectiveLimit, max(usedTotal, knownUsage)))
    }

    private var totalDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(usedTotal), countStyle: .file)
    }

    private var limitDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(effectiveLimit), countStyle: .file)
    }

    private var segments: [CacheUsageSegment] {
        [
            .init(title: "Аудио", bytes: usedStreams, color: .red),
            .init(title: "Обложки", bytes: usedCovers, color: .orange),
            .init(title: "Метаданные", bytes: usedMetadata, color: .yellow),
            .init(title: "Прочее", bytes: unclassifiedUsage, color: .secondary)
        ].filter { $0.bytes > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Кэш приложения".localized)
                    .fontWeight(.medium)
                Spacer()
                Text(L10n.format("format.storage.used", totalDescription, limitDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)

                    HStack(spacing: 1) {
                        ForEach(segments) { segment in
                            segment.color
                                .frame(width: segment.width(in: proxy.size.width, scale: scaleBytes))
                        }
                    }
                }
            }
            .frame(height: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Использование кэша")
            .accessibilityValue(L10n.format("format.storage.accessibilityValue", totalDescription, limitDescription))

            if segments.isEmpty {
                Text("Кэш пока пуст.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(segments) { segment in
                        CacheUsageLegendItem(segment: segment)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CacheUsageSegment: Identifiable {
    let title: String
    let bytes: Int
    let color: Color

    var id: String { title }

    func width(in availableWidth: Double, scale: Double) -> Double {
        guard scale > 0 else { return 0 }
        let fraction = min(max(Double(bytes) / scale, 0), 1)
        return max(availableWidth * fraction, 2)
    }
}

private struct CacheUsageLegendItem: View {
    let segment: CacheUsageSegment

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(segment.color)
                .frame(width: 7, height: 7)
            Text("\(segment.title.localized) \(format(segment.bytes))")
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func format(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// A policy row for a cache limit. A compact menu picker exposes meaningful
/// storage tiers without the false precision of a continuous slider.
private struct CacheBudgetSection: View {
    let title: String
    let details: String
    let selectedLimit: Int?
    let automaticValue: Int
    let choices: [CacheLimitPreset]
    let onSelect: (Int?) -> Void

    private var limitDescription: String {
        CacheLimitPreset.title(for: selectedLimit ?? automaticValue)
            ?? ByteCountFormatter.string(
                fromByteCount: Int64(selectedLimit ?? automaticValue),
                countStyle: .file
            )
    }

    private var displayChoices: [CacheLimitPreset] {
        guard let selectedLimit,
              !choices.contains(where: { $0.bytes == selectedLimit }) else {
            return choices
        }
        return [.init(bytes: selectedLimit, title: limitDescription)] + choices
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.localized)
                    .fontWeight(.medium)
                Text(selectedLimit == nil
                     ? L10n.format("format.storage.automaticLimit", limitDescription.localized)
                     : L10n.format("format.storage.limit", limitDescription.localized))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(details.localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker(
                L10n.format("format.storage.limitTitle", title.localized),
                selection: Binding(get: { selectedLimit }, set: onSelect)
            ) {
                Text("Автоматически".localized).tag(Int?.none)
                Divider()
                ForEach(displayChoices) { preset in
                    Text(preset.title.localized).tag(Optional(preset.bytes))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 128, alignment: .trailing)
            .accessibilityLabel(L10n.format("format.storage.limitTitle", title.localized))
            .accessibilityValue(selectedLimit == nil ? L10n.text("Автоматически") : limitDescription.localized)
        }
        .padding(.vertical, 2)
    }
}

private struct CacheLimitPreset: Identifiable {
    let bytes: Int
    let title: String

    var id: Int { bytes }

    static let all = [
        CacheLimitPreset(megabytes: 512, title: "512 МБ"),
        CacheLimitPreset(megabytes: 1_024, title: "1 ГБ"),
        CacheLimitPreset(megabytes: 1_500, title: "1,5 ГБ"),
        CacheLimitPreset(megabytes: 2_000, title: "2 ГБ"),
        CacheLimitPreset(megabytes: 5_000, title: "5 ГБ"),
        CacheLimitPreset(megabytes: 10_000, title: "10 ГБ"),
        CacheLimitPreset(megabytes: 25_000, title: "25 ГБ"),
        CacheLimitPreset(megabytes: 50_000, title: "50 ГБ")
    ]

    init(megabytes: Int, title: String) {
        self.bytes = megabytes * 1024 * 1024
        self.title = title
    }

    init(bytes: Int, title: String) {
        self.bytes = bytes
        self.title = title
    }

    static func title(for bytes: Int) -> String? {
        all.first(where: { $0.bytes == bytes })?.title
    }
}
