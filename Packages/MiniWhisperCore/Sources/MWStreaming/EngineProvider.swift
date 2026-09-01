import MWConfig

/// The pipeline's seam over engine selection (design §5.2).
public protocol EngineProvider: Sendable {
    func make(config: Config, secrets: any SecretStore) async -> EngineSelection
}
