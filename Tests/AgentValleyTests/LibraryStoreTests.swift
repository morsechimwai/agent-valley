import XCTest
@testable import AgentValley

final class LibraryStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func path() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-valley-library-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("library.sqlite")
    }

    /// A store made 48 h before `t0`, so chapters near `t0` are after `since`.
    private func store(_ file: URL, now: Date? = nil) throws -> LibraryStore {
        try LibraryStore(database: file, now: { now ?? self.t0.addingTimeInterval(-48 * 3600) })
    }

    private func chapter(_ agent: String, session: String = "s", at: Date, seen: Date? = nil, folder: String = "/a", type: String = "Explore") -> Chapter {
        Chapter(agent: agent, session: session, folder: folder, type: type, title: "T", asked: "Q", text: "A", at: at, seenAt: seen)
    }

    // The watcher sees the same transcript again and again; a chapter must not double.
    func testTheSameHandBackIsKeptOnce() throws {
        let s = try store(path())
        s.add([chapter("a", at: t0)])
        s.add([chapter("a", at: t0)])
        XCTAssertEqual(s.chapters(session: "s").count, 1)
    }

    // "Before this version" has to mean the first day, not whenever the app last started.
    func testSinceIsSetOnceAndKept() throws {
        let file = path()
        let first = try store(file).since
        let later = try store(file, now: t0).since
        XCTAssertEqual(first, t0.addingTimeInterval(-48 * 3600))
        XCTAssertEqual(later, first)
    }

    // A quit and restart must not bring old hand-backs back as new.
    func testSeenMarksSurviveAReopen() throws {
        let file = path()
        let s = try store(file)
        s.add([chapter("a", at: t0)])
        s.saw(agents: ["a"], at: t0)
        XCTAssertEqual(try store(file).seenMarks()["a"], t0)
    }

    // Looking at the notch must not swallow a hand-back that lands afterwards.
    func testSeeingDoesNotMarkALaterHandBack() throws {
        let s = try store(path())
        let t1 = t0, t2 = t0.addingTimeInterval(10), t3 = t0.addingTimeInterval(20)
        s.add([chapter("a", at: t1), chapter("a", at: t3)])
        s.saw(agents: ["a"], at: t2)
        XCTAssertEqual(s.chapters(session: "s").map(\.seenAt), [t2, nil])
    }

    // Only recent, unread hand-backs may raise the "new" dot.
    func testUnseenAgentsSkipsOldAndSeen() throws {
        let s = try store(path())
        s.add([chapter("first", at: t0.addingTimeInterval(-2 * 3600)),
               chapter("old", at: t0.addingTimeInterval(-30 * 3600)),
               chapter("read", at: t0.addingTimeInterval(-3600), seen: t0)])
        XCTAssertEqual(s.unseenAgents(since: t0.addingTimeInterval(-HandBack.hold)), ["first"])
    }

    // The shelf shows how many chapters and how many are new, under the session's title.
    func testBooksCountChaptersAndNew() throws {
        let s = try store(path())
        let a = t0.addingTimeInterval(-3600), b = t0.addingTimeInterval(-1800)
        s.add([chapter("a", at: a, seen: a), chapter("b", at: b), chapter("c", session: "z", at: a)])
        s.title(session: "s", "First")
        let books = s.books()
        XCTAssertEqual(books.map(\.session), ["s", "z"])
        XCTAssertEqual(books[0], BookSummary(session: "s", title: "First", folder: "/a", chapters: 2, newCount: 1, last: b, types: ["Explore"]))
        XCTAssertEqual([books[1].chapters, books[1].newCount, books[1].last == a ? 1 : 0], [1, 1, 1])
    }

    // A damaged file must never stop the notch; it is kept aside and a fresh one begun.
    func testABrokenFileIsSetAsideAndANewOneMade() throws {
        let file = path()
        try Data("this is not a database at all, just junk bytes".utf8).write(to: file)
        let s = try store(file)
        XCTAssertTrue(s.books().isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        XCTAssertTrue(names.contains { $0.contains(".broken-") })
    }

    // A book goes whole, though its chapters were written in several folders, and other books stay.
    func testForgetSessionsDeletesWholeBooksOnly() throws {
        let s = try store(path())
        s.add([chapter("a", session: "x", at: t0, folder: "/a"), chapter("b", session: "x", at: t0, folder: "/b"),
               chapter("c", session: "y", at: t0, folder: "/b")])
        s.title(session: "x", "Old book")
        s.forget(sessions: ["x"])
        XCTAssertEqual(s.chapters(session: "x").count, 0)
        XCTAssertEqual(s.chapters(session: "y").count, 1)
        // Its title went too: a later chapter of the session starts a book with no name.
        s.add([chapter("d", session: "x", at: t0.addingTimeInterval(9))])
        XCTAssertEqual(s.books().first { $0.session == "x" }?.title, "")
    }

    // A write that fails must say so, so the caller keeps the hand-back and tries again instead of losing it.
    func testAFailedAddSaysSoAndALaterOneKeepsIt() throws {
        let file = path()
        let s = try store(file)
        let folder = file.deletingLastPathComponent().path
        // No room for the journal a write needs: the folder is closed to writing.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder) }
        XCTAssertFalse(s.add([chapter("a", at: t0)]))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder)
        XCTAssertTrue(s.add([chapter("a", at: t0)]))
        XCTAssertEqual(s.chapters(session: "s").count, 1)
    }

    // Live ingest learns each folder as it goes; git's answer must name the checkout and its remote.
    func testLearnGitFolderKeepsTheCheckoutAndRemote() throws {
        let s = try store(path())
        let repo = path().deletingLastPathComponent().appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("[remote \"origin\"]\n\turl = git@github.com:me/app.git\n".utf8).write(to: repo.appendingPathComponent(".git/config"))
        s.learn(gitFolder: repo.path)
        s.learn(gitFolder: "/nowhere/gone")
        XCTAssertEqual(s.places().checkouts, [repo.path: repo.path])
        XCTAssertEqual(s.places().remotes, [repo.path: "github.com/me/app"])
    }

    // Everything from before this version counts as already read (owner's rule).
    func testAHandBackFromBeforeSinceIsStoredSeen() throws {
        let s = try store(path())
        let before = t0.addingTimeInterval(-48 * 3600 - 100)
        s.add([chapter("a", at: before), chapter("b", at: t0.addingTimeInterval(5))])
        XCTAssertEqual(s.seenMarks(), ["a": before])
    }

    // The page says "Kept since" from the earliest chapter.
    func testOldestIsTheEarliestHandBack() throws {
        let s = try store(path())
        XCTAssertNil(s.oldest())
        s.add([chapter("a", at: t0.addingTimeInterval(7)), chapter("b", at: t0.addingTimeInterval(3))])
        XCTAssertEqual(s.oldest(), t0.addingTimeInterval(3))
    }
}
