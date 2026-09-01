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

public enum WebSocketConnectionError: Error, CustomStringConvertible {
    case unsupportedMessage

    public var description: String {
        switch self {
        case .unsupportedMessage: "unsupported websocket message kind"
        }
    }
}
