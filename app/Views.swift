import AppKit
import Carbon.HIToolbox

// MARK: - Visual system

enum Palette {
    static let accent = NSColor(calibratedRed: 0.91, green: 0.64, blue: 0.24, alpha: 1)  // Lantern amber, #E8A33D
    static let surface = NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.15, alpha: 0.97)  // Night ink, #171527
    static let well = NSColor.white.withAlphaComponent(0.09)
    static let hairline = NSColor.white.withAlphaComponent(0.16)
    static let text = NSColor.white
    static let secondaryText = NSColor.white.withAlphaComponent(0.74)
}

extension NSPanel {
    /// A see-through, borderless panel floating at `level`, which never takes focus from the app being read.
    convenience init(floatingAt level: NSWindow.Level, frame: NSRect) {
        self.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
    }
}

extension NSView {
    /// Follows the pointer over the whole view, even while another app is active.
    func trackPointer(_ events: NSTrackingArea.Options) {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: events.union([.activeAlways, .inVisibleRect]), owner: self))
    }
}

/// The rounded dark panel behind the purpose box and the playback bar.
final class SurfaceView: NSView {
    var radius: CGFloat = 18
    var fill = Palette.surface
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill()
        shape.fill()
        Palette.hairline.setStroke()
        shape.stroke()
    }
}

final class ProgressLine: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        Palette.hairline.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1, yRadius: 1).fill()
        Palette.accent.setFill()
        var done = bounds
        done.size.width *= min(max(fraction, 0), 1)
        NSBezierPath(roundedRect: done, xRadius: 1, yRadius: 1).fill()
    }
}

/// A button with clear hover, pressed and on states that responds to the first click.
final class ControlButton: NSButton {
    var fill = NSColor.clear { didSet { needsDisplay = true } }
    var hoverFill = NSColor.white.withAlphaComponent(0.16)
    var isOn = false { didSet { needsDisplay = true } }
    private var isHovering = false { didSet { needsDisplay = true } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackPointer([.mouseEnteredAndExited])
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        if isHighlighted {
            color = hoverFill.withAlphaComponent(min(hoverFill.alphaComponent + 0.14, 1))
        } else if isOn {
            color = Palette.accent.withAlphaComponent(0.26)
        } else {
            color = isHovering ? hoverFill : fill
        }
        color.setFill()
        let radius = min(bounds.height / 2, 16)
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        super.draw(dirtyRect)
    }

    /// How wide a label is at the size buttons and chips use, before padding.
    static func labelWidth(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)]).size().width
    }

    func setLabel(_ text: String, size: CGFloat = 12.5, color: NSColor = Palette.text) {
        attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold),
        ])
    }
}

