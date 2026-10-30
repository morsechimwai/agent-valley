import XCTest
@testable import AgentValley

final class HistoryReportTests: XCTestCase {
    private let home = "/Users/me"
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date { TranscriptReader.date(from: text)! }

    /// Opus 5.5 at $20 a million out: every 50,000 out is a dollar.
    private func answer(_ id: String, _ at: String, folder: String = "/Users/me/app", session: String = "s1", agent: String = "main",
                        model: String = "claude-opus-5-5", output: Int) -> LedgerAnswer {
        LedgerAnswer(id: id, at: date(at), folder: folder, session: session, agent: agent, model: model, output: output)
    }

    func testAMonthHasABarADayAndAPickedDayItsHours() throws {
        let slice = LedgerSlice(answers: [
            answer("a", "2026-10-01T00:00:00.000Z", output: 50_000),    // $1, the month's first moment
            answer("b", "2026-10-12T21:30:00.000Z", output: 150_000),   // $3
            answer("c", "2026-10-12T09:00:00.000Z", output: 100_000),   // $2
            answer("d", "2026-10-31T23:59:59.000Z", output: 50_000),    // $1, its last second
            answer("e", "2026-11-01T00:00:00.000Z", output: 500_000),   // the next month's
            answer("f", "2026-09-30T23:59:59.000Z", output: 500_000),   // the last month's
        ])
        var pick = HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z"))
        var report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        XCTAssertEqual(report.bars.count, 31)
        XCTAssertEqual(report.total, 7, accuracy: 1e-9)
        XCTAssertEqual(report.bars[0].cost, 1, accuracy: 1e-9)
        XCTAssertEqual(report.bars[11].cost, 5, accuracy: 1e-9)
        XCTAssertEqual(report.bars[30].cost, 1, accuracy: 1e-9)
        XCTAssertTrue(report.hours.isEmpty)
        XCTAssertEqual(report.focus, report.interval)
        XCTAssertEqual(report.focusCost, 7, accuracy: 1e-9)

        pick.day = report.bars[11].interval.start
        report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        XCTAssertEqual(report.hours.count, 24)
        XCTAssertEqual(report.hours[9].cost, 2, accuracy: 1e-9)
        XCTAssertEqual(report.hours[21].cost, 3, accuracy: 1e-9)
        XCTAssertEqual(report.focusCost, 5, accuracy: 1e-9)
        // The total and the bars are still the month's.
        XCTAssertEqual(report.total, 7, accuracy: 1e-9)
        XCTAssertEqual(report.bars.count, 31)

        pick.hour = report.hours[21].interval.start
        report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        XCTAssertEqual(report.focusCost, 3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(report.projects.first).cost, 3, accuracy: 1e-9)

        // A day's bars are its hours; one picked is the focus, and no second row of hours shows.
        report = HistoryReport.make(slice, pick: HistoryPick(span: .day, anchor: date("2026-10-12T12:00:00.000Z"), hour: date("2026-10-12T09:00:00.000Z")),
                                    calendar: utc, home: home)
        XCTAssertEqual(report.bars.count, 24)
        XCTAssertTrue(report.hours.isEmpty)
        XCTAssertEqual(report.total, 5, accuracy: 1e-9)
        XCTAssertEqual(report.focusCost, 2, accuracy: 1e-9)
    }

    // A month as busy as the owner's October 2026: some 42,000 answers in 340 folders. Worked out
    // again at every pick on the main thread, it took 170 ms in a release build, and the window
    // hitched at every click.
    func testABusyMonthIsWorkedOutQuickly() {
        let start = date("2026-10-01T00:00:00.000Z")
        let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5-20251001", "claude-fable-5-1"]
        let folders = (0..<340).map { "/Users/me/.superset/worktrees/p\($0)/w" }
        let answers = (0..<42_000).map { n in
            LedgerAnswer(id: "m\(n)", at: start.addingTimeInterval(Double(n) * 63), folder: folders[n % 340], session: "s\(n % 900)",
                         agent: n % 5 == 0 ? "Explore" : "main", model: models[n % 4], input: 10, read: 50_000, output: 900)
        }
        let pick = HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z"), day: date("2026-10-12T00:00:00.000Z"))
        let started = Date()
        let report = HistoryReport.make(LedgerSlice(answers: answers, folders: folders), pick: pick, calendar: utc, home: home)
        let seconds = Date().timeIntervalSince(started)
        XCTAssertEqual(report.bars.count, 31)
        XCTAssertEqual(report.hours.count, 24)
        XCTAssertEqual(report.projects.count, 340)
        // 0.50 s in a debug build before, run alone; some 0.1 s now, and 0.2 s among the whole suite.
        // CI's shared runners went from 0.24 s to 0.46 s on the same code (2026-10-30), so it gets room.
        let limit = ProcessInfo.processInfo.environment["CI"] == nil ? 0.4 : 1.0
        XCTAssertLessThan(seconds, limit, "\(seconds) s")
    }

