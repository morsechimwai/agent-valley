import XCTest
@testable import AgentValley

final class HistoryDocumentTests: XCTestCase {
    private let home = "/Users/me"
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date { TranscriptReader.date(from: text)! }
    private var anchor: Date { date("2026-10-15T12:00:00.000Z") }
    private var october: DateInterval { HistoryReport.interval(of: .month, around: anchor, calendar: utc) }
    private var printed: Date { date("2026-10-17T08:00:00.000Z") }

    /// Opus 5.5 at $20 a million out: every 50,000 out is a dollar.
    private func answer(_ id: String, _ at: String, folder: String = "/Users/me/app", session: String = "s1", agent: String = "main",
                        output: Int) -> LedgerAnswer {
        LedgerAnswer(id: id, at: date(at), folder: folder, session: session, agent: agent, model: "claude-opus-5-5", output: output)
    }

    /// Two projects in October: api ($15) and app ($8), by every kind of crew.
    private var slice: LedgerSlice {
        LedgerSlice(answers: [
            answer("1", "2026-10-12T10:00:00.000Z", folder: "/Users/me/.superset/worktrees/api/a", session: "rate", output: 500_000),   // $10
            answer("2", "2026-10-12T11:00:00.000Z", folder: "/Users/me/.superset/worktrees/api/b", session: "find",
                   agent: "general-purpose", output: 250_000),                                                                            // $5
            answer("3", "2026-10-13T09:00:00.000Z", session: "viz", agent: "persona-tester", output: 200_000),                        // $4
            answer("4", "2026-10-13T09:30:00.000Z", session: "viz", agent: "pstack:poteto-agent", output: 100_000),                   // $2
            answer("5", "2026-10-14T08:00:00.000Z", session: "viz2", agent: "Explore", output: 50_000),                               // $1
            answer("6", "2026-10-14T09:00:00.000Z", session: "viz", agent: "Plan", output: 50_000),                                   // $1
            answer("7", "2026-11-01T00:00:00.000Z", session: "viz", output: 500_000),                                                 // November's
        ], titles: ["rate": "Rate limits", "find": "Search filters", "viz": "Visualizer", "viz2": "Second"], interval: october)
    }

    private func document(_ pick: HistoryPick, _ slice: LedgerSlice? = nil, calendar: Calendar? = nil) -> HistoryDocument? {
        HistoryDocument.make(slice ?? self.slice, pick: pick, calendar: calendar ?? utc, home: home, printed: printed)
    }

    func testADocumentAddsUpLikeThePage() throws {
        let pick = HistoryPick(span: .month, anchor: anchor)
        let document = try XCTUnwrap(document(pick))
        XCTAssertEqual(document.total, HistoryReport.make(slice, pick: pick, calendar: utc, home: home).total, accuracy: 1e-9)
        XCTAssertEqual(document.total, 23, accuracy: 1e-9)
        XCTAssertEqual(document.lines.map(\.name), ["api", "app"])
        XCTAssertEqual(document.projects, 2)
        XCTAssertEqual(document.answers, 6)
        XCTAssertEqual(document.sessions, 4)
        XCTAssertEqual(document.bars.count, 31)
        XCTAssertEqual(document.interval, october)
        XCTAssertNil(document.project)
        XCTAssertEqual(document.crew.map(\.who), [.leads, .others, .felix, .faye, .judy])
        XCTAssertEqual(document.crew.map(\.name), ["Main sessions", "Other agents", "general-purpose", "Explore", "Plan"])
        XCTAssertEqual(document.crew[0].cost, 10, accuracy: 1e-9)
        XCTAssertEqual(document.crew[1].cost, 6, accuracy: 1e-9)
    }

    func testAProjectReportHoldsNothingOfAnother() throws {
        let document = try XCTUnwrap(document(HistoryPick(span: .month, anchor: anchor, project: "/Users/me/app")))
        XCTAssertEqual(document.project, "app")
        XCTAssertEqual(document.lines.map(\.name), ["Visualizer", "Second"])
        XCTAssertEqual(document.total, 8, accuracy: 1e-9)
        XCTAssertEqual(document.answers, 4)
        XCTAssertEqual(document.sessions, 2)
        XCTAssertEqual(document.bars.map(\.cost).reduce(0, +), 8, accuracy: 1e-9)
        XCTAssertEqual(document.crew.map(\.who), [.others, .faye, .judy])
        let words = document.lines.map(\.name) + document.crew.map(\.name) + document.models.map(\.name)
            + [Format.reportFacts(document)]
        for other in ["api", "Rate limits", "Search filters"] {
            XCTAssertFalse(words.contains { $0.contains(other) }, other)
        }
        XCTAssertFalse(Format.reportFacts(document).contains("project"))
    }

    func testAPickedDayDoesNotNarrowTheReport() {
        let whole = document(HistoryPick(span: .month, anchor: anchor))
        let picked = document(HistoryPick(span: .month, anchor: anchor, day: date("2026-10-13T00:00:00.000Z"), hour: date("2026-10-13T09:00:00.000Z")))
        XCTAssertNotNil(whole)
        XCTAssertEqual(picked, whole)
    }

    func testNoDocumentWhileAnotherStretchLoads() {
        // Stepped on to November, with October's answers still all there is.
        XCTAssertNil(document(HistoryPick(span: .month, anchor: date("2026-11-15T12:00:00.000Z"))))
        // Read, and nothing in it.
        XCTAssertNil(document(HistoryPick(span: .month, anchor: anchor), LedgerSlice(interval: october)))
        // A project that spent nothing in the stretch.
        XCTAssertNil(document(HistoryPick(span: .month, anchor: anchor, project: "elsewhere")))
    }

