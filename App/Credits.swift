import Foundation

/// What the Credits window lists (design §5, R26): each bundled third-party component, who made it
/// and under which licence.
enum Credits {
    struct Entry: Sendable {
        let name: String
        /// What it does in the app, beside the name.
        let purpose: String
        /// Who made it and how the app ships it.
        let attribution: String
        let licence: String
        /// Opened by "Open Licence…".
        var licenceURL: URL?
        /// The full licence shipped inside the app, unfolded by "Show Licence".
        var licenceText: String?

        /// The licence's address as the row shows it, without its scheme.
        var licenceAddress: String? {
            licenceURL.flatMap { url in url.host().map { $0 + url.path() } }
        }
    }

    /// Built at first use, so the bundled licence is read once.
    static let entries = [
        Entry(
            name: "WeSpeaker voice model",
            purpose: "Recognises voices on this Mac",
            attribution: "WeSpeaker ResNet34-LM by the WeSpeaker authors, as published by pyannote and converted to"
                + " Core ML by Fluid Inference. Bundled as a modified Core ML conversion.",
            licence: "CC BY 4.0",
            licenceURL: URL(string: "https://creativecommons.org/licenses/by/4.0")
        ),
        Entry(
            name: "Sparkle",
            purpose: "Checks for and installs updates",
            attribution: "Copyright © 2006–2017 Andy Matuschak and the Sparkle contributors. Includes bsdiff,"
                + " sais-lite and an Ed25519 implementation under their own notices.",
            licence: "MIT-style licence",
            licenceText: Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: "txt")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        ),
    ]
}
