import Foundation

/// F38: `--debug` adds DEBUG-level logging and the `/tmp/mini-whisper.log` file sink.
struct LaunchArguments {
    let debug: Bool

    static let debugLogURL = URL(fileURLWithPath: "/tmp/mini-whisper.log")

    init(arguments: [String] = CommandLine.arguments) {
        debug = arguments.contains("--debug")
    }

    /// True while the app is hosting the `AppTests` bundle, so `AppDelegate` can
    /// skip a startup that would touch the user's config, Keychain and input devices.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
