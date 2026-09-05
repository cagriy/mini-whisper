import Foundation
import MWConfig
import MWCorrections
import MWStreaming

/// A scripted `EngineProvider`: hands back a prepared selection and records what the
/// pipeline asked for, so press-path tests need no real engine.
public final class FakeEngineProvider: EngineProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var selection: EngineSelection
    private var configs: [Config] = []
    private var hints: [RecognitionHints] = []

    public init(engine: (any StreamingEngine)? = nil, notice: EngineNotice? = nil) {
        selection = EngineSelection(engine: engine, notice: notice)
    }

    public var requestedEngines: [EngineName?] { lock.withLock { configs.map(\.streamingEngine) } }
    public var callCount: Int { lock.withLock { configs.count } }
    public var requestedHints: [RecognitionHints] { lock.withLock { hints } }

    /// Changes what the next `make` returns.
    public func set(engine: (any StreamingEngine)?, notice: EngineNotice? = nil) {
        lock.withLock { selection = EngineSelection(engine: engine, notice: notice) }
    }

    public func make(
        config: Config,
        secrets: any SecretStore,
        hints: RecognitionHints
    ) async -> EngineSelection {
        lock.withLock {
            configs.append(config)
            self.hints.append(hints)
            return selection
        }
    }
}
