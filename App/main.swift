import AppKit

if let command = AgentCommand(arguments: CommandLine.arguments) {
    exit(command.run())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
