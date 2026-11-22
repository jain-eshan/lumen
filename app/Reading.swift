import AVFoundation
import NaturalLanguage
import Vision

// MARK: - Reading logic

struct ScreenLine: Equatable {
    var text: String
    var box: CGRect = .zero  // Fractions of the capture, measured from its bottom-left corner.
    var touchesTop = false
    var touchesBottom = false
    var confidence: Float = 1
    /// True for a line made from one whole row of a table by `tableAware`.
    var tableRow = false
}

/// The characters of one screen line covered by a spoken sentence.
struct LineSpan: Equatable {
    let line: Int
    let from: Int
    let to: Int
}

/// How one spoken phrase should be performed.
struct Delivery: Equatable {
    var mood = "neutral"
    var speaker = "narrator"
    var emphasis: [String] = []

    var settings: (speed: Double, cents: Float, gain: Float, pause: Double) {
        switch mood {
        case "measured": return (0.94, -40, 0, 0.5)
        case "building": return (1.05, 45, 1, 0.16)
        case "turning": return (0.9, -70, 0, 0.55)
        case "doubtful": return (0.86, -100, -1.5, 0.65)
        case "warm": return (0.96, 30, 0.5, 0.32)
        case "tender": return (0.92, 20, -1, 0.45)
        case "somber": return (0.85, -75, -2.5, 0.85)
        case "quiet": return (0.92, -50, -3, 0.6)
        default: return (1, 0, 0, 0.22)
        }
    }
}

struct Utterance: Equatable {
    var text: String
    var spans: [LineSpan]
    var pauseAfter: Double
    var delivery = Delivery()

    /// The words sent to the voice, with quotation marks removed and stressed words marked.
    var spokenText: String {
        var spoken = text.filter { !"[]\"“”".contains($0) }
        for word in delivery.emphasis.prefix(2) where !word.isEmpty && word.allSatisfy({ $0.isLetter }) {
            if let range = spoken.range(of: "\\b\(word)\\b", options: [.regularExpression, .caseInsensitive]) {
                spoken.replaceSubrange(range, with: "[\(spoken[range])](+2)")
            }
        }
        return spoken
    }
}

struct PlanItem: Decodable {
    let unit: Int
    var through: Int?
    var mood: String?
    var speaker: String?
    var emphasis: [String]?
    var say: String?
}

struct ReadingPlan: Decodable {
    let material: String
    let items: [PlanItem]
}

func normalized(_ text: String) -> String {
    text.lowercased().filter { $0.isLetter || $0.isNumber }
}

/// Lines already read are checked again several times a second while following, so each one is normalized only once.
final class NormalizedMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var known: [String: String] = [:]

    func callAsFunction(_ texts: [String]) -> [String] {
        lock.withLock {
            if known.count > 100_000 { known.removeAll() }
            return texts.map { text in
                if let done = known[text] { return done }
                let done = normalized(text)
                known[text] = done
                return done
            }
        }
    }
}

let normalizedOnce = NormalizedMemo()

let speakerNames = ["claude", "chatgpt", "gemini", "copilot", "assistant", "you", "me", "user", "human", "interviewer", "candidate"]

let speakerLabel = try! NSRegularExpression(pattern: "^\\s*(\(speakerNames.joined(separator: "|")))\\s*[:\u{FF1A}]\\s*", options: .caseInsensitive)

/// Counts the characters of a chat label such as "Claude:", which is shown on screen but never spoken.
func speakerLabelLength(in text: String) -> Int {
    guard let match = speakerLabel.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range, in: text) else { return 0 }
    return text.distance(from: text.startIndex, to: range.upperBound)
}

/// Removes clipped lines, recognition noise and lines holding only a speaker's name.
func readableLines(_ lines: [ScreenLine]) -> [ScreenLine] {
    lines.filter { line in
        !line.touchesTop && line.confidence >= 0.3 && line.text.contains { $0.isLetter || $0.isNumber }
            && !speakerNames.contains(normalized(line.text))
            // A line ending in › is a folded section, such as Claude's "Checking whether..." thinking summary.
            && !line.text.trimmingCharacters(in: .whitespaces).hasSuffix("\u{203A}")
    }
}

/// Whether new text is worth speaking. Long lines are, and so is a short finished sentence such as "Go ahead.",
/// while a loose label like "Auto" or "Reply" is interface.
func worthReading(_ text: String) -> Bool {
    normalized(text).count >= 16 || (endsThought(text) && text.split(separator: " ").count >= 2)
}

