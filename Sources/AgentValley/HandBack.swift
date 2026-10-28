import Foundation

/// What a lead asked a sub-agent and what came back, kept whole: line breaks stay, unlike `TranscriptReader.clipped`.
enum HandBack {
    static let askedLimit = 4096
    static let resultLimit = 8192

    /// `text` trimmed of surrounding whitespace, cut to `limit` characters and ended with `…` when longer.
    static func kept(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    /// How long a hand-back nobody looked at stays listed.
    static let hold: TimeInterval = 24 * 3600

    /// How much longer than the panel's own look a document stays in sight in an open book
    /// before it counts as seen, about five seconds in all: a pointer passing over the notch
    /// opens the panel for a second, and what it showed then was not read. Seen, it is no longer new.
    static let lookLonger: TimeInterval = 4

    /// Ids of the sub-agent rows whose hand-back awaits a look. A lead's own ended turn hands
    /// nothing back: the reader stamps every file's, the main transcript's too.
    static func awaiting(_ sessions: [SessionCard]) -> Set<String> {
        Set(sessions.flatMap(\.agents).filter(\.awaitsLook).map(\.id))
    }

    /// Ids of the sessions whose cards stay listed and unfolded: one with a new document in its
    /// book, or one seen in the opening that began at `openedAt`, until the panel shuts: a card
    /// must not fold into "N idle" under the eyes of someone reading it.
    static func holding(_ sessions: [SessionCard], openedAt: Date?) -> Set<String> {
        Set(sessions.filter { card in card.agents.contains { fresh($0, openedAt: openedAt) } }.map(AnswerStore.sessionID(of:)))
    }

    /// A hand-back that awaits a look, or was seen in the opening that began at `openedAt`.
    private static func fresh(_ row: AgentRow, openedAt: Date?) -> Bool {
        row.awaitsLook || openedAt.map { opened in row.handBackSeenAt.map { $0 >= opened } ?? false } ?? false
    }

    /// Ids to mark seen as the awaiting set changes: the arrivals when the person is looking, none otherwise.
    static func toMark(old: Set<String>, new: Set<String>, lookingNow: Bool) -> Set<String> {
        lookingNow ? new.subtracting(old) : []
    }

    /// Ids of the finished sub-agents drawn as a document in the book, newest hand-back first:
    /// every one that handed something back while the book is open, none while it is shut.
    static func boxes(_ card: SessionCard, open: Bool) -> [String] {
        guard open else { return [] }
        return card.agents.filter(\.handsBack).sorted { ($0.info.handedBackAt ?? .distantPast) > ($1.info.handedBackAt ?? .distantPast) }.map(\.id)
    }

    /// The documents in the book nobody has looked at in it yet: "N new" on the shut book.
    static func newCount(_ card: SessionCard) -> Int {
        card.agents.filter(\.awaitsLook).count
    }

    /// A hand-back older than the launch was there before anyone could look: seen at its own time.
    static func seenBeforeLaunch(_ file: TrackedFile, launchedAt: Date) -> TrackedFile {
        guard file.seenAt == nil, let back = file.info.handedBackAt, back < launchedAt else { return file }
        var file = file
        file.seenAt = back
        return file
    }
}
