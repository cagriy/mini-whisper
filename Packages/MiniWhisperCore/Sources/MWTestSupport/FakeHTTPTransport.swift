import Foundation
import MWSupport
import MWTranscription

/// One canned HTTP reply.
public struct HTTPStub: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int = 200, json: String = "{}") {
        self.status = status
        body = Data(json.utf8)
    }
}

/// Records the requests the client builds and replays canned replies; the last stub
/// repeats once the script runs out.
public final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    public struct Call: @unchecked Sendable {
        public let request: URLRequest
        public let timeout: Duration
    }

    private let lock = NSLock()
    private var stubs: [HTTPStub]
    private let failure: (any Error)?
    private var recorded: [Call] = []

    public init(stubs: [HTTPStub] = [HTTPStub()], failure: (any Error)? = nil) {
        self.stubs = stubs
        self.failure = failure
    }

    public var calls: [Call] { lock.withLock { recorded } }

    public func send(_ request: URLRequest, timeout: Duration) async throws -> (Data, HTTPURLResponse) {
        let stub = try lock.withLock { () -> HTTPStub in
            recorded.append(Call(request: request, timeout: timeout))
            if let failure { throw failure }
            return stubs.count > 1 ? stubs.removeFirst() : (stubs.first ?? HTTPStub())
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: stub.status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (stub.body, response)
    }
}
