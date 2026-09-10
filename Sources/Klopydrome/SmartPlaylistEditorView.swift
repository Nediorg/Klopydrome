import SwiftUI
import NavidromeClient

// MARK: - Main editor

struct SmartPlaylistEditorView: View {
    /// Existing local playlist to edit, or nil to create a new local one.
    let playlist: SmartPlaylist?
    /// A server-side smart playlist being edited. Mutually exclusive with
    /// `playlist`; when set, Save replaces the server's rules (PUT) and
    /// Save-as creates a new server playlist (POST).
    var server: ServerSmartPlaylist?

    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss

    @State var name: String = ""
    @State var model = QueryEditorModel(root: QueryNode(.group(.all)))
    @State var mode: EditorMode = .visual
    @State var jsonText: String = ""
    @State var jsonError: String?
    /// False while `jsonText` already represents the current visual query.
    @State var needsJSONSerialization = true
    @State var sort: SmartSort = .random
    /// Empty = no limit (all matches), per the "no default limit" requirement.
    @State var limitText: String = ""
    /// Sort direction for non-random picks; encoded as a leading "-".
    @State var descending = false
    /// Verbatim sort string kept when the loaded sort isn't a single picker
    /// field (e.g. multi-field "year,-rating") so the editor never corrupts it.
    @State var customSort: String?
    /// Server global `order` pass-through, cleared once the user re-picks sort.
    @State var orderText: String?
    /// True once the user changes the sort picker/direction; clears custom sort.
    @State var sortTouched = false
    @State var previewState: SmartPreviewState = .idle
    @State var showingPreview = false
    /// "Сохранить как…" prompt for duplicating an existing playlist.
    @State var saveAsPresented = false
    @State var saveAsName = ""
    /// True once the user edits the tree/name/options after load, so Cancel can
    /// offer to discard rather than silently dropping work.
    @State var hasChanges = false
    @State var originalName = ""
    @State var originalQuery: SmartQuery?
    @State var confirmingDiscard = false
    /// Reactive rule count. `model` is an `@State`-held ObservableObject whose
    /// published changes would otherwise not re-render this view's counter.
    @State var ruleCount = 0
    @FocusState private var nameFocused: Bool
    /// Server rules arrive asynchronously. Keep the editor hidden until its
    /// initial model is authoritative, rather than briefly showing an empty tree.
    @State var isLoadingInitialRules: Bool

    init(playlist: SmartPlaylist?, server: ServerSmartPlaylist? = nil) {
        self.playlist = playlist
        self.server = server
        _isLoadingInitialRules = State(initialValue: server != nil)
    }

    enum EditorMode: String, CaseIterable, Identifiable {
        case visual, json
        var id: String { rawValue }
        var label: String { self == .visual ? "Конструктор" : "JSON" }
        var icon: String { self == .visual ? "curlybraces" : "square.3.layers.3d.down.right" }
    }

    enum SmartPreviewState {
        case idle
        case loading
        case loaded([SubsonicSong])
        case failed(String)
    }

    private var isNew: Bool { playlist == nil }
    private var isServer: Bool { server != nil }
    /// A fresh local playlist (no target). Server targets edit in place.
    private var isNewLocal: Bool { playlist == nil && server == nil }
    private var loadID: String { server?.id ?? playlist?.id ?? "new" }
    private static let editorWidth: CGFloat = 960
    private static let editorHeight: CGFloat = 640

    private var hasUnsavedChanges: Bool {
        Self.shouldConfirmDiscard(
            name: name,
            query: visualQuery(),
            originalName: originalName,
            originalQuery: originalQuery
        )
    }

    static func shouldConfirmDiscard(
        name: String,
        query: SmartQuery,
        originalName: String,
        originalQuery: SmartQuery?
    ) -> Bool {
        guard let originalQuery else { return false }
        return name != originalName || query != originalQuery
    }

