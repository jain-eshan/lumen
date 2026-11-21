import AppKit

// MARK: - History

struct SavedPart: Codable {
    var id: String
    var text: String
    var note: String
    var source: Int
    var textOnly: Bool
}

/// One Note for Claude set as kept on disk: its sources, parts, request, and the marked-up copies it saved.
struct SavedSet: Codable {
    var id: String
    var created: Date
    var updated: Date
    var sources: [NoteSource]
    var parts: [SavedPart]
    var ask: String
    var copied: Bool
    var saved: [String: URL]

    /// What the History window calls the set: the document's name, or how many documents it covers.
    var name: String {
        let used = Set(parts.map(\.source)).sorted().map { sources[$0] }
        guard used.count == 1, let source = used.first else { return "\(used.count) documents" }
        return source.title.isEmpty ? (source.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? source.app) : source.title
    }
}

/// A line in the reading log. Only where the reading happened, never what was read.
struct ReadingEntry: Codable {
    var date: Date
    var app: String
    var title: String
}

enum NoteHistory {
    static let keepDays = 30
    /// Tests point this somewhere else.
    static var folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Narrator/History", isDirectory: true)
    static var notesFolder: URL { folder.appendingPathComponent("Notes", isDirectory: true) }
    static var readingFile: URL { folder.appendingPathComponent("reading.json") }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Sortable by time, so the folder lists sets in the order they were started.
    static func newID() -> String {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])
        return stamp.replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(4)
    }

    /// Writes the set and any new pictures, and removes pictures of parts that were taken out.
    static func save(_ set: SavedSet, snips: [Snip]) {
        let folder = notesFolder.appendingPathComponent(set.id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for snip in snips {
                let picture = folder.appendingPathComponent(snip.id + ".png")
                guard !FileManager.default.fileExists(atPath: picture.path) else { continue }
                try NSBitmapImageRep(cgImage: snip.image).representation(using: .png, properties: [:])?.write(to: picture)
            }
            let kept = Set(snips.map { $0.id + ".png" })
            for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where file.hasSuffix(".png") && !kept.contains(file) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
            }
            try encoder.encode(set).write(to: folder.appendingPathComponent("set.json"), options: .atomic)
            note("history: saved set \(set.id) with \(set.parts.count) parts\(set.copied ? ", copied" : "")")
        } catch {
            note("history: could not save set: \(error)")
        }
    }

    static func load(_ id: String) -> (set: SavedSet, snips: [Snip])? {
        let folder = notesFolder.appendingPathComponent(id, isDirectory: true)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("set.json")), let set = try? decoder.decode(SavedSet.self, from: data) else { return nil }
        let snips = set.parts.compactMap { part -> Snip? in
            guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(part.id + ".png") as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return Snip(id: part.id, image: image, text: part.text, note: part.note, source: part.source, textOnly: part.textOnly)
        }
        return (set, snips)
    }

    /// Every saved set, newest first.
    static func sets() -> [SavedSet] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: notesFolder.path)) ?? []
        return ids.compactMap { id in
            (try? Data(contentsOf: notesFolder.appendingPathComponent(id).appendingPathComponent("set.json"))).flatMap { try? decoder.decode(SavedSet.self, from: $0) }
        }.sorted { $0.updated > $1.updated }
    }

    static func delete(_ id: String) {
        try? FileManager.default.removeItem(at: notesFolder.appendingPathComponent(id, isDirectory: true))
        note("history: deleted set \(id)")
    }

    static func reading() -> [ReadingEntry] {
        (try? Data(contentsOf: readingFile)).flatMap { try? decoder.decode([ReadingEntry].self, from: $0) } ?? []
    }

    static func logReading(app: String, title: String, at date: Date = Date()) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode([ReadingEntry(date: date, app: app, title: title)] + reading()).write(to: readingFile, options: .atomic)
        } catch {
            note("history: could not log reading: \(error)")
        }
    }

    /// Removes sets and reading entries older than 30 days. A set counts from its last change or copy.
    static func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        for set in sets() where set.updated < cutoff { delete(set.id) }
        let entries = reading()
        let kept = entries.filter { $0.date >= cutoff }
        if kept.count != entries.count { try? encoder.encode(kept).write(to: readingFile, options: .atomic) }
    }
}

// MARK: The History window

@MainActor
final class HistoryWindow: NSObject {
    private var window: NSWindow?
    var onCopyAgain: ((String) -> Void)?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Lumen History"
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Palette.surface
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 420, height: 300)
            window.center()
            self.window = window
        }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Redraws the lists, for example after a set was copied again.
    func refresh() {
        guard let window else { return }
        let width = window.contentLayoutRect.width
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        content.autoresizingMask = [.width]
        var y: CGFloat = 18

        func label(_ text: String, y: CGFloat, x: CGFloat = 20, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = Palette.text, right: CGFloat = 20) {
            let field = NSTextField(labelWithString: text)
            field.frame = NSRect(x: x, y: y, width: width - x - right, height: size + 6)
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = color
            field.lineBreakMode = .byTruncatingTail
            field.autoresizingMask = [.width]
            content.addSubview(field)
        }
        func when(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) }

        label("Notes for Claude", y: y, size: 14, weight: .semibold, color: Palette.accent)
        y += 30
        let sets = NoteHistory.sets()
        if sets.isEmpty {
            label("No notes yet. Click Lumen and choose Note for Claude.", y: y, color: Palette.secondaryText)
            y += 28
        }
        for (index, set) in sets.enumerated() {
            let count = set.parts.count == 1 ? "1 note" : "\(set.parts.count) notes"
            label(set.name, y: y, weight: .semibold, right: 150)
            label("\(when(set.updated)) · \(count)\(set.copied ? "" : " · not copied yet")", y: y + 19, size: 11.5, color: Palette.secondaryText, right: 150)
            let title = set.copied ? "Copy again" : "Copy"
            let button = ControlButton(frame: NSRect(x: width - 20 - ControlButton.labelWidth(title) - 26, y: y + 6, width: ControlButton.labelWidth(title) + 26, height: 28))
            button.isBordered = false
            button.fill = Palette.well
            button.setLabel(title)
            button.tag = index
            button.target = self
            button.action = #selector(copyAgain(_:))
            button.identifier = NSUserInterfaceItemIdentifier(set.id)
            button.setAccessibilityLabel("\(title): \(set.name)")
            button.autoresizingMask = [.minXMargin]
            content.addSubview(button)
            y += 48
        }

        y += 14
        label("Read aloud", y: y, size: 14, weight: .semibold, color: Palette.accent)
        y += 30
        let reading = NoteHistory.reading()
        if reading.isEmpty {
            label("Nothing read yet.", y: y, color: Palette.secondaryText)
            y += 28
        }
        for entry in reading {
            label(entry.title.isEmpty ? entry.app : entry.title, y: y)
            label("\(when(entry.date)) · \(entry.app)", y: y + 18, size: 11.5, color: Palette.secondaryText)
            y += 42
        }
        y += 8
        let footer = NSTextField(wrappingLabelWithString: "History is kept on this Mac for \(NoteHistory.keepDays) days. Reading is listed by app and window title only, never the text.")
        footer.frame = NSRect(x: 20, y: y, width: width - 40, height: 32)
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = Palette.secondaryText
        footer.autoresizingMask = [.width]
        content.addSubview(footer)
        y += 44

        content.frame.size.height = y
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = content
        window.contentView = scroll
    }

    @objc private func copyAgain(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onCopyAgain?(id)
    }
}