    /// The button is worked out from the page's own report, without making the document, and
    /// says yes exactly when there is a document to make.
    func testExportableSaysWhetherThereIsADocument() {
        let empty = date("2026-10-20T00:00:00.000Z")
        let picks: [(HistoryPick, LedgerSlice)] = [
            (HistoryPick(span: .month, anchor: anchor), slice),
            (HistoryPick(span: .month, anchor: anchor, day: empty), slice),
            (HistoryPick(span: .month, anchor: anchor, day: empty, project: "/Users/me/app"), slice),
            (HistoryPick(span: .month, anchor: date("2026-11-15T12:00:00.000Z")), slice),
            (HistoryPick(span: .month, anchor: anchor), LedgerSlice(interval: october)),
            (HistoryPick(span: .month, anchor: anchor, project: "elsewhere"), slice),
        ]
        for (index, (pick, slice)) in picks.enumerated() {
            let report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
            XCTAssertEqual(report.exportable, document(pick, slice) != nil, "pick \(index)")
        }
        // A picked day with nothing in it still reports the whole month.
        XCTAssertTrue(HistoryReport.make(slice, pick: picks[1].0, calendar: utc, home: home).exportable)
    }

    func testHoursWithWorkCountClockHours() throws {
        let slice = LedgerSlice(answers: ["09:05", "09:55", "10:00", "10:59"].enumerated().map { index, time in
            answer("\(index)", "2026-10-12T\(time):00.000Z", output: 50_000)
        }, interval: october)
        XCTAssertEqual(try XCTUnwrap(document(HistoryPick(span: .month, anchor: anchor), slice)).hoursWithWork, 2)
    }

    func testPagesKeepTheTotalOnTheLastPage() {
        XCTAssertEqual(HistoryDocument.pages(lines: 0, first: 3, later: 5), [0..<0])
        XCTAssertEqual(HistoryDocument.pages(lines: 2, first: 3, later: 5), [0..<2])
        // Three lines fill the first page, and the total goes over to a page of its own.
        XCTAssertEqual(HistoryDocument.pages(lines: 3, first: 3, later: 5), [0..<3, 3..<3])
        XCTAssertEqual(HistoryDocument.pages(lines: 7, first: 3, later: 5), [0..<3, 3..<7])
        XCTAssertEqual(HistoryDocument.pages(lines: 8, first: 3, later: 5), [0..<3, 3..<8, 8..<8])
    }

    func testAFileNameStaysInItsFolder() throws {
        let odd = LedgerSlice(answers: [answer("1", "2026-10-12T10:00:00.000Z", folder: "/Users/me/a:b", output: 50_000)], interval: october)
        let project = try XCTUnwrap(document(HistoryPick(span: .month, anchor: anchor, project: "/Users/me/a:b"), odd))
        XCTAssertEqual(project.fileName(calendar: utc), "a-b October 2026.pdf")
        var monday = utc
        monday.firstWeekday = 2
        let wednesday = date("2026-10-14T12:00:00.000Z")
        let week = HistoryReport.interval(of: .week, around: wednesday, calendar: monday)
        let weekly = LedgerSlice(answers: [answer("1", "2026-10-14T10:00:00.000Z", output: 50_000)], interval: week)
        let every = try XCTUnwrap(document(HistoryPick(span: .week, anchor: wednesday), weekly, calendar: monday))
        XCTAssertEqual(every.fileName(calendar: monday), "AgentValley Oct 12 – 18, 2026.pdf")
    }

    func testReportWords() throws {
        let one = LedgerSlice(answers: [answer("1", "2026-10-12T10:00:00.000Z", output: 50_000)], interval: october)
        XCTAssertEqual(Format.reportFacts(try XCTUnwrap(document(HistoryPick(span: .month, anchor: anchor, project: "/Users/me/app"), one))),
                       "1 session · 1 answer · 1 hour with work")
        XCTAssertEqual(Format.reportFacts(try XCTUnwrap(document(HistoryPick(span: .month, anchor: anchor)))),
                       "4 sessions · 6 answers · 5 hours with work · 2 projects")

        func line(_ first: String, _ last: String) -> CostLine {
            CostLine(id: "s", name: "s", first: date(first), last: date(last))
        }
        XCTAssertEqual(Format.reportDays(line("2026-10-12T10:00:00.000Z", "2026-10-13T09:00:00.000Z"), hourly: false, calendar: utc), "Oct 12 – 13")
        XCTAssertEqual(Format.reportDays(line("2026-10-12T10:00:00.000Z", "2026-10-12T18:00:00.000Z"), hourly: false, calendar: utc), "Oct 12")
        XCTAssertEqual(Format.reportDays(line("2026-10-31T10:00:00.000Z", "2026-11-01T09:00:00.000Z"), hourly: false, calendar: utc), "Oct 31 – Nov 1")
        XCTAssertEqual(Format.reportDays(line("2026-10-12T09:12:00.000Z", "2026-10-12T14:30:00.000Z"), hourly: true, calendar: utc), "09:12 – 14:30")
        XCTAssertEqual(Format.reportDays(line("2026-10-12T09:12:00.000Z", "2026-10-12T09:12:30.000Z"), hourly: true, calendar: utc), "09:12")

        let day = CostBar(interval: DateInterval(start: date("2026-10-12T00:00:00.000Z"), duration: 86_400), cost: 734.43)
        XCTAssertEqual(Format.peakLabel(day, hourly: false, calendar: utc), "Mon 12 · $734.43")
        let hour = CostBar(interval: DateInterval(start: date("2026-10-12T21:00:00.000Z"), duration: 3600), cost: 74.81)
        XCTAssertEqual(Format.peakLabel(hour, hourly: true, calendar: utc), "21:00 · $74.81")
    }
}
