import CoreGraphics

/// Which sessions fold to one line when the full list would overflow the panel.
enum ListFit {
    struct Entry: Equatable {
        let id: String
        /// Height as a full card, with the project heading above it and the gap below.
        let full: CGFloat
        /// Height folded to one line, with the same heading and gap.
        let row: CGFloat
        /// Must stay a full card: it asks something of the person.
        let keepsFull: Bool
        /// Quiet or idle: folds before anything that works.
        let quiet: Bool
        /// Has the project heading over it, so a folded row above stands a card's gap away.
        var header = false
        /// Has sub-agents at work: its lines are the picture, so it folds after plain ones.
        var crew = false
    }

    static let row: CGFloat = 30
    /// Between a folded row and a folded row right under it, in place of a card's gap.
    static let rowGap: CGFloat = 4
    /// The list's padding, top and bottom, less the gap under its last line: each height here
    /// counts the gap under it.
    static let padding: CGFloat = 12 * 2 - cardGap
    /// What a line under the list takes, and the frame around the idle line and the hidden
    /// sessions' box.
    private static let underLine: CGFloat = 24
    private static let underBox: CGFloat = 18

    // Fitted to the panel as drawn by testing/pictures.sh (scenes roomy, list, crew and request).
    private static let cardBase: CGFloat = 38
    private static let place: CGFloat = 19
    private static let cardGap: CGFloat = 10
    private static let stepLine: CGFloat = 22
    private static let permission: CGFloat = 93
    private static let question: CGFloat = 69
    private static let option: CGFloat = 52
    private static let hintLine: CGFloat = 22
    private static let outcomeLine: CGFloat = 26
    private static let wayToAnswer: CGFloat = 34
    private static let agentRow: CGFloat = 43
    /// A sub-agent on one line, and a done line under the book.
    static let agentLine: CGFloat = 24
    /// The book's own line, "N done".
    private static let doneLine: CGFloat = 32
    /// The Asked box: its padding, its label line and the text up to `AskedBox.maxHeight`. An
    /// estimate from the box's layout: the picture check calibrates it.
    // ponytail: always the capped 120 pt of text: exact for the usual long prompt, a short one only folds
    // other cards a little early. Estimate the text's line count when short prompts matter.
    static let askedBox: CGFloat = 8 * 2 + 14 + CardStyle.line + AskedBox.maxHeight + CardStyle.block
    /// A hand-back box under the book: its padding, the header line, two lines of what came
    /// back and the Read all line. An estimate from the box's layout, as `askedBox` is.
    // ponytail: always two lines of text: a one-line hand-back only folds other cards a little early.
    static let handBackBox: CGFloat = 8 * 2 + textLine + CardStyle.line + 2 * textLine + CardStyle.line + textLine + CardStyle.block
    /// The same box read whole: the header, one scroll with what it was asked and what came
    /// back up to `HandBackBox.maxHeight`, and the Show less line.
    // ponytail: always the capped 240 pt: exact for the long hand-back worth reading whole, a short one
    // only folds other cards a little early. Estimate the lines when short ones matter.
    static let readAllBox: CGFloat = 8 * 2 + textLine + CardStyle.line + HandBackBox.maxHeight + CardStyle.line + textLine + CardStyle.block
    /// A line of the panel's own text.
    private static let textLine: CGFloat = 15
    private static let header: CGFloat = 28
    private static let jobLine: CGFloat = 17

    /// The ids to fold: quiet ones from the bottom up, then working ones from the bottom up,
    /// those with a crew last, stopping as soon as the list fits. Cards that keep full are never folded, nor is one
    /// taller than the room: folded, it would leave the panel near empty.
    static func compact(_ entries: [Entry], room: CGFloat) -> Set<String> {
        guard height(entries, folded: []) > room else { return [] }
        let candidates = entries.filter { !$0.keepsFull && $0.full <= room }.reversed()
        var folded: Set<String> = []
        let working = candidates.filter { !$0.quiet }
        for e in candidates.filter(\.quiet) + working.filter { !$0.crew } + working.filter(\.crew) {
            folded.insert(e.id)
            if height(entries, folded: folded) <= room { break }
        }
        return folded
    }

