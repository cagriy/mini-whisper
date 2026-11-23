/// What `applicationShouldTerminate` answers (§5.7 Quit while recording).
enum QuitPolicy {
    enum Reply: Equatable {
        case now, cancel, afterCleanup
    }

    /// `prepared`: the menu's Quit has already stopped the meeting and hidden the main window.
    /// It calls `terminate` from a main-actor task, where a `.terminateLater` reply would never
    /// arrive: AppKit waits for it in a nested event loop, which runs no main-queue work while
    /// that task holds the main queue.
    static func reply(prepared: Bool, recording: Bool, hasMainWindow: Bool, confirm: () -> Bool) -> Reply {
        if prepared { return .now }
        guard recording || hasMainWindow else { return .now }
        if recording, !confirm() { return .cancel }
        return .afterCleanup
    }
}
