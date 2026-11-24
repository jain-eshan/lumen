import AppKit

// MARK: - Lumen, the desktop pet

enum PetMood: String { case idle, reading, talking, thinking, listening, paused, jump, happy }

/// Lumen's poses, cut out of generated art by art/cutout.swift and bundled in Resources/lumen.
enum LumenArt {
    static let poses = ["read", "talk", "walk1", "walk2", "fly", "wave", "listen", "think", "cheer", "sleep"]

    static let frames: [String: NSImage] = {
        var frames: [String: NSImage] = [:]
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("lumen") else { return frames }
        for pose in poses {
            if let image = NSImage(contentsOf: folder.appendingPathComponent("\(pose).png")) { frames[pose] = image }
        }
        return frames
    }()

    /// Where the lantern's flame sits in each pose, as fractions of the frame from the bottom left,
    /// found from the brightest warm pixels so new art needs no measuring.
    static let lanterns: [String: CGPoint] = {
        var spots: [String: CGPoint] = [:]
        for (pose, image) in frames {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let w = cg.width, h = cg.height
            var px = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            var sumX = 0.0, sumY = 0.0, count = 0.0
            for y in 0..<h { for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                if px[i + 3] > 200, r > 245, g > 210, b < 175, r - b > 90 { sumX += Double(x); sumY += Double(y); count += 1 }
            } }
            // Buffer rows run top to bottom.
            if count > 6 { spots[pose] = CGPoint(x: sumX / count / Double(w), y: 1 - sumY / count / Double(h)) }
        }
        return spots
    }()
}