/// Whether Follow should scroll down by itself: only when everything visible is read, nothing is being read or planned,
/// the screen has been still for a couple of seconds, and the last scroll did not already show the end of the page.
func shouldScrollForMore(unreadVisible: Bool, queued: Bool, paused: Bool, stillFor: TimeInterval, sinceScroll: TimeInterval, atEnd: Bool) -> Bool {
    !unreadVisible && !queued && !paused && !atEnd && stillFor >= 2 && sinceScroll >= 1.5
}

/// Keeps new lines positioned where they sit now, so the highlight never marks the wrong place.
func placed(_ lines: [ScreenLine], on screen: [ScreenLine]) -> [ScreenLine] {
    let boxes = Dictionary(screen.map { (normalized($0.text), $0.box) }, uniquingKeysWith: { _, latest in latest })
    return lines.map { line in
        var positioned = line
        positioned.box = boxes[normalized(line.text)] ?? line.box
        return positioned
    }
}

/// Chat apps and purposes about replies keep listening for new text after the current screen is read.
func looksLikeChat(owner: String, title: String, purpose: String) -> Bool {
    let apps = ["claude", "chatgpt", "gemini", "perplexity", "copilot"]
    let place = (owner + " " + title).lowercased()
    let goal = purpose.lowercased()
    return apps.contains { place.contains($0) } || ["repl", "respons", "answer", "mock", "interview"].contains { goal.contains($0) }
}

/// Finds lines not read yet, using long lines already read as anchors after a scroll.
func unreadLines(in current: [ScreenLine], seen: [String]) -> [ScreenLine] {
    // This runs several times a second while following, so each line is normalized once and remembered.
    let seenNormalized = normalizedOnce(seen)
    let seenLines = Set(seenNormalized)
    // Joined text still matches when a resized window wraps the same words differently.
    // Searching it as one NSString is several times faster than String.contains, with the same answers for letters and digits.
    let seenText = seenNormalized.joined() as NSString
    // A new line is asked about twice, once to find the anchor and once to filter, and the search is the slow part.
    var answers: [String: Bool] = [:]
    func wasRead(_ text: String) -> Bool {
        if let known = answers[text] { return known }
        let read = seenLines.contains(text) || (text.count >= 12 && seenText.range(of: text).location != NSNotFound)
        answers[text] = read
        return read
    }
    // Text recognition can misread a letter while a page scrolls, which must not repeat the line.
    let recent = seenNormalized.suffix(60).map { (characters: Array($0), numbers: numbers(in: $0)) }
    func nearlyRead(_ text: String) -> Bool {
        guard text.count >= 16 else { return false }
        let characters = Array(text)
        let found = numbers(in: text)
        return recent.contains {
            abs($0.characters.count - characters.count) <= 3 && $0.numbers == found
                && differsByAtMost(max(2, characters.count / 8), characters, $0.characters)
        }
    }
    let texts = current.map { normalized($0.text) }
    let anchor = texts.lastIndex { $0.count >= 16 && wasRead($0) }
    let start = anchor.map { $0 + 1 } ?? 0
    return current.indices[start...].filter { !wasRead(texts[$0]) && !nearlyRead(texts[$0]) }.map { current[$0] }
}

/// Whether two texts differ by at most `limit` added or removed characters.
/// Counting letters first rules out most pairs cheaply, because every edit changes one letter's count by one.
func differsByAtMost(_ limit: Int, _ text: [Character], _ other: [Character]) -> Bool {
    var counts: [Character: Int] = [:]
    for character in text { counts[character, default: 0] += 1 }
    for character in other { counts[character, default: 0] -= 1 }
    guard counts.values.reduce(0, { $0 + abs($1) }) <= limit else { return false }
    return text.difference(from: other).count <= limit
}

/// A line ending this way can be spoken before the rest of a reply has arrived.
func endsThought(_ text: String) -> Bool {
    let closing = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"”’')]*_"))
    return text.trimmingCharacters(in: closing).last.map { ".!?:;".contains($0) } ?? false
}

// MARK: Tables begin

