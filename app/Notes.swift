import AppKit
import PDFKit

// MARK: - Note for Claude

/// Where a marked part came from: the file a Mac app has open, or the tab a browser shows.
struct NoteSource: Equatable, Codable {
    var title: String
    var app: String
    var filePath: String?
    var link: String?
    var pages: Int?
    var bytes = 0
    var attach = false

    /// Big files start unattached, so one paste can't quietly use up a Claude plan's limit.
    var isLarge: Bool { (pages ?? 0) > 100 || bytes > 30_000_000 }
    var isPDF: Bool { filePath?.lowercased().hasSuffix(".pdf") == true }
    /// A link Claude could open. A `blob:` address is the browser's own temporary copy, so it is never shared.
    var webLink: String? { link.flatMap { $0.hasPrefix("https://") || $0.hasPrefix("http://") ? $0 : nil } }
    /// A document open inside a browser, which Narrator can only see as pictures until it is downloaded.
    var isBrowserPDF: Bool {
        filePath == nil && (title.lowercased().hasSuffix(".pdf") || link?.lowercased().hasSuffix(".pdf") == true || link?.hasPrefix("blob:") == true)
    }
    /// Where the tray says the document is.
    var location: String {
        filePath ?? webLink ?? (link != nil ? "Open inside a web page. Download it to send the whole file." : "No file or link found")
    }

    mutating func useFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        filePath = path
        bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if isPDF { pages = CGPDFDocument(url as CFURL)?.numberOfPages }
        attach = !isLarge
    }

    /// A file opened in a browser counts as the file itself, so a downloaded PDF gets marked up in Chrome or Safari too.
    mutating func useAddress(_ address: String) {
        if let url = URL(string: address), url.isFileURL { useFile(url.path) } else { link = address }
    }

    func sameDocument(as other: NoteSource) -> Bool {
        if let filePath, let otherPath = other.filePath { return filePath == otherPath }
        if let link, let otherLink = other.link { return link == otherLink }
        return title == other.title && app == other.app
    }

    /// How the copied text names this source. `annotated` is the name of the marked-up copy, when there is one.
    func described(annotated: String? = nil) -> String {
        let place = [app, filePath.map { $0 + (attach && annotated == nil ? ", attached" : "") }, webLink].compactMap { $0 }.joined(separator: ", ")
        var text = (title.isEmpty ? "a window (\(place))" : "\"\(title)\" (\(place))") + "."
        if webLink != nil { text += " Claude may not be able to open this link if it needs a login." }
        if let annotated {
            text += " The attached \"\(annotated)\" is this document with my notes added. Its first page lists each note with its page"
                + " and the exact text it is about, and numbered highlights mark the same spots in the pages."
        }
        return text
    }

    /// The line under the Attach switch in the tray.
    var attachDetail: String {
        let size = pages.map { "\($0) page\($0 == 1 ? "" : "s"), about \(($0 * 2000).formatted()) tokens" }
            ?? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return isLarge && !attach ? "Large file, \(size). Turn on to \(isPDF ? "mark it up" : "attach")." : size
    }
}

/// One marked part: a picture at normal size, the text read from it, and the reader's thought.
struct Snip {
    var id = UUID().uuidString
    var image: CGImage
    var text: String
    var note: String
    var source: Int
    var textOnly = false
}

enum NoteBundle {
    static let limit = 10

    static let defaultAsk = "Go through my notes in order and respond to each one."

    /// The short message that goes with the files. Everything in it is also inside the files, because some message
    /// boxes keep only the files when text and files are pasted together.
    static func message(_ snips: [Snip], sources: [NoteSource], ask: String, annotated: [Int: String] = [:], notesFile: String? = nil) -> String {
        let used = sourcesInUse(snips)
        var lines: [String] = []
        if used.count == 1 {
            lines.append("I'm working through \(sources[used[0]].described(annotated: annotated[used[0]]))")
        } else {
            lines.append("I'm working through \(used.count) documents:")
            lines += used.map { "- \(sources[$0].described(annotated: annotated[$0]))" }
        }
        if let notesFile {
            lines.append("The attached \"\(notesFile)\" holds my notes. Its first page says what I want, then each part I marked has its own page"
                + " with the text I marked, a numbered picture of it, and my note.")
        }
        lines += ["", "What I want: \(wish(ask))"]
        return lines.joined(separator: "\n")
    }

