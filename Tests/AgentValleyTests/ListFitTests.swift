import XCTest
@testable import AgentValley

final class ListFitTests: XCTestCase {
    private func entry(_ id: String, _ full: CGFloat, quiet: Bool = false, keepsFull: Bool = false, header: Bool = false) -> ListFit.Entry {
        ListFit.Entry(id: id, full: full, row: 34, keepsFull: keepsFull, quiet: quiet, header: header)
    }

    private func card(main: AgentStatus, agents: [AgentStatus], elapsed: TimeInterval = 0,
                      step: String = "Reading files", steps: Int = 1) -> SessionCard {
        func row(_ id: String, _ status: AgentStatus) -> AgentRow {
            var info = AgentInfo()
            info.lastStep = step
            info.steps = steps
            return AgentRow(id: id, info: info, status: status, elapsed: elapsed, quietFor: 200)
        }
        return SessionCard(id: "s", project: "p", branch: "", main: row("m", main),
                           agents: agents.enumerated().map { row("a\($0.offset)", $0.element) },
                           startedAt: Date(timeIntervalSince1970: 0))
    }

    func testNothingFoldsWhenTheListFits() {
        let e = [entry("a", 100), entry("b", 100)]
        XCTAssertEqual(ListFit.compact(e, room: 200), [])
    }

    func testQuietFoldBeforeWorkingFromTheBottomUp() {
        // a working, b quiet, c working, d quiet: each full 100, row 34. Room for one fold short.
        let e = [entry("a", 100), entry("b", 100, quiet: true), entry("c", 100), entry("d", 100, quiet: true)]
        XCTAssertEqual(ListFit.compact(e, room: 340), ["d"])            // 400 - 66 = 334
        XCTAssertEqual(ListFit.compact(e, room: 270), ["d", "b"])       // 268
        XCTAssertEqual(ListFit.compact(e, room: 210), ["d", "b", "c"])  // 190: b, c, d in a run
    }

    func testAWorkingCardWithACrewFoldsAfterPlainOnes() {
        // a quiet, b plain, d plain, c with a crew at the bottom: each full 100, row 34.
        var c = entry("c", 100)
        c.crew = true
        let e = [entry("a", 100, quiet: true), entry("b", 100), entry("d", 100), c]
        XCTAssertEqual(ListFit.compact(e, room: 270), ["a", "d"])            // 268
        XCTAssertEqual(ListFit.compact(e, room: 210), ["a", "d", "b"])       // 190
        XCTAssertEqual(ListFit.compact(e, room: 150), ["a", "d", "b", "c"])  // 118
    }

    func testKeepsFullWinsOverOrder() {
        let e = [entry("a", 100), entry("b", 300, keepsFull: true)]
        XCTAssertEqual(ListFit.compact(e, room: 100), ["a"])  // still over: scroll, b stays full
    }

    func testACardTallerThanTheRoomStaysFull() {
        // Folded, b would leave the panel near empty: it stays full and the list scrolls.
        XCTAssertEqual(ListFit.compact([entry("b", 600, quiet: true)], room: 400), [])
        XCTAssertEqual(ListFit.compact([entry("a", 100), entry("b", 600, quiet: true)], room: 400), ["a"])
    }

    func testAQuestionIsAsTallAsItsOptions() {
        let option = Ask.Option(label: "", detail: "")
        let two = ListFit.requestHeight(.question(text: "", header: "", options: [option, option]), hidden: false)
        let three = ListFit.requestHeight(.question(text: "", header: "", options: [option, option, option]), hidden: false)
        let permission = ListFit.requestHeight(.permission(Ask.Shown(command: "ls", fields: [])), hidden: false)
        XCTAssertGreaterThan(three, two)
        XCTAssertGreaterThan(two, permission)
        // Put away, a question is drawn as one line and a button, like any other.
        XCTAssertEqual(ListFit.requestHeight(.question(text: "", header: "", options: [option, option, option]), hidden: true), permission)
    }

    func testAnOpenAskedBoxIsCountedInTheCard() {
        let card = card(main: .working, agents: [.working])
        let shut = ListFit.fullHeight(card, header: false, requests: { _ in [] }, settled: { _ in 0 }, hintRow: nil, showingDone: false, oneLineAgents: false)
        let open = ListFit.fullHeight(card, header: false, requests: { _ in [] }, settled: { _ in 0 }, hintRow: nil, showingDone: false, oneLineAgents: false, asked: [card.agents[0].id])
        XCTAssertEqual(open - shut, ListFit.askedBox)
    }

    func testDoneLinesFoldFirstWhenTheListRunsOutOfRoom() {
        let fits = [ListFit.Entry(id: "a", full: 300, row: 40, keepsFull: false, quiet: false, header: false, crew: true)]
        XCTAssertFalse(ListFit.foldsDone(fits, room: 300))
        XCTAssertTrue(ListFit.foldsDone(fits, room: 299))
    }

