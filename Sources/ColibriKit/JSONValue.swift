import Foundation

/// A tolerant JSON value for fields whose shape Colibri does not promise.
public enum JSONValue: Sendable, Equatable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// A string form for scalar values; empty for null, arrays and objects.
    public var displayString: String {
        switch self {
        case .null, .array, .object: return ""
        case .bool(let value): return value ? "1" : "0"
        case .string(let value): return value
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
            return String(value)
        }
    }
}
