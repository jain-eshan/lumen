import AppKit
import PDFKit

// MARK: - Self-test

func renderedTextImage(_ lines: [String]) -> CGImage {
    let size = NSSize(width: 1400, height: 90 * lines.count + 80)
    let image = NSImage(size: size, flipped: true) { rect in
        NSColor.white.setFill()
        rect.fill()
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 40, y: 40 + 90 * index), withAttributes: [.font: NSFont.systemFont(ofSize: 40)])
        }
        return true
    }
    var box = NSRect(origin: .zero, size: size)
    return image.cgImage(forProposedRect: &box, context: nil, hints: nil)!
}

func runSelfTest() -> Int32 {
    var failures = 0
    func check(_ name: String, _ passed: Bool) {
        print((passed ? "PASS " : "FAIL ") + name)
        if !passed { failures += 1 }
    }
    func line(_ text: String) -> ScreenLine { ScreenLine(text: text) }
    func placed(_ text: String, top: CGFloat) -> ScreenLine {
        ScreenLine(text: text, box: CGRect(x: 0.1, y: top - 0.04, width: 0.8, height: 0.04))
    }

    let shown = ["Revenue grew to 148 million dollars.", "Operating margin fell to 9 percent."]
    let recognized = (try? recognizeLinesNow(in: renderedTextImage(shown)))?.map(\.text) ?? []
    check("reads text from an image", recognized == shown)

    let after = [line("Operating margin fell to 9 percent."), line("The board meets on Thursday morning.")]
    check("continues after a scroll without repeating", unreadLines(in: after, seen: shown) == [after[1]])
    check("stops when nothing new appears", unreadLines(in: [line(shown[1])], seen: shown).isEmpty)
    let repeated = [line("Copy"), line("A new reply starts on this line today.")]
    check("short repeated buttons do not hide new text", unreadLines(in: repeated, seen: ["Copy"]) == [repeated[1]])

    let settled = [line("Operating margin fell to 9 percent."), line("Copy")]
    check("finishes when only seen buttons remain below the last line", unreadLines(in: settled, seen: shown + ["Copy"]).isEmpty)
    check("does not repeat a line misread while scrolling", unreadLines(in: [line("Inventory ties up cash until the goods are sold.")], seen: ["Inventory ties up cash untii the goods are sold."]).isEmpty)
    check("keeps a similar line with a different number", unreadLines(in: [line("Operating margin rose to 12 percent in 2024.")], seen: ["Operating margin rose to 12 percent in 2023."]).count == 1)
    let page = [
        ScreenLine(text: "Cash has been very tight across this whole year. Margins are falling", box: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.05)),
        ScreenLine(text: "across every region we track.", box: CGRect(x: 0.1, y: 0.72, width: 0.5, height: 0.05)),
        ScreenLine(text: "Inventory is the next thing to review.", box: CGRect(x: 0.1, y: 0.5, width: 0.7, height: 0.05)),
    ]
    let choices = jumpSentences(page)
    let picked = sentence(at: CGPoint(x: 0.8, y: 0.82), in: choices)
    check("finds the sentence under the pointer", picked.map { choices[$0].text.hasPrefix("Margins") } == true)
    check("starts partway along a line", picked.map { linesToRead(from: choices[$0], in: page)[0].text } == "Margins are falling")
    check("jumping back reads later lines again", seenBeforeJump([page[0].text, page[1].text, page[2].text], line: 1, in: page) == [page[0].text, page[0].text, page[1].text])
    check("jumping ahead skips the lines above", seenBeforeJump([page[0].text], line: 2, in: page).contains(page[1].text))
    check("speaks a finished sentence early", endsThought("The cash cycle matters.”") && !endsThought("The cash cycle matters because"))
    let bubble = ScreenLine(text: "Why does inventory matter?", box: CGRect(x: 0.62, y: 0.8, width: 0.3, height: 0.04))
    let replyLine = ScreenLine(text: "Inventory ties up cash until it sells.", box: CGRect(x: 0.05, y: 0.7, width: 0.8, height: 0.04))
    let bubbleUnits = utterances([bubble, replyLine], in: 0..<2)
    check("local reading skips interface labels", LocalDirector.isClutter("Copy") && LocalDirector.isClutter("2 minutes ago") && !LocalDirector.isClutter("Inventory ties up cash."))
    let contrast = utterances([ScreenLine(text: "Revenue grew steadily across every region last year. However, cash fell sharply in the fourth quarter.")], in: 0..<1)
    check("local reading turns on a contrast", LocalDirector.plan(units: contrast, purpose: "", mood: "Auto", rightSide: [], following: false).items.last?.mood == "turning")
    check("local reading skips the user's own messages", LocalDirector.plan(units: bubbleUnits, purpose: "Claude's replies", mood: "Auto", rightSide: [0], following: false).items.map(\.unit) == [1])
    check("finds a mood in a dictated purpose", LocalDirector.mood(in: "Claude's replies, calm please") == "Calm")
    check("marks the user's message on the right", rightSideUnits(bubbleUnits, lines: [bubble, replyLine], screen: [replyLine, bubble, replyLine]) == [0])

    let source = [line("Region Revenue"), line("North 120"), line("South 80")]
    let table = [Utterance(text: "Region Revenue North 120 South 80", spans: [LineSpan(line: 0, from: 0, to: 14)], pauseAfter: 0.14)]
    let honest = ReadingPlan(material: "case", items: [PlanItem(unit: 0, through: 0, mood: "measured", say: "Revenue was 120 in the North and 80 in the South.")])
    check("keeps a table rewrite that uses screen numbers", utterances(plan: honest, units: table).map(\.text) == [honest.items[0].say!])
    let invented = ReadingPlan(material: "case", items: [PlanItem(unit: 0, through: 0, say: "Revenue was 950 in the North.")])
    check("rejects a rewrite with an invented number", utterances(plan: invented, units: table).map(\.text) == [table[0].text])
    let filtered = ReadingPlan(material: "other", items: [PlanItem(unit: 0, through: 0), PlanItem(unit: 9, through: 12)])
    check("reads chosen units word for word and skips bad ranges", utterances(plan: filtered, units: table).map(\.text) == [table[0].text])
    check("matches voice to material", voice(for: "case") == "bf_emma" && voice(for: "unknown") == "af_heart")

    let short = utterances([line("Paragraph 1. This is the first full sample sentence.")], in: 0..<1)
    check("joins very short sentences so speech does not stutter", short.map(\.text) == ["Paragraph 1. This is the first full sample sentence."])
    let wrapped = utterances([line("The margin recov-"), line("ered by the end of the year.")], in: 0..<2)
    check("rejoins words split across two lines", wrapped.first?.text == "The margin recovered by the end of the year.")
    check("remembers which screen lines a sentence covers", wrapped.first?.spans.map(\.line) == [0, 1])
    let twoSentences = utterances([line("The first sentence ends right here today. The second sentence continues after it.")], in: 0..<1)
    check("marks where each sentence sits within a line", twoSentences.count == 2 && twoSentences[1].spans[0].from > 30)
    let spaced = [placed("First paragraph ends with this line.", top: 0.9), placed("Second paragraph begins much lower.", top: 0.7)]
    check("separates paragraphs using the gap on screen", paragraphRanges(spaced, in: 0..<2).count == 2)
    check("pauses longer at the end of a paragraph", utterances(spaced, in: 0..<2).first?.pauseAfter == 0.42)
    let noisy = [ScreenLine(text: "Clipped title", touchesTop: true), line("• •"), ScreenLine(text: "Blurry", confidence: 0.1), line("Real text")]
    check("ignores clipped lines and recognition noise", readableLines(noisy).map(\.text) == ["Real text"])
    check("drops a chat label before speaking", utterances([line("Claude: Working capital is current assets minus liabilities.")], in: 0..<1).first?.text == "Working capital is current assets minus liabilities.")
    check("keeps the highlight on the words after the label", utterances([line("Claude: Working capital is current assets minus liabilities.")], in: 0..<1).first?.spans.first?.from == 8)
    check("removes a label from rewritten text", utterances(plan: ReadingPlan(material: "other", items: [PlanItem(unit: 0, through: 0, say: "Claude: North sold 120.")]), units: [Utterance(text: "North 120", spans: [], pauseAfter: 0.14)]).map(\.text) == ["North sold 120."])
    check("ignores a line holding only a speaker name", readableLines([line("Claude"), line("A real reply")]).map(\.text) == ["A real reply"])
    check("keeps ordinary sentences that mention a name", speakerLabelLength(in: "Claude said the margin improved.") == 0)
    let rewrapped = [line("The margin recovered by the end of the year"), line("and then fell again.")]
    check("does not repeat text rewrapped by resizing", unreadLines(in: rewrapped, seen: ["The margin recovered by the end of", "the year and then fell again."]).isEmpty)
    check("follows chat apps automatically", looksLikeChat(owner: "Claude", title: "", purpose: ""))
    check("follows when the purpose is about replies", looksLikeChat(owner: "Google Chrome", title: "Notes", purpose: "Read the replies"))
    check("does not follow an ordinary document", !looksLikeChat(owner: "Preview", title: "Case.pdf", purpose: ""))
    let planReply = #"{"is_error":false,"structured_output":{"material":"news","items":[{"unit":0,"through":0,"mood":"turning","speaker":"narrator","emphasis":["fell"],"say":null}]}}"#
    check("reads Claude's reading plan", (try? Planner.decode(Data(planReply.utf8)))?.material == "news")
    check("falls back when Claude reports a problem", (try? Planner.decode(Data(#"{"is_error":true,"result":"limit"}"#.utf8))) == nil)
    let dialogue = utterances([line("\"You never told me,\" she said quietly.")], in: 0..<1)
    check("separates spoken dialogue from narration", dialogue.count == 2 && dialogue[1].text == "she said quietly.")
    check("removes quotation marks before speaking", dialogue.first?.spokenText == "You never told me,")
    var stressed = Utterance(text: "Margin fell sharply.", spans: [], pauseAfter: 0.14)
    stressed.delivery.emphasis = ["fell", "120"]
    check("marks a stressed word for the voice", stressed.spokenText == "Margin [fell](+2) sharply.")
    let longSentence = utterances([line("Revenue grew strongly across every region this year, yet operating margin fell from 14 percent to 9 percent.")], in: 0..<1)
    check("divides a long contrast into two phrases", longSentence.count == 2 && longSentence[1].text.hasPrefix("yet operating"))
    let unknownMood = utterances(plan: ReadingPlan(material: "other", items: [PlanItem(unit: 0, through: 0, mood: "shouting", speaker: "robot")]), units: table)
    check("ignores a mood or speaker it does not know", unknownMood.first?.delivery == Delivery())
    check("gives characters a different voice from the narrator", dialogueVoice(for: "woman", narrator: "af_bella") != "af_bella" && dialogueVoice(for: "narrator", narrator: "bm_george") == "bm_george")
    check("slows and lowers a somber phrase", Delivery(mood: "somber").settings.speed < 1 && Delivery(mood: "somber").settings.cents < 0)
    let spokenReply = #"{"is_error":false,"structured_output":{"spoken":"Python 3.15 is current.","sources":[{"title":"Python","url":"https://www.python.org/downloads/"}]}}"#
    let parsed = (try? ClaudeCode.structuredOutput(Data(spokenReply.utf8))).flatMap { try? JSONDecoder().decode(SpokenAnswer.self, from: $0) }
    check("reads a spoken answer and its sources", parsed?.sources.first?.url == "https://www.python.org/downloads/")
    check("opens ordinary web sources", safeSourceURL("https://www.python.org/downloads/") != nil)
    check("refuses unsafe source links", safeSourceURL("file:///etc/passwd") == nil && safeSourceURL("javascript:alert(1)") == nil)

    func cell(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat = 0.12) -> ScreenLine {
        ScreenLine(text: text, box: CGRect(x: x, y: top - 0.02, width: width, height: 0.02))
    }
    // The recognizer lists a table column by column, so that is the order used here.
    let columnByColumn = [
        cell("Our plans compare as follows:", x: 0.1, top: 0.9, width: 0.6),
        cell("Plan", x: 0.1, top: 0.8), cell("Basic", x: 0.1, top: 0.7), cell("Pro", x: 0.1, top: 0.6), cell("Team", x: 0.1, top: 0.5),
        cell("Price", x: 0.35, top: 0.8), cell("10 dollars", x: 0.35, top: 0.7), cell("20 dollars", x: 0.35, top: 0.6),
        cell("per month", x: 0.35, top: 0.575), cell("40 dollars", x: 0.35, top: 0.5),
        cell("Limit", x: 0.6, top: 0.8), cell("5 users", x: 0.6, top: 0.7), cell("50 users", x: 0.6, top: 0.6), cell("500 users", x: 0.6, top: 0.5),
        cell("Pick the plan that fits.", x: 0.1, top: 0.35, width: 0.5),
    ]
    let rebuilt = tableAware(columnByColumn)
    check("reads a table row by row, headers named", rebuilt.map(\.text) == [
        "Our plans compare as follows:", "Table with columns Plan, Price, and Limit.",
        "Basic. Price: 10 dollars. Limit: 5 users.", "Pro. Price: 20 dollars per month. Limit: 50 users.",
        "Team. Price: 40 dollars. Limit: 500 users.", "Pick the plan that fits.",
    ])
    check("marks the rebuilt rows as table rows", rebuilt.map(\.tableRow) == [false, true, true, true, true, false])
    check("reads each table row as its own paragraph", paragraphRanges(rebuilt, in: 1..<5).count == 4)
    let prose = (0..<12).map { cell("A line of ordinary text number \($0).", x: 0.1, top: 0.9 - CGFloat($0) * 0.03, width: 0.7) }
    check("leaves ordinary text alone", tableAware(prose) == prose)
    let pairs = (0..<6).flatMap { [cell("Term \($0)", x: 0.1, top: 0.9 - CGFloat($0) * 0.1), cell("Its meaning \($0)", x: 0.4, top: 0.9 - CGFloat($0) * 0.1)] }
    check("leaves a two-column list alone", tableAware(pairs) == pairs)
    check("does not change a table twice", tableAware(rebuilt) == rebuilt)
    let glide = stride(from: 0.0, through: 1.0, by: 0.05).map(easedProgress)
    check("the scroll glide starts at 0 and ends at 1", glide.first == 0 && glide.last == 1)
    check("the scroll glide never goes backwards", zip(glide, glide.dropFirst()).allSatisfy { $0 <= $1 })
    check("the scroll glide starts and ends gently", glide[1] < 0.01 && glide[19] > 0.99 && glide[10] == 0.5)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        let marker = HighlightView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        // How strongly the highlight tints the middle of where it should be, from 0 to 1.
        func tint() -> CGFloat {
            guard let image = marker.bitmapImageRepForCachingDisplay(in: marker.bounds) else { return -1 }
            marker.cacheDisplay(in: marker.bounds, to: image)
            let scale = CGFloat(image.pixelsWide) / marker.bounds.width
            return image.colorAt(x: Int(240 * scale), y: Int(90 * scale))?.alphaComponent ?? -1
        }
        marker.segments = [HighlightSegment(rect: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.1), done: 0)]
        check("a highlight fades in instead of popping", tint() < 0.05)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        check("the highlight settles on its place", tint() > 0.15)
        marker.segments = []
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        check("a cleared highlight fades away", tint() < 0.02)
    }

    func status(_ json: String) -> ClaudeSetup { ClaudeCode.setup(fromStatus: Data(json.utf8)) }
    check("sees Claude connected with a Claude plan", status(#"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","email":"a@b.c"}"#) == .ready(email: "a@b.c"))
    check("sees Claude Code signed out", status(#"{"loggedIn":false,"authMethod":"none","apiProvider":"firstParty"}"#) == .signedOut)
    check("refuses an API account that bills by usage", status(#"{"loggedIn":true,"authMethod":"console","apiProvider":"firstParty"}"#) == .apiAccount)
    check("refuses a cloud provider account", status(#"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"bedrock"}"#) == .apiAccount)
    check("treats an unreadable status as signed out", status("not json") == .signedOut)
    let copies = ["/x/claude-code/2.1.99/a/claude.app/Contents/MacOS/claude", "/x/claude-code/2.1.326/b/claude.app/Contents/MacOS/claude"]
    check("uses the newest copy of Claude Code first", ClaudeCode.newestFirst(copies).first == copies[1])
    check("checks the standard Claude Code install folder first", ClaudeCode.installedPaths(home: "/nowhere").first == "/nowhere/.local/bin/claude")
    check("says when the Claude usage limit is reached", ClaudeCode.failureMessage(PlannerError.unusable("Claude AI usage limit reached")).contains("usage limit"))
    check("falls back to a connection hint for other failures", ClaudeCode.failureMessage(CancellationError()).contains("internet connection"))
    let limited = Data(#"{"is_error":true,"result":"Claude AI usage limit reached"}"#.utf8)
    let failure: Error? = { do { _ = try ClaudeCode.structuredOutput(limited); return nil } catch { return error } }()
    check("keeps Claude's reason when a reply fails", failure.map(ClaudeCode.failureMessage)?.contains("usage limit") == true)
    let shot = renderedTextImage(["Working capital is current assets minus current liabilities."])
    let pdfSource = NoteSource(title: "report.pdf", app: "Preview", filePath: "/Users/you/report.pdf", pages: 9, attach: true)
    let tabSource = NoteSource(title: "Case brief", app: "Google Chrome", link: "https://example.com/brief")
    func part(_ text: String, _ note: String, _ source: Int = 0, textOnly: Bool = false) -> Snip { Snip(image: shot, text: text, note: note, source: source, textOnly: textOnly) }
    let single = NoteBundle.message([part("Revenue grew.\nCosts fell.", "Why?"), part("Margins held.", "")], sources: [pdfSource], ask: "", notesFile: "report – notes.pdf")
    check("the message names one source with its file", single.hasPrefix("I'm working through \"report.pdf\" (Preview, /Users/you/report.pdf, attached)."))
    check("the message points at the notes file", single.contains("The attached \"report – notes.pdf\" holds my notes."))
    check("the message asks Claude to answer each note when no request is given", single.hasSuffix("What I want: \(NoteBundle.defaultAsk)"))
    check("the message carries what the reader wants", NoteBundle.message([part("A", "")], sources: [pdfSource], ask: " Fill the table ").hasSuffix("What I want: Fill the table"))
    let mixed = NoteBundle.message([part("A", ""), part("B", "", 1)], sources: [pdfSource, tabSource], ask: "")
    check("the message lists several sources", mixed.contains("through 2 documents:\n- \"report.pdf\"") && mixed.contains("- \"Case brief\""))
    check("the message warns that a link may need a login", mixed.contains("https://example.com/brief). Claude may not be able to open this link if it needs a login."))
    let inPage = NoteSource(title: "JD – Gameberry Labs", app: "Google Chrome", link: "blob:https://placements.isb.edu/989c")
    check("never shares a browser's temporary blob address", !NoteBundle.message([part("A", "")], sources: [inPage], ask: "").contains("blob:") && inPage.isBrowserPDF && inPage.location.hasPrefix("Open inside a web page"))
    let notesFolder = FileManager.default.temporaryDirectory.appendingPathComponent("narrator-notes-test-\(getpid())", isDirectory: true)
    try? FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
    let notesTarget = notesFolder.appendingPathComponent("JD – notes.pdf")
    let notesMade = NoteBundle.notesPDF([0, 1, 2], of: [part("Revenue grew.\nCosts fell.", "Why?"), part("", ""), part("Margins held.", "Check", textOnly: true)], sources: [inPage], ask: "Fill the table", to: notesTarget)
    let notesDoc = PDFDocument(url: notesTarget)
    let pageText = (0..<(notesDoc?.pageCount ?? 0)).map { notesDoc?.page(at: $0)?.string ?? "" }
    check("the notes file has a first page and a page per part", notesMade && pageText.count == 4)
    check("the notes file's first page says what the reader wants", pageText.first?.contains("What I want: Fill the table") == true && pageText.first?.contains("I marked 3 parts") == true)
    check("each part's page has its text and note", pageText.count == 4 && pageText[1].contains("Part 1") && pageText[1].contains("My note: Why?") && pageText[1].contains("Revenue grew. Costs fell."))
    check("a part with no text or note says so", pageText.count == 4 && pageText[2].contains("No note") && pageText[2].contains("No text found"))
    check("a text-only part is marked", pageText.count == 4 && pageText[3].contains("text only"))
    check("names the notes file after the document, safely", NoteBundle.freeName(base: "JD – PM / APM: Gameberry.pdf", in: notesFolder).lastPathComponent == "JD – PM - APM- Gameberry – notes.pdf")
    try? FileManager.default.removeItem(at: notesFolder)
    let small = NoteBundle.shrink(shot, by: 2)
    check("shrinks a Retina capture to half on each side", small.width == shot.width / 2 && small.height == shot.height / 2)
    let badged = NoteBundle.numbered(small, 3)
    check("stamps the part number in the top-left corner", (badged.colorAt(x: 20, y: 26)?.blueComponent ?? 1) < 0.5)
    check("starts a large file unattached", NoteSource(title: "", app: "", pages: 150).isLarge && NoteSource(title: "", app: "", bytes: 40_000_000).isLarge && !pdfSource.isLarge)
    check("tells the token cost of attaching a file", pdfSource.attachDetail == "9 pages, about 18,000 tokens")

    // A three-page PDF with real text, the way a document app saves one.
    let pdfFolder = FileManager.default.temporaryDirectory.appendingPathComponent("narrator-selftest-\(getpid())", isDirectory: true)
    try? FileManager.default.createDirectory(at: pdfFolder, withIntermediateDirectories: true)
    let original = pdfFolder.appendingPathComponent("Case.pdf")
    var pageBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let writer = CGContext(original as CFURL, mediaBox: &pageBox, nil) {
        let pagesText = [["Enterprise search take home", "Sales reps use search to find customer data."],
                         ["Support tickets about search have tripled this year.", "Can't find customer info is the top complaint."],
                         ["Tools and metrics you expect to be around.", "Describe how you will investigate this issue."]]
        for lines in pagesText {
            writer.beginPDFPage(nil)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: writer, flipped: false)
            for (row, text) in lines.enumerated() {
                (text as NSString).draw(at: NSPoint(x: 72, y: 700 - row * 30), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
            }
            writer.endPDFPage()
        }
        writer.closePDF()
    }
    let case3 = PDFDocument(url: original)
    check("finds a marked part on the right page of a PDF", case3.flatMap { NoteBundle.locate("Support tickets about search have tripled this year.\nCan't find customer info is the top complaint.", in: $0) }.map { case3!.index(for: $0.page) } == 1)
    check("does not place a part that is not in the PDF", case3.flatMap { NoteBundle.locate("This sentence appears nowhere in the file at all.", in: $0) } == nil)
    let target = pdfFolder.appendingPathComponent("Case – notes.pdf")
    let made = NoteBundle.annotatedCopy(of: original.path, title: "Case.pdf", notes: [(1, "Support tickets about search have tripled this year.", "Tripled from what base?"), (2, "Nothing like this is in the file anywhere.", "Lost")], ask: "", to: target)
    let marked = PDFDocument(url: target)
    check("annotated copy places only the notes it can find", made?.placed == [1])
    check("annotated copy starts with a notes page Claude can read", marked?.pageCount == 4 && marked?.page(at: 0)?.string?.contains("1. Page 2") == true && marked?.page(at: 0)?.string?.contains("My note: Tripled from what base?") == true)
    check("annotated copy highlights the spot", marked?.page(at: 2)?.annotations.contains { $0.type == "Highlight" } == true)
    check("the original PDF is left untouched", PDFDocument(url: original)?.pageCount == 3 && PDFDocument(url: original)?.page(at: 1)?.annotations.isEmpty == true)
    check("names a copy without overwriting an existing file", NoteBundle.freeName(for: original.path, in: pdfFolder).lastPathComponent == "Case – notes 2.pdf")
    let caseSource = NoteSource(title: "Case.pdf", app: "Preview", filePath: original.path, pages: 3, attach: true)
    let withCopy = NoteBundle.message([part("Support tickets", "Tripled from what base?")], sources: [caseSource], ask: "", annotated: [0: "Case – notes.pdf"])
    check("the message points at the annotated copy", withCopy.contains("The attached \"Case – notes.pdf\" is this document with my notes added") && !withCopy.contains(", attached") && !withCopy.contains("holds my notes"))
    check("knows a PDF open in a browser", NoteSource(title: "Take home 2.pdf", app: "Google Chrome", link: "https://example.com/x.pdf").isBrowserPDF && !caseSource.isBrowserPDF)
    var opened = NoteSource(title: "Case.pdf", app: "Google Chrome")
    opened.useAddress(original.absoluteString)
    check("treats a file opened in a browser as the file", opened.filePath == original.path && opened.link == nil && opened.pages == 3 && opened.attach && !opened.isBrowserPDF)
    var localDoc = NoteSource(title: "", app: "Safari")
    localDoc.useAddress("file:///tmp/Take%20home%202.docx")
    check("reads a file address with spaces", localDoc.filePath == "/tmp/Take home 2.docx")
    var web = NoteSource(title: "Brief", app: "Safari")
    web.useAddress("https://example.com/brief.pdf")
    check("keeps a web address as a link", web.link == "https://example.com/brief.pdf" && web.filePath == nil && web.isBrowserPDF)
    try? FileManager.default.removeItem(at: pdfFolder)

    let realHistory = NoteHistory.folder
    NoteHistory.folder = FileManager.default.temporaryDirectory.appendingPathComponent("narrator-history-test-\(getpid())", isDirectory: true)
    let keptPart = part("Support tickets tripled.", "From what base?")
    NoteHistory.save(SavedSet(id: "test-set", created: Date(), updated: Date(), sources: [pdfSource], parts: [SavedPart(id: keptPart.id, text: keptPart.text, note: keptPart.note, source: 0, textOnly: false)], ask: "Fill the table", copied: false, saved: [:]), snips: [keptPart])
    let reloaded = NoteHistory.load("test-set")
    check("history keeps a set with its notes and pictures", reloaded?.snips.first?.note == "From what base?" && reloaded?.snips.first?.image.width == shot.width && reloaded?.set.ask == "Fill the table")
    check("history names a set after its document", NoteHistory.sets().first?.name == "report.pdf")
    NoteHistory.logReading(app: "Google Chrome", title: "Case brief", at: Date().addingTimeInterval(-40 * 86_400))
    NoteHistory.logReading(app: "Preview", title: "report.pdf")
    check("history logs reading by app and title only", NoteHistory.reading().map(\.app) == ["Preview", "Google Chrome"])
    NoteHistory.prune(now: Date())
    check("history drops reading older than 30 days", NoteHistory.reading().map(\.app) == ["Preview"] && NoteHistory.sets().count == 1)
    NoteHistory.prune(now: Date().addingTimeInterval(31 * 86_400))
    check("history drops a set untouched for 30 days", NoteHistory.sets().isEmpty)
    try? FileManager.default.removeItem(at: NoteHistory.folder)
    NoteHistory.folder = realHistory

    // A scroll the selector hands on can come straight back before it has stepped aside. It must not be handed on again.
    var handedOn = 0
    let realHandOn = SelectionView.handOn
    SelectionView.handOn = { _ in handedOn += 1 }
    let selectorWindow = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
    let selector = SelectionView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    selectorWindow.contentView = selector
    func wheel(tagged: Bool) -> NSEvent {
        let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -20, wheel2: 0, wheel3: 0)!
        if tagged { scroll.setIntegerValueField(.eventSourceUserData, value: SelectionView.handedOn) }
        return NSEvent(cgEvent: scroll)!
    }
    selector.scrollWheel(with: wheel(tagged: false))
    selector.scrollWheel(with: wheel(tagged: true))
    selector.scrollWheel(with: wheel(tagged: false))
    check("the selector hands a scroll on once and drops one that bounces back", handedOn == 1 && selectorWindow.ignoresMouseEvents)
    selectorWindow.ignoresMouseEvents = false
    selector.scrollWheel(with: wheel(tagged: true))
    check("the selector never hands on its own scroll again", handedOn == 1)
    SelectionView.handOn = realHandOn

    print(failures == 0 ? "All self-tests passed" : "\(failures) self-tests failed")
    return failures == 0 ? 0 : 1
}
