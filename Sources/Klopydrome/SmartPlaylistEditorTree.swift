import SwiftUI
import NavidromeClient

// MARK: - Tree mutation helpers

enum QueryTree {

    static func locate(_ id: UUID, in root: QueryNode) -> (parent: QueryNode, index: Int)? {
        for (index, child) in root.children.enumerated() {
            if child.id == id { return (root, index) }
            if child.isGroup, let found = locate(id, in: child) { return found }
        }
        return nil
    }

    static func node(_ id: UUID, in root: QueryNode) -> QueryNode? {
        if root.id == id { return root }
        for child in root.children {
            if let found = node(id, in: child) { return found }
        }
        return nil
    }

    static func isAncestor(_ node: QueryNode, of target: QueryNode) -> Bool {
        if node === target { return true }
        return node.children.contains { isAncestor($0, of: target) }
    }

    static func pruneEmpty(in root: QueryNode) {
        root.children.removeAll { $0.isGroup && $0.children.isEmpty }
        for child in root.children where child.isGroup {
            pruneEmpty(in: child)
        }
    }

    static func remove(_ id: UUID, in root: QueryNode) {
        guard let loc = locate(id, in: root) else { return }
        loc.parent.children.remove(at: loc.index)
        pruneEmpty(in: root)
    }

    static func move(nodeID: UUID, intoGroup groupID: UUID, at index: Int, root: QueryNode) -> Bool {
        guard let source = node(nodeID, in: root),
              let target = node(groupID, in: root),
              let loc = locate(nodeID, in: root) else { return false }
        if source.isGroup, isAncestor(source, of: target) { return false }

        var dest = index
        if loc.parent === target, let srcIndex = target.children.firstIndex(where: { $0.id == nodeID }),
           srcIndex < index {
            dest -= 1
        }
        loc.parent.children.remove(at: loc.index)
        target.children.insert(source, at: dest)
        pruneEmpty(in: root)
        return true
    }
}
// MARK: - Editor model

@MainActor
final class QueryEditorModel: ObservableObject {
    @Published var root: QueryNode
    @Published var insertion: (groupID: UUID, index: Int)?

    init(root: QueryNode) {
        self.root = root
    }

    @discardableResult
    func move(nodeID: UUID, intoGroup groupID: UUID, at index: Int) -> Bool {
        let moved = QueryTree.move(nodeID: nodeID, intoGroup: groupID, at: index, root: root)
        if moved { objectWillChange.send() }
        return moved
    }

    func remove(_ id: UUID) {
        QueryTree.remove(id, in: root)
    }

    /// Insert a deep copy of the node right after itself in the same group.
    func duplicate(_ id: UUID) {
        guard let loc = QueryTree.locate(id, in: root) else { return }
        let copy = QueryNode(style: loc.parent.children[loc.index])
        loc.parent.children.insert(copy, at: loc.index + 1)
    }

    func offer(_ groupID: UUID, _ index: Int) {
        insertion = (groupID, index)
    }

    func clearInsertion(ifCurrent groupID: UUID, at index: Int) {
        if insertion?.groupID == groupID, insertion?.index == index {
            insertion = nil
        }
    }

    func ruleCount() -> Int { count(in: root) }

    private func count(in node: QueryNode) -> Int {
        node.children.reduce(0) { acc, child in
            child.isGroup ? acc + count(in: child) : acc + 1
        }
    }
}
// MARK: - Recursive group view

