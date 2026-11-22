/// Which versions the updater offers, releases only or betas too, stored in `config.json`
/// under `update_channel`. An absent or unrecognised value resolves to `release`.
public enum UpdateChannel: String, CaseIterable, Sendable {
    case release
    case beta
}
