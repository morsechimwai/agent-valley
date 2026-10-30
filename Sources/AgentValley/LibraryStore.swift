import Foundation

/// One hand-back from a sub-agent, kept whole.
struct Chapter: Equatable {
    let agent: String      // sub-agent transcript path, the TrackedFile key
    let session: String    // Claude Code session id
    let folder: String     // the sub-agent's cwd
    let type: String       // agent type, as in AgentInfo.type
    let title: String      // full task description
    let asked: String      // whole message that led to this hand-back
    let text: String       // whole hand-back
    let at: Date           // when it was handed back
    var seenAt: Date?
}

/// A session's chapters, in one line for the shelf.
struct BookSummary: Equatable {
    let session: String
    let title: String
    let folder: String
    let chapters: Int
    let newCount: Int
    let last: Date
    let types: [String]
}

/// The library's database: hand-backs kept for good, and what has been read. Always on; every
/// call runs on one queue because `SQLite` belongs to one thread. A call that fails does nothing
/// and reads as empty: the library is a convenience, never a reason to stop the notch.
final class LibraryStore {
    static var defaultDatabase: URL {
        AnswerServer.defaultDirectory.appendingPathComponent("library.sqlite")
    }

    private let queue = DispatchQueue(label: "agentvalley.library")
    private let db: SQLite
    private let now: () -> Date
    /// The first moment this database was made. Chapters from before it count as already read.
    let since: Date
    /// When the app was last known running, as the database stood when opened: the launch reads
    /// what was handed back after it. Nil before the first stamp.
    let lastAlive: Date?

    init(database: URL = LibraryStore.defaultDatabase, now: @escaping () -> Date = Date.init) throws {
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let made: SQLite
        do {
            made = try Self.prepare(database.path)
        } catch let error as SQLiteError where error.isBroken {
            let aside = database.path + ".broken-" + Self.stamp(now())
            try FileManager.default.moveItem(atPath: database.path, toPath: aside)
            made = try Self.prepare(database.path)
        }
        self.db = made
        self.now = now
        try made.rows("INSERT OR IGNORE INTO meta VALUES ('since', ?)", [.real(now().timeIntervalSince1970)])
        self.since = Date(timeIntervalSince1970: try made.rows("SELECT value FROM meta WHERE key = 'since'").first?[0].real ?? 0)
        self.lastAlive = try made.rows("SELECT value FROM meta WHERE key = 'alive'").first.map { Date(timeIntervalSince1970: $0[0].real) }
    }

