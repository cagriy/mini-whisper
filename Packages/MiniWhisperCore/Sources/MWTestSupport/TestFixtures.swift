import Foundation

/// Fixtures shared by several test targets, copied from the Python repo.
public enum TestFixtures {
    public enum FixtureError: Error, CustomStringConvertible {
        case missing(String)

        public var description: String {
            switch self {
            case .missing(let name): "fixture \(name) is not in the MWTestSupport bundle"
            }
        }
    }

    /// A WAV from `../mini-whisper/tests/fixtures/wav/`, by base name.
    public static func wav(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures/wav")
        else { throw FixtureError.missing(name) }
        return url
    }
}
