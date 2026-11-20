import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - App

/// Leaves follow mode so the reading can continue from the sentence the reader chose.
struct JumpRequested: Error {}

struct ReadingSetup {
    var items: [Utterance]
    var voice: String
    var audio: [Int: Task<URL, Error>] = [:]
}

@MainActor
final class NarratorApp: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private let speech = Speech()
    private let finished = PlaybackFinished()
    private let speeds: [Float] = [1, 1.2, 1.4, 1.7, 0.85]
    private var statusItem: NSStatusItem?
    private var overlays: [OverlayPanel] = []
    private var purposePanel: OverlayPanel?
    private var voiceSample: Task<Void, Never>?
    private var barPanel: NSPanel?
    private var statusLine: NSTextField?
    private var caption: NSTextField?
    private var progressLine: ProgressLine?
    /// Which sentence of how many is being read, for the progress bar.
    private var readingPlace = (index: 0, count: 1)
    private var controls: [NSButton] = []
    private var playButton: ControlButton?
    private var speedButton: ControlButton?
    private var followButton: ControlButton?
    private var jumpButton: ControlButton?
    private var jumpPanel: OverlayPanel?
    private var jumpWasPaused = false
    private var isFindingJump = false
    private var pendingJump: (target: JumpSentence, lines: [ScreenLine])?
    private let pet = Pet()
    private var onboarding = false
    private var accessPoll: Timer?
    private var readingMood = UserDefaults.standard.string(forKey: "mood") ?? "Auto"
    private var readingVoice = UserDefaults.standard.string(forKey: "voice") ?? "Auto"

    /// The voice chosen in the purpose box, or one that suits the material when that is Auto.
    private func narratorVoice(for material: String) -> String {
        voiceChoices.first { $0.title == readingVoice }?.voice ?? voice(for: material)
    }
    private var usesClaude: Bool { UserDefaults.standard.bool(forKey: "claudeDirection") && ClaudeCode.executable() != nil }
    private var statusBeforePause: (String, String)?
    private var barHide: DispatchWorkItem?
    private var highlightPanel: NSPanel?
    private var highlightView: HighlightView?
    private var selectedRect: CGRect?
    private var readingRect: CGRect?
    private var previousApp: NSRunningApplication?
    private var narration: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var isPaused = false
    private var jump = 0
    private var scrolledByUser = false
    private var rescan = false
    private var seen: [String] = []
    private var speed: Float = 1
    private var hotKeys: [EventHotKeyRef?] = []
    private var watchedWindow: WatchedWindow?
    private var windowWatch: Timer?
    private var isCovered = false
    private var windowMargins = NSEdgeInsetsZero
    private var lastWindowMove = Date.distantPast
    private var layoutChanged = false
    private var followNew = false
    private var spareHelper: WarmClaude?
    private var liveLines: [ScreenLine] = []
    private var liveBoxes: [String: CGRect]?
    private var replyQueue: [(lines: [ScreenLine], setup: Task<ReadingSetup, Error>)] = []
    private var replyWaiting: [ScreenLine] = []
    private var claimedLines: [String] = []
    private let answerFinished = PlaybackFinished()
    private var answerPlayer: AVAudioPlayer?
    private var askPanel: OverlayPanel?
    private var askField: PurposeField?
    private var askHint: NSTextField?
    private var askReturnApp: NSRunningApplication?
    private var askTask: Task<Void, Never>?
    private var isAnswering = false
    private var pausedForAsk = false
    private var resumePending = false
    private var askHistory: [(question: String, answer: String)] = []
    private var lastSources: [URL] = []
    private var closeButton: ControlButton?
    private var sourceButton: ControlButton?
    private var isSimulatingAsk = false

    private var currentRect: CGRect { readingRect ?? .zero }
    private var isSettling: Bool { Date().timeIntervalSince(lastWindowMove) < 0.4 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let inputs = CommandLine.arguments.filter { $0.hasPrefix("--direct-text=") || $0.hasPrefix("--direct-output=") }
        if inputs.count == 2 {
            let input = inputs.first { $0.hasPrefix("--direct-text=") }!.dropFirst("--direct-text=".count)
            let output = inputs.first { $0.hasPrefix("--direct-output=") }!.dropFirst("--direct-output=".count)
            Task { await writeDirectedSample(from: String(input), to: String(output)) }
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Narrator")
        let menu = NSMenu()
        let brand = menu.addItem(withTitle: "Narrator, your AI reading agent", action: nil, keyEquivalent: "")
        brand.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Select an area to read", action: #selector(beginSelection), keyEquivalent: "")
        menu.addItem(withTitle: "Play or pause", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(withTitle: "Stop reading", action: #selector(stopReading), keyEquivalent: "")
        menu.addItem(withTitle: "Open last source", action: #selector(openSource), keyEquivalent: "")
        menu.addItem(.separator())
        let askHint = menu.addItem(withTitle: "Ask a question: press Option + Shift + A", action: nil, keyEquivalent: "")
        askHint.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Lumen", action: #selector(togglePet(_:)), keyEquivalent: "").state = pet.isEnabled ? .on : .off
        menu.addItem(withTitle: "Keep Lumen in one place", action: #selector(togglePetStaysPut(_:)), keyEquivalent: "").state = pet.staysPut ? .on : .off
        menu.addItem(withTitle: "Replay welcome", action: #selector(welcome), keyEquivalent: "")
        if ClaudeCode.executable() != nil {
            menu.addItem(withTitle: "Richer voice with Claude (uses your Claude plan)", action: #selector(toggleClaudeDirection(_:)), keyEquivalent: "").state = usesClaude ? .on : .off
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Narrator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.items.filter { $0.action != nil && $0.action != #selector(NSApplication.terminate(_:)) }.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        let saved = UserDefaults.standard.float(forKey: "speed")
        speed = speeds.contains(saved) ? saved : 1

        registerShortcuts()
        watchInput()
        note("launched; screen recording \(CGPreflightScreenCaptureAccess()), accessibility \(AXIsProcessTrusted())")
        do {
            try speech.start()
        } catch {
            note("speech failed to start: \(error)")
            showMessage("Kokoro could not start")
        }
        setUpPet()
        // Lets a test read a known area without using the selector.
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--read-rect=") }) {
            let values = argument.dropFirst("--read-rect=".count).split(separator: ",").compactMap { Double($0) }
            if values.count == 4 {
                let purpose = CommandLine.arguments.first { $0.hasPrefix("--purpose=") }?.dropFirst("--purpose=".count) ?? ""
                previousApp = NSWorkspace.shared.frontmostApplication
                startReading(CGRect(x: values[0], y: values[1], width: values[2], height: values[3]), purpose: String(purpose))
            }
        }
        // Lets a test ask a recorded question at a set moment without using the microphone.
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--simulate-ask=") }) {
            let parts = argument.dropFirst("--simulate-ask=".count).split(separator: ",", maxSplits: 1).map(String.init)
            if parts.count == 2, let delay = Double(parts[0]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.simulateAsk(question: parts[1]) }
            }
        }
        // Measures whether the interface stays responsive while text is being recognised.
        if CommandLine.arguments.contains("--test-responsiveness") {
            Task {
                final class Beat { var last = Date(); var longest = 0.0 }
                let beat = Beat()
                let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
                    let now = Date()
                    beat.longest = max(beat.longest, now.timeIntervalSince(beat.last))
                    beat.last = now
                }
                RunLoop.main.add(timer, forMode: .common)
                let image = renderedTextImage((1...12).map { "Line \($0) of the responsiveness check for text recognition." })
                let began = Date()
                var recognized = 0
                for _ in 0..<40 { recognized += ((try? await recognizeLines(in: image))?.isEmpty == false) ? 1 : 0 }
                timer.invalidate()
                note(String(format: "responsiveness test: %d of 40 recognitions in %.1f seconds, longest interface pause %.0f ms", recognized, Date().timeIntervalSince(began), beat.longest * 1000))
            }
        }
        // Lets a test jump to a sentence with real mouse events.
        for argument in CommandLine.arguments where argument.hasPrefix("--test-jump=") {
            let parts = argument.dropFirst("--test-jump=".count).split(separator: ",", maxSplits: 1).map(String.init)
            guard parts.count == 2, let delay = Double(parts[0]) else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.testJump(to: parts[1]) }
        }
        // Lets a test drag across the selector with real mouse events.
        if CommandLine.arguments.contains("--test-selection") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.beginSelection() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.5) {
                func post(_ type: CGEventType, _ point: CGPoint) {
                    CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                    usleep(40000)
                }
                post(.mouseMoved, CGPoint(x: 400, y: 320))
                post(.leftMouseDown, CGPoint(x: 400, y: 320))
                for step in 1...14 { post(.leftMouseDragged, CGPoint(x: 400 + step * 25, y: 320 + step * 15)) }
                post(.leftMouseUp, CGPoint(x: 750, y: 530))
                note("selection test: mouse events sent")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                note("selection test: purpose box open \(self?.purposePanel != nil), overlays \(self?.overlays.count ?? -1)")
                self?.closeSelectionUI()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        speech.stop()
        spareHelper?.stop()
    }

    // MARK: Lumen and the first run

    private func setUpPet() {
        pet.level = { [weak self] in self?.voiceLevel() ?? 0 }
        pet.readingApp = { [weak self] in self?.previousApp?.localizedName }
        pet.onClick = { [weak self] in self?.petClicked() }
        pet.onMenu = { [weak self] event, view in
            guard let menu = self?.statusItem?.menu else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
        let ready = CGPreflightScreenCaptureAccess() && AXIsProcessTrusted()
        if UserDefaults.standard.bool(forKey: "onboarded"), ready {
            pet.show(swooping: true)
            pet.mood = .happy
            pet.relax(after: 2.5)
        } else {
            welcome()
        }
    }

    /// How loud the voice playing now is, from 0 to 1, so Lumen's mouth and lantern follow it.
    private func voiceLevel() -> Float {
        guard let sound = [answerPlayer, player].compactMap({ $0 }).first(where: { $0.isPlaying }) else { return 0 }
        sound.updateMeters()
        return min(max((sound.averagePower(forChannel: 0) + 42) / 36, 0), 1)
    }

    private func petClicked() {
        if narration != nil {
            togglePause()
        } else if !isAskBusy {
            pet.hideBubble()
            beginSelection()
        }
    }

    @objc private func welcome() {
        onboarding = true
        pet.show(swooping: true)
        pet.mood = .happy
        pet.say("Hi, I'm Lumen, the face of Narrator, your AI reading agent. Point me at anything on your screen and I'll read it to you.", actions: [
            ("Show me", { [weak self] in self?.continueSetup() }),
            ("Later", { [weak self] in self?.finishSetup() }),
        ])
        Task { [weak self] in
            await self?.speech.waitUntilReady()
            guard let self, self.onboarding, self.narration == nil, !self.isAskBusy else { return }
            self.pet.mood = .talking
            await self.say("Hi, I'm Lumen. Read more, without reading. Point me at anything and I'll read it to you.")
            if self.pet.mood == .talking { self.pet.mood = .happy }
        }
    }

    private func continueSetup() {
        accessPoll?.invalidate()
        accessPoll = nil
        pet.show()
        if !CGPreflightScreenCaptureAccess() {
            pet.mood = .listening
            pet.say("First, I need to see your screen. Switch on Narrator in Screen Recording, then reopen me.", actions: [
                ("Open settings", { [weak self] in
                    CGRequestScreenCaptureAccess()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    self?.pet.say("When Narrator is switched on, reopen me so the change takes effect.", actions: [("Reopen Narrator", { self?.relaunch() })])
                }),
                ("Reopen Narrator", { [weak self] in self?.relaunch() }),
            ])
            return
        }
        if !AXIsProcessTrusted() {
            pet.mood = .listening
            pet.say("Next, let me scroll pages and hear your shortcuts. Switch on Narrator in Accessibility.", actions: [
                ("Open settings", { [weak self] in
                    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    self?.pet.say("I'll carry on as soon as it's switched on.")
                }),
            ])
            let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if AXIsProcessTrusted() { self?.continueSetup() } }
            }
            RunLoop.main.add(poll, forMode: .common)
            accessPoll = poll
            return
        }
        pet.mood = .happy
        pet.say("All set. Drag over any text, like a Claude reply, and I'll read it to you. Next time, press Option + Shift + 4.", actions: [
            ("Pick text", { [weak self] in self?.beginSelection() }),
            ("Later", { [weak self] in self?.finishSetup() }),
        ])
    }

    private func finishSetup() {
        accessPoll?.invalidate()
        accessPoll = nil
        onboarding = false
        UserDefaults.standard.set(true, forKey: "onboarded")
        if narration == nil {
            pet.hideBubble()
            pet.relax(after: 1)
        }
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func togglePet(_ sender: NSMenuItem) {
        pet.isEnabled.toggle()
        sender.state = pet.isEnabled ? .on : .off
        guard pet.isEnabled else { return }
        pet.show(swooping: true)
        if narration == nil {
            pet.mood = .happy
            pet.relax(after: 2.5)
        }
    }

    @objc private func togglePetStaysPut(_ sender: NSMenuItem) {
        pet.staysPut.toggle()
        sender.state = pet.staysPut ? .on : .off
    }

    @objc private func toggleClaudeDirection(_ sender: NSMenuItem) {
        let on = !usesClaude
        UserDefaults.standard.set(on, forKey: "claudeDirection")
        sender.state = on ? .on : .off
    }

    // MARK: Shortcuts

    private func registerShortcuts() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let command = id.id
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            Task { @MainActor in narrator.perform(command, pressed: pressed) }
            return noErr
        }, 2, &types, nil, nil)
        // macOS 27 reserves Command + Shift + 6 for Visual Intelligence, so everything uses Option + Shift.
        let keys = [kVK_ANSI_4, kVK_Space, kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_A, kVK_ANSI_J]
        for (index, key) in keys.enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4E415252), id: UInt32(index + 1))
            let status = RegisterEventHotKey(UInt32(key), UInt32(optionKey | shiftKey), id, GetApplicationEventTarget(), 0, &reference)
            note("shortcut \(index + 1) registered with status \(status)")
            hotKeys.append(reference)
        }
    }

    private func perform(_ command: UInt32, pressed: Bool) {
        guard pressed else { return }
        if command == 5 {
            askPressed()
            return
        }
        note("shortcut \(command) pressed")
        switch command {
        case 1: beginSelection()
        case 2: togglePause()
        case 3: skipBack()
        case 4: skipForward()
        case 6: jumpPressed()
        default: break
        }
    }

    private func watchInput() {
        NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            let synthetic = event.cgEvent?.getIntegerValueField(.eventSourceUserData) == syntheticScrollMarker
            let type = event.type
            let isEscape = type == .keyDown && Int(event.keyCode) == kVK_Escape
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self, self.narration != nil || self.isAskBusy else { return }
                if isEscape {
                    if self.jumpPanel != nil || self.isFindingJump { self.cancelJump() } else { self.stopReading() }
                } else if type == .scrollWheel, !synthetic, let rect = self.readingRect, bottomLeftRect(from: rect).contains(location) {
                    self.scrolledByUser = true
                    self.setPaused(true, message: "Paused because you scrolled. Press play to read from here.")
                }
            }
        }
    }

    // MARK: Playback controls

    @objc private func togglePause() {
        guard narration != nil, jumpPanel == nil, !isFindingJump else { return }
        setPaused(!isPaused)
    }

    // MARK: Jump to a sentence

    @objc private func jumpPressed() {
        guard narration != nil, !isAskBusy else { return }
        guard jumpPanel == nil, !isFindingJump else { return cancelJump() }
        jumpWasPaused = isPaused
        isFindingJump = true
        jumpButton?.isOn = true
        setPaused(true)
        setStatus("Jump", "Finding the sentences on screen.")
        Task { [weak self] in
            guard let self else { return }
            let image = try? await capture(self.currentRect)
            let recognized = image == nil ? nil : try? await recognizeLines(in: image!)
            guard self.isFindingJump else { return }
            self.isFindingJump = false
            let lines = readableLines(recognized ?? [])
            let sentences = jumpSentences(lines)
            guard !sentences.isEmpty else {
                self.cancelJump()
                self.showBar(status: "Jump", "I couldn't find any text to jump to here.")
                return
            }
            self.showJumpPicker(sentences, lines: lines)
        }
    }

    private func showJumpPicker(_ sentences: [JumpSentence], lines: [ScreenLine]) {
        let frame = bottomLeftRect(from: currentRect)
        let panel = OverlayPanel(floatingAt: NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1), frame: frame)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = JumpView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.sentences = sentences
        view.onCancel = { [weak self] in self?.cancelJump() }
        view.onPick = { [weak self] index in self?.finishJump(sentences[index], lines: lines) }
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        jumpPanel = panel
        highlightView?.segments = []
        setStatus("Jump", "Click or drag over the sentence to read from. Esc cancels.")
    }

    private func closeJumpPicker() {
        isFindingJump = false
        jumpPanel?.orderOut(nil)
        jumpPanel = nil
        jumpButton?.isOn = false
    }

    private func cancelJump() {
        closeJumpPicker()
        if jumpWasPaused {
            setStatus("Paused", "Press play to continue.")
        } else {
            setPaused(false)
        }
    }

    private func finishJump(_ target: JumpSentence, lines: [ScreenLine]) {
        closeJumpPicker()
        note("jumped to a sentence on line \(target.line + 1) of \(lines.count)")
        pendingJump = (target, lines)
        scrolledByUser = false
        jump = 0
        statusBeforePause = nil
        rescan = true
        finishCurrentSentence()
        player = nil
        setPaused(false)
        setStatus("Jump", "Reading from the sentence you chose.")
    }

    /// Speaks from the chosen sentence. Returns false when another jump or scroll has replaced it.
    private func readPendingJump(purpose: String) async throws {
        guard let chosen = pendingJump else { return }
        pendingJump = nil
        rescan = false
        seen = seenBeforeJump(seen, line: chosen.target.line, in: chosen.lines)
        try await narrate(linesToRead(from: chosen.target, in: chosen.lines), purpose: purpose, alreadyRead: [])
    }

    private func testJump(to words: String) {
        jumpPressed()
        Task { [weak self] in
            for _ in 0..<60 where self?.jumpPanel == nil { try? await Task.sleep(for: .milliseconds(100)) }
            guard let self, let view = self.jumpPanel?.contentView as? JumpView,
                  let box = view.sentences.first(where: { $0.text.contains(words) })?.boxes.first else {
                return note("TEST jump could not find: \(words)")
            }
            let area = self.currentRect
            let point = CGPoint(x: area.minX + box.midX * area.width, y: area.minY + (1 - box.midY) * area.height)
            note("TEST jump to: \(words)")
            DispatchQueue.global().async {
                for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                    CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                    usleep(120000)
                }
            }
        }
    }

    private func setPaused(_ paused: Bool, message: String? = nil) {
        guard paused != isPaused else { return }
        isPaused = paused
        playButton?.image = symbol(paused ? "play.fill" : "pause.fill", label: paused ? "Play" : "Pause")
        playButton?.setAccessibilityLabel(paused ? "Play" : "Pause")
        if paused {
            player?.pause()
            statusBeforePause = (statusLine?.stringValue ?? "", caption?.stringValue ?? "")
            setStatus("Paused", message ?? "Press play to continue.")
        } else if let previous = statusBeforePause, !scrolledByUser {
            statusBeforePause = nil
            setStatus(previous.0, previous.1)
            player?.play()
        } else if scrolledByUser {
            scrolledByUser = false
            rescan = true
            finishCurrentSentence()
        } else {
            player?.play()
        }
    }

    @objc private func skipBack() { skip(by: -1) }
    @objc private func skipForward() { skip(by: 1) }

    private func skip(by amount: Int) {
        guard narration != nil, jumpPanel == nil, !isFindingJump else { return }
        jump = amount
        setPaused(false)
        finishCurrentSentence()
    }

    private func finishCurrentSentence() {
        player?.stop()
        finished.onFinish?()
    }

    @objc private func cycleSpeed() {
        let position = speeds.firstIndex(of: speed) ?? 0
        speed = speeds[(position + 1) % speeds.count]
        UserDefaults.standard.set(speed, forKey: "speed")
        player?.rate = speed
        updateSpeedButton()
    }

    private func updateSpeedButton() {
        speedButton?.setLabel(String(format: speed == floor(speed) ? "%.0f×" : "%.2g×", speed), size: 13)
    }

    @objc private func toggleFollow() {
        followNew.toggle()
        note("follow switched \(followNew ? "on" : "off")")
        updateFollowButton()
    }

    private func updateFollowButton() {
        followButton?.isOn = followNew
        followButton?.setLabel(followNew ? "Follow on" : "Follow off")
        followButton?.setAccessibilityValue(followNew ? "On" : "Off")
    }

    @objc private func stopReading() {
        if isAskBusy {
            cancelAsk()
        } else {
            endReading("Stopped")
        }
    }

    // MARK: Ask a question

    private var isAskBusy: Bool { isAnswering || askPanel != nil }

    /// Opens the Ask box. Pressing the shortcut again sends what is written, or closes the box when it is empty.
    private func askPressed() {
        if jumpPanel != nil || isFindingJump { cancelJump() }
        guard askPanel == nil else {
            let typed = (askField?.currentEditor()?.string ?? askField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if typed.isEmpty { cancelAsk() } else { sendQuestion() }
            return
        }
        stopAnswer()
        beginAskPause()
        openAskBox()
    }

    private func beginAskPause() {
        if resumePending {
            resumePending = false
            pausedForAsk = true
        } else if narration != nil, !isPaused {
            pausedForAsk = true
            setPaused(true)
        }
    }

    /// The rounded text box shared by the purpose box and the Ask box.
    private func textBox(in background: NSView, y: CGFloat, placeholder: String, label: String, action: Selector, onCancel: @escaping () -> Void) -> PurposeField {
        let width = background.frame.width
        let well = SurfaceView(frame: NSRect(x: 14, y: y, width: width - 28, height: 40))
        well.radius = 11
        well.fill = Palette.well
        background.addSubview(well)
        let field = PurposeField(frame: NSRect(x: 28, y: y + 9, width: width - 56, height: 22))
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: Palette.secondaryText,
            .font: NSFont.systemFont(ofSize: 15),
        ])
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.textColor = Palette.text
        field.target = self
        field.action = action
        field.setAccessibilityLabel(label)
        field.onCancel = onCancel
        background.addSubview(field)
        return field
    }

    /// The small grey line of keyboard hints along the bottom of a box.
    private func hintLine(_ text: String, in background: NSView, y: CGFloat) -> NSTextField {
        let hint = NSTextField(labelWithString: text)
        hint.frame = NSRect(x: 16, y: y, width: background.frame.width - 32, height: 16)
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = Palette.secondaryText
        background.addSubview(hint)
        return hint
    }

    private func askBoxContent() -> (view: SurfaceView, field: PurposeField, hint: NSTextField) {
        let background = SurfaceView(frame: NSRect(x: 0, y: 0, width: 560, height: 92))
        let field = textBox(in: background, y: 38, placeholder: "Ask about this, or ask me to search", label: "Ask a question",
                            action: #selector(askEntered), onCancel: { [weak self] in self?.cancelAsk() })
        let hint = hintLine("Type or dictate your question, then press Return.    Esc to cancel", in: background, y: 12)
        return (background, field, hint)
    }

    private func openAskBox() {
        pet.show()
        guard ClaudeCode.executable() != nil else {
            pet.mood = .paused
            pet.say("Asking questions uses Claude Code. Install it and sign in, then try again.", hideAfter: 6)
            finishAsk(nil)
            return
        }
        pet.mood = .listening
        askReturnApp = NSWorkspace.shared.frontmostApplication
        showAsk(status: "Ask", "Your reading is paused.")
        let content = askBoxContent()
        let size = content.view.frame.size
        let bar = barPanel?.frame ?? NSRect(x: 400, y: 800, width: 700, height: 78)
        let panel = OverlayPanel(floatingAt: .screenSaver, frame: NSRect(x: bar.midX - size.width / 2, y: bar.minY - size.height - 8, width: size.width, height: size.height))
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = content.view
        askPanel = panel
        askField = content.field
        askHint = content.hint
        updateControls()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(content.field)
    }

    private func closeAskBox() {
        askPanel?.orderOut(nil)
        askPanel = nil
        askField = nil
        askHint = nil
    }

    @objc private func askEntered() { sendQuestion() }

    private func sendQuestion() {
        guard let field = askField else { return }
        let question = (field.currentEditor()?.string ?? field.stringValue).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        closeAskBox()
        askReturnApp?.activate()
        beginAnswer(question: question)
    }

    private func simulateAsk(question: String) {
        isSimulatingAsk = true
        beginAskPause()
        note("question asked; reading paused: \(pausedForAsk)")
        beginAnswer(question: question)
    }

    private func beginAnswer(question: String) {
        isAnswering = true
        showAsk(status: "Thinking", question)
        askTask = Task { [weak self] in await self?.answer(question) }
    }

    private func answer(_ question: String) async {
        do {
            let began = Date()
            let screen = await screenContext()
            let holdOn = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                await self?.say("One moment.")
            }
            let reply = try await Assistant.answer(question: question, screen: screen, currentSentence: statusBeforePause?.1 ?? "", history: askHistory)
            holdOn.cancel()
            await holdOn.value
            try Task.checkCancellation()
            lastSources = reply.sources.compactMap { safeSourceURL($0.url) }
            askHistory.append((question, reply.spoken))
            askHistory = Array(askHistory.suffix(6))
            note(String(format: "answer ready in %.1f seconds with %d sources", Date().timeIntervalSince(began), lastSources.count))
            if isSimulatingAsk { note("TEST question: \(question) | answer: \(reply.spoken) | sources: \(lastSources.map(\.absoluteString))") }
            updateControls()
            let lines = sentences(in: reply.spoken)
            var audio: [Int: Task<URL, Error>] = [:]
            // Clips made ahead are deleted too when the answer is cancelled partway.
            defer { discardClips(audio.values) }
            for index in lines.indices {
                for ahead in index..<min(index + 2, lines.count) where audio[ahead] == nil {
                    let upcoming = Utterance(text: lines[ahead], spans: [], pauseAfter: 0.14)
                    audio[ahead] = Task { try await self.performedClip(upcoming, narrator: narratorVoice(for: "other")) }
                }
                setStatus("Answer", lines[index])
                await playAnswerClip(try await audio[index]!.value)
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(140))
            }
            note("answer finished")
            finishAsk(nil)
        } catch is CancellationError {
            return
        } catch {
            note("answer failed: \(error)")
            finishAsk("I couldn't get an answer. Check your connection and try again.")
        }
    }

    private func say(_ line: String) async {
        guard let url = try? await performedClip(Utterance(text: line, spans: [], pauseAfter: 0), narrator: narratorVoice(for: "other")) else { return }
        await playAnswerClip(url)
    }

    private func playAnswerClip(_ url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let sound = try? makePlayer(url, volume: 0.88, reportingTo: answerFinished) else { return }
        answerPlayer = sound
        await playToEnd(sound, reportingTo: answerFinished, start: true)
        answerPlayer = nil
    }

    /// A player for one clip that follows the reading speed and measures loudness for Lumen.
    private func makePlayer(_ url: URL, volume: Float, reportingTo finish: PlaybackFinished) throws -> AVAudioPlayer {
        let sound = try AVAudioPlayer(contentsOf: url)
        sound.delegate = finish
        sound.isMeteringEnabled = true
        sound.enableRate = true
        sound.rate = speed
        sound.volume = volume
        sound.prepareToPlay()
        return sound
    }

    /// Returns when the clip ends or is stopped. A paused reading waits here without starting the clip.
    private func playToEnd(_ sound: AVAudioPlayer, reportingTo finish: PlaybackFinished, start: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finish.onFinish = { [weak finish] in
                finish?.onFinish = nil
                continuation.resume()
            }
            if start, !sound.play() { finish.onFinish?() }
        }
    }

    /// Reads the area being narrated, or the window under the cursor when nothing is being read.
    private func screenContext() async -> String {
        var area = narration == nil ? topWindow(at: globalCursorLocation())?.bounds : currentRect
        if let rect = area, let screen = NSScreen.screens.first(where: { topLeftRect(from: $0.frame).intersects(rect) }) {
            area = rect.intersection(topLeftRect(from: screen.frame))
        }
        guard let area, area.width >= 8, area.height >= 8, let image = try? await capture(area),
              let lines = try? await recognizeLines(in: image) else { return "" }
        return readableLines(lines).map(\.text).joined(separator: "\n")
    }

    private func stopAnswer() {
        askTask?.cancel()
        askTask = nil
        isAnswering = false
        answerPlayer?.stop()
        answerFinished.onFinish?()
    }

    private func cancelAsk() {
        if askPanel != nil {
            closeAskBox()
            askReturnApp?.activate()
        }
        stopAnswer()
        finishAsk(nil)
    }

    private func finishAsk(_ message: String?) {
        isAnswering = false
        askTask = nil
        if let message { setStatus("Narrator", message) }
        if pausedForAsk {
            pausedForAsk = false
            resumePending = true
            updateControls()
            let delay = message == nil && lastSources.isEmpty ? 0.6 : 1.8
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, self.resumePending else { return }
                self.resumePending = false
                self.updateControls()
                guard self.narration != nil else { return }
                note("reading resumed")
                self.setPaused(false)
            }
        } else {
            updateControls()
            if narration != nil {
                setStatus("Paused", "Press play to continue.")
            } else {
                hideBar(after: lastSources.isEmpty ? 4 : 10)
                pet.relax(after: 4)
            }
        }
    }

    private func showAsk(status: String, _ text: String) {
        barHide?.cancel()
        if barPanel == nil { buildBar() }
        setStatus(status, text)
        updateControls()
        positionBar()
        barPanel?.orderFrontRegardless()
    }

    @objc private func openSource() {
        guard let url = lastSources.first else { return }
        NSWorkspace.shared.open(url)
    }

    private func endReading(_ message: String) {
        narration?.cancel()
        closeJumpPicker()
        pendingJump = nil
        spareHelper?.stop()
        spareHelper = nil
        narration = nil
        windowWatch?.invalidate()
        windowWatch = nil
        watchedWindow = nil
        isCovered = false
        followNew = false
        pausedForAsk = false
        resumePending = false
        statusBeforePause = nil
        finishCurrentSentence()
        isPaused = false
        clearHighlight()
        showMessage(message)
        pet.mood = .happy
        pet.relax(after: 3)
    }

    // MARK: Follow the window being read

    private func watchWindow(under rect: CGRect) {
        watchedWindow = topWindow(at: CGPoint(x: rect.midX, y: rect.midY))
        note("reading area \(rect) inside window \(watchedWindow?.bounds ?? .zero)")
        if let bounds = watchedWindow?.bounds {
            windowMargins = NSEdgeInsets(top: rect.minY - bounds.minY, left: rect.minX - bounds.minX, bottom: bounds.maxY - rect.maxY, right: bounds.maxX - rect.maxX)
        }
        isCovered = false
        lastWindowMove = .distantPast
        windowWatch?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkWatchedWindow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        windowWatch = timer
    }

    private func checkWatchedWindow() {
        guard let watched = watchedWindow else { return }
        guard let current = windowDetails(watched.id) else {
            note("target window closed")
            endReading("Stopped because the document was closed")
            return
        }
        if current.bounds != watched.bounds { moveReadingArea(with: current, from: watched) }
        watchedWindow = current
        let rect = currentRect
        let fitsOnScreen = NSScreen.screens.contains { topLeftRect(from: $0.frame).contains(rect) }
        let visible = fitsOnScreen && topWindow(at: CGPoint(x: rect.midX, y: rect.midY))?.id == watched.id
        if isCovered == visible { note(visible ? "target window visible" : "target window covered") }
        isCovered = !visible
        highlightPanel?.alphaValue = visible ? 1 : 0
        if visible, !followNew, !current.title.isEmpty, current.title != watched.title {
            note("target window title changed")
            scrolledByUser = true
            setPaused(true, message: "The page changed. Press play to read what's on screen now.")
        }
    }

    /// Keeps the reading area in the same place inside the window as it moves or resizes.
    private func moveReadingArea(with window: WatchedWindow, from previous: WatchedWindow) {
        let bounds = window.bounds
        let rect = CGRect(
            x: bounds.minX + windowMargins.left,
            y: bounds.minY + windowMargins.top,
            width: bounds.width - windowMargins.left - windowMargins.right,
            height: bounds.height - windowMargins.top - windowMargins.bottom
        )
        guard rect.width >= 40, rect.height >= 40 else { return }
        if !isSettling { note("target window moved to \(bounds), reading area \(rect)") }
        readingRect = rect
        lastWindowMove = Date()
        highlightPanel?.setFrame(bottomLeftRect(from: rect), display: true)
        jumpPanel?.setFrame(bottomLeftRect(from: rect), display: true)
        if bounds.size != previous.bounds.size {
            layoutChanged = true
            highlightView?.segments = []
        }
        positionBar()
    }

    private func waitUntilVisible() async throws {
        while isCovered || isSettling {
            if isCovered { setStatus("Waiting", "Bring the document back into view to continue reading.") }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    // MARK: Select and ask for the purpose

    @objc func beginSelection() {
        if isAskBusy { cancelAsk() }
        if narration != nil { endReading("Stopped") }
        closeSelectionUI()
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        overlays = NSScreen.screens.map { screen in
            let panel = OverlayPanel(floatingAt: .screenSaver, frame: screen.frame)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = false
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in self?.finishSelection(rect) }
            panel.contentView = view
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            return panel
        }
        note("selection: overlay opened on \(overlays.count) screens; key \(overlays.first?.isKeyWindow ?? false), app active \(NSApp.isActive)")
    }

    private func closeSelectionUI() {
        if !overlays.isEmpty { note("selection: overlay closed") }
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        purposePanel?.orderOut(nil)
        purposePanel = nil
    }

    private func finishSelection(_ rect: NSRect?) {
        note("selection: finished with \(rect.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nothing")")
        closeSelectionUI()
        guard let rect, rect.width >= 8, rect.height >= 8 else { return }
        selectedRect = topLeftRect(from: rect)
        askPurpose(near: rect)
    }

    private func purposeContent(purpose: String) -> (view: SurfaceView, field: PurposeField) {
        let background = SurfaceView(frame: NSRect(x: 0, y: 0, width: 540, height: 212))
        let field = textBox(in: background, y: 158, placeholder: "What should I read? Try: Claude's replies, calm", label: "What should I read?",
                            action: #selector(purposeEntered(_:)), onCancel: { [weak self] in self?.closeSelectionUI() })
        field.stringValue = purpose

        func row(_ name: String, _ titles: [String], y: CGFloat, action: Selector, selected: Int?, shortcuts: Bool) {
            let label = NSTextField(labelWithString: name)
            label.frame = NSRect(x: 16, y: y + 6, width: 46, height: 16)
            label.font = .systemFont(ofSize: 11.5, weight: .semibold)
            label.textColor = Palette.secondaryText
            background.addSubview(label)
            var x: CGFloat = 64
            for (index, title) in titles.enumerated() {
                let width = ControlButton.labelWidth(title) + 26
                let chip = ControlButton(frame: NSRect(x: x, y: y, width: width, height: 28))
                chip.isBordered = false
                chip.fill = Palette.well
                chip.setLabel(title)
                chip.tag = index
                chip.isOn = index == selected
                chip.target = self
                chip.action = action
                if shortcuts {
                    chip.keyEquivalent = String(index + 1)
                    chip.keyEquivalentModifierMask = .command
                    chip.toolTip = "Command + \(index + 1)"
                }
                chip.setAccessibilityLabel(name + ": " + title)
                background.addSubview(chip)
                x += width + 6
            }
        }
        row("Read", ["Everything", "Claude's replies", "New replies only"], y: 116, action: #selector(choosePreset(_:)), selected: nil, shortcuts: true)
        row("Mood", LocalDirector.moods, y: 80, action: #selector(chooseMood(_:)), selected: LocalDirector.moods.firstIndex(of: readingMood) ?? 0, shortcuts: false)
        row("Voice", voiceChoices.map(\.title), y: 44, action: #selector(chooseVoice(_:)), selected: voiceChoices.firstIndex { $0.title == readingVoice } ?? 0, shortcuts: false)
        _ = hintLine("Return to start    Esc to cancel    Click a voice to hear it", in: background, y: 14)
        return (background, field)
    }

    @objc private func chooseMood(_ sender: ControlButton) {
        readingMood = LocalDirector.moods[sender.tag]
        UserDefaults.standard.set(readingMood, forKey: "mood")
        sender.superview?.subviews.compactMap { $0 as? ControlButton }
            .filter { $0.action == #selector(chooseMood(_:)) }
            .forEach { $0.isOn = $0.tag == sender.tag }
    }

    /// Picks a voice and plays a one-line sample of it, so the choice is heard before reading starts.
    @objc private func chooseVoice(_ sender: ControlButton) {
        let choice = voiceChoices[sender.tag]
        readingVoice = choice.title
        UserDefaults.standard.set(readingVoice, forKey: "voice")
        sender.superview?.subviews.compactMap { $0 as? ControlButton }
            .filter { $0.action == #selector(chooseVoice(_:)) }
            .forEach { $0.isOn = $0.tag == sender.tag }
        voiceSample?.cancel()
        answerPlayer?.stop()
        voiceSample = Task { [weak self] in
            guard let self else { return }
            let line = Utterance(text: choice.sample, spans: [], pauseAfter: 0)
            guard let url = try? await self.performedClip(line, narrator: choice.voice ?? voice(for: "other")) else { return }
            guard !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
            self.pet.mood = .talking
            await self.playAnswerClip(url)
            if self.pet.mood == .talking { self.pet.mood = .idle }
        }
    }

    private func askPurpose(near rect: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main ?? NSScreen.screens[0]
        let content = purposeContent(purpose: UserDefaults.standard.string(forKey: purposeKey) ?? "")
        let size = content.view.frame.size
        let x = min(max(rect.minX, screen.visibleFrame.minX + 12), screen.visibleFrame.maxX - size.width - 12)
        let below = rect.minY - size.height - 10
        let y = below > screen.visibleFrame.minY ? below : min(rect.maxY + 10, screen.visibleFrame.maxY - size.height)
        let panel = OverlayPanel(floatingAt: .screenSaver, frame: NSRect(x: x, y: y, width: size.width, height: size.height))
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = content.view
        purposePanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(content.field)
        content.field.currentEditor()?.selectAll(nil)
    }

    private var purposeKey: String { "purpose." + (previousApp?.bundleIdentifier ?? "any") }

    @objc private func purposeEntered(_ sender: NSTextField) {
        let purpose = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(purpose, forKey: purposeKey)
        if let mood = LocalDirector.mood(in: purpose) {
            readingMood = mood
            UserDefaults.standard.set(mood, forKey: "mood")
        }
        beginReadingSelection(purpose: purpose)
    }

    @objc private func choosePreset(_ sender: NSButton) {
        let purposes = ["", "Read only the replies from Claude.", "Read only the replies from Claude."]
        beginReadingSelection(purpose: purposes[sender.tag], startAtEnd: sender.tag == 2)
    }

    private func beginReadingSelection(purpose: String, startAtEnd: Bool = false) {
        closeSelectionUI()
        previousApp?.activate()
        guard let rect = selectedRect else { return }
        startReading(rect, purpose: purpose, startAtEnd: startAtEnd)
    }

    private func startReading(_ rect: CGRect, purpose: String, startAtEnd: Bool = false) {
        isPaused = false
        jump = 0
        rescan = false
        scrolledByUser = false
        layoutChanged = false
        statusBeforePause = nil
        seen = []
        readingRect = rect
        showHighlight(over: rect)
        watchWindow(under: rect)
        followNew = startAtEnd || looksLikeChat(owner: watchedWindow?.owner ?? "", title: watchedWindow?.title ?? "", purpose: purpose)
        note("window app \(watchedWindow?.owner ?? "none"), follow \(followNew ? "on" : "off")")
        spareHelper?.stop()
        spareHelper = followNew && usesClaude ? try? WarmClaude(system: Planner.system, schema: Planner.schema) : nil
        narration = Task { [weak self] in await self?.read(purpose: purpose, startAtEnd: startAtEnd) }
        showBar(status: "Preparing", "Getting the voice ready.")
        pet.hideBubble()
        pet.show()
        if onboarding {
            finishSetup()
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self] in
                guard let self, self.narration != nil else { return }
                self.pet.say("Tip: press Option + Shift + A to ask me about anything on screen, or Jump to skip to a sentence.", hideAfter: 7)
            }
        }
    }

    // MARK: Read, scroll and continue

    private func read(purpose: String, startAtEnd: Bool) async {
        do {
            await speech.waitUntilReady()
            try await Task.sleep(for: .milliseconds(250))
            if startAtEnd {
                try await waitUntilVisible()
                seen = readableLines(try await recognizeLines(in: await capture(currentRect))).map(\.text)
            } else {
                try await readToTheEnd(purpose: purpose)
            }
            note("first pass done; follow is \(followNew ? "on" : "off")")
            while followNew || pendingJump != nil {
                if pendingJump != nil {
                    try await readToTheEnd(purpose: purpose)
                    continue
                }
                do {
                    try await followNewText(purpose: purpose)
                    break
                } catch is JumpRequested {
                    continue
                }
            }
            note("finished")
            endReading(seen.isEmpty ? "I couldn't find text there. Select a larger area and try again." : "Finished reading")
        } catch is CancellationError {
            return
        } catch {
            note("reading stopped: \(error)")
            endReading(CGPreflightScreenCaptureAccess() ? "Narrator stopped unexpectedly. Select the area again to retry." : "Allow Screen Recording for Narrator in System Settings, then reopen it.")
        }
    }

    private func readToTheEnd(purpose: String) async throws {
        var emptyRounds = 0
        var previousScreen: Data?
        for _ in 0..<300 where emptyRounds < 2 {
            try await waitWhilePaused()
            try await waitUntilVisible()
            if pendingJump != nil {
                emptyRounds = 0
                previousScreen = nil
                try await readPendingJump(purpose: purpose)
                if rescan {
                    rescan = false
                    continue
                }
            }
            layoutChanged = false
            let image = try await capture(currentRect)
            let screen = image.dataProvider?.data as Data?
            if screen != nil, screen == previousScreen {
                note("screen unchanged after scrolling")
                break
            }
            previousScreen = screen
            let lines = readableLines(try await recognizeLines(in: image))
            let fresh = unreadLines(in: lines.filter { !$0.touchesBottom }, seen: seen)
            note("captured \(lines.count) lines, \(fresh.count) new")
            // After the first screen, a stray short fragment is recognition noise, not new content.
            if fresh.isEmpty || (!seen.isEmpty && !fresh.contains { normalized($0.text).count >= 16 }) {
                emptyRounds += 1
            } else {
                emptyRounds = 0
                // Marks where reading will resume while the next part is being worked out.
                if !scrolledByUser, let first = fresh.first { highlightView?.segments = [HighlightSegment(rect: first.box, done: 0)] }
                try await narrate(fresh, purpose: purpose)
            }
            try await waitWhilePaused()
            if rescan {
                rescan = false
                previousScreen = nil
                continue
            }
            checkWatchedWindow()
            try Task.checkCancellation()
            try await waitUntilVisible()
            highlightView?.segments = []
            setStatus("Scrolling", "Moving on to the next part of the page.")
            await scrollDown(in: currentRect, gentle: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            note("scrolled")
            try await waitForPageToSettle()
        }
        try await waitUntilVisible()
        let remaining = unreadLines(in: readableLines(try await recognizeLines(in: await capture(currentRect))), seen: seen)
        if remaining.contains(where: { normalized($0.text).count >= 16 }) { try await narrate(remaining, purpose: purpose) }
    }

    /// After a scroll, waits until the page has stopped moving, so the next look at the screen is sharp. Some pages keep
    /// gliding for a moment, and some never stop changing, so it gives up after about a second.
    private func waitForPageToSettle() async throws {
        try await Task.sleep(for: .milliseconds(120))
        var previous = try await capture(currentRect).dataProvider?.data as Data?
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(100))
            let now = try await capture(currentRect).dataProvider?.data as Data?
            if now != nil, now == previous { return }
            previous = now
        }
    }

    /// Watches for new text and speaks finished sentences while the rest of a reply is still arriving.
    private func followNewText(purpose: String) async throws {
        replyWaiting = []
        claimedLines = []
        liveBoxes = [:]
        defer {
            liveBoxes = nil
            dropQueuedReplies()
        }
        showFollowing()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.watchForReplies(purpose: purpose) }
            group.addTask { try await self.speakReplies() }
            // Stops the watcher as soon as the speaker leaves, which waiting for both would not do.
            while try await group.next() != nil {}
        }
    }

    /// Keeps watching during speech and pauses, so text that scrolls past is never missed.
    private func watchForReplies(purpose: String) async throws {
        var lines: [ScreenLine] = []
        var previousScreen: Data?
        var previousText = ""
        var earlierRound = Set<String>()
        var lastChange = Date()
        var lastNews = Date()
        while followNew {
            try await Task.sleep(for: .milliseconds(350))
            try await waitUntilVisible()
            if Date().timeIntervalSince(lastNews) > 1800 {
                endReading("Stopped following after 30 minutes with no new text")
                throw CancellationError()
            }
            if usesClaude, spareHelper?.isStale != false {
                spareHelper?.stop()
                spareHelper = try? WarmClaude(system: Planner.system, schema: Planner.schema)
            }
            let image = try await capture(currentRect)
            let screen = image.dataProvider?.data as Data?
            if screen == nil || screen != previousScreen {
                previousScreen = screen
                guard let recognized = try? await recognizeLines(in: image) else {
                    note("text recognition skipped")
                    continue
                }
                lines = readableLines(recognized)
                liveLines = lines
                liveBoxes = Dictionary(lines.map { (normalized($0.text), $0.box) }, uniquingKeysWith: { _, latest in latest })
                layoutChanged = false
                let text = lines.map { normalized($0.text) }.joined()
                if text != previousText {
                    previousText = text
                    lastChange = Date()
                }
                // The last line may still be growing, and a finished line reads the same twice in a row.
                let fresh = unreadLines(in: lines.filter { !$0.touchesBottom }, seen: seen + claimedLines + replyWaiting.map(\.text))
                replyWaiting += fresh.dropLast(1).prefix { earlierRound.contains(normalized($0.text)) }
                earlierRound = Set(lines.map { normalized($0.text) })
                if !replyWaiting.isEmpty, replyQueue.isEmpty, !isPaused { setStatus("Following", "New text is arriving. Reading starts after the first full sentence.") }
            }
            guard replyQueue.count < 2 else { continue }
            if let end = replyWaiting.lastIndex(where: { endsThought($0.text) }),
               replyWaiting[...end].contains(where: { normalized($0.text).count >= 16 }) {
                queueReply(placed(Array(replyWaiting[...end]), on: lines), purpose: purpose)
                replyWaiting.removeFirst(end + 1)
                lastNews = Date()
                continue
            }
            // The final lines count as finished once the text stops changing, which takes at least a second.
            guard Date().timeIntervalSince(lastChange) >= 1 else { continue }
            let remaining = replyWaiting + unreadLines(in: lines, seen: seen + claimedLines + replyWaiting.map(\.text))
            guard let last = remaining.last, Date().timeIntervalSince(lastChange) >= (endsThought(last.text) ? 1 : 3.5) else { continue }
            replyWaiting = []
            if remaining.contains(where: { normalized($0.text).count >= 16 }) {
                queueReply(placed(remaining, on: lines), purpose: purpose)
                lastNews = Date()
            } else {
                claimedLines += remaining.map(\.text)
            }
        }
    }

    /// Plans the next part straight away, so it is ready when the current part finishes.
    private func queueReply(_ lines: [ScreenLine], purpose: String) {
        let earlier = seen + claimedLines
        claimedLines += lines.map(\.text)
        note("new text found: \(lines.count) lines")
        let setup = Task { [weak self] () throws -> ReadingSetup in
            guard let self else { throw CancellationError() }
            var setup = try await self.prepareReading(lines, purpose: purpose, alreadyRead: earlier)
            for index in setup.items.indices.prefix(2) {
                let item = setup.items[index]
                let voice = setup.voice
                setup.audio[index] = Task { try await self.performedClip(item, narrator: voice) }
            }
            return setup
        }
        replyQueue.append((lines, setup))
    }

    private func speakReplies() async throws {
        while followNew || !replyQueue.isEmpty {
            if pendingJump != nil { throw JumpRequested() }
            guard let next = replyQueue.first else {
                try await Task.sleep(for: .milliseconds(60))
                continue
            }
            if !isPaused { setStatus("Understanding", "Working out what to read.") }
            try await perform(next.lines, setup: try await next.setup.value)
            if rescan {
                // After the reader scrolls away and returns, find the unread text again from the screen.
                rescan = false
                dropQueuedReplies()
                replyWaiting = []
                claimedLines = []
            } else {
                replyQueue.removeFirst()
            }
            if replyQueue.isEmpty { showFollowing() }
        }
    }

    /// Cancels replies planned ahead and deletes any voice clips already made for them.
    private func dropQueuedReplies() {
        for reply in replyQueue {
            reply.setup.cancel()
            Task { if let setup = try? await reply.setup.value { discardClips(setup.audio.values) } }
        }
        replyQueue = []
    }

    private func showFollowing() {
        highlightView?.segments = []
        progressLine?.fraction = 0
        setStatus("Following", "Waiting for new text. Turn Follow off or press stop when you're done.")
    }

    private func narrate(_ lines: [ScreenLine], purpose: String, alreadyRead: [String]? = nil) async throws {
        setStatus("Understanding", "Working out what to read.")
        try await perform(lines, setup: try await prepareReading(lines, purpose: purpose, alreadyRead: alreadyRead ?? seen))
    }

    private func prepareReading(_ lines: [ScreenLine], purpose: String, alreadyRead: [String]) async throws -> ReadingSetup {
        var items = utterances(lines, in: 0..<lines.count)
        var chosenVoice = narratorVoice(for: "other")
        do {
            let began = Date()
            let rightSide = rightSideUnits(items, lines: lines, screen: followNew && !liveLines.isEmpty ? liveLines : lines)
            let plan: ReadingPlan
            if usesClaude {
                let helper = followNew ? spareHelper : nil
                if followNew { spareHelper = try? WarmClaude(system: Planner.system, schema: Planner.schema) }
                let style = readingMood == "Auto" ? "" : " Read it in a \(readingMood.lowercased()) style."
                let tableRows = Dictionary(uniqueKeysWithValues: items.enumerated().compactMap { index, unit in
                    unit.spans.first.flatMap { lines[$0.line].tableRow ? (index, $0.line) : nil }
                })
                plan = try await Planner.plan(units: items, purpose: purpose + style, alreadyRead: alreadyRead, following: followNew, rightSide: followNew ? rightSide : [], tableRows: tableRows, helper: helper)
            } else {
                plan = LocalDirector.plan(units: items, purpose: purpose, mood: readingMood, rightSide: rightSide, following: followNew)
            }
            items = utterances(plan: plan, units: items)
            chosenVoice = narratorVoice(for: plan.material)
            note("moods: " + Dictionary(grouping: items, by: \.delivery.mood).map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", "))
            note(String(format: "reading plan ready in %.1f seconds", Date().timeIntervalSince(began)))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            note("reading plan unavailable: \(error)")
        }
        note("speaking \(items.count) sentences with \(chosenVoice)")
        return ReadingSetup(items: items, voice: chosenVoice)
    }

    private func perform(_ lines: [ScreenLine], setup: ReadingSetup) async throws {
        let items = setup.items
        let chosenVoice = setup.voice
        var audio = setup.audio
        defer { discardClips(audio.values) }
        var index = 0
        while index < items.count {
            try await waitWhilePaused()
            if rescan { return }
            for ahead in index..<min(index + 3, items.count) where audio[ahead] == nil {
                let upcoming = items[ahead]
                audio[ahead] = Task { try await self.performedClip(upcoming, narrator: chosenVoice) }
            }
            let item = items[index]
            setStatus("Reading  \(index + 1) of \(items.count)", item.text)
            readingPlace = (index, items.count)
            progressLine?.fraction = CGFloat(index) / CGFloat(items.count)
            let url = try await audio[index]!.value
            if rescan { return }
            if CommandLine.arguments.contains("--log-spoken") { note("TEST spoke: \(item.text)") }
            try await play(url, item: item, lines: lines)
            if rescan { return }
            if jump != 0 {
                index = max(0, index + jump)
                jump = 0
                continue
            }
            seen += item.spans.map { lines[$0.line].text }
            // No long pause after the last sentence of a screen, since the page scrolls on right away.
            let isLast = index == items.count - 1
            let full = max(item.pauseAfter, item.delivery.settings.pause) / Double(speed)
            let rest = isLast ? min(full, 0.15) : full
            // The highlight starts gliding to the next sentence just before it is spoken, so the eye is already there.
            let lead = isLast ? 0 : min(0.18, rest * 0.6)
            try await Task.sleep(for: .seconds(rest - lead))
            if lead > 0, jump == 0, !isPaused { highlight(items[index + 1], lines: lines, progress: 0) }
            try await Task.sleep(for: .seconds(lead))
            index = max(0, index + (jump == 0 ? 1 : jump))
            jump = 0
        }
        if rescan { return }
        seen += lines.map(\.text)
    }

    private func performedClip(_ item: Utterance, narrator: String) async throws -> URL {
        let direction = item.delivery.settings
        let voiceName = dialogueVoice(for: item.delivery.speaker, narrator: narrator)
        let raw = try await speech.synthesize(item.spokenText, voice: voiceName, speed: direction.speed)
        return try await Task.detached { try clip(raw, shiftedBy: direction.cents) }.value
    }

    /// Writes a directed reading of a text file, so the full performance can be checked by ear.
    private func writeDirectedSample(from input: String, to output: String) async {
        do {
            try speech.start()
            await speech.waitUntilReady()
            let paragraphs = try String(contentsOfFile: input, encoding: .utf8).components(separatedBy: "\n").filter { !$0.isEmpty }
            let lines = paragraphs.map { ScreenLine(text: $0) }
            let units = utterances(lines, in: 0..<lines.count)
            let plan = try await Planner.plan(units: units, purpose: "", alreadyRead: [], following: false)
            let items = utterances(plan: plan, units: units)
            var samples: [Float] = []
            var format: AVAudioFormat?
            for item in items {
                let url = try await performedClip(item, narrator: narratorVoice(for: plan.material))
                let file = try AVAudioFile(forReading: url)
                format = file.processingFormat
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { continue }
                try file.read(into: buffer)
                let gain = pow(10, item.delivery.settings.gain / 20) * 0.88
                samples += UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)).map { $0 * gain }
                samples += [Float](repeating: 0, count: Int(max(item.pauseAfter, item.delivery.settings.pause) * file.processingFormat.sampleRate))
                print("\(item.delivery.mood) | \(item.delivery.speaker) | \(item.delivery.emphasis.joined(separator: " ")) | \(item.text)")
            }
            if let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) {
                buffer.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
                let file = try AVAudioFile(forWriting: URL(fileURLWithPath: output), settings: format.settings)
                try file.write(from: buffer)
            }
        } catch {
            print("sample failed: \(error)")
        }
        speech.stop()
        exit(0)
    }

    private func waitWhilePaused() async throws {
        while isPaused {
            try await Task.sleep(for: .milliseconds(120))
        }
        try Task.checkCancellation()
    }

    private func play(_ url: URL, item: Utterance, lines: [ScreenLine]) async throws {
        let sound = try makePlayer(url, volume: pow(10, item.delivery.settings.gain / 20) * 0.88, reportingTo: finished)
        player = sound
        highlight(item, lines: lines, progress: 0)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak sound] _ in
            MainActor.assumeIsolated {
                guard let self, let sound, sound.duration > 0 else { return }
                let progress = sound.currentTime / sound.duration
                self.highlight(item, lines: lines, progress: progress)
                // The bar creeps along with the voice, instead of stepping once per sentence.
                self.progressLine?.fraction = (CGFloat(self.readingPlace.index) + CGFloat(progress)) / CGFloat(max(self.readingPlace.count, 1))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        await playToEnd(sound, reportingTo: finished, start: !isPaused)
        timer.invalidate()
        player = nil
        try Task.checkCancellation()
    }

    // MARK: Highlight on the selected area

    private func showHighlight(over rect: CGRect) {
        clearHighlight()
        let frame = bottomLeftRect(from: rect)
        let panel = NSPanel(floatingAt: .floating, frame: frame)
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = HighlightView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        panel.orderFrontRegardless()
        highlightPanel = panel
        highlightView = view
    }

    private func clearHighlight() {
        highlightPanel?.orderOut(nil)
        highlightPanel = nil
        highlightView = nil
    }

    private func highlight(_ item: Utterance, lines: [ScreenLine], progress: Double) {
        guard !scrolledByUser, !layoutChanged else {
            highlightView?.segments = []
            return
        }
        let total = max(item.spans.reduce(0) { $0 + max($1.to - $1.from, 0) }, 1)
        var reached = progress * Double(total)
        highlightView?.segments = item.spans.compactMap { span -> HighlightSegment? in
            guard lines.indices.contains(span.line) else { return nil }
            let line = lines[span.line]
            let box = liveBoxes == nil ? line.box : liveBoxes?[normalized(line.text)]
            let count = CGFloat(max(line.text.count, 1))
            let start = min(CGFloat(span.from), count) / count
            let end = min(CGFloat(span.to), count) / count
            let length = Double(max(span.to - span.from, 1))
            let done = min(max(reached / length, 0), 1)
            reached -= length
            guard let box else { return nil }
            let rect = CGRect(x: box.minX + box.width * start, y: box.minY, width: box.width * (end - start), height: box.height)
            return HighlightSegment(rect: rect, done: CGFloat(done))
        }
    }

    // MARK: Control bar near the notch

    private func symbol(_ name: String, label: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
    }

    private func setStatus(_ status: String, _ text: String) {
        pet.react(to: status)
        statusLine?.stringValue = status
        if let caption, caption.stringValue != text {
            caption.stringValue = text
            // The new line fades in, so the words change gently rather than flipping.
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                caption.alphaValue = 0.3
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    caption.animator().alphaValue = 1
                }
            }
        }
        caption?.toolTip = text
    }

    private func showBar(status: String, _ text: String) {
        barHide?.cancel()
        if barPanel == nil { buildBar() }
        setStatus(status, text)
        updateControls()
        progressLine?.fraction = 0
        playButton?.image = symbol(isPaused ? "play.fill" : "pause.fill", label: isPaused ? "Play" : "Pause")
        updateSpeedButton()
        updateFollowButton()
        positionBar()
        barPanel?.orderFrontRegardless()
    }

    private func updateControls() {
        let asking = isAskBusy || resumePending
        controls.forEach { $0.isHidden = narration == nil || asking }
        progressLine?.isHidden = narration == nil || asking
        closeButton?.isHidden = narration == nil && !isAskBusy
        let showSource = !lastSources.isEmpty && (isAnswering || resumePending || narration == nil) && askPanel == nil
        sourceButton?.isHidden = !showSource
        if showSource, let host = lastSources.first?.host {
            sourceButton?.setLabel("Open " + host.replacingOccurrences(of: "www.", with: ""))
            sourceButton?.setAccessibilityLabel("Open source on " + host)
        }
    }

    private func hideBar(after seconds: Double) {
        barHide?.cancel()
        let hide = DispatchWorkItem { [weak self] in self?.barPanel?.orderOut(nil) }
        barHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: hide)
    }

    private func positionBar() {
        guard let panel = barPanel else { return }
        let area = bottomLeftRect(from: currentRect)
        let screen = NSScreen.screens.first { $0.frame.intersects(area) } ?? NSScreen.screens[0]
        let size = panel.frame.size
        let y = screen.frame.maxY - max(screen.safeAreaInsets.top, 24) - size.height - 6
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: y))
    }

    private func showMessage(_ text: String) {
        showBar(status: "Narrator", text)
        hideBar(after: 4)
    }

    private func buildBar() {
        let size = NSSize(width: 770, height: 78)
        let panel = NSPanel(floatingAt: .statusBar, frame: NSRect(origin: .zero, size: size))
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let background = SurfaceView(frame: NSRect(origin: .zero, size: size))
        let status = NSTextField(labelWithString: "")
        status.frame = NSRect(x: 18, y: 53, width: 360, height: 15)
        status.font = .systemFont(ofSize: 11.5, weight: .semibold)
        status.textColor = Palette.accent
        background.addSubview(status)
        let label = NSTextField(wrappingLabelWithString: "")
        label.frame = NSRect(x: 18, y: 14, width: 360, height: 38)
        label.textColor = Palette.text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
        background.addSubview(label)
        let progress = ProgressLine(frame: NSRect(x: 18, y: 7, width: size.width - 36, height: 2))
        background.addSubview(progress)

        func button(_ x: CGFloat, width: CGFloat = 32, height: CGFloat = 32, image: String? = nil, name: String, action: Selector, help: String) -> ControlButton {
            let control = ControlButton(frame: NSRect(x: x, y: 40 - height / 2 + 2, width: width, height: height))
            control.isBordered = false
            control.title = ""
            control.image = image.flatMap { symbol($0, label: name) }
            control.imagePosition = image == nil ? .noImage : .imageOnly
            control.contentTintColor = Palette.text
            control.target = self
            control.action = action
            control.toolTip = help
            control.setAccessibilityLabel(name)
            background.addSubview(control)
            return control
        }
        let back = button(392, image: "backward.fill", name: "Previous sentence", action: #selector(skipBack), help: "Previous sentence (Option + Shift + ,)")
        let play = button(428, width: 38, height: 38, image: "pause.fill", name: "Pause", action: #selector(togglePause), help: "Play or pause (Option + Shift + Space)")
        play.fill = Palette.text
        play.hoverFill = NSColor.white.withAlphaComponent(0.84)
        play.contentTintColor = .black
        let next = button(470, image: "forward.fill", name: "Next sentence", action: #selector(skipForward), help: "Next sentence (Option + Shift + .)")
        let skipTo = button(512, width: 66, name: "Jump to a sentence", action: #selector(jumpPressed), help: "Choose a sentence on screen to read from (Option + Shift + J)")
        skipTo.setLabel("Jump")
        let rate = button(582, width: 46, name: "Reading speed", action: #selector(cycleSpeed), help: "Change reading speed")
        let follow = button(632, width: 86, name: "Follow new text", action: #selector(toggleFollow), help: "Keep reading new text that appears here")
        let close = button(724, image: "xmark", name: "Stop reading", action: #selector(stopReading), help: "Stop reading (Esc)")
        let source = button(392, width: 250, name: "Open source", action: #selector(openSource), help: "Open this source in your browser")
        source.fill = Palette.well
        source.isHidden = true
        controls = [back, play, next, skipTo, rate, follow]
        jumpButton = skipTo
        closeButton = close
        sourceButton = source
        playButton = play
        speedButton = rate
        followButton = follow
        panel.contentView = background
        barPanel = panel
        statusLine = status
        caption = label
        progressLine = progress
    }

    // MARK: Previews for design review

    func writePreviews(to folder: String) {
        func save(_ view: NSView, _ name: String) {
            guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: image)
            try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildBar()
        guard let bar = barPanel?.contentView else { return }
        updateSpeedButton()
        followNew = true
        updateFollowButton()
        setStatus("Reading  3 of 14", "Working capital is current assets minus current liabilities, which shows how easily a company can pay its short term bills.")
        progressLine?.fraction = 3.0 / 14
        save(bar, "bar-reading")
        progressLine?.fraction = 0
        setStatus("Following", "Waiting for new text. Turn Follow off or press stop when you're done.")
        save(bar, "bar-following")
        followNew = false
        updateFollowButton()
        playButton?.image = symbol("play.fill", label: "Play")
        setStatus("Paused", "Paused because you scrolled. Press play to read from here.")
        save(bar, "bar-paused")
        lastSources = [URL(string: "https://www.python.org/downloads/")!]
        isAnswering = true
        updateControls()
        setStatus("Answer", "The latest stable version of Python is 3.15.2, according to the official downloads page.")
        save(bar, "bar-answer")
        lastSources = []
        isAnswering = false
        let box = askBoxContent()
        save(box.view, "ask-box")
        save(purposeContent(purpose: "").view, "purpose")
        for pose in LumenArt.poses {
            let lumen = PetView(frame: NSRect(origin: .zero, size: pet.size))
            lumen.pose = pose
            lumen.glow = pose == "talk" ? 1 : 0.3
            lumen.sleeping = pose == "sleep"
            lumen.dots = pose == "think" ? 2 : 0
            save(lumen, "lumen-\(pose)")
        }
        save(Pet.bubbleContent("Hi, I'm Lumen, the face of Narrator, your AI reading agent. Point me at anything on your screen and I'll read it to you.", buttons: ["Show me", "Later"], target: nil, action: nil), "lumen-bubble")
        let overlay = SelectionView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        overlay.hover = NSRect(x: 260, y: 120, width: 680, height: 430)
        save(overlay, "selector")
    }
}
