import Foundation

/// JSON-RPC 2.0 messages of MCP's handshake revisions (2025-06-18, 2025-11-25) and its
/// stateless revision (2026-07-28), as typed structs (design §5.8). Decoding ignores unknown
/// fields and rejects any string over `maximumStringLength` characters.
enum MCP {
    static let maximumStringLength = 10_000

    // MARK: Input

    /// Thrown while decoding a string over `maximumStringLength`.
    struct OverlongString: Error {}

    struct BoundedString: Decodable {
        let value: String

        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            guard value.count <= MCP.maximumStringLength else { throw OverlongString() }
            self.value = value
        }
    }

    /// Any JSON object; its members are not read.
    struct Object: Decodable {
        private enum NoKeys: CodingKey {}

        init(from decoder: any Decoder) throws {
            _ = try decoder.container(keyedBy: NoKeys.self)
        }
    }

    /// A string or an integer; never null.
    enum RequestID: Codable {
        case number(Int)
        case string(String)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                self = .number(number)
            } else {
                self = .string(try container.decode(BoundedString.self).value)
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .number(let number): try container.encode(number)
            case .string(let string): try container.encode(string)
            }
        }
    }

    /// The members every message shares, each read leniently so an error reply can still carry
    /// the id.
    struct Header: Decodable {
        enum ID {
            case absent
            case invalid
            case valid(RequestID)
        }

        let jsonrpc: String?
        let id: ID
        let method: String?

        private enum CodingKeys: String, CodingKey {
            case jsonrpc, id, method
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            jsonrpc = try? container.decode(String.self, forKey: .jsonrpc)
            method = try? container.decode(String.self, forKey: .method)
            if !container.contains(.id) {
                id = .absent
            } else if let value = try? container.decode(RequestID.self, forKey: .id) {
                id = .valid(value)
            } else {
                id = .invalid
            }
        }
    }

    /// A request's `params`, decoded as `Params`.
    struct Request<Params: Decodable>: Decodable {
        let params: Params?
    }

    /// The `_meta` members that select the stateless revision.
    struct MetaParams: Decodable {
        struct Meta: Decodable {
            let protocolVersion: BoundedString?
            let clientCapabilities: Object?

            private enum CodingKeys: String, CodingKey {
                case protocolVersion = "io.modelcontextprotocol/protocolVersion"
                case clientCapabilities = "io.modelcontextprotocol/clientCapabilities"
            }
        }

        let meta: Meta?

        private enum CodingKeys: String, CodingKey {
            case meta = "_meta"
        }
    }

    struct InitializeParams: Decodable {
        let protocolVersion: BoundedString
    }

    struct CallParams: Decodable {
        let name: BoundedString
        /// Read only to reject a non-object; each tool decodes its own arguments.
        let arguments: Object?
    }

    struct CallArguments<Arguments: Decodable>: Decodable {
        let arguments: Arguments?
    }

    struct IDArguments: Decodable {
        let id: BoundedString
    }

    struct SearchArguments: Decodable {
        let query: BoundedString
        let limit: Int?
    }

    // MARK: Output

    struct Response<Result: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: RequestID
        let result: Result
    }

    struct ErrorResponse: Encodable {
        struct Body: Encodable {
            let code: Int
            let message: String
            let data: VersionMismatch?
        }

        let jsonrpc = "2.0"
        /// Absent when the request's id could not be read.
        let id: RequestID?
        let error: Body
    }

    struct VersionMismatch: Encodable {
        let supported: [String]
        let requested: String
    }

    /// Encodes as `{}`.
    struct Empty: Encodable {}

    struct Implementation: Encodable {
        let name: String
        let version: String
    }

    struct Capabilities: Encodable {
        let tools = Empty()
    }

    struct InitializeResult: Encodable {
        let protocolVersion: String
        let capabilities = Capabilities()
        let serverInfo: Implementation
    }

    struct DiscoverResult: Encodable {
        let supportedVersions: [String]
        let capabilities = Capabilities()
    }

    struct ToolList: Encodable {
        let tools: [Tool]
    }

    struct Tool: Encodable {
        struct Annotations: Encodable {
            let readOnlyHint = true
            let openWorldHint = false
        }

        let name: String
        let title: String
        let description: String
        let inputSchema: Schema
        let annotations = Annotations()
    }

    struct Schema: Encodable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]?
        let additionalProperties = false
    }

    struct Property: Encodable {
        let type: String
        let description: String
        var minimum: Int?
        var maximum: Int?
        var maxLength: Int?
    }

    struct ToolResult: Encodable {
        struct Text: Encodable {
            let type = "text"
            let text: String
        }

        let content: [Text]
        let isError: Bool
    }

    /// A result as the stateless revision requires it: `resultType`, the server's identity in
    /// `_meta`, and for cacheable results a cache hint.
    struct Stateless<Body: Encodable>: Encodable {
        let body: Body
        let serverInfo: Implementation
        let cacheable: Bool

        private enum CodingKeys: String, CodingKey {
            case resultType, meta = "_meta", ttlMs, cacheScope
        }

        private struct Meta: Encodable {
            let serverInfo: Implementation

            private enum CodingKeys: String, CodingKey {
                case serverInfo = "io.modelcontextprotocol/serverInfo"
            }
        }

        func encode(to encoder: any Encoder) throws {
            try body.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("complete", forKey: .resultType)
            try container.encode(Meta(serverInfo: serverInfo), forKey: .meta)
            guard cacheable else { return }
            // An app update can change the tool list, so clients should not keep it.
            try container.encode(0, forKey: .ttlMs)
            try container.encode("private", forKey: .cacheScope)
        }
    }
}
