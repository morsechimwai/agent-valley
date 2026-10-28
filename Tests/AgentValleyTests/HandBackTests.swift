import XCTest
@testable import AgentValley

final class HandBackTests: XCTestCase {
    func testTwoBoxesAtMostTheNewestFirst() {
        let now = Date()
        func done(_ id: String, back: TimeInterval?, seen: TimeInterval? = nil) -> AgentRow {
            var info = AgentInfo()
            info.handedBackAt = back.map { now.addingTimeInterval($0) }
            var row = AgentRow(id: id, info: info, status: .done, elapsed: 0)
            row.handBackSeenAt = seen.map { now.addingTimeInterval($0) }
            return row
        }
        let card = SessionCard(id: "/r/p/s1", project: "p", branch: "", main: nil,
                               agents: [done("a", back: -30), done("b", back: -20), done("c", back: -10), done("d", back: nil)], startedAt: now)
        XCTAssertEqual(HandBack.boxes(card, openedAt: nil), ["c", "b"])
        // Seen in an earlier opening: a line now. Seen in this one: still a box until the panel shuts.
        var seen = card
        seen.agents[2].handBackSeenAt = now.addingTimeInterval(-5)
        XCTAssertEqual(HandBack.boxes(seen, openedAt: now), ["b", "a"])
        XCTAssertEqual(HandBack.boxes(seen, openedAt: now.addingTimeInterval(-60)), ["c", "b"])
        // A line the person opened to read is a box too, past the cap, in its place by time.
        XCTAssertEqual(HandBack.boxes(seen, openedAt: now, reading: ["c"]), ["c", "b", "a"])
        // Only a finished row's: an id of anything else is no box.
        XCTAssertEqual(HandBack.boxes(seen, openedAt: now, reading: ["x"]), ["b", "a"])
    }

    // Read whole in one opening, a line at the next: what is read goes as the panel shuts.
    func testReadingAllIsForOneOpening() {
        let state = NotchState()
        state.readingAll = ["c"]
        state.showingLegend = true
        state.finishedClosing()
        XCTAssertEqual(state.readingAll, [])
        XCTAssertFalse(state.showingLegend)
    }

    func testOnlyAPersonAtThePanelSeesAHandBackArrive() {
        XCTAssertEqual(HandBack.toMark(old: ["a"], new: ["a", "b"], lookingNow: true), ["b"])
        // Pinned open with nobody at it, or shut: it waits for a look.
        XCTAssertEqual(HandBack.toMark(old: ["a"], new: ["a", "b"], lookingNow: false), [])
        XCTAssertFalse(WaitWatch.looking(openFor: 60, pinned: true, inView: true))
    }

    // Read all opens downward, often past the list's edge: the list is led to it. Show less leaves it be.
    func testReadAllLeadsTheListToTheBoxAndShowLessDoesNot() {
        var reading: Set<String> = []
        XCTAssertEqual(ScrollTarget.reading("a", in: &reading), .readAll("a"))
        XCTAssertEqual(reading, ["a"])
        XCTAssertNil(ScrollTarget.reading("a", in: &reading))
        XCTAssertEqual(reading, [])
    }
}
