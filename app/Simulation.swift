import AppKit

// MARK: - A drawn stand-in for the Claude chat, for evals/run.sh

/// The screen Lumen reads during an eval. It draws a chat the way Claude's looks: the reply on the left, the user's own
/// message in a bubble on the right, a composer bar at the bottom and a side panel that never scrolls. The pixels go
/// through real text recognition, and scrolling only moves the chat when it lands over the chat, so a run needs no window,
/// no cursor and no Screen Recording, and the person at the keyboard never sees it.
final class SimulatedScreen: @unchecked Sendable {
    enum Kind { case user, status, paragraph, heading, bullet }
    struct Block {
        var kind: Kind
        var text: String
    }
    struct Scenario {
        var user: String
        var status: String? = nil
        var reply: [Block]
    }

    static let size = CGSize(width: 1000, height: 800)
    static let scale: CGFloat = 2
    static let scenarios: [String: Scenario] = [
        // A long reply that runs below the screen and ends with a marker.
        "long": Scenario(user: "Can you check my two million estimate against the reported numbers, and tell me what you find?",
                         status: "Checking the estimate against reported numbers now.", reply: [
            Block(kind: .paragraph, text: "The two million estimate was a good one. Reported numbers put it at about two point one million orders a day."),
            Block(kind: .heading, text: "How I got two million"),
            Block(kind: .paragraph, text: "I did not derive it in the document. I used a round number from a rough sense of scale. A strong candidate says it in one line. I have not edited the document."),
            Block(kind: .heading, text: "The check against reported numbers"),
            Block(kind: .bullet, text: "Top down, from the users, the platform had nineteen million monthly users. At about three orders a month, that is about two million orders a day."),
            Block(kind: .bullet, text: "Bottom up, from the order count, the platform reported two hundred million orders in the quarter. That is about two point two million orders a day."),
            Block(kind: .heading, text: "What this means"),
            Block(kind: .paragraph, text: "The estimate holds. The only gap is that the working is not shown. Add one line to the document saying where the number came from."),
            Block(kind: .paragraph, text: "ENDMARKER This is the last sentence of the reply."),
        ]),
        // A long message from the user, which must not be read back to them.
        "usermsg": Scenario(user: "Zanzibar: before you start, please read the whole plan again and tell me whether the goal, the owners and the dates are all written down clearly enough for a stranger to follow it.",
                            reply: [Block(kind: .paragraph, text: "The plan names a goal and an owner for each step. WAYPOINT The dates are the only thing missing.")]),
        // A one-line reply, which is short but still has to be read.
        "short": Scenario(user: "Shall we go ahead?", reply: [Block(kind: .paragraph, text: "Go ahead.")]),
        // Claude's folded "thinking" line, which is interface and not part of the reply.
        "thinking": Scenario(user: "Does the plan name a goal?", status: "Checking whether the plan names a goal \u{203A}",
                             reply: [Block(kind: .paragraph, text: "SIGNPOST Yes, it names a goal in the first line.")]),
    ]

    let owner = "Claude"
    let chatWidth: CGFloat
    private let scenario: Scenario
    private let lock = NSLock()
    private var blocks = [
        Block(kind: .user, text: "What is the plan for the launch?"),
        Block(kind: .paragraph, text: "The launch plan has three steps, and each step has an owner. Nothing else is needed before Friday."),
    ]
    private var offset: CGFloat = 0

    init?(scenario name: String, chatWidth: CGFloat) {
        guard let scenario = Self.scenarios[name] else { return nil }
        self.scenario = scenario
        self.chatWidth = chatWidth
    }

