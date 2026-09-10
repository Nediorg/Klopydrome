import Foundation
import NavidromeClient

// MARK: - Operators

/// Comparison operators for a single rule, matching the "smart playlist"
/// rule DSL used across the Subsonic ecosystem. `dsl` is the server
/// operator name.
enum QueryOperator: String, CaseIterable, Hashable {
    case is_
    case isNot
    case contains
    case notContains
    case startsWith
    case endsWith
    case gt
    case gte
    case lt
    case lte
    case inTheRange
    case inTheLast
    case notInTheLast
    case before
    case after
    case inPlaylist
    case notInPlaylist
    case isMissing
    case isPresent

    var dsl: String {
        switch self {
        case .is_: return "is"
        case .isNot: return "isNot"
        case .inTheRange: return "inTheRange"
        case .inTheLast: return "inTheLast"
        case .notInTheLast: return "notInTheLast"
        case .notInPlaylist: return "notInPlaylist"
        case .isMissing: return "isMissing"
        case .isPresent: return "isPresent"
        default: return rawValue
        }
    }

    var label: String {
        switch self {
        case .is_: return "равно"
        case .isNot: return "не равно"
        case .contains: return "содержит"
        case .notContains: return "не содержит"
        case .startsWith: return "начинается с"
        case .endsWith: return "заканчивается на"
        case .gt: return "больше"
        case .gte: return "не меньше"
        case .lt: return "меньше"
        case .lte: return "не больше"
        case .inTheRange: return "в диапазоне"
        case .inTheLast: return "за последние (дней)"
        case .notInTheLast: return "не было за последние (дней)"
        case .before: return "до даты"
        case .after: return "после даты"
        case .inPlaylist: return "в плейлисте"
        case .notInPlaylist: return "не в плейлисте"
        case .isMissing: return "пустое / отсутствует"
        case .isPresent: return "заполнено / есть"
        }
    }

    /// Text/string operators (LIKE family on the server).
    var isStringLike: Bool {
        switch self {
        case .contains, .notContains, .startsWith, .endsWith: return true
        default: return false
        }
    }

    /// Operators usable on date fields ({YYYY-MM-DD} range predicates).
    var isDateRange: Bool {
        switch self {
        case .inTheRange, .inTheLast, .notInTheLast, .before, .after: return true
        default: return false
        }
    }

    /// Whether the rule's expected value is a boolean flag (true/false).
    var expectsBoolean: Bool {
        self == .isMissing || self == .isPresent
    }

    fileprivate static func fromDSL(_ string: String) -> QueryOperator? {
        if string == "is" { return .is_ }
        return QueryOperator(rawValue: string)
    }
}

// MARK: - Group logic

enum QueryGroupLogic: String, CaseIterable, Hashable {
    case all
    case any

    var label: String {
        switch self {
        case .all: return "Выполняются все"
        case .any: return "Выполняется любое"
        }
    }
}

// MARK: - Value

struct QueryValue: Equatable, Hashable {
    let text: String?
    let number: Double?
    /// `inTheRange` bounds, e.g. numeric [min, max] or date ["YYYY-MM-DD", …].
    let range: [JSONValue]?

    init(text: String) { self.text = text; self.number = nil; self.range = nil }
    init(number: Double) { self.text = nil; self.number = number; self.range = nil }
    init(range: [JSONValue]) { self.text = nil; self.number = nil; self.range = range }
    init(json: JSONValue?) {
        switch json {
        case .string(let text): self = .init(text: text)
        case .number(let value): self = .init(number: value)
        case .bool(let flag): self = .init(number: flag ? 1 : 0)
        case .array(let items): self = .init(range: items)
        case nil: self = .init(text: "")
        }
    }

    static let emptyText = QueryValue(text: "")

    var displayText: String {
        if let number { return number.truncatedString }
        if let range {
            let parts = range.map(\.displayText).joined(separator: " … ")
            return "[\(parts)]"
        }
        return text ?? ""
    }

    /// Zero text (including all-whitespace) counts as "empty"/unset.
    var isEmpty: Bool {
        if let number { return number == 0 }
        if let range { return range.allSatisfy(\.isEmpty) }
        return text?.trimmingCharacters(in: .whitespaces).isEmpty ?? true
    }

    var jsonValue: JSONValue {
        if let number { return .number(number) }
        if let range { return .array(range) }
        return .string(text ?? "")
    }
}

extension Double {
    var truncatedString: String {
        if self == rounded() { return String(Int(self)) }
        return String(self)
    }
}

// MARK: - Rule

