import AppKit

// MARK: - Start

if CommandLine.arguments.contains("--selftest") { exit(runSelfTest()) }
if let preview = CommandLine.arguments.first(where: { $0.hasPrefix("--render-ui=") }) {
    _ = NSApplication.shared
    MainActor.assumeIsolated { NarratorApp().writePreviews(to: String(preview.dropFirst("--render-ui=".count))) }
    exit(0)
}
signal(SIGPIPE, SIG_IGN)

let application = NSApplication.shared
let narrator = MainActor.assumeIsolated { NarratorApp() }
application.delegate = narrator
application.setActivationPolicy(.accessory)
application.run()
