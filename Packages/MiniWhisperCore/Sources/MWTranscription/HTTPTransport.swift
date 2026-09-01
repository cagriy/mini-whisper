import Foundation
import MWSupport

/// The HTTP seam: the real `URLSession` calls live only in `URLSessionTransport`, so
/// `swift test` never reaches the network (N5).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, timeout: Duration) async throws -> (Data, HTTPURLResponse)
}

/// Ephemeral configuration: no cookie, cache or credential persistence (design §5.8).
public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest, timeout: Duration) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = timeout.seconds
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
