import Foundation
import MWConfig

/// A scripted websocket session, in the schema the Python repo's
/// `tests/fixtures/streaming/*.json` already use:
///
/// - `{"await_client": "<type>"}` — hold until the client has sent a message of that
///   type (`__binary__` for binary frames); a dict matches as a key/value subset
/// - `{"server": {...}}` — deliver this JSON event to the engine
/// - `{"server_error": "msg"}` — `receive()` throws
/// - `{"pause": 0.1}` — wait this long on the injected clock before the next step
public struct FixtureScript: Sendable {
    public enum ClientExpectation: Sendable, Equatable {
        case type(String)
        case fields([String: JSONValue])
    }

    public enum Step: Sendable {
        case awaitClient(ClientExpectation)
        case server(String)
        case serverError(String)
        case pause(Duration)
    }

    public enum LoadError: Error, CustomStringConvertible {
        case malformedStep

        public var description: String {
            switch self {
            case .malformedStep: "fixture step is not one of await_client/server/server_error/pause"
            }
        }
    }

    public var steps: [Step]

    public init(steps: [Step]) {
        self.steps = steps
    }

    public static func load(_ data: Data) throws -> FixtureScript {
        struct Document: Decodable { let steps: [JSONValue] }
        let document = try JSONDecoder().decode(Document.self, from: data)
        return FixtureScript(steps: try document.steps.map(step(from:)))
    }

    private static func step(from value: JSONValue) throws -> Step {
        guard case .object(let fields) = value else { throw LoadError.malformedStep }
        if let want = fields["await_client"] {
            switch want {
            case .string(let type): return .awaitClient(.type(type))
            case .object(let subset): return .awaitClient(.fields(subset))
            default: throw LoadError.malformedStep
            }
        }
        if let event = fields["server"] {
            return .server(try encode(event))
        }
        if case .string(let message)? = fields["server_error"] {
            return .serverError(message)
        }
        if case .number(let seconds)? = fields["pause"] {
            return .pause(.seconds(seconds))
        }
        throw LoadError.malformedStep
    }

    private static func encode(_ value: JSONValue) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