// MARK: - Selection overlay

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    var onFinish: ((NSRect?) -> Void)?
    var hover: NSRect?
    var hint = "Scroll to find it, then drag over what to read or click a window    Esc to cancel"
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackPointer([.mouseMoved])
    }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.14).setFill()
        bounds.fill()
        if let target = selection ?? hover {
            // A nearly invisible tint keeps this area clickable, because macOS passes clicks through fully clear pixels.
            NSColor.black.withAlphaComponent(0.015).setFill()
            target.fill(using: .copy)
            Palette.accent.setStroke()
            let outline = NSBezierPath(rect: target.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            outline.stroke()
        }
        guard selection == nil else { return }
        let hint = NSAttributedString(string: self.hint, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: Palette.text,
        ])
        let size = hint.size()
        let top = bounds.maxY - max(window?.screen?.safeAreaInsets.top ?? 0, 28) - 54
        let pill = NSRect(x: bounds.midX - size.width / 2 - 20, y: top, width: size.width + 40, height: 38)
        Palette.surface.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 19, yRadius: 19).fill()
        hint.draw(at: NSPoint(x: pill.minX + 20, y: pill.midY - size.height / 2))
    }

    override func mouseMoved(with event: NSEvent) {
        guard start == nil, let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        hover = windowRect(at: topLeftRect(from: NSRect(origin: point, size: .zero)).origin).map { window.convertFromScreen(bottomLeftRect(from: $0)) }
        needsDisplay = true
    }

    /// Scrolling over the selector scrolls the window underneath, so the reader can bring the right part into view before
    /// dragging. The selector steps aside for the scroll and comes back once it stops. Some apps, Chrome among them,
    /// ignore scrolls sent to them directly, so the scroll has to reach them the ordinary way.
    private var scrollWatch: Any?
    private var stepBack: DispatchWorkItem?
    /// Tags the scrolls the selector hands on. Stepping aside takes a moment to reach the window server, so a scroll
    /// handed on can land on the selector again; without this it would be handed on again, round and round, flooding
    /// the Mac with scrolls until the pointer froze.
    static let handedOn: Int64 = 0x4E415253
    /// How a scroll is handed on. Tests replace it to count them.
    static var handOn: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }

    override func scrollWheel(with event: NSEvent) {
        guard let window, !window.ignoresMouseEvents, let original = event.cgEvent,
              original.getIntegerValueField(.eventSourceUserData) != Self.handedOn, let scroll = original.copy() else { return }
        window.ignoresMouseEvents = true
        scroll.setIntegerValueField(.eventSourceUserData, value: Self.handedOn)
        Self.handOn(scroll)
        if scrollWatch == nil {
            note("selection: scroll passed to the window underneath")
            scrollWatch = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
                MainActor.assumeIsolated { self?.keepSteppedAside() }
            }
        }
        keepSteppedAside()
    }

    private func keepSteppedAside() {
        stepBack?.cancel()
        let back = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.window?.ignoresMouseEvents = false
            if let scrollWatch = self.scrollWatch { NSEvent.removeMonitor(scrollWatch) }
            self.scrollWatch = nil
        }
        stepBack = back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: back)
    }

    deinit {
        if let scrollWatch { NSEvent.removeMonitor(scrollWatch) }
    }

    override func mouseDown(with event: NSEvent) {
        note("selection: mouse down; window key \(window?.isKeyWindow ?? false), app active \(NSApp.isActive)")
        start = convert(event.locationInWindow, from: nil)
        current = start
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        note("selection: mouse up; area \(selection.map { "\(Int($0.width))x\(Int($0.height))" } ?? "none")")
        guard let selection, let window else { return onFinish?(nil) ?? () }
        if selection.width < 8 || selection.height < 8 {
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let clicked = windowRect(at: topLeftRect(from: NSRect(origin: point, size: .zero)).origin)
            onFinish?(clicked.map(bottomLeftRect(from:)))
        } else {
            onFinish?(window.convertToScreen(selection))
        }
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { onFinish?(nil) }
    }
}

