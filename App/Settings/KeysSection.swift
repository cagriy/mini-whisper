import MWConfig
import SwiftUI

/// The five Keychain accounts (F3). Fields show a mask, never the stored key,
/// and a key is only ever handed to `SecretStore`.
struct KeysSection: View {
    let model: SettingsModel

    @State private var drafts: [KeyAccount: String] = [:]

    static let rows: [(KeyAccount, String)] = [
        (.openai, "OpenAI"),
        (.elevenlabs, "ElevenLabs"),
        (.speechmatics, "Speechmatics"),
        (.assemblyai, "AssemblyAI"),
        (.anthropic, "Anthropic"),
    ]

    var body: some View {
        Card {
            ForEach(Self.rows, id: \.0) { account, title in
                SettingRow(
                    title,
                    description: account == Self.rows.last?.0
                        ? "Keys are stored in the macOS Keychain (service “mini-whisper”) and never"
                            + " written to disk. macOS may ask once to allow access to a key saved by"
                            + " the previous version. Removing a key disables the features that need it."
                        : nil,
                    error: model.error(for: account)
                ) {
                    HStack(spacing: DS.Space.s4) {
                        SecureField(
                            "not set",
                            text: Binding(
                                get: { drafts[account] ?? "" },
                                set: { drafts[account] = $0 }
                            ),
                            prompt: Text("")
                        )
                        .fieldPlaceholder("not set", shown: (drafts[account] ?? "").isEmpty)
                        .dsField()
                        .frame(width: 240)
                        Button("Save") {
                            model.saveKey(account, value: drafts[account] ?? "")
                            drafts[account] = model.mask(for: account)
                        }
                        .buttonStyle(.pill(size: .small))
                    }
                }
            }
        }
        .onAppear(perform: resetDrafts)
    }

    private func resetDrafts() {
        model.refreshKeys()
        drafts = Dictionary(uniqueKeysWithValues: KeyAccount.allCases.map { ($0, model.mask(for: $0)) })
    }
}
