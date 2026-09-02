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
