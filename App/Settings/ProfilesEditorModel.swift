import Foundation
import MWConfig
import MWSupport
import Observation

/// The per-app profiles table and its detail form (F27). The Default row is
/// synthetic — it is never stored — and a bundle ID belongs to at most one
/// profile, which is enforced here rather than left to the view.
@MainActor
@Observable
final class ProfilesEditorModel {
    struct Row: Identifiable, Equatable {
        var id: String
        var name: String
        var apps: String
        var cleanup: String
        var submitKey: String
        var isDefault: Bool
    }

    static let defaultRowID = "__default__"

    private let store: ConfigStore
    private let apps: any AppListing
    private let defaultPrompt: () -> String

    private(set) var profiles: [Profile]
    private(set) var appAssignmentError: String?
    private var cleanupEnabled: Bool
    var selection: String? = ProfilesEditorModel.defaultRowID {
        didSet { appAssignmentError = nil }
    }

    init(
        config: Config,
        store: ConfigStore,
        apps: any AppListing,
        defaultPrompt: @escaping () -> String
    ) {
        profiles = config.profiles
        cleanupEnabled = config.cleanupEnabled
        self.store = store
        self.apps = apps
        self.defaultPrompt = defaultPrompt
    }

    // MARK: - Table

    var rows: [Row] {
        let defaultRow = Row(
            id: Self.defaultRowID,
            name: "Default",
            apps: "everything else",
            cleanup: cleanupEnabled ? "on" : "off",
            submitKey: Self.label(for: .enter),
            isDefault: true
        )
        return [defaultRow] + profiles.map { profile in
            Row(
                id: profile.id,
                name: profile.name,
                apps: profile.bundleIDs.map(displayName).joined(separator: ", "),
                cleanup: profile.cleanupEnabled ? "on" : "off",
                submitKey: Self.label(for: profile.submitKey),
                isDefault: false
            )
        }
    }

    var selectedProfile: Profile? {
        profiles.first { $0.id == selection }
    }

    var runningApps: [AppChoice] { apps.sortedRunningApps() }

    func displayName(_ bundleID: String) -> String { apps.name(forBundleID: bundleID) }

    static func label(for key: SubmitKey) -> String {
        switch key {
        case .enter: "Enter"
        case .shiftEnter: "Shift+Enter"
        case .cmdEnter: "Cmd+Enter"
        }
    }

    /// The Default row mirrors the top-level cleanup setting, which `SettingsModel`
    /// owns.
    func setDefaultCleanup(_ enabled: Bool) {
        cleanupEnabled = enabled
    }

    // MARK: - Editing

    func add() async {
        let profile = Profile(id: UUID().uuidString, name: "New Profile")
        profiles.append(profile)
        selection = profile.id
        await persist()
    }

    func remove(_ id: String) async {
        guard profiles.contains(where: { $0.id == id }) else { return }
        profiles.removeAll { $0.id == id }
        if selection == id { selection = Self.defaultRowID }
        await persist()
    }

    /// F27: rejected when any profile already claims the bundle ID.
    @discardableResult
    func addBundleID(_ bundleID: String, to profileID: String) async -> Bool {
        if let owner = profiles.first(where: { $0.bundleIDs.contains(bundleID) }) {
            appAssignmentError = "\(displayName(bundleID)) already belongs to “\(owner.name)”."
            return false
        }
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return false }
        appAssignmentError = nil
        profiles[index].bundleIDs.append(bundleID)
        await persist()
        return true
    }

    func removeBundleID(_ bundleID: String, from profileID: String) async {
        await edit(profileID) { $0.bundleIDs.removeAll { $0 == bundleID } }
    }

    func setName(_ name: String, for profileID: String) async {
        await edit(profileID) { $0.name = name }
    }

    func setCleanupEnabled(_ enabled: Bool, for profileID: String) async {
        await edit(profileID) { $0.cleanupEnabled = enabled }
    }

    func setSubmitKey(_ key: SubmitKey, for profileID: String) async {
        await edit(profileID) { $0.submitKey = key }
    }

    /// An empty editor means "use prompt.txt" (design §5.3).
    func setPrompt(_ prompt: String, for profileID: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        await edit(profileID) { $0.cleanupPrompt = trimmed.isEmpty ? nil : trimmed }
    }

    /// The prompt a row actually uses; the Default row and a null profile prompt
    /// both resolve to `prompt.txt`.
    func prompt(for rowID: String) -> String {
        profiles.first { $0.id == rowID }?.cleanupPrompt ?? defaultPrompt()
    }

    private func edit(_ profileID: String, _ mutate: (inout Profile) -> Void) async {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        mutate(&profiles[index])
        await persist()
    }

    private func persist() async {
        let profiles = profiles
        do {
            try await store.update { @Sendable in $0.profiles = profiles }
        } catch {
            Log.config.error("Could not save profiles: \(AnyError(error).description)")
        }
    }
}
