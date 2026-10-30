import XCTest
@testable import AgentValley

final class LibraryTests: XCTestCase {
    private let home = "/Users/me"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func book(_ session: String, _ folder: String, ago: TimeInterval = 0, new: Int = 0) -> BookSummary {
        BookSummary(session: session, title: session, folder: folder, chapters: 1, newCount: new,
                    last: now.addingTimeInterval(-ago), types: [])
    }

    private func shelf(_ key: String, checkouts: [String], last: Date? = nil) -> Shelf {
        Shelf(key: key, name: key, books: [], newCount: 0, last: last ?? now, checkouts: checkouts)
    }

    // A worktree is no project of its own: its books sit on the checkout's shelf, as its cost does in History.
    func testBooksOfWorktreesShareTheirCheckoutsShelf() {
        let checkout = "/Users/me/.superset/projects/agent-valley"
        let live = "/Users/me/.superset/worktrees/AgentValley/live"
        let shelves = Library.shelves([book("a", checkout, ago: 30, new: 1), book("b", live, ago: 20, new: 2),
                                       book("c", "/Users/me/.superset/worktrees/AgentValley/gone", ago: 10)],
                                      home: home, checkouts: [live: checkout], remotes: [:])
        // "gone" has no answer of its own, but a sibling worktree of the project does: its books join too.
        XCTAssertEqual(shelves.count, 1)
        XCTAssertEqual(shelves.first { $0.name == "agent-valley" }?.books.map(\.session), ["c", "b", "a"])
        XCTAssertEqual(shelves.first { $0.name == "agent-valley" }?.newCount, 3)
        XCTAssertEqual(shelves.first?.checkouts, [checkout, "/Users/me/.superset/worktrees/AgentValley/gone"])
    }

    // Two projects of one name need the folder each is in, or the page shows two shelves alike.
    func testClashingNamesGetTheirParent() {
        let shelves = Library.shelves([book("a", "/Users/me/work/website", ago: 5), book("b", "/Users/me/play/website", ago: 10),
                                       book("c", "/Users/me/blog", ago: 1)], home: home, checkouts: [:], remotes: [:])
        XCTAssertEqual(shelves.map(\.name), ["blog", "website · work", "website · play"])
    }

    // A deleted worktree is routine; its checkout still stands, so the shelf stays and nothing is marked.
    func testADeletedWorktreeKeepsItsShelf() {
        let result = Library.sweep([shelf("k", checkouts: ["/gone-worktree", "/checkout"])], missing: [:], now: now) { $0 == "/checkout" }
        XCTAssertEqual(result.shown.map(\.key), ["k"])
        XCTAssertTrue(result.set.isEmpty)
        XCTAssertTrue(result.delete.isEmpty)
    }

    // A drive that is unplugged must not cost the library: hide at once, delete only after 30 days.
    func testAMissingCheckoutHidesBeforeItDeletes() {
        let shelves = [shelf("k", checkouts: ["/x"])]
        let first = Library.sweep(shelves, missing: [:], now: now) { _ in false }
        XCTAssertTrue(first.shown.isEmpty)
        XCTAssertEqual(first.set["k"], .some(now))
        XCTAssertTrue(first.delete.isEmpty)
        let day29 = Library.sweep(shelves, missing: ["k": now], now: now.addingTimeInterval(29 * 86400)) { _ in false }
        XCTAssertTrue(day29.shown.isEmpty)
        XCTAssertTrue(day29.delete.isEmpty)
        let day30 = Library.sweep(shelves, missing: ["k": now], now: now.addingTimeInterval(30 * 86400)) { _ in false }
        XCTAssertEqual(day30.delete, ["k"])
    }

    // The drive comes back: the shelf shows again and its clock is cleared, so a later absence counts from zero.
    func testAShelfThatComesBackShowsAndClears() {
        let result = Library.sweep([shelf("k", checkouts: ["/x"])], missing: ["k": now.addingTimeInterval(-86400)], now: now) { _ in true }
        XCTAssertEqual(result.shown.map(\.key), ["k"])
        XCTAssertEqual(result.clear, ["k"])
        XCTAssertTrue(result.set.isEmpty)
    }

    // Buckets are not folders: nothing can go missing from them, so they never hide and never delete.
    func testBucketsAreNeverHiddenOrDeleted() {
        let keys = [Projects.scratch, Projects.temporary, Projects.supersetSessions, Projects.unknown, "~"]
        let shelves = keys.map { shelf($0, checkouts: ["/nowhere"]) }
        let old = Dictionary(uniqueKeysWithValues: keys.map { ($0, now.addingTimeInterval(-90 * 86400)) })
        let result = Library.sweep(shelves, missing: old, now: now) { _ in false }
        XCTAssertEqual(result.shown.map(\.key), keys)
        XCTAssertTrue(result.delete.isEmpty)
        XCTAssertTrue(result.set.isEmpty)
    }

    // A shelf goes by the folder used last, so a project renamed on disk shows its new name.
    func testAShelfIsNamedAfterTheFolderUsedLast() {
        let remote = "git:github.com/me/app"
        let old = "/Users/me/old-name", new = "/Users/me/new-name"
        let shelves = Library.shelves([book("a", old, ago: 100), book("b", new, ago: 10)], home: home,
                                      checkouts: [old: old, new: new], remotes: [old: "github.com/me/app", new: "github.com/me/app"])
        XCTAssertEqual(shelves.map(\.key), [remote])
        XCTAssertEqual(shelves.map(\.name), ["new-name"])
    }

    // Many folders of one place with no time to tell them apart: the first by folder wins, not whichever a
    // dictionary lists first. One sample could pass by luck, so there are 50 to pick from.
    func testATieOnLastUsedGoesToTheFirstFolder() {
        var places: [String: Projects.Place] = [:]
        for index in 0..<50 {
            places[String(format: "/Users/me/f%02d/app", index)] = Projects.Place(key: "k", name: "name\(index)", parent: "")
        }
        XCTAssertEqual(Projects.names(places, lastUsed: [:]), ["k": "name0"])
    }

    // A hand-back after the mark proves the folder was there (a drive worked on all month), so the 30 days count from the later of the two.
    func testTheThirtyDaysCountFromTheLastBookToo() {
        let marked = ["k": now.addingTimeInterval(-31 * 86400)]
        let fresh = Library.sweep([shelf("k", checkouts: ["/x"], last: now.addingTimeInterval(-86400))], missing: marked, now: now) { _ in false }
        XCTAssertTrue(fresh.delete.isEmpty)
        let stale = Library.sweep([shelf("k", checkouts: ["/x"], last: now.addingTimeInterval(-31 * 86400))], missing: marked, now: now) { _ in false }
        XCTAssertEqual(stale.delete, ["k"])
    }

    // A worktree learned before places were learned live has no checkout on record; its shelf key is the checkout, so the shelf stays while that stands.
    func testAShelfKeyThatIsAFolderCountsAsACheckout() {
        let gone = "/Users/me/app/.claude/worktrees/side"
        let shelves = Library.shelves([book("a", gone)], home: home, checkouts: [:], remotes: [:])
        XCTAssertEqual(shelves.first?.checkouts, ["/Users/me/app", gone])
        XCTAssertEqual(Library.sweep(shelves, missing: [:], now: now) { $0 == "/Users/me/app" }.shown.count, 1)
    }
}