/// The text recognizer returns a table one column at a time, which reads as nonsense. This finds a table by how its
/// cells line up, then replaces its lines with one line per row: the row's label, then "Header: value" for each other column.
func tableAware(_ lines: [ScreenLine]) -> [ScreenLine] {
    let sized = lines.indices.filter { lines[$0].box.width > 0 && !lines[$0].tableRow }
    guard sized.count >= 9 else { return lines }

    // Columns are lines starting at the same left edge. Lines in a column are listed top to bottom.
    var columnOf: [Int: Int] = [:]
    var edges: [CGFloat] = []
    var lastEdge: CGFloat = -1
    for index in sized.sorted(by: { lines[$0].box.minX < lines[$1].box.minX }) {
        let x = lines[index].box.minX
        if x - lastEdge > 0.006 { edges.append(x) }
        lastEdge = x
        columnOf[index] = edges.count - 1
    }
    let byTop = sized.sorted { lines[$0].box.maxY > lines[$1].box.maxY }
    var byColumn: [Int: [Int]] = [:]
    for index in byTop { byColumn[columnOf[index]!, default: []].append(index) }

    /// A line sitting right under another in its column is a wrapped cell, not a new row.
    func tight(_ above: Int, _ below: Int) -> Bool {
        lines[above].box.minY - lines[below].box.maxY <= 0.9 * max(lines[above].box.height, lines[below].box.height)
    }
    var wraps = Set<Int>()
    for column in byColumn.values {
        for (above, below) in zip(column, column.dropFirst()) where tight(above, below) { wraps.insert(below) }
    }

    // Lines whose tops match form a candidate row. Three or more in a row of columns, repeated, is a table.
    let typical = sized.map { lines[$0].box.height }.sorted()[sized.count / 2]
    var groups: [[Int]] = []
    for index in byTop {
        if let previous = groups.last?.last, lines[previous].box.maxY - lines[index].box.maxY <= 0.35 * typical {
            groups[groups.count - 1].append(index)
        } else {
            groups.append([index])
        }
    }
    let starts: [[Int: Int]] = groups
        .filter { group in group.filter { wraps.contains($0) }.count * 2 < group.count }
        .map { group in Dictionary(group.map { (columnOf[$0]!, $0) }, uniquingKeysWith: { first, _ in first }) }
        .filter { $0.count >= 3 }

    // The table is the set of columns that lines up with the most cells over three or more rows. Columns far apart,
    // such as a sidebar and a menu on the other side of the page, do not count.
    func close(_ columns: [Int], _ members: [Int]) -> Bool {
        zip(columns, columns.dropFirst()).allSatisfy { left, right in
            let gaps = members.compactMap { row in starts[row][left].map { edges[right] - lines[$0].box.maxX } }.sorted()
            return gaps.isEmpty || gaps[gaps.count / 2] <= 0.25
        }
    }
    let startColumns = starts.map { Set($0.keys) }
    var remaining = Array(starts.indices)
    var tables: [(rows: [[Int: Int]], columns: [Int])] = []
    while starts.count <= 150 {
        var best: (score: Int, columns: [Int], rows: [Int])?
        var tried = Set<[Int]>()
        for (offset, a) in remaining.enumerated() {
            for b in remaining[(offset + 1)...] {
                var columns = startColumns[a].intersection(startColumns[b]).sorted()
                guard columns.count >= 3, tried.insert(columns).inserted else { continue }
                // A real column shows up in most rows; one that lines up by chance does not.
                var rows: [Int] = []
                while columns.count >= 3 {
                    rows = remaining.filter { startColumns[$0].intersection(columns).count * 10 >= columns.count * 7 }
                    let kept = columns.filter { column in rows.filter { startColumns[$0].contains(column) }.count * 10 >= rows.count * 8 }
                    if kept.count == columns.count { break }
                    columns = kept
                }
                guard columns.count >= 3, rows.count >= 3, close(columns, rows) else { continue }
                let score = rows.reduce(0) { $0 + startColumns[$1].intersection(columns).count }
                if score > (best?.score ?? 0) { best = (score, columns, rows) }
            }
        }
        guard let table = best else { break }
        tables.append((table.rows.map { starts[$0] }, table.columns))
        remaining.removeAll { table.rows.contains($0) }
    }
    guard !tables.isEmpty else { return lines }

    func union(_ indexes: [Int]) -> CGRect { indexes.dropFirst().reduce(lines[indexes[0]].box) { $0.union(lines[$1].box) } }
    func joined(_ cell: [Int]) -> String {
        cell.reduce("") { text, index in
            let next = lines[index].text.trimmingCharacters(in: .whitespaces)
            return text.hasSuffix("-") ? text + next : (text.isEmpty ? next : text + " " + next)
        }
    }
    func ended(_ text: String) -> String {
        let plain = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
        return plain.isEmpty ? "" : (".!?".contains(plain.last!) ? plain : plain + ".")
    }

    var consumed = Set<Int>()
    var inserts: [Int: [ScreenLine]] = [:]
    for table in tables {
        var rows = table.rows.map { row in table.columns.map { column in row[column].map { [$0] } ?? [] } }
        var startAt: [Int: Int] = [:]
        for (row, cells) in rows.enumerated() { for cell in cells { if let index = cell.first { startAt[index] = row } } }

        // Wrapped lines under a cell belong to it, unless they run into the next column or past the cell's width.
        for (position, column) in table.columns.enumerated() {
            let widest = rows.compactMap { $0[position].first }.map { lines[$0].box.width }.max() ?? 0
            let limit = position + 1 < table.columns.count ? edges[table.columns[position + 1]] - 0.004 : edges[column] + widest * 1.3
            var currentRow: Int?
            var previous: Int?
            for index in byColumn[column] ?? [] {
                if let start = startAt[index] {
                    currentRow = start
                    previous = index
                } else if let row = currentRow, let above = previous, tight(above, index), lines[index].box.maxX <= limit {
                    rows[row][position].append(index)
                    previous = index
                } else {
                    currentRow = nil
                    previous = nil
                }
            }
        }

        let cells = rows.map { $0.map(joined) }
        let headed = cells[0].filter { $0.contains { $0.isNumber } }.count * 2 <= cells[0].filter { !$0.isEmpty }.count
        var made: [ScreenLine] = []
        for (row, values) in cells.enumerated() {
            let sentence: String
            if headed && row == 0 {
                let names = values.filter { !$0.isEmpty }
                sentence = "Table with columns " + (names.count > 1 ? names.dropLast().joined(separator: ", ") + ", and " + names.last! : names.joined()) + "."
            } else if headed {
                let pairs = values.indices.dropFirst().filter { !values[$0].isEmpty }.map { (cells[0][$0].isEmpty ? "" : cells[0][$0] + ": ") + values[$0] }
                sentence = ([values[0]] + pairs).map(ended).filter { !$0.isEmpty }.joined(separator: " ")
            } else {
                sentence = values.map(ended).filter { !$0.isEmpty }.joined(separator: " ")
            }
            let covered = rows[row].flatMap { $0 }
            guard !sentence.isEmpty, !covered.isEmpty else { continue }
            made.append(ScreenLine(
                text: sentence, box: union(covered),
                touchesTop: covered.contains { lines[$0].touchesTop }, touchesBottom: covered.contains { lines[$0].touchesBottom },
                confidence: covered.map { lines[$0].confidence }.min() ?? 1, tableRow: true
            ))
            consumed.formUnion(covered)
        }
        if let at = rows.flatMap({ $0.flatMap { $0 } }).min() { inserts[at] = made }
    }

    var result: [ScreenLine] = []
    for index in lines.indices {
        result += inserts[index] ?? []
        if !consumed.contains(index) { result.append(lines[index]) }
    }
    return result
}

