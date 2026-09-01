import Foundation
import MWConfig

/// A provider rejected the session or the audio; the engine fails once and the
/// pipeline falls back to batch transcription (F20, F21).
public enum CloudAdapterError: Error, Equatable, CustomStringConvertible {
    case provider(engine: EngineName, detail: String)

    public var description: String {
        switch self {
        case .provider(let engine, let detail): "\(engine.rawValue) error: \(detail)"
        }
    }
}

/// The JSON plumbing the three cloud adapters share (design §5.4).
enum AdapterJSON {
    /// One JSON object as a text frame.
    static func text(_ fields: [String: JSONValue]) -> WebSocketMessage {
        .text(compact(.object(fields)))
    }

    /// The object a text frame carries; nil for binary and non-object frames.
    static func fields(_ message: WebSocketMessage) -> [String: JSONValue]? {
        guard case .text(let json) = message,
              case .object(let fields)? = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        else { return nil }
        return fields
    }

    /// Compact JSON for an error detail.
    static func compact(_ value: JSONValue?) -> String {
        guard let value, let data = try? JSONEncoder().encode(value) else { return "unknown" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}
