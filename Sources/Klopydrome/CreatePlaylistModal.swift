import SwiftUI
import PhotosUI
import NavidromeClient

/// Apple-Music-style "New / Edit playlist" modal: a cover-art carousel with peek
/// neighbors and hover arrows, focused name, description, public toggle, and Cancel / Done actions.
struct CreatePlaylistModal: View {
    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss

    let songs: [SubsonicSong]
    var existing: PlaylistSummary? = nil
    /// Called after a successful create or edit so the presenting view can
    /// refresh its own content (e.g. reload a playlist's detail).
    var onSaved: (() -> Void)?
    var onDismiss: (() -> Void)?

    @State var name = ""
    @State var description = ""
    @State var isPublic = false
    @State var selectedCover = 1
    @State var visibleIndex: Int? = 1
    var activeVisibleIndex: Int { visibleIndex ?? selectedIndex }
    @State var creating = false
    @State var customImage: NSImage?
    @State var showFilePicker = false
    @State var showPhotosPicker = false
    @State var selectedPhotoItem: PhotosPickerItem?
    @State var isCarouselHovered = false
    @State var hoveredCoverIndex: Int?
    @FocusState var nameFocused: Bool
    @FocusState var descriptionFocused: Bool

    /// Seeds the fields in `init` (not `.onAppear`): mutating `@State` during
    /// the sheet's first display cycle re-enters AppKit's constraint pass and
    /// crashes on macOS with the "marked as needing more Update Constraints"
    /// exception — latent on any screen, fatal inside a NavigationSplitView.
    init(
        songs: [SubsonicSong],
        existing: PlaylistSummary? = nil,
        onSaved: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.songs = songs
        self.existing = existing
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        _name = State(initialValue: existing?.displayName ?? "")
        _description = State(initialValue: existing?.comment ?? "")
        _isPublic = State(initialValue: existing?.isPublic ?? false)
        let initialCover = (existing?.coverArt != nil) ? 0 : 1
        _selectedCover = State(initialValue: initialCover)
        _visibleIndex = State(initialValue: initialCover)
    }

    /// Gallery options: slot 0 is the custom photo (or current cover when editing),
    /// followed by the preset swatches.
    enum Swatch: Identifiable {
        case photo(String?)
        case preset(PlaylistCoverPreset)

        var id: String {
            switch self {
            case .photo(let art): return art ?? "custom_photo_slot"
            case .preset(let preset): return preset.id
            }
        }
    }

    var swatches: [Swatch] {
        let photoSlot: Swatch = .photo(isEditing ? existing?.coverArt : nil)
        return [photoSlot] + PlaylistCoverPreset.all.map { .preset($0) }
    }

    let coverSize: CGFloat = 160
    let modalWidth: CGFloat = 370

    var pageCount: Int { swatches.count }
    var selectedIndex: Int { max(0, min(selectedCover, pageCount - 1)) }
    var isEditing: Bool { existing != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// The preset chosen (nil when slot 0 / photo selected).
    var selectedPreset: PlaylistCoverPreset? {
        if selectedIndex > 0, case .preset(let preset) = swatches[selectedIndex] {
            return preset
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(isEditing ? "Изменить плейлист".localized : "Новый плейлист".localized)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 20)

                coverCarousel

                VStack(spacing: 10) {
                    titleField
                    descriptionField
                    publicToggle
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: 10) {
                Button("Отменить".localized) { dismissSelf() }
                    .buttonStyle(.plain)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                    )
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    create()
                } label: {
                    Text(isEditing ? "Сохранить".localized : "Создать".localized)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(canCreate ? AMColor.accent : AMColor.accent.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canCreate || creating)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: modalWidth)
        .onAppear {
            nameFocused = !isEditing
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.png, .jpeg, .image]) { result in
            handlePickedFile(result)
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            handlePickedPhoto(newItem)
        }
    }

    var canCreate: Bool { !trimmedName.isEmpty }

    // MARK: Fields

    private var titleField: some View {
        TextField("Название плейлиста".localized, text: $name)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(fieldBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(nameFocused ? AMColor.accent : Color.clear, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .focused($nameFocused)
            .onSubmit { create() }
    }

    private var descriptionField: some View {
        ZStack(alignment: .topLeading) {
            if description.isEmpty {
                Text("Описание (необязательно)".localized)
                    .font(.body)
                    .kerning(-0.5)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $description)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .focused($descriptionFocused)
        }
        .frame(height: 72)
        .background(fieldBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(descriptionFocused ? AMColor.accent : Color.clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            descriptionFocused = true
        }
    }

    private var publicToggle: some View {
        Toggle("Публичный плейлист".localized, isOn: $isPublic)
            .toggleStyle(.switch)
            .padding(.horizontal, 2)
            .padding(.top, 2)
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result,
              let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) else { return }
        let cropped = img.squareCropped()
        withAnimation(.easeInOut(duration: 0.25)) {
            customImage = cropped
            selectedCover = 0
            visibleIndex = 0
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = NSImage(data: data) {
                let cropped = img.squareCropped()
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        customImage = cropped
                        selectedCover = 0
                        visibleIndex = 0
                    }
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.06))
    }

    private func create() {
        guard canCreate else { return }
        guard app.confirmOfflineAction() else { return }
        creating = true
        Task {
            var playlistId: String?
            if isEditing, let existing {
                playlistId = existing.id
                try? await app.client?.updatePlaylist(
                    id: existing.id,
                    name: trimmedName,
                    comment: description,
                    isPublic: isPublic
                )
            } else {
                let created = await app.createPlaylist(
                    name: trimmedName,
                    songs: songs,
                    comment: description,
                    isPublic: isPublic
                )
                playlistId = created?.id
            }
            if let playlistId, let coverData = await selectedCoverPNG() {
                try? await app.client?.uploadPlaylistCover(playlistId: playlistId, imageData: coverData)
                CoverArtStore.shared.clearMemoryCache()
                await app.cache?.removeFile(for: .covers, key: playlistId)
                await app.cache?.removeFile(for: .covers, key: "pl-\(playlistId)")
            }
            // Editing must refresh the sidebar summaries and reload the open playlist detail.
            if isEditing, let existing {
                app.invalidatePlaylistDetail(for: existing.id)
                await app.refreshPlaylists()
                let target = app.library.playlists.first(where: { $0.id == existing.id })
                    ?? PlaylistSummary(id: existing.id, name: trimmedName, comment: description, isPublic: isPublic)
                await app.reloadPlaylist(target)
            }
            onSaved?()
            creating = false
            dismissSelf()
        }
    }

    func dismissSelf() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    /// Renders the currently selected cover as PNG bytes, or nil when the user
    /// picked the existing artwork. A user-supplied image is re-encoded directly.
    func selectedCoverPNG() async -> Data? {
        if selectedIndex == 0 {
            if let customImage {
                return await MainActor.run { customImage.pngData() }
            }
            return nil
        }
        if let preset = selectedPreset {
            return await MainActor.run { preset.pngData(title: name) }
        }
        return nil
    }
}