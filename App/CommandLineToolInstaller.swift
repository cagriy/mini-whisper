import Foundation

/// Settings' *Install…* for `/usr/local/bin/mini-whisper` (design §5.3, §5.8, R22): a wrapper
/// script, never a symlink, that runs this app's binary and finds the app by bundle id if it
/// moved. The only input is the app's own path, single-quoted.
enum CommandLineToolInstaller {
    static let path = "/usr/local/bin/mini-whisper"
    private static let bundleLookup = #"path to application id "com.ips.mini-whisper""#

    struct Failure: Error {
        let message: String
    }

    static func script(appPath: String) -> String {
        """
        #!/bin/sh
        APP=\(shellQuoted(appPath))
        if [ ! -x "$APP/Contents/MacOS/Mini Whisper" ]; then
          APP=$(osascript -e 'POSIX path of (\(bundleLookup))' 2>/dev/null | sed 's:/$::')
        fi
        exec "$APP/Contents/MacOS/Mini Whisper" "$@"

        """
    }

    /// Run as root. `rm -f` first, so a symlink already at the path is replaced, not written through.
    static func installCommand(script: String) -> String {
        "mkdir -p /usr/local/bin && rm -f \(path) && printf '%s' \(shellQuoted(script)) > \(path) && chmod 755 \(path)"
    }

    static func appleScript(command: String) -> String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    /// Asks for an administrator password; the failure carries AppleScript's message, such as
    /// "User canceled.".
    @MainActor
    static func install(appPath: String = Bundle.main.bundleURL.path) -> Result<Void, Failure> {
        let source = appleScript(command: installCommand(script: script(appPath: appPath)))
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            return .failure(Failure(message: "Could not prepare the installer."))
        }
        appleScript.executeAndReturnError(&error)
        if let error {
            return .failure(Failure(message: error[NSAppleScript.errorMessage] as? String ?? "Install failed."))
        }
        return .success(())
    }

    /// True when the file there is this app's wrapper.
    static func isInstalled(at path: String = path) -> Bool {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return text.hasPrefix("#!/bin/sh\n") && text.contains(bundleLookup)
    }

    /// The Claude Code registration the Settings row shows and copies.
    static func mcpCommand(installed: Bool, binaryPath: String) -> String {
        "claude mcp add --transport stdio mini-whisper -- \(installed ? "mini-whisper" : shellQuoted(binaryPath)) mcp"
    }

    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
