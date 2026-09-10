import SwiftUI
import NavidromeClient

/// Apple-Music-style "New playlist" sheet: a cover-art carousel with center
/// snapping, focused name + description fields, and Cancel / Create actions.
///
/// Themed to the app's adaptive palette but with a translucent, blurred
/// presentation background. Editing a future playlist reuses this by passing
/// `existing`.
struct CreatePlaylistModal: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let songs: [SubsonicSong]
    var existing: PlaylistSummary? = nil
    /// Called after a successful create or edit so the presenting view can
    /// refresh its own content (e.g. reload a playlist's detail).
    var onSaved: (() -> Void)?

    @State private var name = ""
    @State private var description = ""
    @State private var selectedCover = 0
    @State private var creating = false
    @State private var customImage: NSImage?
    @State private var showFilePicker = false
    @FocusState private var nameFocused: Bool

    /// Seeds the fields in `init` (not `.onAppear`): mutating `@State` during
    /// the sheet's first display cycle re-enters AppKit's constraint pass and
    /// crashes on macOS with the "marked as needing more Update Constraints"
    /// exception — latent on any screen, fatal inside a NavigationSplitView.
    init(songs: [SubsonicSong], existing: PlaylistSummary? = nil, onSaved: (() -> Void)? = nil) {
        self.songs = songs
        self.existing = existing
        self.onSaved = onSaved
        _name = State(initialValue: existing?.displayName ?? "")
        _description = State(initialValue: existing?.comment ?? "")
    }

    /// Gallery options: leading "no cover" (or the current cover when editing,
    /// which keeps the artwork as-is), then the preset swatches, then a
    /// trailing "upload image" slot.
    private enum Swatch: Identifiable {
        case none
        case current(String)
        case preset(PlaylistCoverPreset)
        case upload

        var id: String {
            switch self {
            case .none: return "none"
            case .current: return "current"
            case .preset(let p): return p.id
            case .upload: return "upload"
            }
        }
    }

    /// First tile shows the actual current cover in edit mode — picking it
    /// means "keep as is". Otherwise a generic "empty" slot.
    private var swatches: [Swatch] {
        if isEditing, let art = existing?.coverArt {
            return [.current(art)] + PlaylistCoverPreset.all.map { .preset($0) } + [.upload]
        }
        return [.none] + PlaylistCoverPreset.all.map { .preset($0) } + [.upload]
    }

    private let coverSize: CGFloat = 140

    private var pageCount: Int { swatches.count }
    private var selectedIndex: Int { max(0, min(selectedCover, pageCount - 1)) }
    private var isEditing: Bool { existing != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// The preset chosen (nil when none / upload selected).
    private var selectedPreset: PlaylistCoverPreset? {
        if case .preset(let p) = swatches[selectedIndex] { return p }
        return nil
    }

    /// A compact line describing the songs being added to a fresh playlist,
    /// e.g. "17 треков" or the song title when only one is selected.
    private var songsTitle: String {
        if songs.count == 1, let song = songs.first {
            return "\(song.displayTitle) — \(song.artist ?? "Неизвестно")"
        }
        return "\(songs.count) \(Pluralized.song(songs.count))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Изменить плейлист" : "Новый плейлист")
                .font(.title3.bold())

            coverCarousel

            VStack(spacing: 10) {
                titleField
                descriptionField
            }

            Divider()

            HStack(spacing: 10) {
                Button("Отменить") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    create()
                } label: {
                    Label(isEditing ? "Сохранить" : "Создать",
                          systemImage: singular || isEditing ? "checkmark" : "plus")
                        .frame(minWidth: 90)
                        .opacity(canCreate ? 1 : 0.5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || creating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            nameFocused = !isEditing
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.png, .jpeg, .image]) { result in
            guard case .success(let url) = result,
                  let data = try? Data(contentsOf: url),
                  let img = NSImage(data: data) else { return }
            customImage = img
            withAnimation(.snappy(duration: 0.2)) { selectedCover = pageCount - 1 }
        }
    }

    private var canCreate: Bool { !trimmedName.isEmpty }
    private var singular: Bool { songs.count == 1 }

    // MARK: Cover carousel — center item at full scale, neighbors scaled/faded

    private var coverCarousel: some View {
        VStack(spacing: 12) {
            ZStack {
                neighborTile(offset: -1)
                activeTile
                neighborTile(offset: +1)

                carouselChevron(systemImage: "chevron.left") {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedCover = (selectedCover - 1 + pageCount) % pageCount
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                carouselChevron(systemImage: "chevron.right") {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedCover = (selectedCover + 1) % pageCount
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 150)

            pageIndicator
        }
    }

    private func carouselChevron(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .help(systemImage == "chevron.left" ? "Предыдущая обложка" : "Следующая обложка")
    }

    private var activeTile: some View {
        coverTile(selectedIndex, isActive: true)
    }

    private func neighborTile(offset: Int) -> some View {
        let idx = selectedIndex + offset
        return Group {
            if idx >= 0 && idx < pageCount {
                coverTile(idx, isActive: false)
                    .scaleEffect(0.85)
                    .opacity(0.4)
            }
        }
    }

    private func coverTile(_ index: Int, isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AMColor.surface)
            .overlay {
                swatchContent(swatches[index])
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AMColor.accent, lineWidth: 3)
                    .opacity(isActive ? 1 : 0)
            }
            .frame(width: coverSize, height: coverSize)
            .contentShape(Rectangle())
            .zIndex(isActive ? 1 : 0)
            .onTapGesture {
                if case .upload = swatches[index] { showFilePicker = true }
                else {
                    withAnimation(.snappy(duration: 0.2)) { selectedCover = index }
                }
            }
    }

    @ViewBuilder
    private func swatchContent(_ swatch: Swatch) -> some View {
        // Preset fills the whole tile like the other slots; the "no cover" and
        // "upload" rectangles stretch to the full overlay, so the gradient must
        // match or it renders visibly smaller.
        let size = coverSize
        switch swatch {
        case .none:
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.08))
                Image(systemName: "music.note")
                    .font(.system(size: coverSize * 0.28))
                    .foregroundStyle(.tertiary)
            }
        case .current(let coverArt):
            CoverArtView(coverArt: coverArt, size: coverSize, cornerRadius: 12)
        case .preset(let preset):
            preset.view(size: size, title: name)
        case .upload:
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.08))
                if let customImage {
                    Image(nsImage: customImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: coverSize * 0.24, weight: .bold))
                        .foregroundStyle(AMColor.accent)
                }
            }
            .clipped()
        }
    }

    /// Icon + dots; the leading marker is a photo glyph (custom artwork slot).
    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Array(swatches.enumerated()), id: \.element.id) { index, _ in
                Circle()
                    .fill(index == selectedIndex ? AMColor.accent : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedIndex)
    }

    // MARK: Fields

    private var titleField: some View {
        TextField(isEditing ? "Название плейлиста" : "Название плейлиста", text: $name)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(fieldBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(nameFocused ? AMColor.accent : .clear, lineWidth: 2)
            }
            .focused($nameFocused)
            .onSubmit { create() }
    }

    private var descriptionField: some View {
        ZStack(alignment: .topLeading) {
            if description.isEmpty {
                Text("Описание (необязательно)".localized)
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .allowsHitTesting(false)
            }
            MultilineTextEditor(text: $description)
                .padding(8)
        }
        .frame(minHeight: 72)
        .background(fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.06))
    }

    private func create() {
        guard canCreate else { return }
        creating = true
        Task {
            var playlistId: String?
            if isEditing, let existing {
                playlistId = existing.id
                try? await app.client?.updatePlaylist(id: existing.id, name: trimmedName, comment: description)
            } else {
                let created = await app.createPlaylist(name: trimmedName, songs: songs, comment: description)
                playlistId = created?.id
            }
            if let playlistId, let coverData = await selectedCoverPNG() {
                try? await app.client?.uploadPlaylistCover(playlistId: playlistId, imageData: coverData)
            }
            // Editing must refresh the sidebar summaries too — create already does.
            if isEditing { await app.refreshPlaylists() }
            onSaved?()
            creating = false
            dismiss()
        }
    }

    /// Renders the currently selected cover as PNG bytes, or nil when the user
    /// picked "Без обложки". A user-supplied image is re-encoded directly.
    private func selectedCoverPNG() async -> Data? {
        switch swatches[selectedIndex] {
        case .none, .current:
            return nil
        case .preset(let preset):
            return await MainActor.run { preset.pngData(title: name) }
        case .upload:
            return await MainActor.run { customImage?.pngData() }
        }
    }
}