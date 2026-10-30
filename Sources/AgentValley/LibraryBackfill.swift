import Foundation

extension Chapter {
    /// One chapter per hand-back a sub-agent's transcript has made. Live ingest and backfill share this.
    static func from(_ info: AgentInfo, agent: String, session: String) -> [Chapter] {
        info.records.map {
            Chapter(agent: agent, session: session, folder: info.cwd, type: info.type,
                    title: info.fullTask.isEmpty ? info.task : info.fullTask,
                    asked: $0.asked, text: $0.text, at: $0.at)
        }
    }
}

/// Reads the transcripts still on disk into the library: all of them once, so old work shows up
/// too, then at each launch those that moved while the app was not running.
enum LibraryBackfill {
    static let queue = DispatchQueue(label: "agent-valley.library-backfill", qos: .utility)

    /// Reads every sub-agent transcript under `root` once, then marks the store backfilled. A store
    /// already backfilled reads only the sub-agent files modified since the app last ran. `done`
    /// fires either way, on `queue`.
    static func run(root: URL, into library: LibraryStore, ledger: URL? = UsageLedger.defaultDatabase,
                    done: @escaping () -> Void = {}) {
        queue.async {
            if !library.backfilled {
                learnPlaces(from: ledger, into: library)
                read(root: root.path, into: library, after: nil)
                library.markBackfilled()
            } else {
                // A minute back: the running app stamps itself at most once a minute.
                read(root: root.path, into: library, after: (library.lastAlive ?? library.since).addingTimeInterval(-60))
            }
            library.markAlive(at: Date())
            done()
        }
    }

    /// Each sub-agent transcript under `root` (with `after`, only those modified since), and the
    /// title of each session that handed something back.
    private static func read(root: String, into library: LibraryStore, after cutoff: Date?) {
        var folders = Set<String>()
        var titled = Set<String>()
        let names = FileManager.default.enumerator(atPath: root)?.compactMap { $0 as? String } ?? []
        for name in names where name.hasSuffix(".jsonl") {
            let path = root + "/" + name
            guard case .sub(let key)? = AgentStore.classify(path, root: root) else { continue }
            if let cutoff {
                let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
                guard let modified, modified >= cutoff else { continue }
            }
            var info = AgentInfo()
            guard let handle = FileHandle(forReadingAtPath: path) else { continue }
            _ = TranscriptReader.readLines(from: handle) { TranscriptReader.apply(line: $0, to: &info) }
            try? handle.close()
            if let meta = FileManager.default.contents(atPath: String(path.dropLast(".jsonl".count)) + ".meta.json") {
                _ = TranscriptReader.applyMeta(meta, to: &info)
            }
            let session = (key as NSString).lastPathComponent
            library.add(Chapter.from(info, agent: path, session: session))
            guard !info.records.isEmpty else { continue }
            if !info.cwd.isEmpty { folders.insert(info.cwd) }
            // The book's title is in the session's main transcript, beside its folder.
            if titled.insert(key).inserted, let title = mainTitle(path: key + ".jsonl", session: session) {
                library.title(session: title.session, title.title)
            }
        }
        let known = library.places()
        for folder in folders where known.checkouts[folder] == nil { library.learn(gitFolder: folder) }
    }

    /// The last `ai-title` line in a main transcript wins; only lines that say so are parsed.
    private static func mainTitle(path: String, session: String) -> (session: String, title: String)? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var found: (session: String, title: String)?
        _ = TranscriptReader.readLines(from: handle) {
            if let title = UsageLedger.title(fromLine: $0, session: session) { found = title }
        }
        return found
    }

    /// Folder to checkout to remote, as the usage ledger learned them. A missing or broken file adds nothing.
    private static func learnPlaces(from ledger: URL?, into library: LibraryStore) {
        // The wrapper creates a file that is not there, so a missing ledger is not opened at all.
        guard let ledger, FileManager.default.fileExists(atPath: ledger.path), let db = try? SQLite(path: ledger.path),
              let rows = try? db.rows("SELECT c.folder, c.checkout, r.remote FROM checkouts c LEFT JOIN remotes r ON r.checkout = c.checkout")
        else { return }
        for row in rows {
            library.learn(folder: row[0].text, checkout: row[1].text, remote: row[2] == .null ? nil : row[2].text)
        }
    }
}