    static func wish(_ ask: String) -> String {
        let wish = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        return wish.isEmpty ? defaultAsk : wish
    }

    /// Cuts long text at a whole word.
    static func clipped(_ text: String, to limit: Int) -> String {
        text.count > limit ? text.prefix(limit).split(separator: " ").dropLast().joined(separator: " ") + "…" : text
    }

    /// Shrinks a Retina capture to normal size, which keeps text readable at a quarter of the image tokens.
    static func shrink(_ image: CGImage, by scale: CGFloat) -> CGImage {
        guard scale > 1 else { return image }
        let width = Int((CGFloat(image.width) / scale).rounded()), height = Int((CGFloat(image.height) / scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// The picture with its part number in the top-left corner, so Claude can match it to the text.
    static func numbered(_ image: CGImage, _ number: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.width, pixelsHigh: image.height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let label = NSAttributedString(string: "\(number)", attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .bold), .foregroundColor: NSColor.black])
        let size = label.size()
        let badge = NSRect(x: 6, y: CGFloat(image.height) - size.height - 14, width: max(size.width + 14, size.height + 8), height: size.height + 8)
        Palette.accent.setFill()
        NSBezierPath(roundedRect: badge, xRadius: badge.height / 2, yRadius: badge.height / 2).fill()
        label.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.minY + 4))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func sourcesInUse(_ snips: [Snip]) -> [Int] {
        var used: [Int] = []
        for snip in snips where !used.contains(snip.source) { used.append(snip.source) }
        return used
    }

    static var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    /// Puts the message and the files on the clipboard, so one paste carries all of it. A PDF on this Mac becomes an
    /// annotated copy; every other part goes into one notes PDF. Both are saved in `saveFolder`, and `saved` lists this
    /// set's earlier files, which are replaced rather than added to. Returns the files it saved: annotated copies by
    /// original path, and the notes PDF as "notes".
    static func copy(_ snips: [Snip], sources: [NoteSource], ask: String, savingIn saveFolder: URL = downloads, replacing saved: [String: URL] = [:]) throws -> [String: URL] {
        var placed = Set<Int>(), annotated: [Int: String] = [:], copies: [String: URL] = [:], attached: [URL] = []
        for source in sourcesInUse(snips) where sources[source].attach {
            guard let path = sources[source].filePath, FileManager.default.fileExists(atPath: path) else { continue }
            let parts = snips.indices.filter { snips[$0].source == source }
            if sources[source].isPDF, let copy = annotatedCopy(of: path, title: sources[source].title.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : sources[source].title, notes: parts.map { ($0 + 1, snips[$0].text, snips[$0].note) },
                                                               ask: ask, to: saved[path] ?? freeName(for: path, in: saveFolder)) {
                placed.formUnion(copy.placed.map { $0 - 1 })
                annotated[source] = copy.url.lastPathComponent
                copies[path] = copy.url
                attached.append(copy.url)
            } else {
                attached.append(URL(fileURLWithPath: path))
            }
        }
        var notesFile: String?
        let rest = snips.indices.filter { !placed.contains($0) }
        if !rest.isEmpty {
            let used = sourcesInUse(snips)
            let name = used.count == 1 && !sources[used[0]].title.isEmpty ? sources[used[0]].title : "Notes for Claude"
            let target = saved["notes"] ?? freeName(base: name, in: saveFolder)
            guard notesPDF(rest, of: snips, sources: sources, ask: ask, to: target) else { throw CocoaError(.fileWriteUnknown) }
            copies["notes"] = target
            notesFile = target.lastPathComponent
            attached.insert(target, at: 0)
        }
        let text = NSPasteboardItem()
        text.setString(message(snips, sources: sources, ask: ask, annotated: annotated, notesFile: notesFile), forType: .string)
        let items = [text] + attached.map { file in
            let item = NSPasteboardItem()
            item.setString(file.absoluteString, forType: .fileURL)
            return item
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items)
        return copies
    }

