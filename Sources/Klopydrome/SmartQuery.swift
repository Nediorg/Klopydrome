import Foundation
import NavidromeClient

// MARK: - Operators

enum QueryOperator: String, CaseIterable, Hashable {
    case `is` = "is"
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

    var dsl: String { rawValue }

    var label: String {
        switch self {
        case .is: return "equals"
        case .isNot: return "not equal"
        case .contains: return "contains"
        case .notContains: return "does not contain"
        case .startsWith: return "starts with"
        case .endsWith: return "ends with"
        case .gt: return "greater than"
        case .gte: return "not less than"
        case .lt: return "less than"
        case .lte: return "not more than"
        case .inTheRange: return "in range"
        case .inTheLast: return "in the last (days)"
        case .notInTheLast: return "not in the last (days)"
        case .before: return "before date"
        case .after: return "after date"
        case .inPlaylist: return "in playlist"
        case .notInPlaylist: return "not in playlist"
        case .isMissing: return "empty / missing"
        case .isPresent: return "filled / exists"
        }
    }

    var isStringLike: Bool {
        switch self {
        case .contains, .notContains, .startsWith, .endsWith: return true
        default: return false
        }
    }

    var isDateRange: Bool {
        switch self {
        case .inTheRange, .inTheLast, .notInTheLast, .before, .after: return true
        default: return false
        }
    }

    var expectsBoolean: Bool {
        self == .isMissing || self == .isPresent
    }
}

enum QueryGroupLogic: String, CaseIterable, Hashable {
    case all
    case any

    var label: String {
        switch self {
        case .all: return "All rules match"
        case .any: return "Any rule matches"
        }
    }
}

struct QueryValue: Equatable, Hashable {
    let text: String?
    let number: Double?
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

struct QueryRule: Equatable, Hashable {
    var field: QueryField
    var op: QueryOperator
    var value: QueryValue
    var customField: String?

    static let empty = QueryRule(field: .artist, op: .contains, value: .emptyText)
}

final class QueryNode: Identifiable, ObservableObject {
    let id = UUID()

    enum Kind: Equatable {
        case group(QueryGroupLogic)
        case rule(QueryRule)
    }

    @Published var kind: Kind
    @Published var children: [QueryNode] = []

    init(_ kind: Kind) { self.kind = kind }

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

    var isEmpty: Bool {
        switch self {
        case .string(let text): return text.trimmingCharacters(in: .whitespaces).isEmpty
        case .number(let value): return value == 0
        case .bool: return false
        case .array(let items): return items.allSatisfy(\.isEmpty)
        }
    }
}

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
        let metaKeys = ["sort", "limit", "limitPercent", "offset", "refreshDelay", "liveUpdate", "order"]
        let keys = c.allKeys.filter { !metaKeys.contains($0.stringValue) }
        guard let key = keys.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Empty expression"))
        }
        if let logic = QueryGroupLogic(rawValue: key.stringValue) {
            let arr = try c.decode([QueryExpr].self, forKey: key)
            self.init(group: logic, children: arr)
        } else if let queryOperator = QueryOperator(rawValue: key.stringValue) {
            let sub = try c.nestedContainer(keyedBy: DynKey.self, forKey: key)
            guard let fieldKey = sub.allKeys.first else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Empty rule"))
            }
            let val = try sub.decode(JSONValue.self, forKey: fieldKey)
            self.init(rule: queryOperator, field: fieldKey.stringValue, value: val)
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
        if case .string(let s) = value, s.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        let actual = QueryField(dsl: field)?.value(from: song)
        let expected = QueryValue(json: value)
        return op.matches(actual: actual, expected: expected)
    }
}

struct SmartQuery: Codable, Equatable, Hashable {
    var root: QueryExpr
    var sort: String?
    var limit: Int?
    var limitPercent: Int?
    var offset: Int?
    var refreshDelay: String?
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

    func replace(with expr: QueryExpr) {
        children = []
        for child in expr.children {
            children.append(QueryNode(expr: child))
        }
    }
}