    var body: some View {
        Group {
            if isLoadingInitialRules {
                ProgressView("Загрузка правил…")
                    .controlSize(.large)
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    options
                    Divider()
                    editorBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                    Divider()
                    footer
                }
            }
        }
        .frame(width: Self.editorWidth, height: Self.editorHeight)
        .task(id: loadID) { await load() }
        .onReceive(model.objectWillChange) {
            hasChanges = true
            needsJSONSerialization = true
            ruleCount = model.ruleCount()
        }
        .onChange(of: name) { _, _ in hasChanges = true }
        .alert(isNew ? "" : "Сохранить как…", isPresented: $saveAsPresented) {
            TextField("Название копии", text: $saveAsName)
            Button("Сохранить") { saveAs() }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Отменить изменения?", isPresented: $confirmingDiscard) {
            Button("Отменить изменения", role: .destructive) { dismiss() }
            Button("Остаться", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(isNewLocal ? "Новый умный плейлист" : "Редактор правил")
                .font(.headline)
            TextField("Название", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .frame(minWidth: 320, maxWidth: .infinity)
                .onAppear { nameFocused = true }
            Spacer()
            Picker("Режим", selection: $mode) {
                ForEach(EditorMode.allCases) { m in
                    Label(m.label.localized, systemImage: m.icon).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()
            .onChange(of: mode) { _, newMode in
                if newMode == .json { serializeToJSON() } else { readFromJSONIfValid() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var options: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Label("Лимит", systemImage: "number")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                TextField("—", text: limitBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .monospacedDigit()
                    .help("Пусто — без лимита (все совпадения)")
            }
            Picker("Порядок", selection: sortBinding) {
                ForEach(SmartSort.allCases, id: \.self) { sort in Text(sort.label.localized).tag(sort) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Поле сортировки. При изменении заменяет сохранённое нестандартное правило порядка.")
            Picker("Направление", selection: descendingBinding) {
                Text("По возрастанию".localized).tag(false)
                Text("По убыванию".localized).tag(true)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(sort == .random)
            .help("Направление сортировки (для «Случайно» не используется)")
            Spacer()
            Text(L10n.format("format.rule.count", ruleCount))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityValue(L10n.format("format.rule.count", ruleCount))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Only the active editor exists in the hierarchy. The previous ZStack
    /// kept the hidden `jsonEditor` (a full-area `TextEditor`) stacked above
    /// the visual tree with just `opacity(0)` + `allowsHitTesting(false)`,
    /// and that flag does not reliably reach the AppKit text view on Tahoe —
    /// the invisible editor swallowed clicks and hover across the whole modal
    /// (pickers, checkboxes, delete buttons, text fields; menus opened only
    /// by luck). Conditional rendering removes the failure class entirely:
    /// state lives in bindings/`model`, so nothing is lost on mode switch
    /// (scroll offset resets, acceptable).
    private var editorBody: some View {
        Group {
            if mode == .visual {
                visualEditor
            } else {
                jsonEditor
            }
        }
    }

    private var visualEditor: some View {
        ScrollView([.horizontal, .vertical]) {
            GroupRecursiveView(group: model.root, root: model.root, model: model, depth: 0)
                .fixedSize(horizontal: true, vertical: false)
                .padding(12)
        }
    }

    private var jsonEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            if let jsonError {
                Label(jsonError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if case .loading = previewState {
                ProgressView()
                    .controlSize(.small)
            }
            Button(isLoading ? "Загрузка…" : "Показать") {
                preview()
            }
            .buttonStyle(.link)
            .disabled(isLoading)
            .popover(isPresented: $showingPreview, arrowEdge: .bottom) {
                previewContent
            }
            Spacer()
            Button("Отмена") {
                if hasUnsavedChanges {
                    confirmingDiscard = true
                } else {
                    dismiss()
                }
            }
            if !isNewLocal {
                Button("Сохранить как…") { saveAsPresented = true }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button(isNewLocal ? "Создать" : "Сохранить") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    var isLoading: Bool {
        if case .loading = previewState { return true }
        return false
    }

    private var previewContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Просмотр".localized)
                    .font(.headline)
                if case .loaded(let songs) = previewState, !songs.isEmpty {
                    Text(L10n.format("format.smartPlaylist.songs", songs.count))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            Divider()
            switch previewState {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Повторить") { preview() }
                }
            case .loaded(let songs) where songs.isEmpty:
                ContentUnavailableView {
                    Label("Нет совпадений", systemImage: "music.note.list")
                } description: {
                    Text("Ни одна песня не подходит под текущие правила.".localized)
                }
            case .loaded(let songs):
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            QueueTrackRow(
                                song: song,
                                isCurrent: app.player.currentSong?.id == song.id
                            ) {
                                app.play(songs, at: index)
                            }
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .frame(width: 520, height: 420)
    }
}