    /// One PDF with every part: a first page saying what the reader wants and where the parts are from, then a page per
    /// part with the text read from it, a numbered picture, and the note. It is real page text, so Claude reads it all.
    static func notesPDF(_ parts: [Int], of snips: [Snip], sources: [NoteSource], ask: String, to target: URL) -> Bool {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(target as CFURL, mediaBox: &box, nil) else { return false }
        let margin: CGFloat = 54, width = box.width - margin * 2
        func text(_ string: String, _ font: NSFont, color: NSColor = .black) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        }
        /// Draws a block of text below `top` and returns where the next block starts.
        func draw(_ string: NSAttributedString, below top: CGFloat, gap: CGFloat = 10) -> CGFloat {
            let setter = CTFramesetterCreateWithAttributedString(string)
            let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: top - margin), nil)
            let area = CGRect(x: margin, y: top - ceil(size.height), width: width, height: ceil(size.height))
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: area, transform: nil), nil), context)
            return area.minY - gap
        }
        let used = sourcesInUse(parts.map { snips[$0] })
        func letter(_ source: Int) -> String { String(UnicodeScalar(65 + (used.firstIndex(of: source) ?? 0))!) }
        let count = parts.count == 1 ? "1 part" : "\(parts.count) parts"

        context.beginPDFPage(nil)
        var top = box.height - margin
        top = draw(text("Notes for Claude", .boldSystemFont(ofSize: 22)), below: top, gap: 14)
        let from = used.count == 1 ? sources[used[0]].described() : "\(used.count) documents, listed below."
        top = draw(text("I marked \(count) of \(from) Each part has its own page after this one: the text I marked, a numbered picture of it, and my note.", .systemFont(ofSize: 12)), below: top, gap: 14)
        top = draw(text("What I want: \(wish(ask))", .boldSystemFont(ofSize: 13)), below: top, gap: 14)
        if used.count > 1 {
            for source in used { top = draw(text("Document \(letter(source)): \(sources[source].described())", .systemFont(ofSize: 11)), below: top, gap: 6) }
        }
        context.endPDFPage()

        for index in parts {
            let snip = snips[index], number = index + 1
            context.beginPDFPage(nil)
            top = box.height - margin
            let heading = "Part \(number)" + (used.count > 1 ? " · from document \(letter(snip.source))" : "") + (snip.textOnly ? " · text only" : "")
            top = draw(text(heading, .boldSystemFont(ofSize: 16)), below: top, gap: 8)
            let note = snip.note.trimmingCharacters(in: .whitespacesAndNewlines)
            top = draw(text(note.isEmpty ? "No note: I marked this part." : "My note: \(note)", .boldSystemFont(ofSize: 12.5)), below: top, gap: 10)
            let marked = snip.text.split(separator: "\n").joined(separator: " ").trimmingCharacters(in: .whitespaces)
            top = draw(text(marked.isEmpty ? "(No text found in this part. See the picture.)" : "Text I marked: \"\(clipped(marked, to: 1200))\"", .systemFont(ofSize: 10.5), color: .darkGray), below: top, gap: 14)
            if !snip.textOnly, top > margin + 40, let picture = numbered(snip.image, number).cgImage {
                let scale = min(width / CGFloat(picture.width), (top - margin) / CGFloat(picture.height), 1)
                let size = CGSize(width: CGFloat(picture.width) * scale, height: CGFloat(picture.height) * scale)
                context.draw(picture, in: CGRect(x: margin, y: top - size.height, width: size.width, height: size.height))
            }
            context.endPDFPage()
        }
        context.closePDF()
        return true
    }

    static func freeName(for path: String, in folder: URL) -> URL {
        freeName(base: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, in: folder)
    }

    /// "Report – notes.pdf", or "Report – notes 2.pdf" when that name is taken, so nothing the reader has is overwritten.
    static func freeName(base name: String, in folder: URL) -> URL {
        let safe = String(name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").prefix(80)).trimmingCharacters(in: .whitespaces)
        let base = (safe.lowercased().hasSuffix(".pdf") ? String(safe.dropLast(4)) : safe) + " – notes"
        var candidate = folder.appendingPathComponent(base + ".pdf")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(number).pdf")
            number += 1
        }
        return candidate
    }

    // MARK: Annotated PDF

    /// Finds a marked part in the PDF by searching for the lines read from the screen. The page where the most lines
    /// match wins, and each matching line is returned once so its words can be highlighted.
    static func locate(_ text: String, in document: PDFDocument) -> (page: PDFPage, lines: [PDFSelection])? {
        let wanted = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 12 }
        var hits: [Int: [PDFSelection]] = [:]
        for line in wanted.prefix(8) {
            var pagesSeen = Set<Int>()
            for match in document.findString(line, withOptions: [.caseInsensitive]) {
                guard let page = match.pages.first else { continue }
                let index = document.index(for: page)
                if pagesSeen.insert(index).inserted { hits[index, default: []].append(match) }
            }
        }
        guard let best = hits.max(by: { $0.value.count < $1.value.count || ($0.value.count == $1.value.count && $0.key > $1.key) }),
              let page = document.page(at: best.key) else { return nil }
        return (page, best.value)
    }

    /// Saves a copy of the PDF with each note highlighted where it belongs, numbered, and listed on a first page.
    /// Returns nil when no note could be placed or the file can't be read, so the caller attaches the original instead.
    static func annotatedCopy(of path: String, title: String, notes: [(number: Int, text: String, note: String)], ask: String, to target: URL) -> (url: URL, placed: [Int])? {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)), !document.isLocked, let first = document.page(at: 0) else { return nil }
        var placed: [(number: Int, page: Int, text: String, note: String)] = []
        for item in notes {
            guard let spot = locate(item.text, in: document) else { continue }
            var area = CGRect.null
            for line in spot.lines.flatMap({ $0.selectionsByLine() }) {
                let bounds = line.bounds(for: spot.page)
                area = area.union(bounds)
                let mark = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                mark.color = Palette.accent.withAlphaComponent(0.45)
                mark.contents = "Note \(item.number)" + (item.note.isEmpty ? "" : ": \(item.note)")
                spot.page.addAnnotation(mark)
            }
            let badge = PDFAnnotation(bounds: CGRect(x: max(area.minX - 24, 2), y: area.maxY - 16, width: 20, height: 16), forType: .freeText, withProperties: nil)
            badge.contents = "\(item.number)"
            badge.font = .boldSystemFont(ofSize: 11)
            badge.fontColor = .black
            badge.color = Palette.accent
            badge.alignment = .center
            badge.border = PDFBorder()
            badge.border?.lineWidth = 0
            spot.page.addAnnotation(badge)
            if !item.note.isEmpty {
                // A comment beside the spot, which opens with a click in Preview.
                let pageBox = spot.page.bounds(for: .mediaBox)
                let comment = PDFAnnotation(bounds: CGRect(x: min(area.maxX + 4, pageBox.maxX - 22), y: area.maxY - 18, width: 18, height: 18), forType: .text, withProperties: nil)
                comment.contents = item.note
                comment.color = Palette.accent
                spot.page.addAnnotation(comment)
            }
            placed.append((item.number, document.index(for: spot.page) + 1, item.text, item.note))
        }
        guard !placed.isEmpty else { return nil }
        let cover = coverPages(title: title, ask: ask, notes: placed, size: first.bounds(for: .mediaBox).size)
        for index in 0..<(cover?.pageCount ?? 0) {
            if let page = cover?.page(at: index)?.copy() as? PDFPage { document.insert(page, at: index) }
        }
        guard document.write(to: target) else { return nil }
        return (target, placed.map(\.number))
    }

    /// The "Notes for Claude" page: real page text, so Claude reads every note even if it skips the comments in the pages.
    static func coverPages(title: String, ask: String, notes: [(number: Int, page: Int, text: String, note: String)], size: CGSize) -> PDFDocument? {
        let body = NSMutableAttributedString()
        func add(_ text: String, _ font: NSFont, after: CGFloat = 6) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = after
            body.append(NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: style]))
        }
        add("Notes for Claude", .boldSystemFont(ofSize: 20), after: 10)
        add("These are my notes on \"\(title)\". Each note is numbered, and the same number marks its highlighted spot in the pages after this one."
            + " Page numbers are the document's own, not counting this notes page.", .systemFont(ofSize: 11), after: 10)
        add("What I want: \(wish(ask))", .boldSystemFont(ofSize: 11), after: 16)
        for note in notes {
            add("\(note.number). Page \(note.page)", .boldSystemFont(ofSize: 12), after: 3)
            let quote = note.text.split(separator: "\n").joined(separator: " ")
            add("\"\(clipped(quote, to: 300))\"", .systemFont(ofSize: 10.5), after: 3)
            add(note.note.isEmpty ? "No note: I highlighted this part." : "My note: \(note.note)", .systemFont(ofSize: 11), after: 14)
        }
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        var start = 0
        while start < body.length {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), CGPath(rect: box.insetBy(dx: 54, dy: 54), transform: nil), nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let shown = CTFrameGetVisibleStringRange(frame).length
            guard shown > 0 else { break }
            start += shown
        }
        context.closePDF()
        return PDFDocument(data: data as Data)
    }
}

