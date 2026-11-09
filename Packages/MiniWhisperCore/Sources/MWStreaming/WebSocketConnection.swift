import Foundation

public enum WebSocketMessage: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// The socket seam: the real transport in `URLSessionWebSocketConnection`, a scripted
/// one in tests (design §5.2).
public protocol WebSocketConnection: Sendable {
    func send(_ message: WebSocketMessage) async throws
    func receive() async throws -> WebSocketMessage
    func close()
}

/// `LocalizedError` so `AnyError`, and with it the engine's failure log, names the close
/// code.
public enum WebSocketConnectionError: LocalizedError, Equatable, CustomStringConvertible {
    case unsupportedMessage
    /// The server closed the socket.
    case closed(code: Int, reason: String?)

    public var description: String {
        switch self {
        case .unsupportedMessage: "unsupported websocket message kind"
        case .closed(let code, let reason?): "websocket closed by server (\(code): \(reason))"
        case .closed(let code, nil): "websocket closed by server (\(code))"
        }
    }

    public var errorDescription: String? { description }
}