// MARK: Tables end

/// Chat apps place the user's own messages to the right of the column holding the replies.
func rightSideUnits(_ units: [Utterance], lines: [ScreenLine], screen: [ScreenLine]) -> Set<Int> {
    let edges = screen.filter { $0.box.width > 0 }.map(\.box.minX).sorted()
    guard !edges.isEmpty else { return [] }
    // The replies start at the leftmost edge that a second line shares. The middle edge cannot be used,
    // because a long message from the user has the most lines and would then count as the replies' column.
    let column = edges.indices.first { index in edges[(index + 1)...].first.map { $0 - edges[index] < 0.012 } ?? false }.map { edges[$0] } ?? edges[0]
    return Set(units.indices.filter { index in
        !units[index].spans.isEmpty && units[index].spans.allSatisfy { span in
            guard lines.indices.contains(span.line) else { return false }
            let box = lines[span.line].box
            let besideOtherText = screen.contains { abs($0.box.midY - box.midY) < box.height / 2 && $0.box.minX < box.minX - 0.01 }
            return box.minX - column > 0.11 && !besideOtherText
        }
    })
}

/// Splits lines into paragraphs using the space between them on screen.
func paragraphRanges(_ lines: [ScreenLine], in range: Range<Int>) -> [Range<Int>] {
    guard !range.isEmpty else { return [] }
    let widest = lines[range].map(\.box.width).max() ?? 0
    var paragraphs: [Range<Int>] = []
    var start = range.lowerBound
    for index in (range.lowerBound + 1)..<max(range.upperBound, range.lowerBound + 1) where index < range.upperBound {
        let above = lines[index - 1]
        let below = lines[index]
        let height = max(above.box.height, below.box.height)
        let wideGap = height > 0 && above.box.minY - below.box.maxY > height * 0.9
        let endedEarly = widest > 0 && above.box.width < widest * 0.72 && ".!?:".contains(above.text.last ?? " ")
        if wideGap || endedEarly || below.box.minY > above.box.minY || speakerLabelLength(in: below.text) > 0 || above.tableRow || below.tableRow {
            paragraphs.append(start..<index)
            start = index
        }
    }
    paragraphs.append(start..<range.upperBound)
    return paragraphs
}