struct QueryRule: Equatable, Hashable {
    var field: QueryField
    var op: QueryOperator
    var value: QueryValue
    /// Raw DSL name of an unknown field kept verbatim (with `field == .custom`)
    /// so server rules using custom tags round-trip without corruption.
    var customField: String?

    static let empty = QueryRule(field: .artist, op: .contains, value: .emptyText)
}

// MARK: - Fields

// `QueryField` (full server vocabulary) lives in SmartFields.swift.

// MARK: - QueryNode (reference-semantics tree)

/// A node in the query tree. A `group` holds ordered children; a `rule` holds a
/// predicate. Reference semantics give every node a stable `id`, which SwiftUI's
/// `.draggable()`/`.dropDestination()` needs for reliable identity across passes.
final class QueryNode: Identifiable, ObservableObject {
    let id = UUID()

    enum Kind: Equatable {
        case group(QueryGroupLogic)
        case rule(QueryRule)
    }

    @Published var kind: Kind
    @Published var children: [QueryNode] = []

    init(_ kind: Kind) { self.kind = kind }

    /// Deep copy of another node: kind plus recursively copied children.
    convenience init(style: QueryNode) {
        self.init(style.kind)
        children = style.children.map { QueryNode(style: $0) }
    }

    var isGroup: Bool {
        if case .group = kind { return true }
        return false
    }

    var logic: QueryGroupLogic? {
        if case .group(let logic) = kind { return logic }
        return nil
    }

    var rule: QueryRule? {
        if case .rule(let rule) = kind { return rule }
        return nil
    }

    func mapExpr() -> QueryExpr {
        switch kind {
        case .group(let logic):
            return QueryExpr(group: logic, children: children.map { $0.mapExpr() })
        case .rule(let rule):
            let fieldDSL = rule.customField ?? rule.field.dsl
            return QueryExpr(rule: rule.op, field: fieldDSL, value: rule.value.jsonValue)
        }
    }
}

// MARK: - JSON wire model (server smart-playlist DSL)

/// Single-key object → dynamic coding keys: produces `{ "<key>": value }`
/// exactly like the server DSL (a group key like "all", or an operator key).
struct DynKey: CodingKey {
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
    var stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }
    init(_ s: String) { self.stringValue = s }
}

enum JSONValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { self = .string(text); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let flag = try? container.decode(Bool.self) { self = .bool(flag); return }
        if let items = try? container.decode([JSONValue].self) { self = .array(items); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text): try container.encode(text)
        case .number(let value): try container.encode(value)
        case .bool(let flag): try container.encode(flag)
        case .array(let items): try container.encode(items)
        }
    }

    /// Zero text (including whitespace-only) and zero numbers count as "unset".
    var isEmpty: Bool {
        switch self {
        case .string(let text): return text.trimmingCharacters(in: .whitespaces).isEmpty
        case .number(let value): return value == 0
        case .bool: return false
        case .array(let items): return items.allSatisfy(\.isEmpty)
        }
    }
}

/// A node in JSON form: exactly one payload key ("all"/"any" for groups, an
/// operator name for rules) mapping to either an expression array or `{field:value}`.
struct QueryExpr: Codable, Equatable, Hashable {
    var isGroup: Bool
    var groupLogic: QueryGroupLogic?
    var op: QueryOperator?
    var field: String?
    var value: JSONValue?
    var children: [QueryExpr]

    init(group logic: QueryGroupLogic, children: [QueryExpr]) {
        isGroup = true
        groupLogic = logic
        self.children = children
    }