    private static func prepare(_ path: String) throws -> SQLite {
        let db = try SQLite(path: path)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value);
            CREATE TABLE IF NOT EXISTS chapters (
                agent TEXT NOT NULL, at REAL NOT NULL, session TEXT NOT NULL, folder TEXT NOT NULL, type TEXT NOT NULL,
                title TEXT NOT NULL, asked TEXT NOT NULL, text TEXT NOT NULL, seen REAL,
                PRIMARY KEY (agent, at));
            CREATE INDEX IF NOT EXISTS chapters_session ON chapters (session, at);
            CREATE TABLE IF NOT EXISTS books (session TEXT PRIMARY KEY, title TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS places (folder TEXT PRIMARY KEY, checkout TEXT, remote TEXT);
            CREATE TABLE IF NOT EXISTS missing (key TEXT PRIMARY KEY, since REAL NOT NULL);
            PRAGMA user_version = 1;
            """)
        return db
    }

    private static func stamp(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd-HHmmss"
        return format.string(from: date)
    }

    private func date(_ value: SQLValue) -> Date { Date(timeIntervalSince1970: value.real) }
    private func stamp(_ date: Date?) -> SQLValue { date.map { .real($0.timeIntervalSince1970) } ?? .null }

    // MARK: Filled once

    /// Whether the old transcripts were already read into the library.
    var backfilled: Bool {
        queue.sync { ((try? db.rows("SELECT 1 FROM meta WHERE key = 'backfilled'")) ?? []).isEmpty == false }
    }

    func markBackfilled() {
        queue.sync { _ = try? db.rows("INSERT OR IGNORE INTO meta VALUES ('backfilled', 1)") }
    }

    /// The app is running at `date`. Read back as `lastAlive` by the next launch.
    func markAlive(at date: Date) {
        queue.sync { _ = try? db.rows("INSERT OR REPLACE INTO meta VALUES ('alive', ?)", [stamp(date)]) }
    }

    // MARK: Chapters

    /// Keeps each chapter once, by agent and time. One from before `since` is stored as read.
    /// All or none: false when they could not be written, so the caller can keep them for another try.
    @discardableResult
    func add(_ chapters: [Chapter]) -> Bool {
        queue.sync {
            do {
                try db.execute("BEGIN")
                for chapter in chapters {
                    let seen = chapter.seenAt ?? (chapter.at < since ? chapter.at : nil)
                    _ = try db.rows("INSERT OR IGNORE INTO chapters VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                    [.text(chapter.agent), stamp(chapter.at), .text(chapter.session), .text(chapter.folder),
                                     .text(chapter.type), .text(chapter.title), .text(chapter.asked), .text(chapter.text), stamp(seen)])
                }
                try db.execute("COMMIT")
                return true
            } catch {
                try? db.execute("ROLLBACK")
                return false
            }
        }
    }

    func title(session: String, _ title: String) {
        queue.sync {
            _ = try? db.rows("INSERT INTO books VALUES (?, ?) ON CONFLICT(session) DO UPDATE SET title = excluded.title",
                             [.text(session), .text(title)])
        }
    }

    /// Marks as read what these agents handed back at or before `at`.
    func saw(agents: Set<String>, at: Date) {
        queue.sync {
            for agent in agents {
                _ = try? db.rows("UPDATE chapters SET seen = ? WHERE agent = ? AND seen IS NULL AND at <= ?",
                                 [stamp(at), .text(agent), stamp(at)])
            }
        }
    }

    func seenMarks() -> [String: Date] {
        queue.sync {
            let rows = (try? db.rows("SELECT agent, max(seen) FROM chapters WHERE seen IS NOT NULL GROUP BY agent")) ?? []
            return Dictionary(rows.map { ($0[0].text, date($0[1])) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func unseenAgents(since: Date) -> [String] {
        queue.sync {
            ((try? db.rows("SELECT DISTINCT agent FROM chapters WHERE seen IS NULL AND at >= ? ORDER BY agent", [stamp(since)])) ?? [])
                .map { $0[0].text }
        }
    }

    /// Newest book first. "New" is unseen and handed back within the hold.
    func books() -> [BookSummary] {
        queue.sync {
            let fresh = now().addingTimeInterval(-HandBack.hold)
            let rows = (try? db.rows("""
                SELECT c.session, COALESCE(b.title, ''), c.folder, c.type, c.at, c.seen
                FROM chapters c LEFT JOIN books b ON b.session = c.session ORDER BY c.at
                """)) ?? []
            var order: [String] = []
            var made: [String: BookSummary] = [:]
            for row in rows {
                let session = row[0].text, at = date(row[4])
                let new = row[5] == .null && at >= fresh ? 1 : 0
                let old = made[session]
                if old == nil { order.append(session) }
                var types = old?.types ?? []
                if !types.contains(row[3].text) { types.append(row[3].text) }
                made[session] = BookSummary(session: session, title: row[1].text, folder: row[2].text,
                                            chapters: (old?.chapters ?? 0) + 1, newCount: (old?.newCount ?? 0) + new,
                                            last: at, types: types)
            }
            return order.compactMap { made[$0] }.sorted { $0.last > $1.last }
        }
    }

    /// Oldest first.
    func chapters(session: String) -> [Chapter] {
        queue.sync {
            ((try? db.rows("SELECT agent, session, folder, type, title, asked, text, at, seen FROM chapters WHERE session = ? ORDER BY at, agent",
                           [.text(session)])) ?? []).map {
                Chapter(agent: $0[0].text, session: $0[1].text, folder: $0[2].text, type: $0[3].text, title: $0[4].text,
                        asked: $0[5].text, text: $0[6].text, at: date($0[7]), seenAt: $0[8] == .null ? nil : date($0[8]))
            }
        }
    }

    /// The earliest hand-back kept.
    func oldest() -> Date? {
        queue.sync {
            guard let row = (try? db.rows("SELECT min(at) FROM chapters"))?.first, row[0] != .null else { return nil }
            return date(row[0])
        }
    }

    // MARK: Places

    /// The first answer for a folder wins.
    func learn(folder: String, checkout: String?, remote: String?) {
        queue.sync {
            _ = try? db.rows("INSERT OR IGNORE INTO places VALUES (?, ?, ?)",
                             [.text(folder), checkout.map { .text($0) } ?? .null, remote.map { .text($0) } ?? .null])
        }
    }

    /// The checkout git says `folder` sits in, and its remote. A folder that is gone, or in no
    /// repository, is not kept, so a later answer still counts.
    func learn(gitFolder folder: String) {
        guard FileManager.default.fileExists(atPath: folder), let place = AgentStore.gitPlace(of: folder) else { return }
        learn(folder: folder, checkout: place.checkout, remote: Projects.remote(of: place.checkout))
    }

    /// Folders to their checkouts, and checkouts to their remotes, as `Projects.place` takes them.
    func places() -> (checkouts: [String: String], remotes: [String: String]) {
        queue.sync {
            var checkouts: [String: String] = [:], remotes: [String: String] = [:]
            for row in (try? db.rows("SELECT folder, checkout, remote FROM places")) ?? [] {
                if row[1] != .null { checkouts[row[0].text] = row[1].text }
                if row[1] != .null, row[2] != .null { remotes[row[1].text] = row[2].text }
            }
            return (checkouts, remotes)
        }
    }

    func missing() -> [String: Date] {
        queue.sync {
            Dictionary(((try? db.rows("SELECT key, since FROM missing")) ?? []).map { ($0[0].text, date($0[1])) },
                       uniquingKeysWith: { first, _ in first })
        }
    }

    func setMissing(_ key: String, since: Date?) {
        queue.sync {
            if let since {
                _ = try? db.rows("INSERT OR REPLACE INTO missing VALUES (?, ?)", [.text(key), stamp(since)])
            } else {
                _ = try? db.rows("DELETE FROM missing WHERE key = ?", [.text(key)])
            }
        }
    }

    /// Deletes these sessions' books: every chapter, whichever folder it was written in, and the title.
    func forget(sessions: [String]) {
        queue.sync {
            for session in sessions {
                _ = try? db.rows("DELETE FROM chapters WHERE session = ?", [.text(session)])
                _ = try? db.rows("DELETE FROM books WHERE session = ?", [.text(session)])
            }
        }
    }
}
