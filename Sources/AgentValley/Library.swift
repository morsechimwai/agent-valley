import Foundation

/// One project's books on the Library page.
struct Shelf: Equatable {
    let key: String
    let name: String
    let books: [BookSummary]
    let newCount: Int
    let last: Date
    let checkouts: [String]
}

enum Library {
    /// How long a shelf whose folders are all gone stays in the database before its rows go.
    static let keepMissing: TimeInterval = 30 * 24 * 3600

    /// Books on shelves by project, named as History names them; newest shelf first, books newest first.
    static func shelves(_ books: [BookSummary], home: String, checkouts: [String: String], remotes: [String: String]) -> [Shelf] {
        // ponytail: no folder-rename joining (`moves`); a renamed folder makes a new shelf.
        var placed: [String: Projects.Place] = [:]
        var lastUsed: [String: Date] = [:]
        for book in books {
            placed[book.folder] = placed[book.folder]
                ?? Projects.place(of: book.folder, home: home, checkouts: checkouts, remotes: remotes)
            lastUsed[book.folder] = max(lastUsed[book.folder] ?? .distantPast, book.last)
        }
        let names = Projects.names(placed, lastUsed: lastUsed)
        return Dictionary(grouping: books, by: { placed[$0.folder]!.key }).map { key, group in
            let sorted = group.sorted { $0.last > $1.last }
            // A key that is a folder is the checkout `place` worked out, for folders git was never asked about.
            let own = key.hasPrefix("/") ? [key] : []
            return Shelf(key: key, name: names[key] ?? key, books: sorted, newCount: sorted.reduce(0) { $0 + $1.newCount },
                         last: sorted[0].last, checkouts: Set(sorted.map { checkouts[$0.folder] ?? $0.folder } + own).sorted())
        }.sorted { $0.last != $1.last ? $0.last > $1.last : $0.key < $1.key }
    }

    /// The fixed places `Projects.place` hands out: they are no folder that can go missing.
    static func isBucket(_ shelf: Shelf) -> Bool {
        [Projects.scratch, Projects.temporary, Projects.supersetSessions, Projects.unknown, "~"].contains(shelf.key)
    }

    /// Missing marks to set (key to the day it was first seen gone), marks to clear (sorted), keys to delete now, and the shelves to show.
    /// A key is deleted 30 days after the later of its mark and its last book; the caller clears the mark of what it deleted.
    static func sweep(_ shelves: [Shelf], missing: [String: Date], now: Date, exists: (String) -> Bool)
        -> (set: [String: Date], clear: [String], delete: [String], shown: [Shelf]) {
        var set: [String: Date] = [:]
        var clear: [String] = []
        var delete: [String] = []
        var shown: [Shelf] = []
        for shelf in shelves {
            if isBucket(shelf) || shelf.checkouts.contains(where: exists) {
                shown.append(shelf)
                if missing[shelf.key] != nil, !isBucket(shelf) { clear.append(shelf.key) }
            } else if let since = missing[shelf.key] {
                // A hand-back after the mark proves the folder was there then.
                if now.timeIntervalSince(max(since, shelf.last)) >= keepMissing { delete.append(shelf.key) }
            } else {
                set[shelf.key] = now
            }
        }
        return (set, clear.sorted(), delete, shown)
    }
}