// MARK: Finding the source

/// The file a window has open, which most Mac document apps report to Accessibility.
func documentPath(pid: pid_t, title: String) -> String? {
    func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
    let windows = value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
    for window in windows where windows.count == 1 || value(window, kAXTitleAttribute) as? String == title {
        if let document = value(window, kAXDocumentAttribute) as? String, let url = URL(string: document), url.isFileURL { return url.path }
    }
    return nil
}

/// What each browser calls the address of the tab in front.
let browserTabAddress = [
    "com.google.Chrome": "URL of active tab of front window",
    "com.microsoft.edgemac": "URL of active tab of front window",
    "com.brave.Browser": "URL of active tab of front window",
    "company.thebrowser.Browser": "URL of active tab of front window",
    "com.apple.Safari": "URL of front document",
]

/// Asks a browser for the address of its front tab: a web link, or a file on this Mac opened in the browser.
/// macOS asks the reader once per browser before allowing it.
func browserLink(bundleID: String) async -> String? {
    guard let address = browserTabAddress[bundleID] else { return nil }
    return await Task.detached {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(bundleID)\" to return \(address)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // Long enough to answer the permission prompt, short enough not to hang if the browser is stuck.
        let giveUp = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: giveUp)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        giveUp.cancel()
        let link = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return ["https://", "http://", "file://"].contains { link.hasPrefix($0) } ? link : nil
    }.value
}

