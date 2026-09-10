import SwiftUI
import NavidromeClient

// MARK: - Logic (moved out of the main editor file to keep both files within size limits)

extension SmartPlaylistEditorView {
    // MARK: Load

    func load() async {
        if var server {
            isLoadingInitialRules = true
            defer { isLoadingInitialRules = false }
            server.query = await app.loadServerRules(id: server.id)
            loadServer(server)
            return
        }
        loadLocal()
    }

    func loadServer(_ server: ServerSmartPlaylist) {
        name = server.name
        orderText = server.query?.order
        if let query = server.query {
            model = QueryEditorModel(root: QueryNode(query: query))
            limitText = query.limit.map(String.init) ?? ""
            apply(query.sort)
        } else {
            model = QueryEditorModel(root: QueryNode(.group(.all)))
            limitText = ""
            sort = .random
            descending = false
            customSort = nil
            sortTouched = false
        }
        ruleCount = model.ruleCount()
        captureCleanState()
    }

    func loadLocal() {
        guard let playlist else {
            model = QueryEditorModel(root: QueryNode(.group(.all)))
            name = ""
            limitText = ""
            sort = .random
            descending = false
            customSort = nil
            orderText = nil
            sortTouched = false
            ruleCount = model.ruleCount()
            captureCleanState()
            return
        }
        name = playlist.name
        orderText = nil
        if let query = playlist.query {
            model = QueryEditorModel(root: QueryNode(query: query))
            limitText = query.limit.map(String.init) ?? ""
            apply(query.sort)
        } else {
            // Legacy single-field playlist → synthesize an equivalent rule tree.
            var rules: [QueryNode] = []
            if let genre = playlist.trimmedGenre {
                rules.append(QueryNode(.rule(QueryRule(field: .genre, op: .is_, value: .init(text: genre)))))
            }
            if playlist.starredOnly {
                rules.append(QueryNode(.rule(QueryRule(field: .loved, op: .is_, value: .init(number: 1)))))
            }
            if let minPlayCount = playlist.minPlayCount {
                let count = Double(minPlayCount)
                rules.append(QueryNode(.rule(QueryRule(field: .playCount, op: .gte, value: .init(number: count)))))
            }
            if let minRating = playlist.minRating {
                let rating = Double(minRating)
                rules.append(QueryNode(.rule(QueryRule(field: .rating, op: .gte, value: .init(number: rating)))))
            }
            if rules.isEmpty { rules.append(QueryNode(.rule(.empty))) }
            let root = QueryNode(.group(.all))
            root.children = rules
            model = QueryEditorModel(root: root)
            limitText = playlist.limit.map(String.init) ?? ""
            sort = playlist.shuffleOrder ? .random : .title
            descending = false
            customSort = nil
            sortTouched = false
        }
        ruleCount = model.ruleCount()
        captureCleanState()
    }

    func captureCleanState() {
        originalName = name
        originalQuery = visualQuery()
        hasChanges = false
    }

    /// Applies a loaded sort string to the picker/direction state, preserving
    /// unrecognised (e.g. multi-field) sort strings verbatim in `customSort`.
    func apply(_ sortString: String?) {
        sortTouched = false
        customSort = nil
        if let sortString, let parsed = SmartSort(json: sortString) {
            sort = parsed
            descending = parsed != .random && sortString.hasPrefix("-")
        } else if let sortString {
            customSort = sortString
            sort = .title
            descending = false
        } else {
            sort = .random
            descending = false
        }
    }

    func markSortTouched() {
        hasChanges = true
        needsJSONSerialization = true
        sortTouched = true
        customSort = nil
    }

    /// User-facing bindings that record a manual sort change. Programmatic
    /// writes from `load()`/`apply()` stay direct so preserved multi-field
    /// sorts survive.
    var sortBinding: Binding<SmartSort> {
        Binding(get: { sort }, set: { sort = $0; markSortTouched() })
    }

    var descendingBinding: Binding<Bool> {
        Binding(get: { descending }, set: { descending = $0; markSortTouched() })
    }

    var limitBinding: Binding<String> {
        Binding(get: { limitText }, set: { newValue in
            limitText = newValue
            hasChanges = true
            needsJSONSerialization = true
        })
    }

    // MARK: JSON round-trip

    /// The visual tree as a query document. A preserved multi-field sort stays
    /// byte-identical; once the user re-picks a single field the picker's
    /// field+direction and the (cleared) global order are used.
    func visualQuery() -> SmartQuery {
        if let customSort, !sortTouched {
            return SmartQuery(root: model.root.mapExpr(), sort: customSort,
                              limit: Int(limitText), order: orderText)
        }
        return SmartQuery(root: model.root.mapExpr(),
                          sort: sort.json(descending: descending), limit: Int(limitText))
    }

