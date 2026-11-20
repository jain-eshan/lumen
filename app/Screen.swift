import AppKit
import ScreenCaptureKit

// MARK: - Screen actions

func capture(_ rect: CGRect) async throws -> CGImage {
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

/// Scrolls in small steps so the page glides, and only borrows the cursor if it is elsewhere.
func scrollDown(in rect: CGRect) async {
    let steps = 10
    let step = Int32(-(rect.height * 0.75) / CGFloat(steps))
    let cursor = globalCursorLocation()
    let target = CGPoint(x: rect.midX, y: rect.midY)
    let borrowCursor = !rect.contains(cursor)
    if borrowCursor { CGWarpMouseCursorPosition(target) }
    for _ in 0..<steps {
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: step, wheel2: 0, wheel3: 0) {
            event.location = borrowCursor ? target : cursor
            event.setIntegerValueField(.eventSourceUserData, value: syntheticScrollMarker)
            event.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(for: .milliseconds(18))
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
}

func watchedWindow(from window: [String: Any]) -> WatchedWindow? {
    guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: bounds),
          let id = window[kCGWindowNumber as String] as? CGWindowID else { return nil }
    return WatchedWindow(id: id, title: window[kCGWindowName as String] as? String ?? "", owner: window[kCGWindowOwnerName as String] as? String ?? "", bounds: rect)
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