    /// The list's height with these folded: a folded row with another right under it, no
    /// heading between, stands closer to it than a card does.
    static func height(_ entries: [Entry], folded: Set<String>) -> CGFloat {
        entries.indices.reduce(0) { total, i in
            let e = entries[i]
            guard folded.contains(e.id) else { return total + e.full }
            let next = i + 1 < entries.count ? entries[i + 1] : nil
            let closer = next.map { folded.contains($0.id) && !$0.header } ?? false
            return total + e.row - (closer ? cardGap - rowGap : 0)
        }
    }

    /// What the lines under the list take from it: the idle line, the hidden sessions' box
    /// with a line for each and one more for all of them when there are several, and plain
    /// lines such as the token line and the notices.
    static func under(idle: Bool, hidden: Int, plain: Int) -> CGFloat {
        let lines = (idle ? 1 : 0) + (hidden > 1 ? hidden + 1 : hidden) + plain
        let boxes = (idle ? 1 : 0) + (hidden > 0 ? 1 : 0)
        return underLine * CGFloat(lines) + underBox * CGFloat(boxes)
    }

    /// A request's height from its structure: a question by its options, anything else, or one
    /// put away, as a permission request.
    static func requestHeight(_ kind: Ask.Kind, hidden: Bool) -> CGFloat {
        guard !hidden, case .question(_, _, let options) = kind else { return permission }
        return question + CGFloat(options.count) * option
    }

    /// A card's height from its structure alone: never from text, time or step count. `requests`
    /// gives the height of each request under a row, `settled` how many lines under it say what
    /// became of one, and `hintRow` is the row with the list's line explaining "quiet". `boxes` are
    /// the done agents drawn as a hand-back box, `reading` those read whole.
    static func fullHeight(_ card: SessionCard, header hasHeader: Bool, requests: (String) -> [CGFloat], settled: (String) -> Int,
                           hintRow: String?, showingDone: Bool, oneLineAgents: Bool, asked: Set<String> = [],
                           boxes: [String] = [], reading: Set<String> = []) -> CGFloat {
        var h = cardBase + place + cardGap
        // The jobs it left running: three lines at most, then one that says how many more.
        if !card.jobs.isEmpty { h += CGFloat(min(card.jobs.count, 3) + (card.jobs.count > 3 ? 1 : 0)) * jobLine + CardStyle.block - CardStyle.line }
        if let main = card.main, main.status != .done, requests(main.id).isEmpty, !main.step.isEmpty { h += stepLine }
        // Its task list: up to five lines, each as tall as a job's.
        if let tasks = card.taskLines { h += CGFloat(tasks.lines) * jobLine + CardStyle.block - CardStyle.line }
        for r in card.rows {
            let asked = requests(r.id)
            h += asked.reduce(0, +) + CGFloat(settled(r.id)) * outcomeLine
            if r.status == .needsYou && asked.isEmpty { h += wayToAnswer }
            if r.id == hintRow { h += hintLine }
        }
        h += CGFloat(card.liveAgents().count) * (oneLineAgents ? agentLine : agentRow)
        h += CGFloat(card.liveAgents().filter { asked.contains($0.id) }.count) * askedBox
        // In an open book a document each, and a line each for those that handed nothing back. Shut, nothing.
        let done = card.doneAgents()
        if !done.isEmpty { h += doneLine }
        for row in done where showingDone {
            h += boxes.contains(row.id) ? (reading.contains(row.id) ? readAllBox : handBackBox) : agentLine
        }
        return hasHeader ? h + header : h
    }

    /// A folded row's height, with its heading and a card's gap under it.
    static func rowHeight(header hasHeader: Bool) -> CGFloat { row + cardGap + (hasHeader ? header : 0) }
}