final class PurposeField: NSTextField {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Narrator has no Edit menu, which is what normally turns Command + V and friends into paste and copy. Without this,
    /// pasting and dictation apps such as Wispr Flow, which insert text by pressing Command + V, would do nothing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let editing: [String: Selector] = [
            "v": #selector(NSText.paste(_:)), "c": #selector(NSText.copy(_:)), "x": #selector(NSText.cut(_:)),
            "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:")),
        ]
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, let editor = currentEditor(),
           let action = event.charactersIgnoringModifiers.flatMap({ editing[$0.lowercased()] }), editor.responds(to: action) {
            editor.perform(action, with: self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Reading highlight

struct HighlightSegment {
    let rect: CGRect
    let done: CGFloat
}

/// Marks the sentence being read and sweeps across it in time with the voice.
final class HighlightView: NSView {
    /// Where the highlights should be. The view glides to them, so moving to the next sentence, line or screen is one
    /// smooth motion, and a highlight fades in and out instead of popping.
    var segments: [HighlightSegment] = [] { didSet { retarget() } }

    private struct Shown {
        var rect: CGRect
        var done: CGFloat
        var alpha: CGFloat
    }
    private var shown: [Shown] = []
    private var glide: Timer?
    private var lastTick = Date()

    private func retarget() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            shown = segments.map { Shown(rect: $0.rect, done: $0.done, alpha: 1) }
            needsDisplay = true
            return
        }
        for (index, segment) in segments.enumerated() {
            if index < shown.count {
                shown[index].done = segment.done
            } else {
                // A new highlight grows out of the last one, or fades in where it is if there was none.
                shown.append(Shown(rect: shown.last?.rect ?? segment.rect, done: segment.done, alpha: shown.isEmpty ? 0 : 1))
            }
        }
        needsDisplay = true
        guard glide == nil, !shown.isEmpty else { return }
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            MainActor.assumeIsolated { self.glideStep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        glide = timer
    }

    private func glideStep() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.05)
        lastTick = now
        let move = CGFloat(1 - exp(-dt / 0.06))
        let fade = CGFloat(1 - exp(-dt / 0.09))
        var settled = true
        var kept: [Shown] = []
        for (index, var item) in shown.enumerated() {
            if index < segments.count {
                let goal = segments[index].rect
                let close = abs(goal.minX - item.rect.minX) < 0.0004 && abs(goal.minY - item.rect.minY) < 0.0004
                    && abs(goal.width - item.rect.width) < 0.0004 && abs(goal.height - item.rect.height) < 0.0004
                if close {
                    item.rect = goal
                } else {
                    settled = false
                    item.rect = CGRect(
                        x: item.rect.minX + (goal.minX - item.rect.minX) * move, y: item.rect.minY + (goal.minY - item.rect.minY) * move,
                        width: item.rect.width + (goal.width - item.rect.width) * move, height: item.rect.height + (goal.height - item.rect.height) * move
                    )
                }
                item.alpha += (1 - item.alpha) * fade
                if item.alpha < 0.995 { settled = false } else { item.alpha = 1 }
            } else {
                // A highlight that is no longer wanted fades away.
                item.alpha -= CGFloat(dt / 0.18)
                if item.alpha <= 0 { continue }
                settled = false
            }
            kept.append(item)
        }
        shown = kept
        needsDisplay = true
        if settled {
            glide?.invalidate()
            glide = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.4).setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        outline.lineWidth = 1.5
        outline.stroke()
        let accent = Palette.accent
        for segment in shown where segment.rect.width > 0 {
            let area = NSRect(
                x: segment.rect.minX * bounds.width - 3,
                y: segment.rect.minY * bounds.height - 2,
                width: segment.rect.width * bounds.width + 6,
                height: segment.rect.height * bounds.height + 4
            )
            accent.withAlphaComponent(0.2 * segment.alpha).setFill()
            NSBezierPath(roundedRect: area, xRadius: 4, yRadius: 4).fill()
            guard segment.done > 0 else { continue }
            var spoken = area
            spoken.size.width *= segment.done
            accent.withAlphaComponent(0.45 * segment.alpha).setFill()
            NSBezierPath(roundedRect: spoken, xRadius: 4, yRadius: 4).fill()
            if segment.done < 1 {
                accent.withAlphaComponent(segment.alpha).setFill()
                NSRect(x: spoken.maxX - 1, y: area.minY, width: 2, height: area.height).fill()
            }
        }
    }
}

/// Shows the sentences on screen. Clicking one, or dragging across several, continues reading from there.
final class JumpView: NSView {
    var sentences: [JumpSentence] = []
    var onPick: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    private var hovered: Int?
    private var dragStart: Int?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackPointer([.mouseMoved])
    }

    private func index(for event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return sentence(at: CGPoint(x: point.x / bounds.width, y: point.y / bounds.height), in: sentences)
    }

    override func draw(_ dirtyRect: NSRect) {
        // A nearly invisible tint keeps the whole area clickable.
        NSColor.black.withAlphaComponent(0.015).setFill()
        bounds.fill()
        let first = min(dragStart ?? hovered ?? -1, hovered ?? -1)
        let last = max(dragStart ?? hovered ?? -1, hovered ?? -1)
        for (index, item) in sentences.enumerated() {
            Palette.accent.withAlphaComponent(index >= first && index <= last && first >= 0 ? 0.45 : 0.1).setFill()
            for box in item.boxes {
                let area = NSRect(x: box.minX * bounds.width - 3, y: box.minY * bounds.height - 2, width: box.width * bounds.width + 6, height: box.height * bounds.height + 4)
                NSBezierPath(roundedRect: area, xRadius: 4, yRadius: 4).fill()
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = index(for: event)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = index(for: event)
        hovered = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseUp(with event: NSEvent) {
        hovered = index(for: event)
        guard let dragStart, let hovered else { return }
        onPick?(min(dragStart, hovered))
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { onCancel?() }
    }
}
