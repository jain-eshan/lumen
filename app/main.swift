import AppKit

// MARK: - Start

if CommandLine.arguments.contains("--selftest") { exit(runSelfTest()) }
if let preview = CommandLine.arguments.first(where: { $0.hasPrefix("--render-ui=") }) {
    _ = NSApplication.shared
    MainActor.assumeIsolated { NarratorApp().writePreviews(to: String(preview.dropFirst("--render-ui=".count))) }
    exit(0)
}
signal(SIGPIPE, SIG_IGN)
if let path = CommandLine.arguments.first(where: { $0.hasPrefix("--log-file=") }) { logFile = URL(fileURLWithPath: String(path.dropFirst("--log-file=".count))) }

let application = NSApplication.shared
let narrator = MainActor.assumeIsolated { NarratorApp() }
application.delegate = narrator
// An eval has no windows, no menu bar icon and no Dock icon.
application.setActivationPolicy(CommandLine.arguments.contains { $0.hasPrefix("--simulate-screen=") } ? .prohibited : .accessory)
application.run()
