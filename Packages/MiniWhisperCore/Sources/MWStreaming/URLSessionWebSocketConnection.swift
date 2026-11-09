import Foundation

/// `URLSessionWebSocketTask` over an ephemeral session — no cookie or cache
/// persistence (design §5.8). Adapter headers carry the API key and are never logged.
public final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    public init(url: URL, headers: [String: String]) {
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        session = URLSession(configuration: .ephemeral)
        task = session.webSocketTask(with: request)
        task.resume()
    }

    public func send(_ message: WebSocketMessage) async throws {
        switch message {
        case .text(let text): try await task.send(.string(text))
        case .binary(let data): try await task.send(.data(data))
        }
    }

    public func receive() async throws -> WebSocketMessage {
        let message: URLSessionWebSocketTask.Message
        do {
            message = try await task.receive()
        } catch {
            throw Self.closeError(code: task.closeCode.rawValue, reason: task.closeReason) ?? error
        }
        switch message {
        case .string(let text): return .text(text)
        case .data(let data): return .binary(data)
        @unknown default: throw WebSocketConnectionError.unsupportedMessage
        }
    }

    /// The server's close frame as an error, or `nil` when the socket was not closed by
    /// a close frame (`.invalid`).
    public static func closeError(code: Int, reason: Data?) -> WebSocketConnectionError? {
        guard code != URLSessionWebSocketTask.CloseCode.invalid.rawValue else { return nil }
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }
        return .closed(code: code, reason: text?.isEmpty == false ? text : nil)
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}
