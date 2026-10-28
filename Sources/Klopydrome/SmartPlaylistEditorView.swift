import SwiftUI
import NavidromeClient

struct SmartPlaylistEditorView: View {
    let playlist: SmartPlaylist?
    var server: ServerSmartPlaylist?
    var onDismiss: (() -> Void)?

    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss

    @State var name: String = ""
    @State var model = QueryEditorModel(root: QueryNode(.group(.all)))
    @State var mode: EditorMode = .visual
    @State var jsonText: String = ""
    @State var jsonError: String?
    @State var needsJSONSerialization = true
    @State var sort: SmartSort = .random
    @State var limitText: String = ""
    @State var descending = false
    @State var customSort: String?
    @State var orderText: String?
    @State var sortTouched = false
    @State var previewState: SmartPreviewState = .idle
    @State var showingPreview = false
    @State var saveAsPresented = false
    @State var saveAsName = ""
    @State var hasChanges = false
    @State var originalName = ""
    @State var originalQuery: SmartQuery?
    @State var confirmingDiscard = false
    @State var ruleCount = 0
    @FocusState private var nameFocused: Bool
    @State var isLoadingInitialRules: Bool

    init(playlist: SmartPlaylist?, server: ServerSmartPlaylist? = nil, onDismiss: (() -> Void)? = nil) {
        self.playlist = playlist
        self.server = server
        self.onDismiss = onDismiss
        _isLoadingInitialRules = State(initialValue: server != nil)
    }

    enum EditorMode: String, CaseIterable, Identifiable {
        case visual, json
        var id: String { rawValue }
        var label: String { self == .visual ? "Visual Editor" : "JSON" }
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
    private var isNewLocal: Bool { playlist == nil && server == nil }
    private var loadID: String { server?.id ?? playlist?.id ?? "new" }
    private static let minEditorWidth: CGFloat = 720
    private static let maxEditorWidth: CGFloat = 960
    private static let minEditorHeight: CGFloat = 480
    private static let maxEditorHeight: CGFloat = 640

    var hasUnsavedChanges: Bool {
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
                ProgressView("Loading rules…".localized)
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
        .frame(
            minWidth: Self.minEditorWidth,
            maxWidth: Self.maxEditorWidth,
            minHeight: Self.minEditorHeight,
            maxHeight: Self.maxEditorHeight
        )
        .onInWindowModalAttemptDismiss {
            if hasUnsavedChanges {
                confirmingDiscard = true
            } else {
                dismissModal()
            }
        }
        .task(id: loadID) { await load() }
        .onReceive(model.objectWillChange) {
            hasChanges = true
            needsJSONSerialization = true
            ruleCount = model.ruleCount()
        }
        .onChange(of: name) { _, _ in hasChanges = true }
        .alert(isNew ? "" : "Save As…".localized, isPresented: $saveAsPresented) {
            TextField("Copy name".localized, text: $saveAsName)
            Button("Save".localized) { saveAs() }
            Button("Cancel".localized, role: .cancel) {}
        }
        .confirmationDialog("Discard Changes?".localized, isPresented: $confirmingDiscard) {
            Button("Discard Changes".localized, role: .destructive) { dismissModal() }
            Button("Keep Editing".localized, role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text((isNewLocal ? "New Smart Playlist" : "Rule Editor").localized)
                .font(.headline)
            TextField("Name".localized, text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .frame(minWidth: 320, maxWidth: .infinity)
                .onAppear { nameFocused = true }
            Spacer()
            Picker("Mode".localized, selection: $mode) {
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
                Label("Limit".localized, systemImage: "number")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                TextField("—", text: limitBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .monospacedDigit()
                    .help("Empty — no limit (all matches)".localized)
            }
            Picker("Order".localized, selection: sortBinding) {
                ForEach(SmartSort.allCases, id: \.self) { sort in Text(sort.label.localized).tag(sort) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Sort field. Replaces custom order rules.".localized)
            Picker("Direction".localized, selection: descendingBinding) {
                Text("Ascending".localized).tag(false)
                Text("Descending".localized).tag(true)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(sort == .random)
            .help("Sort direction (not used for Random)".localized)
            Spacer()
            Text(L10n.format("format.rule.count", ruleCount))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityValue(L10n.format("format.rule.count", ruleCount))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

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
            Button((isLoading ? "Loading…" : "Show").localized) {
                preview()
            }
            .buttonStyle(.link)
            .disabled(isLoading)
            .popover(isPresented: $showingPreview, arrowEdge: .bottom) {
                previewContent
            }
            Spacer()
            Button("Cancel".localized) {
                if hasUnsavedChanges {
                    confirmingDiscard = true
                } else {
                    dismissModal()
                }
            }
            if !isNewLocal {
                Button("Save As…".localized) { saveAsPresented = true }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button((isNewLocal ? "Create" : "Save").localized) { save() }
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
}
