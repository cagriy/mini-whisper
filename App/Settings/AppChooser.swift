import AppKit

/// One app the user can attach to a profile.
struct AppChoice: Identifiable, Hashable, Sendable {
    var bundleID: String
    var name: String

    var id: String { bundleID }
}

/// The app-list seam so `ProfilesEditorModel` is testable without a running
/// workspace (design N5).
protocol AppListing: Sendable {
    func runningApps() -> [AppChoice]
    /// The Finder name for a bundle ID that is not running, when it can be found.
    func displayName(forBundleID bundleID: String) -> String?
}

extension AppListing {
    /// Running apps with a bundle ID, deduplicated and ordered by name.
    func sortedRunningApps() -> [AppChoice] {
        var seen: Set<String> = []
        return runningApps()
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The name to show for a bundle ID: the Finder name when the app can be found,
    /// otherwise the last component, which is the readable half of a bundle ID.
    func name(forBundleID bundleID: String) -> String {
        displayName(forBundleID: bundleID)
            ?? bundleID.split(separator: ".").last.map(String.init)
            ?? bundleID
    }
}

struct NSWorkspaceApps: AppListing {
    func runningApps() -> [AppChoice] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  let name = app.localizedName
            else { return nil }
            return AppChoice(bundleID: bundleID, name: name)
        }
    }

    func displayName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}

/// The “Add…” fallback: pick a bundle from /Applications and read its bundle ID.
@MainActor
enum AppChooser {
    static func chooseFromApplications() -> AppChoice? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return nil }
        return AppChoice(bundleID: bundleID, name: FileManager.default.displayName(atPath: url.path))
    }
}
