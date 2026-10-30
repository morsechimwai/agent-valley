import XCTest
@testable import AgentValley

final class LibraryBackfillTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("agent-valley-backfill-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        addTeardownBlock { [temp] in try? FileManager.default.removeItem(at: temp!) }
    }

    private var root: URL { temp.appendingPathComponent("projects") }

    private func library(since: Date = Date()) throws -> LibraryStore {
        try LibraryStore(database: temp.appendingPathComponent("lib/library.sqlite"), now: { since })
    }

    private func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// A session with a titled main transcript and one sub-agent that handed back at `back`.
    private func session(_ id: String, title: String, agent: String = "a1", folder: String, back: Date) throws {
        let dir = root.appendingPathComponent("proj/\(id)/subagents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let prompt = #"{"type":"user","timestamp":"\#(stamp(back.addingTimeInterval(-60)))","cwd":"\#(folder)","message":{"role":"user","content":"Find files in \#(id)"}}"#
        let answer = #"{"type":"assistant","timestamp":"\#(stamp(back))","cwd":"\#(folder)","message":{"model":"claude-haiku-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"Found three in \#(id)."}]}}"#
        try Data((prompt + "\n" + answer + "\n").utf8).write(to: dir.appendingPathComponent("agent-\(agent).jsonl"))
        try Data(#"{"agentType":"Explore","description":"Look around \#(id)"}"#.utf8).write(to: dir.appendingPathComponent("agent-\(agent).meta.json"))
        let first = #"{"type":"ai-title","aiTitle":"Old title"}"#, last = #"{"type":"ai-title","aiTitle":"\#(title)"}"#
        try Data((first + "\n" + last + "\n").utf8).write(to: root.appendingPathComponent("proj/\(id).jsonl"))
    }

    private func fakeLedger(folder: String, checkout: String, remote: String) throws -> URL {
        let url = temp.appendingPathComponent("history.sqlite")
        let db = try SQLite(path: url.path)
        try db.execute("""
            CREATE TABLE checkouts (folder TEXT PRIMARY KEY, checkout TEXT NOT NULL);
            CREATE TABLE remotes (checkout TEXT PRIMARY KEY, remote TEXT NOT NULL);
            INSERT INTO checkouts VALUES ('\(folder)', '\(checkout)');
            INSERT INTO remotes VALUES ('\(checkout)', '\(remote)');
            """)
        return url
    }

    private func backfill(_ library: LibraryStore, ledger: URL? = nil) {
        let finished = expectation(description: "done")
        LibraryBackfill.run(root: root, into: library, ledger: ledger) { finished.fulfill() }
        wait(for: [finished], timeout: 10)
    }

    // The point of the backfill: old sessions must show up as books with their titles and where they were made.
    func testBackfillFillsChaptersTitlesAndPlaces() throws {
        let gone = "/nowhere/gone-" + UUID().uuidString
        try session("s1", title: "Fix the login", folder: gone, back: Date())
        try session("s2", title: "Write the docs", folder: "/nowhere/other", back: Date())
        let ledger = try fakeLedger(folder: gone, checkout: "/Users/me/web", remote: "github.com/me/web")
        let library = try library()
        backfill(library, ledger: ledger)
        XCTAssertEqual(library.chapters(session: "s1").first?.text, "Found three in s1.")
        XCTAssertEqual(library.chapters(session: "s2").count, 1)
        XCTAssertEqual(Set(library.books().map(\.title)), ["Fix the login", "Write the docs"])
        XCTAssertEqual(library.places().checkouts[gone], "/Users/me/web")
        XCTAssertEqual(library.places().remotes["/Users/me/web"], "github.com/me/web")
        XCTAssertNil(library.places().checkouts["/nowhere/other"])
    }

    // Old work must not light up as new on the first update, so chapters from before the library are stored as read.
    func testBackfilledChaptersBeforeSinceAreSeen() throws {
        let old = Date().addingTimeInterval(-86400)
        try session("s1", title: "T", folder: "/nowhere", back: old)
        let library = try library(since: Date())
        backfill(library)
        let chapter = try XCTUnwrap(library.chapters(session: "s1").first)
        XCTAssertEqual(chapter.seenAt, chapter.at)
    }

    // Live ingest may already have filed a hand-back; reading it again must not make a twin.
    func testABackfillAfterLiveReadingAddsNoTwins() throws {
        try session("s1", title: "T", folder: "/nowhere", back: Date())
        let library = try library()
        let live = AgentStore(root: root, library: library)
        live.ingest(path: root.path + "/proj/s1/subagents/agent-a1.jsonl")
        XCTAssertEqual(library.chapters(session: "s1").count, 1)
        backfill(library)
        XCTAssertEqual(library.chapters(session: "s1").count, 1)
    }

    // It must stay off the main thread and read everything once: a later run reads only what moved since the app last ran, yet still says done.
    func testBackfillRunsOnItsOwnQueue() throws {
        let key = DispatchSpecificKey<Bool>()
        LibraryBackfill.queue.setSpecific(key: key, value: true)
        defer { LibraryBackfill.queue.setSpecific(key: key, value: nil) }
        try session("s1", title: "T", folder: "/nowhere", back: Date())
        let library = try library()
        var onQueue: Bool?
        let first = expectation(description: "first")
        LibraryBackfill.run(root: root, into: library, ledger: nil) {
            onQueue = DispatchQueue.getSpecific(key: key)
            first.fulfill()
        }
        wait(for: [first], timeout: 10)
        XCTAssertEqual(onQueue, true)
        XCTAssertTrue(library.backfilled)
        // Older than this run of the app and never read: the full read is not done again.
        try session("s2", title: "U", folder: "/nowhere", back: Date().addingTimeInterval(-7200))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)],
                                              ofItemAtPath: root.path + "/proj/s2/subagents/agent-a1.jsonl")
        try session("s3", title: "V", folder: "/nowhere", back: Date())
        backfill(library)
        XCTAssertEqual(library.chapters(session: "s1").count, 1)
        XCTAssertTrue(library.chapters(session: "s2").isEmpty)
        XCTAssertEqual(library.chapters(session: "s3").count, 1)
    }

    // What runs at launch must never move the stamp it reads from, or a slow catch-up would skip the hours the app was closed.
    func testLastAliveIsAsTheDatabaseWasOpened() throws {
        let file = temp.appendingPathComponent("lib/library.sqlite")
        let then = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try LibraryStore(database: file)
        XCTAssertNil(first.lastAlive)
        first.markAlive(at: then)
        XCTAssertNil(first.lastAlive)
        XCTAssertEqual(try LibraryStore(database: file).lastAlive, then)
    }
}
