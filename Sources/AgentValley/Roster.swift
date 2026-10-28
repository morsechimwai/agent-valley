import Foundation

/// Who sits in which session, kept on disk so it holds across launches. Each project has a
/// regular, named by its checkout (out of git, the folder its sessions start in), for good. A
/// session gets the regular while the regular is free, and someone else while the regular is at
/// another of the project's sessions: one person is never in two places. Nobody changes seats for as long as a session
/// lasts. /clear starts a new session at the same desk, and the old one has let go of the
/// regular by then, so the regular stays.
struct Roster: Codable, Equatable {
    struct Seat: Codable, Equatable {
        var look: LeadLook
        var project: String
        /// When the session was last listed, to an hour.
        var seen: Date
        /// True once the session's agent was told its name (`CrewIntro`); nil before, and in
        /// rosters written before this was kept.
        var named: Bool?
    }

    /// Each project's regular, by its checkout, or the folder its sessions start in out of git.
    var regulars: [String: LeadLook] = [:]
    /// Who sits in each session, by session id.
    var seats: [String: Seat] = [:]

    /// Seats every session of `cards` that has no seat yet, oldest first, and gives each card the
    /// look of whoever sits in it. `busy`: whether someone is at a session, by session id.
    mutating func seat(_ cards: [SessionCard], busy: (String) -> Bool, now: Date) -> [SessionCard] {
        for card in cards.sorted(by: { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }) {
            guard let main = card.main else { continue }
            // A worktree sits at its checkout's desk.
            let project = card.git?.checkout ?? (main.info.cwd.isEmpty ? card.project : main.info.cwd)
            _ = seat(session: AnswerStore.sessionID(of: card), project: project, busy: busy, now: now)
        }
        seats = seats.filter { now.timeIntervalSince($0.value.seen) < AgentStore.forgetAfter }
        return cards.map { card in
            var card = card
            card.look = seats[AnswerStore.sessionID(of: card)]?.look
            return card
        }
    }

    /// Who sits in session `id` of `project`, seating it first when it has no seat: the regular
    /// while the regular is free, else someone else. A seated session keeps whoever sits there.
    mutating func seat(session id: String, project: String, busy: (String) -> Bool, now: Date) -> LeadLook {
        if let seat = seats[id] {
            // To the hour: a write a second would be for nothing.
            if now.timeIntervalSince(seat.seen) >= 3600 { seats[id]?.seen = now }
            return seat.look
        }
        let regular = regulars[project] ?? Self.pick(by: project, taken: Array(regulars.values))
        regulars[project] = regular
        let regularIsOut = seats.contains { $0.key != id && $0.value.project == project && $0.value.look == regular && busy($0.key) }
        let look = regularIsOut
            ? Self.pick(by: id, taken: Array(regulars.values) + seats.filter { busy($0.key) }.map(\.value.look))
            : regular
        seats[id] = Seat(look: look, project: project, seen: now)
        return look
    }

    /// Notes that session `id`'s agent was told its name. Seats nobody.
    mutating func markNamed(_ id: String) {
        seats[id]?.named = true
    }

    /// Who sits in each session, by session id: what `crew status` shows in the session's terminal.
    var looks: [String: LeadLook] { seats.mapValues(\.look) }

    /// A look unlike those `taken` while there are faces, hair and shirts enough, counting on
    /// from where the hash of `seed` points. A shirt too close to the hair is never picked while
    /// another is left: the beard would run into it. That comes before the shirt being one
    /// nobody else wears.
    static func pick(by seed: String, taken: [LeadLook]) -> LeadLook {
        let face = pick(Person.leads.count, by: seed + "/face", taken: taken.map(\.face))
        let hair = pick(Person.leadHair.count, by: seed + "/hair", taken: taken.map(\.hair))
        let shirt = pick(Person.leadShirts.count, by: seed, taken: taken.map(\.shirt)) {
            !Person.close(Person.leadHair[hair], Person.leadShirts[$0])
        }
        return LeadLook(face: face, hair: hair, shirt: shirt)
    }

    /// Of `count` choices, the first that the fewest have taken, counting on from where the hash
    /// of `seed` points. Only those `allowed` lets through, while there are any.
    private static func pick(_ count: Int, by seed: String, taken: [Int], allowed: (Int) -> Bool = { _ in true }) -> Int {
        let start = Int(MascotKind.hash(seed) % UInt32(count))
        let order = (0..<count).map { (start + $0) % count }
        let choices = order.contains(where: allowed) ? order.filter(allowed) : order
        return choices.min { one, other in taken.filter { $0 == one }.count < taken.filter { $0 == other }.count } ?? start
    }

    /// The roster in `file`, or an empty one when there is none or it can't be read.
    static func load(_ file: URL) -> Roster {
        (try? Data(contentsOf: file)).flatMap { try? decoder.decode(Roster.self, from: $0) } ?? Roster()
    }

    func save(_ file: URL) throws {
        try Self.encoder.encode(self).write(to: file, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
