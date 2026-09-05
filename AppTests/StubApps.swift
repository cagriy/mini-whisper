import Foundation
@testable import MiniWhisper

/// The `AppListing` seam every model that names or offers apps is tested through.
struct StubApps: AppListing {
    var apps: [AppChoice] = []
    var names: [String: String] = [:]

    func runningApps() -> [AppChoice] { apps }
    func displayName(forBundleID bundleID: String) -> String? { names[bundleID] }
}