    func testHandBackBoxesStayAndDoneLinesFold() {
        let c = card(main: .working, agents: [.done, .done, .done])
        let first = c.agents[0].id
        let h = { (shown: Bool, boxes: [String], reading: Set<String>) in
            ListFit.fullHeight(c, header: false, requests: { _ in [] }, settled: { _ in 0 }, hintRow: nil, showingDone: shown, oneLineAgents: false,
                               boxes: boxes, reading: reading) }
        let envelope = h(false, [], [])
        XCTAssertEqual(h(true, [first], []) - envelope, ListFit.handBackBox + 2 * ListFit.agentLine)
        XCTAssertEqual(h(true, [first], [first]) - envelope, ListFit.readAllBox + 2 * ListFit.agentLine)
        // Folded, the lines go into "3 done"; the box stays.
        XCTAssertEqual(h(false, [first], []) - envelope, ListFit.handBackBox)
        XCTAssertEqual(h(true, [], []) - envelope, 3 * ListFit.agentLine)
        // Read whole, it is one scroll of what it was asked and what came back, not two.
        XCTAssertLessThan(ListFit.readAllBox, HandBackBox.maxHeight + AskedBox.maxHeight)
    }

    func testTheQuietHintTakesALine() {
        let c = card(main: .working, agents: [.quiet])
        let h = { (hint: String?) in
            ListFit.fullHeight(c, header: false, requests: { _ in [] }, settled: { _ in 0 }, hintRow: hint, showingDone: false, oneLineAgents: false) }
        XCTAssertGreaterThan(h("a0"), h(nil))
        XCTAssertEqual(h("elsewhere"), h(nil))
    }

    func testWhatBecameOfARequestTakesALine() {
        let c = card(main: .needsYou, agents: [])
        let h = { (outcomes: Int) in
            ListFit.fullHeight(c, header: false, requests: { _ in [] }, settled: { _ in outcomes }, hintRow: nil, showingDone: false, oneLineAgents: false) }
        XCTAssertGreaterThan(h(1), h(0))
    }

    func testHeightIgnoresTextThatTicks() {
        let a = card(main: .working, agents: [.working], elapsed: 5, step: "Edit", steps: 2)
        let later = card(main: .working, agents: [.working], elapsed: 900, step: "Running the whole test suite again", steps: 40)
        XCTAssertEqual(ListFit.fullHeight(a, header: false, requests: { _ in [] }, settled: { _ in 0 }, hintRow: nil, showingDone: false, oneLineAgents: false),
                       ListFit.fullHeight(later, header: false, requests: { _ in [] }, settled: { _ in 0 }, hintRow: nil, showingDone: false, oneLineAgents: false))
    }

    func testHeightGrowsWithStructure() {
        let bash = ListFit.requestHeight(.permission(Ask.Shown(command: "ls", fields: [])), hidden: false)
        let h = { (c: SessionCard, header: Bool, req: Int, done: Bool) in
            ListFit.fullHeight(c, header: header, requests: { _ in Array(repeating: bash, count: req) }, settled: { _ in 0 }, hintRow: nil,
                               showingDone: done, oneLineAgents: false) }
        let one = card(main: .working, agents: [.working]), two = card(main: .working, agents: [.working, .working])
        XCTAssertGreaterThan(h(two, false, 0, false), h(one, false, 0, false))
        XCTAssertGreaterThan(h(one, true, 0, false), h(one, false, 0, false))
        XCTAssertGreaterThan(h(one, false, 1, false), h(one, false, 0, false))
        let withDone = card(main: .working, agents: [.working, .done])
        XCTAssertGreaterThan(h(withDone, false, 0, true), h(withDone, false, 0, false))
    }

    func testJobLinesTakeRoomUpToThreeAndAMoreLine() {
        let h = { (count: Int) -> CGFloat in
            var c = self.card(main: .working, agents: [])
            c.jobs = (0..<count).map { BackgroundJob(id: "j\($0)", kind: .shell, name: "x", startedAt: Date(timeIntervalSince1970: 0), endsBy: nil) }
            return ListFit.fullHeight(c, header: false, requests: { _ in [] }, settled: { _ in 0 }, hintRow: nil, showingDone: false, oneLineAgents: false)
        }
        XCTAssertGreaterThan(h(1), h(0))
        XCTAssertEqual(h(2) - h(1), h(3) - h(2))
        XCTAssertEqual(h(4), h(5))     // three lines and "+N more"
        XCTAssertEqual(h(4) - h(3), h(3) - h(2))
    }

    func testRowHeightCountsTheHeader() {
        XCTAssertGreaterThan(ListFit.rowHeight(header: true), ListFit.rowHeight(header: false))
        XCTAssertEqual(ListFit.rowHeight(header: false), ListFit.row + 10)  // a card's gap under it
    }

    func testFoldedRowsRightUnderOneAnotherStandCloser() {
        // a over b: 4 points apart, not 10. c has a heading over it, so b keeps a card's gap.
        let e = [entry("a", 100), entry("b", 100), entry("c", 100, header: true)]
        XCTAssertEqual(ListFit.height(e, folded: ["a", "b", "c"]), 34 - 6 + 34 + 34)
        XCTAssertEqual(ListFit.height(e, folded: ["a", "c"]), 34 + 100 + 34)
    }

    func testHiddenSessionsTakeALineEachAndOneForAll() {
        let one = ListFit.under(idle: false, hidden: 1, plain: 0)
        XCTAssertEqual(ListFit.under(idle: true, hidden: 0, plain: 0), one)
        XCTAssertEqual(ListFit.under(idle: false, hidden: 3, plain: 0) - ListFit.under(idle: false, hidden: 2, plain: 0),
                       ListFit.under(idle: false, hidden: 0, plain: 1))
        XCTAssertEqual(ListFit.under(idle: false, hidden: 2, plain: 0), one + 2 * ListFit.under(idle: false, hidden: 0, plain: 1))
    }
}