/// Draws one pose of Lumen, mirrored when walking left, with the lantern glow, sleep z's and thinking dots on top.
final class PetView: NSView {
    var pose = "read" { didSet { if pose != oldValue { needsDisplay = true } } }
    var facingLeft = false { didSet { if facingLeft != oldValue { needsDisplay = true } } }
    var glow: CGFloat = 0 { didSet { redrawIfMoved() } }
    var tilt: CGFloat = 0 { didSet { redrawIfMoved() } }
    var stretch: CGFloat = 0 { didSet { redrawIfMoved() } }
    var sleeping = false { didSet { if sleeping != oldValue { needsDisplay = true } } }
    var dots = 0 { didSet { if dots != oldValue { needsDisplay = true } } }
    /// What was last drawn, so Lumen standing still is not redrawn thirty times a second.
    private var drawn: (glow: CGFloat, tilt: CGFloat, stretch: CGFloat) = (-1, 0, 0)
    var onClick: (() -> Void)?
    var onMenu: ((NSEvent) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDrop: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var pressedAt: NSPoint?
    private var dragging = false
    static let artShare: CGFloat = 0.82

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: dragging ? .closedHand : .openHand) }
    override func mouseDown(with event: NSEvent) { pressedAt = NSEvent.mouseLocation; dragging = false }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if let start = pressedAt, !dragging, hypot(point.x - start.x, point.y - start.y) > 4 { dragging = true }
        if dragging { onDrag?(point) }
    }
    override func mouseUp(with event: NSEvent) {
        if dragging { onDrop?() } else { onClick?() }
        pressedAt = nil
        dragging = false
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackPointer([.mouseEnteredAndExited])
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    /// Changes smaller than these are invisible: a tenth of a pixel, or a sliver of the lantern's brightness.
    private func redrawIfMoved() {
        if abs(glow - drawn.glow) > 0.002 || abs(tilt - drawn.tilt) > 0.0005 || abs(stretch - drawn.stretch) > 0.0005 { needsDisplay = true }
    }

    /// The art stands on the bottom edge, centred, leaving the top of the view for z's and dots.
    var artRect: NSRect {
        let height = bounds.height * PetView.artShare
        let image = LumenArt.frames["read"]?.size ?? NSSize(width: 241, height: 244)
        let width = height * image.width / image.height
        return NSRect(x: bounds.midX - width / 2, y: 0, width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawn = (glow, tilt, stretch)
        let art = artRect
        if let image = LumenArt.frames[pose] {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: art.midX, yBy: art.minY)
            transform.rotate(byRadians: tilt)
            transform.scaleX(by: (facingLeft ? -1 : 1) * (1 - stretch * 0.5), yBy: 1 + stretch)
            transform.concat()
            let local = NSRect(x: -art.width / 2, y: 0, width: art.width, height: art.height)
            image.draw(in: local, from: .zero, operation: .sourceOver, fraction: 1)
            if glow > 0.02, let spot = LumenArt.lanterns[pose] {
                // The lantern brightens with the voice.
                let centre = NSPoint(x: local.minX + spot.x * local.width, y: local.minY + spot.y * local.height)
                let warm = NSColor(calibratedRed: 1, green: 0.78, blue: 0.38, alpha: 1)
                NSGraphicsContext.current?.compositingOperation = .plusLighter
                NSGradient(colors: [warm.withAlphaComponent(0.7 * glow), warm.withAlphaComponent(0)])?
                    .draw(fromCenter: centre, radius: 0, toCenter: centre, radius: local.width * (0.08 + 0.1 * glow), options: [])
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        let ink = NSColor(calibratedRed: 0.78, green: 0.74, blue: 0.9, alpha: 1)
        if sleeping {
            for (index, size) in [CGFloat(11), 15].enumerated() {
                let rise = CGFloat((dots + index * 2) % 6) * 2
                NSAttributedString(string: "z", attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: ink.withAlphaComponent(0.9)])
                    .draw(at: NSPoint(x: art.midX + 18 + CGFloat(index) * 12, y: art.maxY * 0.55 + CGFloat(index) * 12 + rise))
            }
        } else if dots > 0 {
            for index in 0..<3 {
                ink.withAlphaComponent(index < dots ? 1 : 0.3).setFill()
                NSBezierPath(ovalIn: NSRect(x: art.midX - 10 + CGFloat(index) * 9, y: art.maxY + 4, width: 6, height: 6)).fill()
            }
        }
    }
}

/// Where Lumen can stand, from each screen's full area and its usable area (the usable area already leaves out the Dock
/// and the menu bar). A Dock along the bottom of a screen is her floor. With no Dock there (hidden, at a side, or none at
/// all) she stands on the bottom edge of the screen she is on, clear of a side Dock.
func lumenGround(screens: [(frame: CGRect, visible: CGRect)], x: CGFloat) -> (floor: CGFloat, range: ClosedRange<CGFloat>, bottomDock: Bool) {
    let docked = screens.first { $0.visible.minY > $0.frame.minY + 1 }
    let screen = docked ?? screens.first { x >= $0.frame.minX && x < $0.frame.maxX } ?? screens[0]
    let floor = docked == nil ? screen.frame.minY : screen.visible.minY - 3
    return (floor, (screen.visible.minX + 70)...(screen.visible.maxX - 70), docked != nil)
}

/// Lumen lives on top of the Dock: wanders along it, flutters over long distances, sits on the icon of the app
/// being read, reads aloud with its mouth and lantern following the voice, and can be picked up and dropped.
@MainActor
final class Pet: NSObject {
    let size = NSSize(width: 106, height: 114)
    var onClick: (() -> Void)?
    var onMenu: ((NSEvent, NSView) -> Void)?
    /// Loudness of the voice playing now, from 0 to 1.
    var level: () -> Float = { 0 }
    /// Name of the app being read, so Lumen can sit on its Dock icon.
    var readingApp: () -> String? = { nil }
    private let view: PetView
    private var panel: NSPanel?
    private var bubble: NSPanel?
    private var bubbleActions: [() -> Void] = []
    private var bubbleHide: DispatchWorkItem?
    /// A bubble with buttons is waiting on the reader, as opposed to a passing tip.
    var isAsking: Bool { bubble != nil && !bubbleActions.isEmpty }
    private var relaxWork: DispatchWorkItem?
    private var timer: Timer?
    private enum Motion { case standing, walking, flying, gliding, carried }
    private var motion = Motion.standing
    private var feet = CGPoint.zero
    private var goalX: CGFloat?
    private var flight: (from: CGFloat, to: CGFloat, progress: CGFloat)?
    private var grab = CGVector.zero
    private var hopStart = -100
    private var tick = 0
    private var lastActivity = Date()
    private var nextWander = Date().addingTimeInterval(12)
    private var dockInfo: (at: Date, bar: ClosedRange<CGFloat>?, icons: [String: CGFloat])?
    private var lastGround = ""
    private var currentMood = PetMood.idle
    private var showingHint = false
    private var hintTurn = 0
    private var hintHide: DispatchWorkItem?

    override init() {
        view = PetView(frame: NSRect(origin: .zero, size: size))
        super.init()
        view.onClick = { [weak self] in
            self?.wake()
            self?.onClick?()
        }
        view.onMenu = { [weak self] event in
            guard let self else { return }
            self.onMenu?(event, self.view)
        }
        view.onDrag = { [weak self] point in self?.carry(to: point) }
        view.onDrop = { [weak self] in self?.drop() }
        view.onHover = { [weak self] inside in self?.hover(inside) }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Lumen. Click to pick text to read.")
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "showPet") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "showPet")
            if !newValue { hideNow() }
        }
    }

    /// Keeps Lumen where it was last put, instead of wandering the Dock or following the app being read.
    var staysPut: Bool {
        get { UserDefaults.standard.bool(forKey: "petStaysPut") }
        set {
            UserDefaults.standard.set(newValue, forKey: "petStaysPut")
            guard newValue else { return }
            goalX = nil
            flight = nil
            if motion == .walking { motion = .standing }
            if motion == .flying { motion = .gliding }
            if feet != .zero { UserDefaults.standard.set(Double(feet.x), forKey: "petHomeX") }
        }
    }

    var mood: PetMood {
        get { currentMood }
        set {
            currentMood = newValue
            wake()
            if newValue == .happy { hopStart = tick }
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func show(swooping: Bool = false) {
        relaxWork?.cancel()
        guard isEnabled else { return }
        if panel == nil {
            // Just above the Dock, so Lumen can stand on it. Hidden in full-screen apps, where there is no Dock.
            let panel = NSPanel(floatingAt: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1), frame: NSRect(origin: .zero, size: size))
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel.contentView = view
            self.panel = panel
        }
        guard let panel, !panel.isVisible || panel.alphaValue < 1 else { return }
        let dock = self.dock()
        if feet == .zero {
            let home = UserDefaults.standard.object(forKey: "petHomeX") as? Double
            let x = staysPut ? home.map { min(max(CGFloat($0), dock.range.lowerBound), dock.range.upperBound) } : nil
            feet = CGPoint(x: x ?? dock.range.lowerBound + (dock.range.upperBound - dock.range.lowerBound) * 0.3, y: dock.floor)
        }
        // Lumen flutters down onto the Dock, or simply appears when motion is reduced.
        if swooping && !reduceMotion {
            feet.y = dock.floor + 320
            motion = .gliding
        } else {
            feet.y = dock.floor
            motion = .standing
        }
        place()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 1
        }
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.step() } }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    /// Goes back to wandering after a moment, closing any bubble.
    func relax(after seconds: Double) {
        relaxWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideBubble()
            self?.mood = .idle
        }
        relaxWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func hideNow() {
        hideBubble()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
                self.timer?.invalidate()
                self.timer = nil
            }
        })
    }

    func react(to status: String) {
        let moods: [(String, PetMood)] = [
            ("Reading", .reading), ("Answer", .talking), ("Paused", .paused), ("Waiting", .paused), ("Understanding", .thinking),
            ("Preparing", .thinking), ("Scrolling", .thinking), ("Thinking", .thinking), ("Jump", .jump), ("Following", .idle), ("Lumen", .happy),
        ]
        if let match = moods.first(where: { status.hasPrefix($0.0) }) { mood = match.1 }
    }

    /// What Lumen says when the pointer rests on it. Each line is playful and says what a click does now.
    static let hints: [String: [String]] = [
        "idle": [
            "Hi, I'm Lumen. Click me and point at anything. I'll read it to you.",
            "Option + Shift + 4 is our secret handshake. It picks something to read.",
            "Got a question about your screen? Press Option + Shift + A and ask away.",
            "Click me, choose Note for Claude, and mark the parts you want to talk about.",
            "You can pick me up and drop me. I always flutter back.",
            "Read more. Without reading. Click me and I'll show you.",
            "I read by lantern light. Your screen counts.",
            "Click me for a story. Or an email. I'm not fussy.",
        ],
        "sleep": ["Zzz. Dreaming of footnotes. Click to wake me."],
        "reading": ["Reading! Click me to pause. I'll keep my place.", "Shh, good part. Click me if you need a pause."],
        "paused": ["Click me and I'll carry on from here."],
        "thinking": ["One moment, finding the right page."],
        "listening": ["I'm all antennae. Type your question and press Return."],
        "jump": ["Click the sentence you want and I'll jump there."],
    ]

    private func hover(_ inside: Bool) {
        hintHide?.cancel()
        guard inside else {
            guard showingHint else { return }
            let hide = DispatchWorkItem { [weak self] in
                guard let self, self.showingHint else { return }
                self.hideBubble()
            }
            hintHide = hide
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: hide)
            return
        }
        // Never covers a message that is waiting for an answer.
        guard bubble == nil || showingHint, motion != .carried else { return }
        let state: String
        if view.sleeping { state = "sleep" } else {
            switch currentMood {
            case .reading, .talking: state = "reading"
            case .paused: state = "paused"
            case .thinking: state = "thinking"
            case .listening: state = "listening"
            case .jump: state = "jump"
            case .idle, .happy: state = "idle"
            }
        }
        let lines = Pet.hints[state] ?? Pet.hints["idle"]!
        if showingHint, bubble != nil { return }
        say(lines[hintTurn % lines.count], hideAfter: 6)
        hintTurn += 1
        showingHint = true
    }

    private func wake() {
        lastActivity = Date()
        view.sleeping = false
    }

    // MARK: Where the Dock is

    /// The Dock's top edge and width, and where each app's icon sits. Without a Dock at the bottom, the screen's bottom edge.
    /// The floor is worked out on every call, so a Dock that is resized, hidden or moved is noticed at once. Only the slower
    /// look at the Dock's icons is kept for a few seconds.
    private func dock() -> (floor: CGFloat, range: ClosedRange<CGFloat>, icons: [String: CGFloat]) {
        let ground = lumenGround(screens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) }, x: feet.x)
        var range = ground.range
        var icons: [String: CGFloat] = [:]
        if ground.bottomDock {
            if dockInfo == nil || Date().timeIntervalSince(dockInfo!.at) >= 3 { dockInfo = readDock() }
            // The Dock's own width, if it lies on this screen. Otherwise the screen's width.
            if let bar = dockInfo?.bar, bar.lowerBound < range.upperBound, bar.upperBound > range.lowerBound {
                range = max(bar.lowerBound, range.lowerBound)...min(bar.upperBound, range.upperBound)
            }
            icons = dockInfo?.icons ?? [:]
        } else {
            dockInfo = nil
        }
        let summary = "dock: \(ground.bottomDock ? "" : "none at the bottom, ")floor \(Int(ground.floor)), walks \(Int(range.lowerBound))...\(Int(range.upperBound)), \(icons.count) icons"
        if summary != lastGround { note(summary) }
        lastGround = summary
        return (ground.floor, range, icons)
    }

    /// The Dock's width and where each app's icon sits, read through Accessibility.
    private func readDock() -> (at: Date, bar: ClosedRange<CGFloat>?, icons: [String: CGFloat]) {
        var bar: ClosedRange<CGFloat>?
        var icons: [String: CGFloat] = [:]
        if AXIsProcessTrusted(), let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
                var result: CFTypeRef?
                return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
            }
            func frame(_ element: AXUIElement) -> CGRect {
                var origin = CGPoint.zero, size = CGSize.zero
                if let v = value(element, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &origin) }
                if let v = value(element, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &size) }
                return CGRect(origin: origin, size: size)
            }
            let app = AXUIElementCreateApplication(process.processIdentifier)
            for list in (value(app, kAXChildrenAttribute) as? [AXUIElement]) ?? [] where (value(list, kAXRoleAttribute) as? String) == "AXList" {
                let strip = frame(list)
                if strip.width > 160 { bar = (strip.minX + 40)...(strip.maxX - 40) }
                for item in (value(list, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                    if let title = value(item, kAXTitleAttribute) as? String { icons[title] = frame(item).midX }
                }
            }
        }
        return (Date(), bar, icons)
    }

    // MARK: Moving

    private func carry(to point: NSPoint) {
        hideBubble()
        if motion != .carried {
            grab = CGVector(dx: point.x - feet.x, dy: point.y - feet.y)
            motion = .carried
        }
        wake()
        feet = CGPoint(x: point.x - grab.dx, y: point.y - grab.dy)
    }

    private func drop() {
        goalX = nil
        flight = nil
        if staysPut { UserDefaults.standard.set(Double(feet.x), forKey: "petHomeX") }
        motion = reduceMotion ? .standing : .gliding
        if reduceMotion { feet.y = dock().floor }
    }

    private func place() {
        guard let panel else { return }
        let origin = NSPoint(x: (feet.x - size.width / 2).rounded(), y: feet.y.rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if let bubble { place(bubble) }
    }

    private func step() {
        guard let panel, panel.isVisible else { return }
        tick += 1
        let dock = self.dock()
        let pointer = NSEvent.mouseLocation
        let speaking = currentMood == .reading || currentMood == .talking
        let voice = CGFloat(speaking ? level() : 0)
        let still = reduceMotion

        // Where Lumen wants to be.
        if speaking || currentMood == .paused {
            if !staysPut, let app = readingApp(), let x = dock.icons[app] { goalX = x }
        } else if currentMood == .idle, motion == .standing, !view.sleeping, !still, !staysPut, Date() > nextWander {
            let span = dock.range.upperBound - dock.range.lowerBound
            var x = dock.range.lowerBound + CGFloat.random(in: 0...1) * span
            if abs(x - feet.x) < 90 { x = feet.x + (x < feet.x ? -140 : 140) }
            goalX = min(max(x, dock.range.lowerBound), dock.range.upperBound)
            nextWander = Date().addingTimeInterval(Double.random(in: 14...32))
        }
        // Step aside when the pointer is over the Dock right below, so magnified icons stay clickable.
        if motion == .standing, !speaking, !still, pointer.y < dock.floor, abs(pointer.x - feet.x) < 46, goalX == nil {
            goalX = feet.x + (pointer.x < feet.x ? 110 : -110)
        }
        // The Dock moved, shrank or went away under Lumen: she heads back onto it instead of hovering past its end.
        if motion == .standing, goalX == nil, feet.x < dock.range.lowerBound - 2 || feet.x > dock.range.upperBound + 2 {
            goalX = feet.x
        }
        if let goal = goalX { goalX = min(max(goal, dock.range.lowerBound), dock.range.upperBound) }

        switch motion {
        case .carried:
            break
        case .gliding:
            // Fluttering down, drifting toward the Dock if it was dropped beyond its ends.
            feet.y -= 4.5
            feet.x += (min(max(feet.x, dock.range.lowerBound), dock.range.upperBound) - feet.x) * 0.05
            if feet.y <= dock.floor {
                feet.y = dock.floor
                motion = .standing
                view.stretch = -0.12
            }
        case .flying:
            guard var trip = flight else { motion = .standing; break }
            trip.progress = min(trip.progress + 4.5 / max(abs(trip.to - trip.from), 1), 1)
            feet.x = trip.from + (trip.to - trip.from) * trip.progress
            feet.y = dock.floor + sin(trip.progress * .pi) * 70
            flight = trip
            if trip.progress >= 1 {
                feet.y = dock.floor
                motion = .standing
                flight = nil
                goalX = nil
                view.stretch = -0.1
            }
        case .standing, .walking:
            // The floor changed (the Dock grew, shrank, hid or moved): flutter down, or ease up, instead of jumping.
            let gap = dock.floor - feet.y
            if still || abs(gap) < 1 {
                feet.y = dock.floor
            } else if gap < -8 {
                motion = .gliding
                break
            } else {
                feet.y += min(max(gap, -4.5), 4.5)
            }
            if let goal = goalX, abs(goal - feet.x) > 2 {
                if still {
                    feet.x = goal
                    goalX = nil
                } else if abs(goal - feet.x) > 260 {
                    flight = (feet.x, goal, 0)
                    motion = .flying
                } else {
                    motion = .walking
                    feet.x += goal > feet.x ? min(1.6, goal - feet.x) : max(-1.6, goal - feet.x)
                }
                view.facingLeft = goal < feet.x
            } else {
                goalX = nil
                motion = .standing
            }
        }

        // Falls asleep after a few quiet minutes on the Dock.
        if currentMood == .idle, motion == .standing, Date().timeIntervalSince(lastActivity) > 180 { view.sleeping = true }

        // Which pose to show.
        let hop = CGFloat(tick - hopStart) / 24
        let pose: String
        switch motion {
        case .carried, .gliding, .flying: pose = "fly"
        case .walking: pose = (tick / 6) % 2 == 0 ? "walk1" : "walk2"
        case .standing:
            if view.sleeping { pose = "sleep" } else {
                switch currentMood {
                case .reading, .talking: pose = voice > 0.22 ? "talk" : "read"
                case .thinking: pose = "think"
                case .listening, .jump: pose = "listen"
                case .happy: pose = hop < 1.6 ? "cheer" : "wave"
                case .paused: pose = "read"
                case .idle:
                    let nearby = abs(pointer.x - feet.x) < 150 && pointer.y > dock.floor && pointer.y < dock.floor + 220
                    pose = nearby ? "wave" : "read"
                    if nearby { view.facingLeft = pointer.x < feet.x }
                }
            }
        }
        view.pose = pose
        if motion == .standing && (speaking || currentMood == .happy) { view.facingLeft = false }

        // Small motions: a hop when happy, wing flutter in the air, a landing squash, a sway when carried.
        let flutter = pose == "fly" && !still ? CGFloat(sin(Double(tick) * 0.9)) : 0
        view.stretch = still ? 0 : view.stretch * 0.8 + flutter * 0.025
        view.tilt = motion == .carried && !still ? CGFloat(sin(Double(tick) * 0.18)) * 0.12 : 0
        var lift: CGFloat = 0
        if currentMood == .happy, hop < 1, !still, motion == .standing { lift = sin(hop * .pi) * 22 }
        if pose == "fly", !still { lift += CGFloat(sin(Double(tick) * 0.3)) * 3 }
        let glowGoal: CGFloat = speaking ? 0.35 + voice * 0.65 : (view.sleeping ? 0.12 : 0.25)
        view.glow += (glowGoal - view.glow) * 0.35
        view.dots = view.sleeping ? tick / 8 : (currentMood == .thinking ? (tick / 9) % 3 + 1 : 0)
        let resting = feet
        feet.y += lift
        place()
        feet = resting
    }

    // MARK: Speech bubble

    /// Shows a short line from Lumen with up to two buttons. The first button is the main action.
    func say(_ text: String, actions: [(String, () -> Void)] = [], hideAfter seconds: Double? = nil) {
        hideBubble()
        showingHint = false
        guard isEnabled, panel?.isVisible == true else { return }
        wake()
        let content = Pet.bubbleContent(text, buttons: actions.map(\.0), target: self, action: #selector(bubbleButton(_:)))
        bubbleActions = actions.map(\.1)
        let bubble = NSPanel(floatingAt: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2), frame: content.frame)
        bubble.hasShadow = true
        bubble.hidesOnDeactivate = false
        bubble.appearance = NSAppearance(named: .darkAqua)
        bubble.collectionBehavior = [.canJoinAllSpaces, .stationary]
        bubble.contentView = content
        place(bubble)
        bubble.orderFrontRegardless()
        self.bubble = bubble
        if let seconds {
            let hide = DispatchWorkItem { [weak self] in self?.hideBubble() }
            bubbleHide = hide
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: hide)
        }
    }

    static func bubbleContent(_ text: String, buttons: [String], target: AnyObject?, action: Selector?) -> SurfaceView {
        let width: CGFloat = 300
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = Palette.text
        label.preferredMaxLayoutWidth = width - 32
        let textHeight = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - 32, height: 1000)).height ?? 40)
        let height = textHeight + 28 + (buttons.isEmpty ? 0 : 40)
        let view = SurfaceView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.radius = 16
        label.frame = NSRect(x: 16, y: height - 14 - textHeight, width: width - 32, height: textHeight)
        view.addSubview(label)
        var x: CGFloat = 16
        for (index, title) in buttons.enumerated() {
            let buttonWidth = ControlButton.labelWidth(title) + 30
            let button = ControlButton(frame: NSRect(x: x, y: 14, width: buttonWidth, height: 28))
            button.isBordered = false
            button.fill = index == 0 ? Palette.accent : Palette.well
            button.hoverFill = index == 0 ? Palette.accent.withAlphaComponent(0.82) : NSColor.white.withAlphaComponent(0.16)
            button.setLabel(title, color: index == 0 ? .black : Palette.text)
            button.tag = index
            button.target = target
            button.action = action
            button.setAccessibilityLabel(title)
            view.addSubview(button)
            x += buttonWidth + 8
        }
        return view
    }

    @objc private func bubbleButton(_ sender: NSButton) {
        let actions = bubbleActions
        hideBubble()
        if actions.indices.contains(sender.tag) { actions[sender.tag]() }
    }

    func hideBubble() {
        showingHint = false
        bubbleHide?.cancel()
        bubble?.orderOut(nil)
        bubble = nil
        bubbleActions = []
    }

    /// The bubble sits above Lumen's head, kept on screen.
    private func place(_ bubble: NSPanel) {
        guard let panel else { return }
        let pet = panel.frame
        let screen = (NSScreen.screens.first { $0.frame.intersects(pet) } ?? NSScreen.main ?? NSScreen.screens[0]).frame
        let size = bubble.frame.size
        let x = min(max(pet.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let y = min(pet.maxY - 6, screen.maxY - size.height - 8)
        bubble.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