    func serializeToJSON() {
        guard needsJSONSerialization else {
            jsonError = nil
            return
        }
        let query = visualQuery()
        guard let data = try? JSONEncoder().encode(query),
              let serialized = String(data: data, encoding: .utf8) else {
            return
        }
        if jsonText != serialized { jsonText = serialized }
        needsJSONSerialization = false
        jsonError = nil
    }

    func readFromJSONIfValid() {
        // Returning from JSON mode: keep the existing tree when the decoded
        // document is equivalent, even if its text was reformatted manually.
        guard let data = jsonText.data(using: .utf8),
              let parser = try? JSONDecoder().decode(SmartQuery.self, from: data) else {
            jsonError = "Некорректный JSON — правила не изменены."
            return
        }
        guard parser != visualQuery() else {
            jsonError = nil
            return
        }

        jsonError = nil
        model = QueryEditorModel(root: QueryNode(query: parser))
        limitText = parser.limit.map(String.init) ?? ""
        orderText = parser.order
        apply(parser.sort)
        needsJSONSerialization = false
        hasChanges = true
    }

    func preview() {
        guard mode == .visual, !isLoading else { return }
        previewState = .loading
        showingPreview = true
        let query = visualQuery()
        Task {
            do {
                previewState = .loaded(try await app.previewSmartQuery(query))
            } catch {
                previewState = .failed(error.localizedDescription)
            }
        }
    }

    func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let server {
            saveServer(server)
            return
        }
        let query: SmartQuery
        if mode == .json {
            guard let data = jsonText.data(using: .utf8),
                  let parser = try? JSONDecoder().decode(SmartQuery.self, from: data) else {
                jsonError = "Некорректный JSON — сохранение отменено."
                return
            }
            query = parser
        } else {
            query = visualQuery()
        }

        var smartPlaylist = playlist ?? SmartPlaylist(name: trimmed)
        smartPlaylist.name = trimmed
        smartPlaylist.query = query
        smartPlaylist.limit = query.limit
        smartPlaylist.shuffleOrder = query.sort?.contains("random") == true
        // Legacy convenience fields are delegated to the query; clear them.
        smartPlaylist.genre = nil
        smartPlaylist.starredOnly = false
        smartPlaylist.minPlayCount = nil
        smartPlaylist.minRating = nil
        app.upsertSmartPlaylist(smartPlaylist)
        hasChanges = false
        dismiss()
    }

    /// Save and replace: PUT the edited rules back to the server playlist.
    func saveServer(_ target: ServerSmartPlaylist) {
        guard let query = buildQueryOrReturnToJSON() else {
            jsonError = "Некорректный JSON — сохранение отменено."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        Task { @MainActor in
            do {
                try await app.saveServerRules(id: target.id, name: trimmed,
                                              isPublic: target.isPublic,
                                              comment: target.comment, query: query)
                hasChanges = false
                dismiss()
            } catch {
                jsonError = error.localizedDescription
            }
        }
    }

    /// Duplicates the current playlist under a new name (a "Save as"). Local
    /// playlists copy into a new local playlist; server playlists create a new
    /// server-side smart playlist and navigate to it.
    func saveAs() {
        let trimmed = saveAsName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        saveAsPresented = false
        let query = buildQueryOrReturnToJSON()
        guard let query else {
            jsonError = "Некорректный JSON — сохранение отменено."
            return
        }
        name = trimmed
        if let server {
            saveAsServer(server, name: trimmed, query: query)
            return
        }
        var copy = SmartPlaylist(name: trimmed)
        copy.query = query
        copy.limit = query.limit
        copy.shuffleOrder = query.sort?.contains("random") == true
        app.upsertSmartPlaylist(copy)
        app.showPlaylistsGrid()
        hasChanges = false
        dismiss()
    }

    func saveAsServer(_ target: ServerSmartPlaylist, name: String, query: SmartQuery) {
        Task { @MainActor in
            do {
                if let summary = try await app.createServerPlaylist(name: name,
                                                                    comment: target.comment, query: query) {
                    app.showServerPlaylist(summary)
                }
                hasChanges = false
                dismiss()
            } catch {
                jsonError = error.localizedDescription
            }
        }
    }

    func buildQueryOrReturnToJSON() -> SmartQuery? {
        if mode == .json {
            guard let data = jsonText.data(using: .utf8),
                  let parser = try? JSONDecoder().decode(SmartQuery.self, from: data) else {
                return nil
            }
            return parser
        }
        return visualQuery()
    }
}
