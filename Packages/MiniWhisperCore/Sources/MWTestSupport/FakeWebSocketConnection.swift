import Foundation
import MWConfig
import MWStreaming
import MWSupport

/// Scripted websocket: server events are gated on what the client has sent, mirroring
/// `FakeSocket` in `../mini-whisper/tests/test_websocket_engines.py`. When the script
/// runs out, `receive()` blocks until the connection is closed or the task cancelled.
public final class FakeWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    public enum ScriptedError: Error, CustomStringConvertible {
        case server(String)

        public var description: String {
            switch self {
            case .server(let message): message
            }
        }
    }

    private enum Action {
        case deliver(WebSocketMessage)
        case fail(String)
        case pause(Duration)
        case wait
    }

    private let lock = NSLock()
    private let clock: any Clock
    private var steps: [FixtureScript.Step]
    private var sent: [WebSocketMessage] = []
    /// Sent messages already consumed by an `await_client` step.
    private var cursor = 0
    private var closed = false
    private var waiters: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private var cancelledWaiters: Set<UInt64> = []
    private var nextWaiterID: UInt64 = 0

    public init(script: FixtureScript, clock: any Clock) {
        steps = script.steps
        self.clock = clock
    }

    public var sentMessages: [WebSocketMessage] { lock.withLock { sent } }

    public var sentTypes: [String] { sentMessages.map(Self.type(of:)) }

    public var binaryPayloads: [Data] {
        sentMessages.compactMap { message in
            if case .binary(let data) = message { return data }
            return nil
        }
    }

    public func send(_ message: WebSocketMessage) async throws {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            sent.append(message)
            defer { waiters.removeAll() }
            return Array(waiters.values)
        }
        for waiter in pending { waiter.resume() }
    }

    public func receive() async throws -> WebSocketMessage {
        while true {
            try Task.checkCancellation()
            switch lock.withLock({ nextActionLocked() }) {
            case .deliver(let message): return message
            case .fail(let message): throw ScriptedError.server(message)
            case .pause(let duration): try await clock.sleep(for: duration)
            case .wait: await waitForSend()
            }
        }
    }

    public func close() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            closed = true
            defer { waiters.removeAll() }
            return Array(waiters.values)
        }
        for waiter in pending { waiter.resume() }
    }

    private func nextActionLocked() -> Action {
        while case .awaitClient(let want)? = steps.first {
            guard let index = (cursor..<sent.count).first(where: { Self.matches(sent[$0], want) }) else {
                return .wait
            }
            cursor = index + 1
            steps.removeFirst()
        }
        guard !steps.isEmpty else { return .wait }
        switch steps.removeFirst() {
        case .server(let json): return .deliver(.text(json))
        case .serverError(let message): return .fail(message)
        case .pause(let duration): return .pause(duration)
        case .awaitClient: return .wait
        }
    }

    private func waitForSend() async {
        let id = lock.withLock { () -> UInt64 in
            nextWaiterID += 1
            return nextWaiterID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    if closed || cancelledWaiters.remove(id) != nil { return true }
                    waiters[id] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                guard let waiter = waiters.removeValue(forKey: id) else {
                    cancelledWaiters.insert(id)
                    return nil
                }
                return waiter
            }
            waiter?.resume()
        }
    }

    private static func type(of message: WebSocketMessage) -> String {
        switch message {
        case .binary: return "__binary__"
        case .text(let json):
            guard case .object(let fields)? = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
            else { return "" }
            for key in ["type", "message", "message_type"] {
                if case .string(let value)? = fields[key] { return value }
            }
            return ""
        }
    }

    private static func matches(_ message: WebSocketMessage, _ want: FixtureScript.ClientExpectation) -> Bool {
        switch want {
        case .type(let wanted):
            return type(of: message) == wanted
        case .fields(let subset):
            guard case .text(let json) = message,
                  case .object(let fields)? = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
            else { return false }
            return subset.allSatisfy { fields[$0.key] == $0.value }
        }
    }
}