struct GroupRecursiveView: View {
    @ObservedObject var group: QueryNode
    var root: QueryNode
    var model: QueryEditorModel
    var depth: Int = 0

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            childrenBlock
            addRow
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(nestedSurface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(isDropTarget ? AMColor.accent : Color.gray.opacity(0.28),
                          lineWidth: isDropTarget ? 2 : 1))
        .overlay(alignment: .leading) {
            // Hierarchy rail: makes nesting readable at a glance.
            if depth > 0 {
                Rectangle().fill(Color.gray.opacity(0.35))
                    .frame(width: 2)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)
            }
        }
        .padding(.leading, depth > 0 ? 22 : 0)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Дублировать группу") { duplicateSelf() }
            Button("Удалить группу", role: .destructive) {
                withAnimation(Motion.spring(Motion.expand)) { model.remove(group.id) }
            }
        }
        .dropDestination(for: QueryDrag.self) { payload, _ in
            guard let drag = payload.first else { return false }
            return model.move(nodeID: drag.nodeID, intoGroup: group.id, at: children.count)
        } isTargeted: { targeted in
            isDropTarget = targeted
            if targeted { model.offer(group.id, children.count) }
        }
    }

    /// Slightly stronger fill for nested groups so the hierarchy reads clearly.
    private var nestedSurface: Color {
        if depth == 0 { return AMColor.surface.opacity(0.4) }
        return Color.gray.opacity(0.10 + Double(depth) * 0.03)
    }

    private var children: [QueryNode] { group.children }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .draggable(QueryDrag(nodeID: group.id, isGroup: true))
                .help("Переместить группу")
                .accessibilityLabel("Переместить группу")

            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d.down.right").foregroundStyle(.secondary)
                Text("Группа".localized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .fixedSize()
            Picker("Логика", selection: logicBinding) {
                ForEach(QueryGroupLogic.allCases, id: \.self) { logic in
                    Text(logic.label.localized).tag(logic)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 12)
            if depth > 0 {
                Button {
                    withAnimation(Motion.spring(Motion.expand)) { model.remove(group.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Удалить группу")
                .accessibilityLabel("Удалить группу")
            }
        }
    }

    /// Buttons that add to THIS group, placed where new rules appear (bottom),
    /// so the eye doesn't have to jump from the header to the append point.
    private var addRow: some View {
        HStack(spacing: 10) {
            addAction(Label("Правило", systemImage: "plus"), help: "Добавить правило") { addRule() }
            addAction(Label("Группа", systemImage: "plus.square.stack"),
                      help: "Добавить вложенную группу") { addGroup() }
            Spacer()
        }
        .padding(.top, 2)
    }

    /// A constructive "add" action. The editor's root tints everything with the
    /// system accent, so no per-button tint is needed here.
    private func addAction(_ label: Label<Text, Image>, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { label }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
    }

    private var logicBinding: Binding<QueryGroupLogic> {
        Binding(
            get: { group.logic ?? .all },
            set: { newValue in
                if case .group = group.kind { group.kind = .group(newValue) }
            }
        )
    }

    private var childrenBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                insertionSlot(at: index)
                childRow(child)
            }
            insertionSlot(at: children.count)
        }
    }

    private func insertionSlot(at index: Int) -> some View {
        let isHovered = model.insertion?.groupID == group.id && model.insertion?.index == index
        return SlotLine(isHighlighted: isHovered)
            .dropDestination(for: QueryDrag.self) { payload, _ in
                guard let drag = payload.first else { return false }
                return model.move(nodeID: drag.nodeID, intoGroup: group.id, at: index)
            } isTargeted: { targeted in
                if targeted {
                    model.offer(group.id, index)
                } else {
                    model.clearInsertion(ifCurrent: group.id, at: index)
                }
            }
    }

    @ViewBuilder
    private func childRow(_ node: QueryNode) -> some View {
        if node.isGroup {
            GroupRecursiveView(group: node, root: root, model: model, depth: depth + 1)
        } else {
            RuleRow(node: node, model: model)
        }
    }

    private func addRule() { addNode(QueryNode(.rule(.empty))) }
    private func addGroup() { addNode(QueryNode(.group(.all))) }

    private func addNode(_ node: QueryNode) {
        withAnimation(Motion.spring(Motion.expand)) {
            group.children.append(node)
        }
    }
    private func duplicateSelf() {
        withAnimation(Motion.spring(Motion.expand)) {
            model.duplicate(group.id)
        }
    }
}
/// Insertion slots between rows. Kept slim (10pt still catches drops; the
/// group container itself accepts drops appended at the end), so stacked
/// rules don't drift apart — the old 22pt slots read as huge dead gaps.
private struct SlotLine: View {
    let isHighlighted: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(maxWidth: .infinity, minHeight: 10)
            if isHighlighted {
                AMColor.accent.frame(height: 2)
            }
        }
        .contentShape(Rectangle())
    }
}