let quotePattern = try! NSRegularExpression(pattern: #"["“][^"”]+["”]"#)
let clausePattern = try! NSRegularExpression(pattern: #",\s+(?=(?:yet|but|or|while|although|though|however)\b)"#, options: .caseInsensitive)

/// Finds where a sentence should divide so speech, narration and long clauses can each be performed.
func clauseCuts(in sentence: String) -> [Int] {
    let characters = Array(sentence)
    var cuts = Set<Int>()
    let whole = NSRange(sentence.startIndex..., in: sentence)
    for match in quotePattern.matches(in: sentence, range: whole) {
        guard let range = Range(match.range, in: sentence) else { continue }
        cuts.insert(sentence.distance(from: sentence.startIndex, to: range.lowerBound))
        cuts.insert(sentence.distance(from: sentence.startIndex, to: range.upperBound))
    }
    if characters.count > 70 {
        for match in clausePattern.matches(in: sentence, range: whole) {
            guard let range = Range(match.range, in: sentence) else { continue }
            cuts.insert(sentence.distance(from: sentence.startIndex, to: range.upperBound))
        }
    }
    return cuts.filter { $0 > 0 && $0 < characters.count }.sorted()
}

/// Turns one paragraph into natural spoken phrases that remember where they sit on screen.
func utterances(_ lines: [ScreenLine], paragraph: Range<Int>) -> [Utterance] {
    var text = ""
    var owners: [(line: Int, offset: Int)] = []
    for index in paragraph {
        let labelLength = index == paragraph.lowerBound ? speakerLabelLength(in: lines[index].text) : 0
        var characters = Array(lines[index].text.dropFirst(labelLength))
        let isLast = index + 1 == paragraph.upperBound
        let joinsWord = !isLast && characters.last == "-" && lines[index + 1].text.first?.isLowercase == true
        if joinsWord { characters.removeLast() }
        for (offset, character) in characters.enumerated() {
            text.append(character)
            owners.append((index, offset + labelLength))
        }
        if !joinsWord && !isLast {
            text.append(" ")
            owners.append((index, characters.count + labelLength))
        }
    }

    var result: [Utterance] = []
    var previousWasWhole = false
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    for range in tokenizer.tokens(for: text.startIndex..<text.endIndex) {
        let sentence = String(text[range])
        let characters = Array(sentence)
        let sentenceStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let cuts = clauseCuts(in: sentence)
        let bounds = [0] + cuts + [characters.count]
        for (first, last) in zip(bounds, bounds.dropFirst()) {
            let clause = String(characters[first..<last]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clause.isEmpty else { continue }
            let start = min(sentenceStart + first, owners.count)
            let end = min(sentenceStart + last, owners.count)
            var spans: [LineSpan] = []
            for owner in owners[start..<end] {
                if let previous = spans.last, previous.line == owner.line {
                    spans[spans.count - 1] = LineSpan(line: previous.line, from: previous.from, to: owner.offset + 1)
                } else {
                    spans.append(LineSpan(line: owner.line, from: owner.offset, to: owner.offset + 1))
                }
            }
            if cuts.isEmpty, previousWasWhole, let previous = result.last, previous.text.count < 30 {
                var joined = spans
                if let firstSpan = joined.first, let lastSpan = previous.spans.last, firstSpan.line == lastSpan.line {
                    joined[0] = LineSpan(line: firstSpan.line, from: lastSpan.from, to: firstSpan.to)
                    joined = previous.spans.dropLast() + joined
                } else {
                    joined = previous.spans + joined
                }
                result[result.count - 1] = Utterance(text: previous.text + " " + clause, spans: joined, pauseAfter: 0.14)
            } else {
                result.append(Utterance(text: clause, spans: spans, pauseAfter: 0.14))
            }
            previousWasWhole = cuts.isEmpty
        }
    }
    if !result.isEmpty { result[result.count - 1].pauseAfter = 0.42 }
    return result
}

func utterances(_ lines: [ScreenLine], in range: Range<Int>) -> [Utterance] {
    paragraphRanges(lines, in: range).flatMap { utterances(lines, paragraph: $0) }
}

/// A sentence on screen that the reader can jump to.
struct JumpSentence: Equatable {
    let text: String
    let line: Int
    let offset: Int
    let boxes: [CGRect]
}

func jumpSentences(_ lines: [ScreenLine]) -> [JumpSentence] {
    utterances(lines, in: 0..<lines.count).compactMap { unit in
        guard let first = unit.spans.first else { return nil }
        let boxes = unit.spans.map { span -> CGRect in
            let box = lines[span.line].box
            let count = CGFloat(max(lines[span.line].text.count, 1))
            return CGRect(x: box.minX + box.width * CGFloat(span.from) / count, y: box.minY, width: box.width * CGFloat(span.to - span.from) / count, height: box.height)
        }
        return JumpSentence(text: unit.text, line: first.line, offset: first.from, boxes: boxes)
    }
}

/// Finds the sentence closest to a point given as fractions of the reading area.
func sentence(at point: CGPoint, in sentences: [JumpSentence]) -> Int? {
    func distance(_ item: JumpSentence) -> CGFloat {
        item.boxes.map { box in
            let across = max(box.minX - point.x, 0, point.x - box.maxX)
            let down = max(box.minY - point.y, 0, point.y - box.maxY)
            return across * across + down * down * 16
        }.min() ?? .greatestFiniteMagnitude
    }
    return sentences.indices.min { distance(sentences[$0]) < distance(sentences[$1]) }
}

/// Everything on screen from the chosen sentence onward, starting partway along its first line.
func linesToRead(from target: JumpSentence, in lines: [ScreenLine]) -> [ScreenLine] {
    var chosen = Array(lines[target.line...])
    let share = CGFloat(target.offset) / CGFloat(max(chosen[0].text.count, 1))
    chosen[0].text = String(chosen[0].text.dropFirst(target.offset))
    chosen[0].box.origin.x += chosen[0].box.width * share
    chosen[0].box.size.width *= 1 - share
    return chosen
}

/// Forgets what was read after the chosen line, so jumping back reads it again, and skips what sits above it.
func seenBeforeJump(_ history: [String], line: Int, in lines: [ScreenLine]) -> [String] {
    let later = Set(lines[line...].map { normalized($0.text) }.filter { $0.count >= 16 })
    let cut = history.firstIndex { later.contains(normalized($0)) } ?? history.count
    return Array(history[..<cut]) + lines[...line].map(\.text)
}

let numberPattern = try! NSRegularExpression(pattern: #"\d[\d,]*(?:\.\d+)?"#)

func numbers(in text: String) -> Set<String> {
    let range = NSRange(text.startIndex..., in: text)
    return Set(numberPattern.matches(in: text, range: range).compactMap {
        Range($0.range, in: text).map { text[$0].replacingOccurrences(of: ",", with: "") }
    })
}

/// Applies Claude's direction. Rewritten text containing a number absent from the screen is read as shown.
func utterances(plan: ReadingPlan, units: [Utterance]) -> [Utterance] {
    let moods: Set<String> = ["neutral", "measured", "building", "turning", "doubtful", "warm", "tender", "somber", "quiet"]
    return plan.items.flatMap { item -> [Utterance] in
        let last = item.through ?? item.unit
        guard item.unit >= 0, item.unit <= last, last < units.count else { return [] }
        let covered = Array(units[item.unit...last])
        let delivery = Delivery(
            mood: moods.contains(item.mood ?? "") ? item.mood! : "neutral",
            speaker: ["woman", "man"].contains(item.speaker ?? "") ? item.speaker! : "narrator",
            emphasis: item.emphasis ?? []
        )
        let source = covered.map(\.text).joined(separator: " ")
        if let say = item.say?.trimmingCharacters(in: .whitespacesAndNewlines), !say.isEmpty, numbers(in: say).isSubset(of: numbers(in: source)) {
            let spans = covered.flatMap(\.spans)
            return sentences(in: String(say.dropFirst(speakerLabelLength(in: say)))).map {
                Utterance(text: $0, spans: spans, pauseAfter: covered.last?.pauseAfter ?? 0.14, delivery: delivery)
            }
        }
        return covered.map { unit in
            var directed = unit
            directed.delivery = delivery
            return directed
        }
    }
}

func dialogueVoice(for speaker: String, narrator: String) -> String {
    switch speaker {
    case "woman": return narrator == "af_bella" ? "af_heart" : "af_bella"
    case "man": return narrator == "am_michael" ? "bm_george" : "am_michael"
    default: return narrator
    }
}

/// Shifts a clip's pitch without changing its speed, then trims the silence the shift adds.
func clip(_ url: URL, shiftedBy cents: Float) throws -> URL {
    guard cents != 0 else { return url }
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let shift = AVAudioUnitTimePitch()
    shift.pitch = cents
    engine.attach(player)
    engine.attach(shift)
    engine.connect(player, to: shift, format: format)
    engine.connect(shift, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try engine.start()
    player.scheduleFile(file, at: nil)
    player.play()
    guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else { return url }
    var samples: [Float] = []
    while engine.manualRenderingSampleTime < file.length + 8192 {
        let frames = min(AVAudioFrameCount(file.length + 8192 - engine.manualRenderingSampleTime), buffer.frameCapacity)
        guard try engine.renderOffline(frames, to: buffer) == .success, let channel = buffer.floatChannelData?[0] else { break }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
    engine.stop()
    guard let first = samples.firstIndex(where: { abs($0) > 0.004 }), let last = samples.lastIndex(where: { abs($0) > 0.004 }) else { return url }
    let rate = Int(format.sampleRate)
    let kept = Array(samples[max(0, first - rate * 3 / 100)..<min(samples.count, last + rate * 6 / 100)])
    guard let trimmed = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(kept.count)) else { return url }
    trimmed.frameLength = AVAudioFrameCount(kept.count)
    kept.withUnsafeBufferPointer { trimmed.floatChannelData?[0].update(from: $0.baseAddress!, count: kept.count) }
    let target = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".wav")
    let output = try AVAudioFile(forWriting: target, settings: format.settings)
    try output.write(from: trimmed)
    try? FileManager.default.removeItem(at: url)
    return target
}

func sentences(in text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap {
        let sentence = text[$0].trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nil : sentence
    }
}

/// Voices offered in the purpose box. Auto picks one to suit what is being read.
let voiceChoices: [(title: String, voice: String?, sample: String)] = [
    ("Auto", nil, "I'll pick a voice to suit what you're reading."),
    ("Woman (US)", "af_heart", "Hi, I'm Heart. I'll read to you like this."),
    ("Woman (UK)", "bf_emma", "Hello, I'm Emma. Shall I read this for you?"),
    ("Man (US)", "am_michael", "Hey, I'm Michael. Here's how I sound."),
    ("Man (UK)", "bm_george", "Good evening, I'm George. Let's begin."),
]

func voice(for material: String) -> String {
    ["case": "bf_emma", "news": "af_heart", "novel": "bm_george"][material] ?? "af_heart"
}

struct RecognitionTimedOut: Error {}

/// Makes sure a waiting task is resumed exactly once, whichever result arrives first.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}

/// Text recognition can wait on the main thread, so running it there would freeze the whole app.
func recognizeLines(in image: CGImage) async throws -> [ScreenLine] {
    let request = VNRecognizeTextRequest()
    let once = ResumeOnce()
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let lines = try recognizeLinesNow(in: image, using: request)
                if once.claim() { continuation.resume(returning: lines) }
            } catch {
                if once.claim() { continuation.resume(throwing: error) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            guard once.claim() else { return }
            request.cancel()
            continuation.resume(throwing: RecognitionTimedOut())
        }
    }
}

func recognizeLinesNow(in image: CGImage, using request: VNRecognizeTextRequest = VNRecognizeTextRequest()) throws -> [ScreenLine] {
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: image).perform([request])
    return tableAware((request.results ?? []).compactMap { observation in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let box = observation.boundingBox
        return ScreenLine(text: candidate.string, box: box, touchesTop: box.maxY > 0.985, touchesBottom: box.minY < 0.015, confidence: candidate.confidence)
    })
}
