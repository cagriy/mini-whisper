import Foundation
import MWConfig

/// A voice embedding: 256 floats, stored as the base64 of their little-endian float32 bytes.
public struct VoiceVector: Codable, Sendable, Equatable {
    public static let dimension = 256

    public var values: [Float]

    public init(_ values: [Float]) {
        self.values = values
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let data = Data(base64Encoded: try container.decode(String.self)),
              data.count == Self.dimension * MemoryLayout<UInt32>.size
        else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "not the base64 of \(Self.dimension) float32 values"
            )
        }
        values = data.withUnsafeBytes { bytes in
            (0..<Self.dimension).map { index in
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(
                    fromByteOffset: index * MemoryLayout<UInt32>.size, as: UInt32.self
                )))
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var data = Data(capacity: values.count * MemoryLayout<UInt32>.size)
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        var container = encoder.singleValueContainer()
        try container.encode(data.base64EncodedString())
    }

    /// Zero when either vector has no length or the dimensions differ.
    public func cosine(_ other: VoiceVector) -> Double {
        guard values.count == other.values.count else { return 0 }
        var dot = 0.0, left = 0.0, right = 0.0
        for (a, b) in zip(values, other.values) {
            dot += Double(a) * Double(b)
            left += Double(a) * Double(a)
            right += Double(b) * Double(b)
        }
        guard left > 0, right > 0 else { return 0 }
        return dot / (left.squareRoot() * right.squareRoot())
    }

    /// Unit length; a zero vector stays zero.
    public var normalised: VoiceVector {
        let length = values.reduce(0.0) { $0 + Double($1) * Double($1) }.squareRoot()
        guard length > 0 else { return self }
        return VoiceVector(values.map { Float(Double($0) / length) })
    }

    /// The normalised, seconds-weighted sum (R7); nil when there is nothing to combine.
    public static func combine(_ parts: [(VoiceVector, seconds: Double)]) -> VoiceVector? {
        guard let dimension = parts.first?.0.values.count else { return nil }
        var sum = [Double](repeating: 0, count: dimension)
        for (vector, seconds) in parts where vector.values.count == dimension {
            for index in 0..<dimension { sum[index] += Double(vector.values[index]) * seconds }
        }
        let combined = VoiceVector(sum.map { Float($0) }).normalised
        return combined.values.contains { $0 != 0 } ? combined : nil
    }
}

/// A name the app attached to a provider key from a known person's voice.
public struct NameMatch: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case suggested, applied }

    /// The provider key, `"<session>:<label>"`.
    public var key: String
    /// The person's name when matched.
    public var name: String
    /// Nil only for a future non-voice source.
    public var person: UUID?
    public var source: String
    public var state: State
    /// Nil on the Speechmatics route.
    public var score: Double?

    public init(
        key: String, name: String, person: UUID?, source: String = "voice", state: State, score: Double? = nil
    ) {
        self.key = key
        self.name = name
        self.person = person
        self.source = source
        self.state = state
        self.score = score
    }
}

/// `voices.json` in a meeting's folder: its speakers' vectors or identifiers, never audio.
public struct MeetingVoices: Codable, Sendable, Equatable {
    public static let currentSchema = 1
    /// The user's microphone voice in a remote meeting on the local route.
    public static let userKey = "user"

    public struct Entry: Codable, Sendable, Equatable {
        /// The speech behind the entry.
        public var seconds: Double
        public var vector: VoiceVector?
        public var identifier: String?

        public init(seconds: Double, vector: VoiceVector? = nil, identifier: String? = nil) {
            self.seconds = seconds
            self.vector = vector
            self.identifier = identifier
        }
    }

    public var schema: Int
    public var route: VoiceRoute
    /// `wespeaker_v2` on the local route, the tier on Speechmatics.
    public var model: String
    public var keys: [String: Entry]

    public init(route: VoiceRoute, model: String, keys: [String: Entry] = [:]) {
        schema = Self.currentSchema
        self.route = route
        self.model = model
        self.keys = keys
    }
}
