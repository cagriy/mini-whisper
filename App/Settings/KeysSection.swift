import MWConfig
import SwiftUI

/// The three Keychain accounts (F3). Fields show a mask, never the stored key,
/// and a key is only ever handed to `SecretStore`.
struct KeysSection: View {
    let model: SettingsModel

    @State private var drafts: [KeyAccount: String] = [:]

    private static let rows: [(KeyAccount, String)] = [
        (.openai, "OpenAI"),
        (.elevenlabs, "ElevenLabs"),
        (.speechmatics, "Speechmatics"),
    ]

    var body: some View {
        SettingsPane(title: "Keys") {
            ForEach(Self.rows, id: \.0) { account, title in
                row(account, title: title)
            }
            SettingsFootnote(
                "Keys are stored in the macOS Keychain (service “mini-whisper”) and never"
                    + " written to disk. macOS may ask once to allow access to a key saved by"
                    + " the previous version. Removing a key disables the features that need it."
            )
        }
        .onAppear(perform: resetDrafts)
    }

    private func row(_ account: KeyAccount, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).frame(width: 110, alignment: .leading)
                SecureField(
                    "not set",
                    text: Binding(
                        get: { drafts[account] ?? "" },
                        set: { drafts[account] = $0 }
                    )
                )
                .frame(width: 240)
                Button("Save") {
                    model.saveKey(account, value: drafts[account] ?? "")
                    drafts[account] = model.mask(for: account)
                }
            }
            if let error = model.error(for: account) {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func resetDrafts() {
        model.refreshKeys()
        drafts = Dictionary(uniqueKeysWithValues: KeyAccount.allCases.map { ($0, model.mask(for: $0)) })
    }
}
