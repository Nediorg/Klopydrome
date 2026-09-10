import SwiftUI
import NavidromeClient

// MARK: - Rule row

struct RuleRow: View {
    @ObservedObject var node: QueryNode
    let model: QueryEditorModel
    @Environment(AppState.self) private var app
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 0.8 : 0.25)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .draggable(QueryDrag(nodeID: node.id, isGroup: false))
                .accessibilityLabel("Переместить правило")
                .accessibilityAddTraits(.isButton)

            fieldPicker
            opPicker
            valueEditor

            Button {
                withAnimation(Motion.spring(Motion.expand)) {
                    model.remove(node.id)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    // Hit box lives inside the label (frame + contentShape),
                    // so the whole 24pt square clicks, not just the glyph.
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Удалить правило")
            .accessibilityLabel("Удалить правило")
        }
        .padding(.vertical, 2)
        .hoverFill(fill: Color.primary.opacity(0.05), cornerRadius: 6)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Дублировать") { duplicate() }
            Button("Удалить", role: .destructive) {
                withAnimation(Motion.spring(Motion.expand)) { model.remove(node.id) }
            }
        }
    }

    private var current: QueryRule { node.rule ?? .empty }

    private func duplicate() {
        withAnimation(Motion.spring(Motion.expand)) {
            model.duplicate(node.id)
        }
    }

    private var fieldPicker: some View {
        Picker("Поле", selection: fieldBinding) {
            ForEach(QueryField.allCases) { field in Text(field.label.localized).tag(field) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 156)
    }

    private var fieldBinding: Binding<QueryField> {
        Binding(
            get: { current.field },
            set: { newField in
                let allowed = newField.allowedOperators
                let keepsOp = current.field.allowedOperators.contains(current.op)
                let resolved = keepsOp ? current.op : allowed.first ?? .contains
                let value: QueryValue = newField.isBoolean ? .init(number: 1) : .emptyText
                node.kind = .rule(QueryRule(field: newField, op: resolved, value: value))
            }
        )
    }

    private var opPicker: some View {
        Picker("Оператор", selection: opBinding) {
            ForEach(current.field.allowedOperators, id: \.self) { option in Text(option.label.localized).tag(option) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 148)
    }

    private var opBinding: Binding<QueryOperator> {
        Binding(
            get: { current.op },
            set: { node.kind = .rule(QueryRule(field: current.field, op: $0, value: current.value)) }
        )
    }

    private var valueEditor: some View {
        Group {
            if current.field == .playlistID {
                playlistMenu
            } else if current.op.expectsBoolean || current.field.isBoolean {
                Toggle(current.op.expectsBoolean ? "Отметить" : "Избранные", isOn: booleanBinding)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 170, alignment: .leading)
            } else if current.op == .inTheRange {
                rangeEditor
            } else if current.field == .genre {
                genrePicker
            } else if current.field.isNumeric {
                TextField("Значение", text: numericTextBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .monospacedDigit()
            } else {
                TextField("Значение", text: textBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
            }
        }
    }

    /// Two bound inputs for the `inTheRange` operator (numbers for numeric fields,
    /// dates for date fields).
    private var rangeEditor: some View {
        HStack(spacing: 4) {
            rangeField(0, placeholder: "от")
            Text("—").foregroundStyle(.secondary)
            rangeField(1, placeholder: "до")
        }
    }

    private func rangeField(_ index: Int, placeholder: String) -> some View {
        TextField(placeholder, text: rangeTextBinding(index))
            .textFieldStyle(.roundedBorder)
            .frame(width: 84)
            .monospacedDigit()
    }

    private func rangeTextBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let range = current.value.range, range.indices.contains(index) else { return "" }
                return range[index].displayText
            },
            set: { newValue in
                var range = current.value.range ?? [.number(0), .number(0)]
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                let value: JSONValue
                if current.field.isNumeric {
                    let num = Double(trimmed.filter { $0.isNumber || $0 == "." }) ?? 0
                    value = .number(num)
                } else {
                    value = .string(trimmed)
                }
                while range.count <= index { range.append(.number(0)) }
                range[index] = value
                node.kind = .rule(QueryRule(field: current.field, op: current.op, value: .init(range: range)))
            }
        )
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: { current.value.number == 1 },
            set: { node.kind = .rule(QueryRule(
                field: current.field,
                op: current.op,
                value: .init(number: $0 ? 1 : 0))) }
        )
    }

    /// A menu of the user's playlists for `inPlaylist`/`notInPlaylist` rules.
    private var playlistMenu: some View {
        Menu {
            ForEach(app.library.playlists) { playlist in
                Button(playlist.displayName) {
                    node.kind = .rule(QueryRule(field: .playlistID, op: current.op, value: .init(text: playlist.id)))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedPlaylistName)
                    .foregroundStyle(current.value.text?.isEmpty == false ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(width: 170, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.gray.opacity(0.3)))
        }
        .menuStyle(.borderlessButton)
    }

    private var selectedPlaylistName: String {
        guard let id = current.value.text, !id.isEmpty,
              let playlist = app.library.playlists.first(where: { $0.id == id }) else {
            return "Выберите плейлист…"
        }
        return playlist.displayName
    }

    /// Known genres from the server in a menu, so the user never typos a genre
    /// that silently matches nothing. Typed value stays as the "custom" entry.
    private var genrePicker: some View {
        Menu {
            ForEach(app.availableGenres) { genre in
                Button(genre.value ?? "") {
                    node.kind = .rule(QueryRule(field: .genre, op: current.op, value: .init(text: genre.value ?? "")))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.value.text?.isEmpty == false ? current.value.text! : "Выберите жанр…")
                    .foregroundStyle(current.value.text?.isEmpty == false ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(width: 170, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.gray.opacity(0.3)))
        }
        .menuStyle(.borderlessButton)
        .task { await app.loadGenresIfNeeded() }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { current.value.text ?? "" },
            set: { node.kind = .rule(QueryRule(field: current.field, op: current.op, value: .init(text: $0))) }
        )
    }

    private var numericTextBinding: Binding<String> {
        Binding(
            get: { current.value.displayText },
            set: { newValue in
                let num = Double(newValue.filter { $0.isNumber || $0 == "." }) ?? 0
                node.kind = .rule(QueryRule(field: current.field, op: current.op, value: .init(number: num)))
            }
        )
    }
}