    init(rule op: QueryOperator, field: String, value: JSONValue) {
        isGroup = false
        self.op = op
        self.field = field
        self.value = value
        children = []
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynKey.self)
        // Ignore the SmartQuery meta keys that can sit alongside the root
        // expression in the same JSON object (sort/limit/limitPercent/offset/
        // refreshDelay + the legacy liveUpdate/order markers).
        let metaKeys = ["sort", "limit", "limitPercent", "offset", "refreshDelay", "liveUpdate", "order"]
        let keys = c.allKeys.filter { !metaKeys.contains($0.stringValue) }
        guard let key = keys.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Empty expression"))
        }
        if let logic = QueryGroupLogic(rawValue: key.stringValue) {
            let arr = try c.decode([QueryExpr].self, forKey: key)
            self.init(group: logic, children: arr)
        } else if let op = QueryOperator.fromDSL(key.stringValue) {
            let sub = try c.nestedContainer(keyedBy: DynKey.self, forKey: key)
            guard let fieldKey = sub.allKeys.first else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Empty rule"))
            }
            let val = try sub.decode(JSONValue.self, forKey: fieldKey)
            self.init(rule: op, field: fieldKey.stringValue, value: val)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unrecognized key: \(key.stringValue)"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynKey.self)
        if isGroup, let logic = groupLogic {
            let key = DynKey(logic.rawValue)
            try c.encode(children, forKey: key)
        } else if let op, let field, let value {
            let key = DynKey(op.dsl)
            var sub = c.nestedContainer(keyedBy: DynKey.self, forKey: key)
            try sub.encode(value, forKey: DynKey(field))
        }
    }

    func matches(_ song: SubsonicSong) -> Bool {
        if isGroup, let logic = groupLogic {
            if children.isEmpty { return false }
            switch logic {
            case .all: return children.allSatisfy { $0.matches(song) }
            case .any: return children.contains { $0.matches(song) }
            }
        }
        guard let op, let field, let value else { return false }
        // A blank text rule (e.g. an untouched "contains") must not match every
        // song. Numeric values — including 0 for boolean fields like "starred" —
        // are legitimate comparison values and are never treated as unset.
        if case .string(let s) = value, s.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        let actual = QueryField(dsl: field)?.value(from: song)
        let expected = QueryValue(json: value)
        return op.matches(actual: actual, expected: expected)
    }
}

/// The full query document: a root expression plus optional sort/limit and the
/// server's top-level meta keys (limitPercent/offset/refreshDelay are preserved
/// on round-trip but not exposed in the editor).
struct SmartQuery: Codable, Equatable, Hashable {
    var root: QueryExpr
    var sort: String?
    var limit: Int?
    var limitPercent: Int?
    var offset: Int?
    var refreshDelay: String?
    /// Server global sort-direction override ("asc"/"desc") that reverses every
    /// sort field. Passed through for lossless round-trip; the editor re-picks
    /// per-field direction instead.
    var order: String?

    enum StaticKeys: String, CodingKey {
        case sort, limit, limitPercent, offset, refreshDelay, order
    }

    init(root: QueryExpr, sort: String? = nil, limit: Int? = nil,
         limitPercent: Int? = nil, offset: Int? = nil, refreshDelay: String? = nil,
         order: String? = nil) {
        self.root = root
        self.sort = sort
        self.limit = limit
        self.limitPercent = limitPercent
        self.offset = offset
        self.refreshDelay = refreshDelay
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let meta = try decoder.container(keyedBy: StaticKeys.self)
        sort = try meta.decodeIfPresent(String.self, forKey: .sort)
        limit = try meta.decodeIfPresent(Int.self, forKey: .limit)
        limitPercent = try meta.decodeIfPresent(Int.self, forKey: .limitPercent)
        offset = try meta.decodeIfPresent(Int.self, forKey: .offset)
        refreshDelay = try meta.decodeIfPresent(String.self, forKey: .refreshDelay)
        order = try meta.decodeIfPresent(String.self, forKey: .order)
        root = try QueryExpr(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var meta = encoder.container(keyedBy: StaticKeys.self)
        try meta.encodeIfPresent(sort, forKey: .sort)
        try meta.encodeIfPresent(limit, forKey: .limit)
        try meta.encodeIfPresent(limitPercent, forKey: .limitPercent)
        try meta.encodeIfPresent(offset, forKey: .offset)
        try meta.encodeIfPresent(refreshDelay, forKey: .refreshDelay)
        try meta.encodeIfPresent(order, forKey: .order)
        try root.encode(to: encoder)
    }
}

// MARK: - Tree building from JSON

extension QueryNode {

    /// Build a UI tree from a `SmartQuery`'s root expression.
    convenience init(query: SmartQuery) {
        let root = query.root
        if root.isGroup, let logic = root.groupLogic {
            self.init(.group(logic))
            replace(with: root)
        } else {
            self.init(.group(.all))
            children = [QueryNode(expr: root)]
        }
    }

    /// A bare expression (group or rule) as a standalone node.
    convenience init(expr: QueryExpr) {
        if expr.isGroup, let logic = expr.groupLogic {
            self.init(.group(logic))
            replace(with: expr)
        } else if let op = expr.op, let field = expr.field {
            let knownField = QueryField(dsl: field)
            let rule = QueryRule(field: knownField ?? .custom,
                                 op: op,
                                 value: QueryValue(json: expr.value),
                                 customField: knownField == nil ? field : nil)
            self.init(.rule(rule))
        } else {
            self.init(.group(.all))
        }
    }

    /// Fill this (group) node's children from a JSON expression.
    func replace(with expr: QueryExpr) {
        children = []
        for child in expr.children {
            children.append(QueryNode(expr: child))
        }
    }
}