    func testAReportIsReadyOnlyOverTheAnswersOfItsOwnStretch() {
        let october = HistoryReport.interval(of: .month, around: date("2026-10-15T12:00:00.000Z"), calendar: utc)
        let slice = LedgerSlice(answers: [answer("a", "2026-10-12T09:00:00.000Z", output: 50_000)], interval: october)
        XCTAssertTrue(HistoryReport.make(slice, pick: HistoryPick(anchor: date("2026-10-15T12:00:00.000Z")), calendar: utc, home: home).ready)
        // Stepped on to November, with October's answers still all there is: not yet $0.00.
        XCTAssertFalse(HistoryReport.make(slice, pick: HistoryPick(anchor: date("2026-11-15T12:00:00.000Z")), calendar: utc, home: home).ready)
        // Nothing read yet, as when the page opens.
        XCTAssertFalse(HistoryReport.make(LedgerSlice(), pick: HistoryPick(anchor: date("2026-10-15T12:00:00.000Z")), calendar: utc, home: home).ready)
    }

    func testADayTheClocksChangeHasTwentyThreeOrTwentyFiveHours() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        func hours(_ at: String) -> Int {
            HistoryReport.make(LedgerSlice(), pick: HistoryPick(span: .day, anchor: date(at)), calendar: newYork, home: home).bars.count
        }
        XCTAssertEqual(hours("2026-03-08T17:00:00.000Z"), 23)
        XCTAssertEqual(hours("2026-11-01T17:00:00.000Z"), 25)
        XCTAssertEqual(hours("2026-10-15T17:00:00.000Z"), 24)
    }

    func testAWeekStartsOnTheDayTheMacSays() {
        var sunday = utc
        sunday.firstWeekday = 1
        var monday = utc
        monday.firstWeekday = 2
        let wednesday = date("2026-10-14T12:00:00.000Z")
        XCTAssertEqual(HistoryReport.interval(of: .week, around: wednesday, calendar: sunday).start, date("2026-10-11T00:00:00.000Z"))
        let week = HistoryReport.interval(of: .week, around: wednesday, calendar: monday)
        XCTAssertEqual(week.start, date("2026-10-12T00:00:00.000Z"))
        XCTAssertEqual(HistoryReport.make(LedgerSlice(), pick: HistoryPick(span: .week, anchor: wednesday), calendar: monday, home: home).bars.count, 7)
        XCTAssertEqual(Format.spanTitle(.week, week, calendar: monday), "Oct 12 – 18, 2026")
        let across = HistoryReport.interval(of: .week, around: date("2026-10-01T12:00:00.000Z"), calendar: monday)
        XCTAssertEqual(Format.spanTitle(.week, across, calendar: monday), "Sep 28 – Oct 4, 2026")
    }

    // A project's worktrees and its checkout are one line, whatever Superset calls the project.
    func testAProjectsWorktreesAreOneLineWithItsCheckout() {
        let checkout = "/Users/me/.superset/projects/agent-valley"
        let slice = LedgerSlice(answers: [
            answer("1", "2026-10-12T10:00:00.000Z", folder: checkout, output: 50_000),
            answer("2", "2026-10-12T11:00:00.000Z", folder: "/Users/me/.superset/worktrees/AgentValley/live", output: 50_000),
            answer("3", "2026-10-12T12:00:00.000Z", folder: "/Users/me/.superset/worktrees/AgentValley/gone", output: 50_000),
        ], checkouts: ["/Users/me/.superset/worktrees/AgentValley/live": checkout])
        let report = HistoryReport.make(slice, pick: HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z")), calendar: utc, home: home)
        XCTAssertEqual(report.projects.map(\.name), ["agent-valley"])
        XCTAssertEqual(report.projects.first?.cost ?? 0, 3, accuracy: 1e-9)
    }

    // Two projects of one name are two lines, each saying the folder it is in; a name no other
    // project has stays as it is.
    func testTwoProjectsOfOneNameSayWhereEachIs() {
        let slice = LedgerSlice(answers: [
            answer("1", "2026-10-12T10:00:00.000Z", folder: "/Users/me/work/website", output: 150_000),   // $3
            answer("2", "2026-10-12T11:00:00.000Z", folder: "/Users/me/play/website", output: 100_000),   // $2
            answer("3", "2026-10-12T12:00:00.000Z", folder: "/Users/me/blog", output: 50_000),            // $1
        ])
        var pick = HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z"))
        var report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        XCTAssertEqual(report.projects.map(\.name), ["website · work", "website · play", "blog"])
        XCTAssertEqual(report.projects.map(\.id), ["/Users/me/work/website", "/Users/me/play/website", "/Users/me/blog"])
        pick.project = "/Users/me/play/website"
        report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        XCTAssertEqual(report.projectName, "website · play")
        XCTAssertEqual(report.total, 2, accuracy: 1e-9)
        XCTAssertEqual(report.sessions.map(\.name), ["website · play · Oct 12"])
        // A stretch the other spent nothing in: the name alone.
        let alone = LedgerSlice(answers: [slice.answers[0], answer("4", "2026-11-02T10:00:00.000Z", folder: "/Users/me/play/website", output: 50_000)])
        XCTAssertEqual(HistoryReport.make(alone, pick: HistoryPick(span: .month, anchor: date("2026-11-15T12:00:00.000Z")), calendar: utc, home: home)
            .projects.map(\.name), ["website"])
    }

    // A checkout renamed is one line with its new name, back to before the rename: the address
    // of its remote is the same. A folder its session went into is the project it began in.
    func testARenamedCheckoutIsOneLineByItsNewName() {
        let old = "/Users/me/agents-visualizer", new = "/Users/me/agent-valley"
        let slice = LedgerSlice(answers: [
            answer("1", "2026-10-05T10:00:00.000Z", folder: old, session: "a", output: 50_000),
            answer("2", "2026-10-05T11:00:00.000Z", folder: old + "/site", session: "a", output: 50_000),
            answer("3", "2026-10-20T10:00:00.000Z", folder: new, session: "b", output: 100_000),
            // Gone before git was asked, and no remote known: by the folder its session began in.
            answer("4", "2026-10-06T10:00:00.000Z", folder: "/Users/me/gone", session: "c", output: 50_000),
            answer("5", "2026-10-06T11:00:00.000Z", folder: "/Users/me/gone/site/public", session: "c", output: 50_000),
        ], folders: [old, old + "/site", new, "/Users/me/gone", "/Users/me/gone/site/public"],
           checkouts: [old: old, old + "/site": old, new: new],
           remotes: [old: "github.com/me/agent-valley", new: "github.com/me/agent-valley"],
           starts: ["a": old, "b": new, "c": "/Users/me/gone"],
           lastUsed: [old: date("2026-10-05T10:00:00.000Z"), old + "/site": date("2026-10-05T11:00:00.000Z"), new: date("2026-10-20T10:00:00.000Z"),
                      "/Users/me/gone": date("2026-10-06T10:00:00.000Z"), "/Users/me/gone/site/public": date("2026-10-06T11:00:00.000Z")])
        let month = HistoryReport.make(slice, pick: HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z")), calendar: utc, home: home)
        XCTAssertEqual(month.projects.map(\.name), ["agent-valley", "gone"])
        XCTAssertEqual(month.projects.map(\.cost), [4, 2])
        // Renamed with no remote known, but under a session: one line too.
        var moved = slice
        moved.remotes = [:]
        moved.checkouts = [new: new]
        moved.moves = [old: new]
        let one = HistoryReport.make(moved, pick: HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z")), calendar: utc, home: home)
        XCTAssertEqual(one.projects.map(\.name), ["agent-valley", "gone"])
        XCTAssertEqual(one.projects.map(\.id).first, new)
        // The week before the rename goes by the new name too.
        let week = HistoryReport.make(slice, pick: HistoryPick(span: .week, anchor: date("2026-10-05T12:00:00.000Z")), calendar: utc, home: home)
        XCTAssertEqual(week.projects.first?.name, "agent-valley")
        XCTAssertEqual(week.projects.first?.cost ?? 0, 2, accuracy: 1e-9)
    }

    func testWhatWasSpentOnWhatAndByWhom() throws {
        let slice = LedgerSlice(answers: [
            answer("1", "2026-10-12T10:00:00.000Z", folder: "/Users/me/.superset/worktrees/api/a", session: "rate", output: 500_000),   // $10
            answer("2", "2026-10-12T11:00:00.000Z", folder: "/Users/me/.superset/worktrees/api/b", session: "find",
                   agent: "general-purpose", output: 250_000),                                                                            // $5
            answer("3", "2026-10-12T12:00:00.000Z", session: "viz", model: "claude-sonnet-5-5", output: 400_000),                         // $4
            // No session: named by its project and its day. A plugin's type without the plugin.
            answer("4", "2026-10-12T12:30:00.000Z", session: "", agent: "pstack:poteto-agent", model: "claude-haiku-4-5-20251001", output: 200_000), // $1
            // A model with no price: its tokens are told apart, not priced.
            answer("5", "2026-10-12T13:00:00.000Z", session: "viz", model: "claude-opus-5-7", output: 1000),
        ], titles: ["rate": "Rate limits", "find": "Search filters", "viz": "Visualizer agents"])
        var pick = HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z"))
        var report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        XCTAssertEqual(report.total, 20, accuracy: 1e-9)
        XCTAssertEqual(report.unpriced, 1000)
        XCTAssertEqual(report.projects.map(\.name), ["api", "app"])
        XCTAssertEqual(report.projects[0].cost, 15, accuracy: 1e-9)
        // Each line counts its answers and sessions, and when the first and the last were.
        XCTAssertEqual(report.projects[0].answers, 2)
        XCTAssertEqual(report.projects[0].sessions, 2)
        XCTAssertEqual(report.projects[1].answers, 3)
        XCTAssertEqual(report.projects[0].first, date("2026-10-12T10:00:00.000Z"))
        XCTAssertEqual(report.projects[0].last, date("2026-10-12T11:00:00.000Z"))
        // The first level has no sessions: they are a project's own, one level down.
        XCTAssertTrue(report.sessions.isEmpty)
        // Two parts named and the rest as others: the panel is narrow.
        XCTAssertEqual(report.models.map(\.name), ["Opus 5.5", "Sonnet 5.5", "others"])
        XCTAssertEqual(report.models[2].cost, 1, accuracy: 1e-9)
        XCTAssertEqual(report.models[2].unpriced, 1000)
        // Three are shown as three.
        XCTAssertEqual(report.agents.map(\.name), ["main", "general-purpose", "poteto-agent"])
        XCTAssertEqual(report.agents[0].cost, 14, accuracy: 1e-9)

        pick.project = "/Users/me/app"
        report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        // In a project everything is the project's: its total, its sessions, its models.
        XCTAssertEqual(report.total, 5, accuracy: 1e-9)
        XCTAssertEqual(report.unpriced, 1000)
        XCTAssertEqual(report.sessions.map(\.name), ["Visualizer agents", "app · Oct 12"])
        XCTAssertEqual(report.models.map(\.name), ["Sonnet 5.5", "Haiku 4.5", "Opus 5.7"])
        XCTAssertEqual(Format.dollars(report.models[2]), "—")
        XCTAssertEqual(report.agents.map(\.name), ["main", "poteto-agent"])
        // The list of projects stays the whole stretch's, for the level above.
        XCTAssertEqual(report.projects.map(\.name), ["api", "app"])
        // Unknown folder, for a line that gave none.
        let lost = HistoryReport.make(LedgerSlice(answers: [answer("x", "2026-10-12T10:00:00.000Z", folder: "", session: "", output: 50_000)]),
                                      pick: HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z"), project: "Unknown folder"),
                                      calendar: utc, home: home)
        XCTAssertEqual(lost.projects.map(\.name), ["Unknown folder"])
        XCTAssertEqual(lost.sessions.map(\.name), ["Unknown folder · Oct 12"])
    }

    // In a project every session is listed, not only the costliest. A split names two parts and
    // puts the rest together as others, but shows three as three: "others" for one part would
    // hide a name for nothing.
    func testEverySessionOfAProjectAndTwoNamedParts() {
        let answers = (1...7).map { answer("\($0)", "2026-10-12T10:00:00.000Z", session: "s\($0)", agent: "type\($0)", output: $0 * 50_000) }
        let report = HistoryReport.make(LedgerSlice(answers: answers),
                                        pick: HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z"), project: "/Users/me/app"),
                                        calendar: utc, home: home)
        XCTAssertEqual(report.sessions.map(\.id), ["s7", "s6", "s5", "s4", "s3", "s2", "s1"])
        XCTAssertEqual(report.agents.map(\.name), ["type7", "type6", "others"])
        XCTAssertEqual(report.agents[2].cost, 15, accuracy: 1e-9)
        let three = Array(report.agents.prefix(2)) + [CostLine(id: "x", name: "x", cost: 0.5)]
        XCTAssertEqual(HistoryReport.folded(three).map(\.name), ["type7", "type6", "x"])
    }

    func testOthersAddUpAnswersAndSessions() {
        let lines = [(1, 1), (2, 1), (3, 2), (4, 3)].enumerated().map { index, counts in
            CostLine(id: "\(index)", name: "\(index)", cost: Double(10 - index), answers: counts.0, sessions: counts.1)
        }
        let folded = HistoryReport.folded(lines)
        XCTAssertEqual(folded.map(\.name), ["0", "1", "others"])
        XCTAssertEqual(folded[2].answers, 7)
        XCTAssertEqual(folded[2].sessions, 5)
    }

    // A project's bars are its own: when it spent, not when everything did.
    func testAProjectsBarsAndHoursAreItsOwn() {
        let slice = LedgerSlice(answers: [
            answer("a", "2026-10-12T09:00:00.000Z", folder: "/Users/me/app", output: 100_000),    // app, $2
            answer("b", "2026-10-12T21:30:00.000Z", folder: "/Users/me/other", output: 150_000),  // other, $3
            answer("c", "2026-10-03T10:00:00.000Z", folder: "/Users/me/other", output: 50_000),   // other, $1
        ])
        var pick = HistoryPick(span: .month, anchor: date("2026-10-15T12:00:00.000Z"), project: "/Users/me/app")
        var report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        XCTAssertEqual(report.total, 2, accuracy: 1e-9)
        XCTAssertEqual(report.bars[11].cost, 2, accuracy: 1e-9)
        XCTAssertEqual(report.bars[2].cost, 0, accuracy: 1e-9)
        pick.day = report.bars[11].interval.start
        report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        XCTAssertEqual(report.hours[9].cost, 2, accuracy: 1e-9)
        XCTAssertEqual(report.hours[21].cost, 0, accuracy: 1e-9)
        XCTAssertEqual(report.focusCost, 2, accuracy: 1e-9)
        // Back at the level of every project, the same day picked: everything that day.
        pick.project = nil
        report = HistoryReport.make(slice, pick: pick, calendar: utc, home: home)
        XCTAssertEqual(report.focusCost, 5, accuracy: 1e-9)
        XCTAssertEqual(report.projects.map(\.name), ["other", "app"])
        // A stretch the project spent nothing in: no sessions, and the page says so.
        report = HistoryReport.make(slice, pick: HistoryPick(span: .month, anchor: date("2026-09-15T12:00:00.000Z"), project: "/Users/me/app"), calendar: utc, home: home)
        XCTAssertTrue(report.sessions.isEmpty)
        XCTAssertEqual(report.total, 0)
    }

    // A split in one line under its bar: whole dollars, to fit the panel.
    func testASplitInOneLine() {
        XCTAssertEqual(Format.wholeDollars(4048.52), "$4,049")
        XCTAssertEqual(Format.wholeDollars(0.4), "<$1")
        XCTAssertEqual(Format.wholeDollars(0.5), "$1")
        XCTAssertEqual(Format.wholeDollars(0), "$0")
        XCTAssertEqual(Format.splitLine([CostLine(id: "a", name: "Opus 5.5", cost: 4048.52), CostLine(id: "b", name: "Sonnet 5.5", cost: 159.02),
                                         CostLine(id: "others", name: "others", cost: 112.51)]),
                       "Opus 5.5 $4,049 · Sonnet 5.5 $159 · others $113")
        XCTAssertEqual(Format.splitLine([CostLine(id: "x", name: "Opus 5.7", unpriced: 1000)]), "Opus 5.7 —")
    }

    func testModelsByNameAndMoneyAndTheWindowsWords() {
        XCTAssertEqual(Format.model("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(Format.model("claude-haiku-4-5-20251001"), "Haiku 4.5")
        XCTAssertEqual(Format.model("claude-opus-4-20250514"), "Opus 4")
        XCTAssertEqual(Format.model("claude-fable-5-1"), "Fable 5.1")
        XCTAssertEqual(Format.model("gpt-5"), "gpt-5")
        // An id of the older shape keeps its words, less "claude-" and the date.
        XCTAssertEqual(Format.model("claude-3-5-haiku-20241022"), "3-5-haiku")
        XCTAssertEqual(HistoryReport.agentName("pstack:poteto-agent"), "poteto-agent")
        XCTAssertEqual(HistoryReport.agentName("general-purpose"), "general-purpose")
        XCTAssertEqual(Format.dollars(4284.3), "$4,284.30")
        XCTAssertEqual(Format.dollars(0), "$0.00")
        XCTAssertEqual(Format.dollars(0.004), "<$0.01")
        XCTAssertEqual(Format.dollars(0.005), "$0.01")
        XCTAssertEqual(Format.dollars(1234.567), "$1,234.57")
        XCTAssertEqual(Format.unpriced(12_345), "+ 12,345 tokens with no price")
        XCTAssertEqual(Format.readingHistory(ReadingProgress(done: 1200, of: 3128)), "Reading history… 1,200 of 3,128 files")
        XCTAssertEqual(Format.historyFoot(since: date("2026-09-13T08:00:00.000Z"), calendar: utc), "History since Sep 13, 2026 · API prices as of Oct 15, 2026")
        XCTAssertEqual(Format.historyFoot(since: nil, calendar: utc), "API prices as of Oct 15, 2026")
        XCTAssertEqual(Format.noUse, "No token use in this period.")
        XCTAssertEqual(Format.atAPIPrices, "at API prices")
        // The page's own words, in the panel.
        XCTAssertEqual(Format.allProjects, "All projects")
        XCTAssertEqual(Format.showsSessions, "Shows its sessions")
        XCTAssertEqual(Format.historyBelow, "More below")
    }

    // The owner's Mac counts years the Buddhist way, and the first picture said "October 2569"
    // beside prices of 2026. The window speaks English: its years are the common era's, its time
    // zone and the first day of its week the Mac's.
    func testTheWindowCountsYearsAsTheCommonEra() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        buddhist.firstWeekday = 2
        let calendar = HistoryReport.calendar(from: buddhist)
        XCTAssertEqual(calendar.identifier, .gregorian)
        XCTAssertEqual(calendar.timeZone, buddhist.timeZone)
        XCTAssertEqual(calendar.firstWeekday, 2)
        let month = HistoryReport.interval(of: .month, around: date("2026-10-15T12:00:00.000Z"), calendar: calendar)
        XCTAssertEqual(Format.spanTitle(.month, month, calendar: calendar), "October 2026")
        XCTAssertEqual(Format.historyFoot(since: month.start, calendar: calendar), "History since Oct 1, 2026 · API prices as of Oct 15, 2026")
    }

    func testDatesAsTheWindowSaysThem() {
        let month = HistoryReport.interval(of: .month, around: date("2026-10-15T12:00:00.000Z"), calendar: utc)
        XCTAssertEqual(Format.spanTitle(.month, month, calendar: utc), "October 2026")
        let day = HistoryReport.interval(of: .day, around: date("2026-10-12T12:00:00.000Z"), calendar: utc)
        XCTAssertEqual(Format.spanTitle(.day, day, calendar: utc), "Mon, Oct 12, 2026")
        XCTAssertEqual(Format.pickTitle(day, hourly: false, calendar: utc), "Oct 12")
        let hour = DateInterval(start: date("2026-10-12T21:00:00.000Z"), duration: 3600)
        XCTAssertEqual(Format.pickTitle(hour, hourly: true, calendar: utc), "Oct 12, 21:00")
        XCTAssertEqual(Format.barLabel(CostBar(interval: day, cost: 739.25), hourly: false, calendar: utc), "Oct 12, $739.25")
        XCTAssertEqual(Format.barLabel(CostBar(interval: hour, cost: 74.81), hourly: true, calendar: utc), "21:00, $74.81")
        XCTAssertEqual(Format.axisLabel(CostBar(interval: day), hourly: false, calendar: utc), "Oct 12")
        XCTAssertEqual(Format.axisLabel(CostBar(interval: hour), hourly: true, calendar: utc), "21:00")
        XCTAssertEqual(Format.splitLabel([CostLine(id: "a", name: "Opus 5.5", cost: 3990.18), CostLine(id: "b", name: "Sonnet 5.5", cost: 186.35)]),
                       "Opus 5.5, $3,990.18; Sonnet 5.5, $186.35")
        XCTAssertEqual(Format.showAll("October 2026"), "Show all of October 2026")
    }
}