func noteSource(for window: WatchedWindow?) async -> NoteSource {
    guard let window else { return NoteSource(title: "", app: "an app") }
    var source = NoteSource(title: window.title, app: window.owner)
    if let path = documentPath(pid: window.pid, title: window.title) {
        source.useFile(path)
    } else if let bundleID = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier {
        if let address = await browserLink(bundleID: bundleID) { source.useAddress(address) }
    }
    return source
}

// MARK: The tray

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The floating list of marked parts, with the switches and the Copy button.
@MainActor
final class NoteTray: NSObject {
    private(set) var snips: [Snip] = []
    private(set) var sources: [NoteSource] = []
    private(set) var copied = false
    /// The annotated copies saved for this set, so copying again replaces them.
    private var saved: [String: URL] = [:]
    /// Where annotated copies go. Tests point it somewhere else.
    var saveFolder = NoteBundle.downloads
    private var ask = ""
    private var panel: OverlayPanel?
    private var drag = DragMemory()
    private var askField: PurposeField?
    private var screen: NSScreen?
    var onSnipAnother: (() -> Void)?
    var onCopied: ((Int, [String]) -> Void)?
    /// This set's place in History, made when its first part is added.
    private(set) var setID: String?
    private var created = Date()
    /// Off for the interface previews, which must not write to History.
    var keepsHistory = true

