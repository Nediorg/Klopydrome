import SwiftUI
import NavidromeClient

struct CacheSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var showConfirmation = false
    @State private var usedStreams = 0
    @State private var usedTotal = 0
    @State private var usedCovers = 0
    @State private var usedMetadata = 0
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

    private var cacheStarredSongsBinding: Binding<Bool> {
        Binding(
            get: { app.serverConfig.effectiveCacheStarredSongs },
            set: { enabled in
                app.serverConfig.cacheStarredSongs = enabled
                if enabled {
                    app.cacheAllStarredSongs()
                }
            }
        )
    }

    private var cacheStarredAlbumsBinding: Binding<Bool> {
        Binding(
            get: { app.serverConfig.effectiveCacheStarredAlbums },
            set: { enabled in
                app.serverConfig.cacheStarredAlbums = enabled
                if enabled {
                    app.cacheAllStarredAlbums()
                }
            }
        )
    }

    private var cacheStarredArtistsBinding: Binding<Bool> {
        Binding(
            get: { app.serverConfig.effectiveCacheStarredArtists },
            set: { enabled in
                app.serverConfig.cacheStarredArtists = enabled
                if enabled {
                    app.cacheAllStarredArtists()
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Save played songs".localized,
                    isOn: Bindable(app).serverConfig.cacheEnabled
                )
                Toggle(
                    "Favorite tracks".localized,
                    isOn: cacheStarredSongsBinding
                )
                .disabled(!app.serverConfig.cacheEnabled)
                Toggle(
                    "Favorite albums".localized,
                    isOn: cacheStarredAlbumsBinding
                )
                .disabled(!app.serverConfig.cacheEnabled)
                Toggle(
                    "Favorite artists".localized,
                    isOn: cacheStarredArtistsBinding
                )
                .disabled(!app.serverConfig.cacheEnabled)
            } header: {
                Text("Cache for offline listening".localized)
            } footer: {
                Text(
                    "Automatically saves selected library items for playback without internet.".localized
                )
            }

            Section("Cache usage".localized) {
                CacheUsageOverview(
                    usedStreams: usedStreams,
                    usedCovers: usedCovers,
                    usedMetadata: usedMetadata,
                    usedTotal: usedTotal,
                    totalLimit: effectiveTotalLimit
                )

                Button("Clear Cache…".localized, role: .destructive) {
                    showConfirmation = true
                }
            }

            Section("Cache Limits".localized) {
                CacheBudgetSection(
                    title: "Audio Cache".localized,
                    details: "Includes downloaded and streamed tracks.".localized,
                    selectedLimit: configuredStreamLimit,
                    automaticValue: effectiveStreamLimit,
                    choices: CacheLimitPreset.all,
                    onSelect: selectStreamLimit
                )
                CacheBudgetSection(
                    title: "Total Cache".localized,
                    details: "Includes audio, covers, and metadata.".localized,
                    selectedLimit: configuredTotalLimit,
                    automaticValue: effectiveTotalLimit,
                    choices: CacheLimitPreset.all,
                    onSelect: selectTotalLimit
                )
            }
        }
        .formStyle(.grouped)
        .padding()
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
            "Clear All Cache?".localized,
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear".localized, role: .destructive) {
                Task {
                    await app.clearCache()
                    try? await Task.sleep(for: .milliseconds(400))
                    reloadToken &+= 1
                }
            }
            Button("Cancel".localized, role: .cancel) {}
        } message: {
            Text("All cached songs, artwork, and metadata will be deleted.".localized)
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
            .init(title: "Audio".localized, bytes: usedStreams, color: .red),
            .init(title: "Covers".localized, bytes: usedCovers, color: .orange),
            .init(title: "Metadata".localized, bytes: usedMetadata, color: .yellow),
            .init(title: "Other".localized, bytes: unclassifiedUsage, color: .secondary)
        ].filter { $0.bytes > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Application cache".localized)
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
            .accessibilityLabel("Cache usage".localized)
            .accessibilityValue(L10n.format("format.storage.accessibilityValue", totalDescription, limitDescription))

            if segments.isEmpty {
                Text("Cache is empty.".localized)
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
                Text(details.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker(
                L10n.format("format.storage.limitTitle", title.localized),
                selection: Binding(get: { selectedLimit }, set: onSelect)
            ) {
                Text(L10n.format("format.storage.automaticLimit", limitDescription.localized)).tag(Int?.none)
                Divider()
                ForEach(displayChoices) { preset in
                    Text(preset.title.localized).tag(Optional(preset.bytes))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 140, alignment: .trailing)
            .accessibilityLabel(L10n.format("format.storage.limitTitle", title.localized))
            .accessibilityValue(selectedLimit == nil
                ? L10n.format("format.storage.automaticLimit", limitDescription.localized)
                : limitDescription.localized)
        }
        .padding(.vertical, 2)
    }
}

private struct CacheLimitPreset: Identifiable {
    let bytes: Int
    let title: String

    var id: Int { bytes }

    static let all: [CacheLimitPreset] = [
        512, 1_024, 1_500, 2_000, 5_000, 10_000, 25_000, 50_000
    ].map { megabytes in
        let bytes = megabytes * 1024 * 1024
        let title = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return CacheLimitPreset(bytes: bytes, title: title)
    }

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
