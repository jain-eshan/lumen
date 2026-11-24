import AppKit
import ScreenCaptureKit

// MARK: - Screen actions

/// Set only by evals (`--simulate-screen`): the screen Lumen reads is then drawn in memory, so nothing shows on the real one.
nonisolated(unsafe) var simulatedScreen: SimulatedScreen?

func capture(_ rect: CGRect) async throws -> CGImage {
    if let simulated = simulatedScreen { return simulated.image(for: rect) }
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    guard let display = content.displays.first(where: { $0.frame.contains(center) }) else {
        note("capture area \(rect) is outside displays \(content.displays.map(\.frame))")
        throw SpeechError.failed("The selected area is no longer on screen")
    }
    let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }
    let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
    let configuration = SCStreamConfiguration()
    let scale = CGFloat(filter.pointPixelScale)
    configuration.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    configuration.width = Int(rect.width * scale)
    configuration.height = Int(rect.height * scale)
    configuration.showsCursor = false
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
}

let syntheticScrollMarker: Int64 = 0x4E415252

func globalCursorLocation() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

/// How far through a glide the page should be, from 0 to 1, easing in and out so it starts and stops gently.
func easedProgress(_ time: Double) -> Double {
    let t = min(max(time, 0), 1)
    return t * t * (3 - 2 * t)
}

/// Glides the page down a screen the way a trackpad flick does: slow, quick, slow. It follows the clock rather than
/// counting steps, so the motion stays even if a step runs late. It scrolls whatever is under `target`, borrowing the
/// cursor unless it is already there, because a cursor inside the area can still be over a panel that does not scroll.
func scrollDown(in rect: CGRect, at target: CGPoint, gentle: Bool = false) async {
    let distance = Int(rect.height * 0.75)
    if let simulated = simulatedScreen {
        simulated.scroll(at: target, by: distance)
        try? await Task.sleep(for: .milliseconds(150))
        return
    }
    let duration = gentle ? 0.15 : min(max(Double(distance) / 850, 0.55), 0.9)
    let cursor = globalCursorLocation()
    let borrowCursor = hypot(cursor.x - target.x, cursor.y - target.y) > 40
    if borrowCursor { CGWarpMouseCursorPosition(target) }
    let clock = ContinuousClock()
    let began = clock.now
    var sent = 0
    while sent < distance {
        let elapsed = (clock.now - began)
        let time = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let reached = time >= duration ? distance : Int((Double(distance) * easedProgress(time / duration)).rounded())
        if reached > sent, let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-(reached - sent)), wheel2: 0, wheel3: 0) {
            event.location = borrowCursor ? target : cursor
            event.setIntegerValueField(.eventSourceUserData, value: syntheticScrollMarker)
            event.post(tap: .cghidEventTap)
            sent = reached
        }
        try? await Task.sleep(for: .milliseconds(8))
    }
    if borrowCursor { CGWarpMouseCursorPosition(cursor) }
}

/// Converts AppKit's bottom-left coordinates to the screen capture's top-left coordinates.
func topLeftRect(from rect: NSRect) -> CGRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}

func bottomLeftRect(from rect: CGRect) -> NSRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}

struct WatchedWindow: Equatable {
    let id: CGWindowID
    let title: String
    let owner: String
    let bounds: CGRect
    var pid: pid_t = 0
}

func watchedWindow(from window: [String: Any]) -> WatchedWindow? {
    guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: bounds),
          let id = window[kCGWindowNumber as String] as? CGWindowID else { return nil }
    return WatchedWindow(id: id, title: window[kCGWindowName as String] as? String ?? "", owner: window[kCGWindowOwnerName as String] as? String ?? "", bounds: rect,
                         pid: window[kCGWindowOwnerPID as String] as? pid_t ?? 0)
}

func topWindow(at point: CGPoint) -> WatchedWindow? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    // macOS briefly places invisible helper windows over the screen, and those are never the document.
    let systemHelpers: Set<String> = ["AquaAppearanceHelper", "Window Server", "screencaptureui", "Dock", "Control Center", "Notification Center"]
    for window in windows where (window[kCGWindowLayer as String] as? Int) == 0 && (window[kCGWindowOwnerPID as String] as? pid_t) != getpid()
        && (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 {
        if let details = watchedWindow(from: window), details.bounds.contains(point), !systemHelpers.contains(details.owner) { return details }
    }
    return nil
}

func windowRect(at point: CGPoint) -> CGRect? { topWindow(at: point)?.bounds }

func windowDetails(_ id: CGWindowID) -> WatchedWindow? {
    (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first.flatMap(watchedWindow(from:))
}