    var isFull: Bool { snips.count >= NoteBundle.limit }
    var view: NSView? { panel?.contentView }

    func add(_ snip: Snip, from source: NoteSource, on screen: NSScreen) {
        if snips.isEmpty { created = Date() }
        // A new part means the copy on the clipboard is out of date.
        copied = false
        var snip = snip
        if let known = sources.firstIndex(where: { $0.sameDocument(as: source) }) {
            snip.source = known
        } else {
            sources.append(source)
            snip.source = sources.count - 1
        }
        snips.append(snip)
        self.screen = screen
        rebuild()
    }

    /// Loads a set saved in History back into the tray.
    func restore(_ set: SavedSet, snips: [Snip], on screen: NSScreen) {
        clear()
        self.snips = snips
        sources = set.sources
        ask = set.ask
        saved = set.saved
        copied = set.copied
        setID = set.id
        created = set.created
        self.screen = screen
        rebuild()
    }

    /// Remembers which set is open in the tray, so it comes back after a quit or crash. A closed set stays in History only.
    static let openSetKey = "openNoteSet"

    /// Deletes this set from History too, for Delete or when its last part is removed.
    func forget() {
        if let setID { NoteHistory.delete(setID) }
        clear()
    }

    /// Closes the tray. The set stays in History.
    func clear() {
        if keepsHistory { UserDefaults.standard.removeObject(forKey: Self.openSetKey) }
        setID = nil
        snips = []
        sources = []
        ask = ""
        copied = false
        saved = [:]
        panel?.orderOut(nil)
        panel = nil
        askField = nil
    }

    private func rebuild() {
        ask = askField?.stringValue ?? ask
        guard !snips.isEmpty else { return forget() }
        persist()
        let width: CGFloat = 360
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        var y: CGFloat = 14

        func label(_ text: String, _ frame: NSRect, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = Palette.text, lines: Int = 1) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.frame = frame
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = color
            field.maximumNumberOfLines = lines
            field.lineBreakMode = lines == 1 ? .byTruncatingMiddle : .byWordWrapping
            field.cell?.truncatesLastVisibleLine = true
            content.addSubview(field)
            return field
        }
        func chip(_ title: String, x: CGFloat, y: CGFloat, tag: Int, action: Selector, on: Bool = false, primary: Bool = false, enabled: Bool = true) -> CGFloat {
            let chipWidth = ControlButton.labelWidth(title) + 24
            let button = ControlButton(frame: NSRect(x: x, y: y, width: chipWidth, height: 26))
            button.isBordered = false
            button.fill = primary ? Palette.accent : Palette.well
            button.hoverFill = primary ? Palette.accent.withAlphaComponent(0.82) : NSColor.white.withAlphaComponent(0.16)
            button.setLabel(title, color: primary ? .black : (enabled ? Palette.text : Palette.secondaryText))
            button.isOn = on
            button.isEnabled = enabled
            button.tag = tag
            button.target = self
            button.action = action
            button.setAccessibilityLabel(title)
            content.addSubview(button)
            return x + chipWidth + 6
        }

