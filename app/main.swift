import AppKit

// MARK: - Start

if CommandLine.arguments.contains("--selftest") { exit(runSelfTest()) }
// Draws the app icon: Lumen standing on a reading line.
if let target = CommandLine.arguments.first(where: { $0.hasPrefix("--render-icon=") }) {
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let icon = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: icon)
        NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185).fill()
        Palette.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: 250, y: 290, width: 524, height: 34), xRadius: 17, yRadius: 17).fill()
        LumenArt.frames["read"]?.draw(in: NSRect(x: 305, y: 318, width: 414, height: 420))
        NSGraphicsContext.restoreGraphicsState()
        try? icon.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(target.dropFirst("--render-icon=".count))))
    }
    exit(0)
}
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
