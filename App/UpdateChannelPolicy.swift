import MWConfig

/// The update channel's rules (design v10 §5), kept free of Sparkle so they are unit-tested.
enum UpdateChannelPolicy {
    /// Sparkle's allowed channels; the default channel is always included, so Release is empty.
    static func sparkleChannels(for channel: UpdateChannel) -> Set<String> {
        switch channel {
        case .release: []
        case .beta: ["beta"]
        }
    }

    /// R8: display only, so `b0` passes; the release pipeline is what rejects it.
    static func isBeta(version: String) -> Bool {
        version.wholeMatch(of: /\d+\.\d+\.\d+b\d+/) != nil
    }

    /// Reports a channel change after the first apply, so loading the config at launch
    /// neither logs nor resets Sparkle's update cycle (R6).
    struct Tracker {
        private var last: UpdateChannel?

        mutating func apply(_ channel: UpdateChannel) -> Bool {
            defer { last = channel }
            return last != nil && last != channel
        }
    }
}