        _ = label("Notes for Claude", NSRect(x: 16, y: y, width: 200, height: 17), size: 13, weight: .semibold, color: Palette.accent)
        label("\(snips.count) of \(NoteBundle.limit)", NSRect(x: width - 120, y: y + 1, width: 70, height: 16), size: 11.5, color: Palette.secondaryText).alignment = .right
        let close = ControlButton(frame: NSRect(x: width - 42, y: y - 4, width: 26, height: 26))
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        close.contentTintColor = Palette.text
        close.target = self
        close.action = #selector(closeTray)
        close.toolTip = "Close. Your notes stay in History."
        close.setAccessibilityLabel("Close the tray. Your notes stay in History.")
        content.addSubview(close)
        y += 28
        let files = saved.values.map(\.lastPathComponent).sorted()
        let status = !copied ? "Saved in History as you go. Close with × when you're done."
            : files.isEmpty ? "Copied. Paste into any Claude chat or project." : "Copied, and saved \(files.joined(separator: ", ")) in Downloads. Paste into any Claude chat."
        _ = label(status, NSRect(x: 16, y: y, width: width - 32, height: 30), size: 11.5, color: Palette.secondaryText, lines: 2)
        y += 38

        for (index, snip) in snips.enumerated() {
            let picture = NSImageView(frame: NSRect(x: 16, y: y, width: 92, height: 58))
            picture.image = NSImage(cgImage: snip.image, size: .zero)
            picture.imageScaling = .scaleProportionallyUpOrDown
            picture.alphaValue = snip.textOnly ? 0.35 : 1
            picture.wantsLayer = true
            picture.layer?.cornerRadius = 6
            picture.layer?.backgroundColor = Palette.well.cgColor
            content.addSubview(picture)
            // The same number Claude sees on the copied picture, drawn at a size readable in the tray.
            let number = label("\(index + 1)", NSRect(x: 20, y: y + 4, width: 20, height: 18), size: 11, weight: .bold, color: .black)
            number.alignment = .center
            number.drawsBackground = true
            number.backgroundColor = Palette.accent
            number.wantsLayer = true
            number.layer?.cornerRadius = 9
            let note = snip.note.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = label(note.isEmpty ? "No note" : note, NSRect(x: 118, y: y, width: width - 134, height: 30), color: note.isEmpty ? Palette.secondaryText : Palette.text, lines: 2)
            let hasText = !snip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let next = chip((snip.textOnly ? "☑" : "☐") + " Text only", x: 118, y: y + 32, tag: index, action: #selector(toggleTextOnly(_:)), on: snip.textOnly, enabled: hasText)
            _ = chip("Remove", x: next, y: y + 32, tag: index, action: #selector(removeSnip(_:)))
            y += 70
        }

        var used: [Int] = []
        for snip in snips where !used.contains(snip.source) { used.append(snip.source) }
        for index in used {
            let source = sources[index]
            y += 4
            _ = label(source.title.isEmpty ? source.app : "\(source.app) · \(source.title)", NSRect(x: 16, y: y, width: width - 32, height: 16), weight: .semibold)
            _ = label(source.location, NSRect(x: 16, y: y + 17, width: width - 32, height: 15), size: 11, color: Palette.secondaryText)
            y += 38
            if source.filePath != nil {
                // Shown as a tick box, since it switches something on or off rather than doing it now.
                _ = chip((source.attach ? "☑ " : "☐ ") + (source.isPDF ? "Send marked-up copy" : "Send whole file"), x: 16, y: y, tag: index, action: #selector(toggleAttach(_:)), on: source.attach)
                _ = label(source.attachDetail, NSRect(x: 18, y: y + 31, width: width - 34, height: 16), size: 11, color: Palette.secondaryText)
                y += 54
            } else if source.webLink != nil {
                _ = chip("Remove link", x: 16, y: y, tag: index, action: #selector(removeLink(_:)))
                y += 34
            }
        }

        y += 4
        let well = SurfaceView(frame: NSRect(x: 14, y: y, width: width - 28, height: 36))
        well.radius = 10
        well.fill = Palette.well
        content.addSubview(well)
        let field = PurposeField(frame: NSRect(x: 26, y: y + 9, width: width - 52, height: 20))
        field.placeholderAttributedString = NSAttributedString(string: "What should Claude do? (optional)", attributes: [.foregroundColor: Palette.secondaryText, .font: NSFont.systemFont(ofSize: 13)])
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = Palette.text
        field.stringValue = ask
        field.setAccessibilityLabel("What should Claude do?")
        content.addSubview(field)
        askField = field
        y += 46
        if copied {
            var x = chip("Done", x: 16, y: y, tag: 0, action: #selector(closeTray), primary: true)
            x = chip("Copy again", x: x, y: y, tag: 0, action: #selector(copyAll))
            _ = chip("Snip another", x: x, y: y, tag: 0, action: #selector(snipAnother), enabled: !isFull)
        } else {
            var x = chip("Copy all", x: 16, y: y, tag: 0, action: #selector(copyAll), primary: true)
            x = chip("Snip another", x: x, y: y, tag: 0, action: #selector(snipAnother), enabled: !isFull)
            _ = chip("Delete", x: x, y: y, tag: 0, action: #selector(discard))
        }
        y += 40

        let screen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let height = min(y, screen.visibleFrame.height - 24)
        content.frame.size.height = y
        let background = SurfaceView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let scroll = NSScrollView(frame: background.bounds)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = y > height
        scroll.documentView = content
        background.addSubview(scroll)
        let frame = NSRect(x: screen.visibleFrame.maxX - width - 16, y: screen.visibleFrame.midY - height / 2, width: width, height: height)
        // Once the reader drags the tray, it stays there as parts are added, instead of jumping back to the side.
        let opening = panel == nil
        if opening {
            let panel = OverlayPanel(floatingAt: .floating, frame: frame)
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        if let panel {
            if !opening { drag.noteDrag(of: panel) }
            panel.setFrame(NSRect(origin: panel.frame.origin, size: frame.size), display: false)
            panel.contentView = background
            drag.place(panel, home: frame.origin, on: screen.frame, opening: true)
            panel.orderFrontRegardless()
        }
    }

    /// Saves the set to History after every change, so quitting, a crash or a restart loses nothing.
    private func persist() {
        guard keepsHistory else { return }
        let id = setID ?? NoteHistory.newID()
        setID = id
        UserDefaults.standard.set(id, forKey: Self.openSetKey)
        let parts = snips.map { SavedPart(id: $0.id, text: $0.text, note: $0.note, source: $0.source, textOnly: $0.textOnly) }
        NoteHistory.save(SavedSet(id: id, created: created, updated: Date(), sources: sources, parts: parts, ask: ask, copied: copied, saved: saved), snips: snips)
    }

    @objc private func toggleTextOnly(_ sender: NSButton) {
        snips[sender.tag].textOnly.toggle()
        rebuild()
    }

    @objc private func removeSnip(_ sender: NSButton) {
        snips.remove(at: sender.tag)
        rebuild()
    }

    @objc private func toggleAttach(_ sender: NSButton) {
        sources[sender.tag].attach.toggle()
        rebuild()
    }

    @objc private func removeLink(_ sender: NSButton) {
        sources[sender.tag].link = nil
        rebuild()
    }

    @objc private func snipAnother() { onSnipAnother?() }

    @objc func copyAll() {
        ask = askField?.stringValue ?? ask
        do {
            saved = try NoteBundle.copy(snips, sources: sources, ask: ask, savingIn: saveFolder, replacing: saved)
        } catch {
            note("notes: copy failed: \(error)")
            return
        }
        copied = true
        note("notes: copied \(snips.count) parts")
        onCopied?(snips.count, saved.values.map(\.lastPathComponent).sorted())
        rebuild()
    }

    /// Closes the tray and keeps the set in History.
    @objc private func closeTray() {
        ask = askField?.stringValue ?? ask
        persist()
        clear()
    }

    @objc private func discard() {
        let alert = NSAlert()
        alert.messageText = "Delete these notes?"
        alert.informativeText = "Your \(snips.count) marked part\(snips.count == 1 ? "" : "s") and notes will be deleted, and removed from History too. To keep them, close the tray with × instead."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Keep")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        forget()
    }
}