    /// The new message and the reply arrive a while after the start, so the reader is already running, and the reply
    /// streams in word by word below the screen with no auto-scroll, like the Claude chat.
    func start(after delay: Double = 14) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            append(Block(kind: .user, text: scenario.user))
            try? await Task.sleep(for: .seconds(3))
            if let status = scenario.status { append(Block(kind: .status, text: status)) }
            try? await Task.sleep(for: .seconds(2))
            for block in scenario.reply {
                var words = block.text.split(separator: " ").map(String.init)
                var shown = ""
                while !words.isEmpty {
                    shown += (shown.isEmpty ? "" : " ") + words.removeFirst()
                    set(Block(kind: block.kind, text: shown), isNew: shown.split(separator: " ").count == 1)
                    try? await Task.sleep(for: .milliseconds(140))
                }
            }
        }
    }

    private func append(_ block: Block) { lock.withLock { blocks.append(block) } }
    private func set(_ block: Block, isNew: Bool) { lock.withLock { if isNew { blocks.append(block) } else { blocks[blocks.count - 1] = block } } }

    /// A scroll moves the chat only when it lands over the chat, which is what a real scroll does.
    func scroll(at point: CGPoint, by distance: Int) {
        guard point.x >= 0, point.x < chatWidth else { return }
        lock.withLock {
            let overflow = layout(blocks).height + 24 + 150 - Self.size.height
            offset = min(max(0, offset + CGFloat(distance)), max(0, overflow))
        }
    }

    func image(for rect: CGRect) -> CGImage {
        let (blocks, offset) = lock.withLock { (blocks, self.offset) }
        let pixels = CGSize(width: Self.size.width * Self.scale, height: Self.size.height * Self.scale)
        let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: Self.scale, y: Self.scale)
        context.translateBy(x: 0, y: Self.size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw(blocks, offset: offset)
        NSGraphicsContext.restoreGraphicsState()
        let whole = context.makeImage()!
        let crop = CGRect(x: rect.minX * Self.scale, y: rect.minY * Self.scale, width: rect.width * Self.scale, height: rect.height * Self.scale)
        return whole.cropping(to: crop.intersection(CGRect(origin: .zero, size: pixels))) ?? whole
    }

    // MARK: Drawing

    private let page = NSColor(red: 0.98, green: 0.976, blue: 0.96, alpha: 1)

    private func attributes(_ kind: Kind) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 29.5
        style.maximumLineHeight = 29.5
        let size: CGFloat = kind == .heading ? 20 : 19
        let font = NSFont(name: kind == .heading ? "Georgia-Bold" : "Georgia", size: size) ?? .systemFont(ofSize: size)
        return [.font: font, .paragraphStyle: style, .foregroundColor: kind == .status ? NSColor(white: 0.47, alpha: 1) : NSColor(white: 0.13, alpha: 1)]
    }

    private func height(of text: String, kind: Kind, width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(with: CGSize(width: width, height: 100_000), options: .usesLineFragmentOrigin, attributes: attributes(kind)).height)
    }

    private struct Placed {
        var block: Block
        var frame: CGRect  // The text, in chat coordinates before scrolling.
        var bubble: CGRect?
    }

    private func layout(_ blocks: [Block]) -> (items: [Placed], height: CGFloat) {
        let left: CGFloat = 26
        let width = chatWidth - 52
        var y: CGFloat = 24
        var items: [Placed] = []
        for (index, block) in blocks.enumerated() {
            switch block.kind {
            case .user:
                let limit = width * 0.78
                let measured = (block.text as NSString).boundingRect(with: CGSize(width: limit - 32, height: 100_000), options: .usesLineFragmentOrigin, attributes: attributes(.user))
                let bubbleWidth = min(limit, ceil(measured.width) + 32)
                let textHeight = height(of: block.text, kind: .user, width: bubbleWidth - 32)
                let bubble = CGRect(x: left + width - bubbleWidth, y: y, width: bubbleWidth, height: textHeight + 20)
                items.append(Placed(block: block, frame: CGRect(x: bubble.minX + 16, y: y + 10, width: bubbleWidth - 32, height: textHeight), bubble: bubble))
                y += bubble.height + 22
            case .status:
                let h = height(of: block.text, kind: .status, width: width)
                items.append(Placed(block: block, frame: CGRect(x: left, y: y, width: width, height: h)))
                y += h + 16
            case .heading:
                y += 22
                let h = height(of: block.text, kind: .heading, width: width)
                items.append(Placed(block: block, frame: CGRect(x: left, y: y, width: width, height: h)))
                y += h + 8
            case .paragraph:
                let h = height(of: block.text, kind: .paragraph, width: width)
                items.append(Placed(block: block, frame: CGRect(x: left, y: y, width: width, height: h)))
                y += h + 14
            case .bullet:
                let h = height(of: block.text, kind: .bullet, width: width - 38)
                items.append(Placed(block: block, frame: CGRect(x: left + 38, y: y, width: width - 38, height: h)))
                y += h + 8
                if index + 1 == blocks.count || blocks[index + 1].kind != .bullet { y += 6 }
            }
        }
        return (items, y)
    }

    private func draw(_ blocks: [Block], offset: CGFloat) {
        page.setFill()
        NSRect(origin: .zero, size: Self.size).fill()
        for item in layout(blocks).items {
            let shift = CGAffineTransform(translationX: 0, y: -offset)
            if let bubble = item.bubble {
                NSColor(red: 0.925, green: 0.914, blue: 0.882, alpha: 1).setFill()
                NSBezierPath(roundedRect: bubble.applying(shift), xRadius: 14, yRadius: 14).fill()
            }
            if item.block.kind == .bullet {
                ("\u{2022}" as NSString).draw(in: CGRect(x: item.frame.minX - 18, y: item.frame.minY, width: 20, height: 30).applying(shift), withAttributes: attributes(.bullet))
            }
            (item.block.text as NSString).draw(with: item.frame.applying(shift), options: .usesLineFragmentOrigin, attributes: attributes(item.block.kind))
        }
        // The composer sits over the bottom of the chat, as in the real app.
        page.setFill()
        NSRect(x: 0, y: Self.size.height - 96, width: chatWidth, height: 96).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 22, y: Self.size.height - 82, width: chatWidth - 44, height: 60), xRadius: 14, yRadius: 14).fill()
        ("Reply" as NSString).draw(at: NSPoint(x: 38, y: Self.size.height - 66), withAttributes: attributes(.status))
        // A side panel that never scrolls.
        NSColor.white.setFill()
        NSRect(x: chatWidth, y: 0, width: Self.size.width - chatWidth, height: Self.size.height).fill()
        NSColor(white: 0.87, alpha: 1).setFill()
        NSRect(x: chatWidth, y: 0, width: 1, height: Self.size.height).fill()
        ("Document panel. This side is not part of the reply." as NSString)
            .draw(with: CGRect(x: chatWidth + 20, y: 20, width: Self.size.width - chatWidth - 40, height: 120), options: .usesLineFragmentOrigin, attributes: attributes(.paragraph))
    }
}
