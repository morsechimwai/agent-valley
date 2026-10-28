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

    /// Ids of the sub-agent rows whose hand-back awaits a look. A lead's own ended turn hands
    /// nothing back: the reader stamps every file's, the main transcript's too.
    static func awaiting(_ sessions: [SessionCard]) -> Set<String> {
        Set(sessions.flatMap(\.agents).filter(\.awaitsLook).map(\.id))
    }

    /// Ids of the sessions that draw a hand-back box in the opening that began at `openedAt`: one
    /// awaiting a look, or seen in this opening. Their cards stay listed and unfolded until the
    /// panel shuts. A line opened to read whole does not count: one clicked in the unfolded idle
    /// list would pull its card out of that list.
    static func holding(_ sessions: [SessionCard], openedAt: Date?) -> Set<String> {
        Set(sessions.filter { !boxes($0, openedAt: openedAt).isEmpty }.map(AnswerStore.sessionID(of:)))
    }

    /// Ids to mark seen as the awaiting set changes: the arrivals when the person is looking, none otherwise.
    static func toMark(old: Set<String>, new: Set<String>, lookingNow: Bool) -> Set<String> {
        lookingNow ? new.subtracting(old) : []
    }

    /// Boxes a card shows of its own accord: a lead sends out five to eight sub-agents at once, and
    /// a box each would run the card off the panel. The rest are lines from the start.
    static let maxBoxes = 2

    /// Ids of the finished sub-agents drawn as a box under the envelope, newest hand-back first:
    /// the newest `maxBoxes` that await a look or were seen in the opening that began at
    /// `openedAt` (it does not shrink while read), and any the person opened to read whole.
    static func boxes(_ card: SessionCard, openedAt: Date?, reading: Set<String> = []) -> [String] {
        let done = card.agents.filter(\.handsBack).sorted { ($0.info.handedBackAt ?? .distantPast) > ($1.info.handedBackAt ?? .distantPast) }
        let fresh = done.filter { row in
            row.awaitsLook || openedAt.map { opened in row.handBackSeenAt.map { $0 >= opened } ?? false } ?? false
        }.prefix(maxBoxes).map(\.id)
        return done.map(\.id).filter { fresh.contains($0) || reading.contains($0) }
    }

    /// A hand-back older than the launch was there before anyone could look: seen at its own time.
    static func seenBeforeLaunch(_ file: TrackedFile, launchedAt: Date) -> TrackedFile {
        guard file.seenAt == nil, let back = file.info.handedBackAt, back < launchedAt else { return file }
        var file = file
        file.seenAt = back
        return file
    }
}
