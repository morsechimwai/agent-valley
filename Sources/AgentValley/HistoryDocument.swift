import Foundation

/// One row of By agent in a report: a kind of agent, by the name Claude Code gives it, and what
/// its answers cost.
struct HistoryCrewLine: Equatable {
    enum Who: Hashable { case leads, felix, faye, judy, others }
    let who: Who
    let name: String
    var cost = 0.0
}

/// Everything a PDF report of the History page holds: the whole stretch on the page, and the
/// project if one is picked. A day or an hour picked from the bars does not narrow it. No disk
/// and no clock here: everything is handed in.
struct HistoryDocument: Equatable {
    let span: Span
    let interval: DateInterval
    /// The project's name. nil for every project.
    let project: String?
    let printed: Date
    let total: Double
    let unpriced: Int
    let answers: Int
    let sessions: Int
    /// How many projects. Said only on a report of every project.
    let projects: Int
    /// Hours by the clock with at least one answer in them.
    let hoursWithWork: Int
    let bars: [CostBar]
    /// Costliest first, and only those with answers.
    let crew: [HistoryCrewLine]
    let models: [CostLine]
    /// Every project, or every session of the project: costliest first, none folded.
    let lines: [CostLine]

    /// nil while the slice is another stretch's, or nothing was used in the stretch.
    static func make(_ slice: LedgerSlice, pick: HistoryPick, calendar: Calendar, home: String, printed: Date) -> HistoryDocument? {
        let whole = HistoryPick(span: pick.span, anchor: pick.anchor, project: pick.project)
        let report = HistoryReport.make(slice, pick: whole, calendar: calendar, home: home)
        guard report.ready else { return nil }
        let priced = HistoryReport.priced(slice, in: report.interval, home: home)
        let scope = pick.project.map { project in priced.filter { $0.project == project } } ?? priced
        guard !scope.isEmpty else { return nil }
        let hours = Set(scope.compactMap { calendar.dateInterval(of: .hour, for: $0.answer.at)?.start })
        return HistoryDocument(span: pick.span, interval: report.interval, project: report.projectName, printed: printed,
                               total: report.total, unpriced: report.unpriced, answers: scope.count,
                               sessions: Set(scope.map(\.answer.session)).count, projects: report.projects.count,
                               hoursWithWork: hours.count, bars: report.bars, crew: crew(scope), models: report.models,
                               lines: pick.project == nil ? report.projects : report.sessions)
    }

    /// The agent types as a client can read them: each one Claude Code ships on its own row, and
    /// every type it does not ship on one row of other agents.
    static func crew(_ scope: [HistoryReport.Priced]) -> [HistoryCrewLine] {
        var rows: [HistoryCrewLine.Who: HistoryCrewLine] = [:]
        for type in HistoryReport.lines(scope, by: { HistoryReport.agentName($0.answer.agent) }) {
            let row: HistoryCrewLine
            switch MascotKind(type: type.id) {
            case .lead: row = HistoryCrewLine(who: .leads, name: "Main sessions")
            case .general: row = HistoryCrewLine(who: .felix, name: "general-purpose")
            case .explore: row = HistoryCrewLine(who: .faye, name: "Explore")
            case .plan: row = HistoryCrewLine(who: .judy, name: "Plan")
            case .other: row = HistoryCrewLine(who: .others, name: "Other agents")
            }
            var sum = rows[row.who] ?? row
            sum.cost += type.cost
            rows[row.who] = sum
        }
        return rows.values.sorted { $0.cost != $1.cost ? $0.cost > $1.cost : $0.name < $1.name }
    }

    /// Ranges of `lines` page by page. The row after the last line holds the total, and it must
    /// fit on the last page with them: a full last page sends it over to a page of its own.
    static func pages(lines: Int, first: Int, later: Int) -> [Range<Int>] {
        precondition(first > 0 && later > 0)
        var pages: [Range<Int>] = []
        var start = 0
        var room = first
        while true {
            pages.append(start..<min(lines, start + room))
            if lines + 1 - start <= room { return pages }
            start = pages[pages.count - 1].upperBound
            room = later
        }
    }

    /// "agents-visualizer October 2026.pdf". No "/" or ":", which would make it a path.
    func fileName(calendar: Calendar) -> String {
        let title = (project ?? "AgentValley") + " " + Format.spanTitle(span, interval, calendar: calendar)
        return title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".pdf"
    }
}

extension HistoryReport {
    /// Whether `HistoryDocument.make` has a document to make, read off the page's report without
    /// making it: the totals are the whole stretch's, whatever day or hour is picked.
    var exportable: Bool { ready && (total > 0 || unpriced > 0) }
}

extension Format {
    /// "250 sessions · 10,442 answers · 75 hours with work", and " · 143 projects" on a report of
    /// every project.
    static func reportFacts(_ document: HistoryDocument) -> String {
        var parts = [counted(document.sessions, "session", "sessions"), counted(document.answers, "answer", "answers"),
                     counted(document.hoursWithWork, "hour with work", "hours with work")]
        if document.project == nil { parts.append(counted(document.projects, "project", "projects")) }
        return parts.joined(separator: " · ")
    }

    /// "1 answer", "10,442 answers".
    static func counted(_ value: Int, _ one: String, _ many: String) -> String { "\(count(value)) \(value == 1 ? one : many)" }

    /// When a session worked: "Oct 12 – 13", "Oct 15", "Oct 31 – Nov 1". On a day's report its
    /// times: "09:12 – 14:30", "09:12".
    static func reportDays(_ line: CostLine, hourly: Bool, calendar: Calendar) -> String {
        guard let first = line.first, let last = line.last else { return "" }
        let start = date(hourly ? "HH:mm" : "MMM d", first, calendar)
        let end: String
        if hourly {
            end = date("HH:mm", last, calendar)
        } else if calendar.isDate(first, inSameDayAs: last) {
            end = start
        } else {
            end = date(calendar.isDate(first, equalTo: last, toGranularity: .month) ? "d" : "MMM d", last, calendar)
        }
        return start == end ? start : "\(start) – \(end)"
    }

    /// Over the costliest bar: "Mon 12 · $734.43", and on a day's report "21:00 · $74.81".
    static func peakLabel(_ bar: CostBar, hourly: Bool, calendar: Calendar) -> String {
        date(hourly ? "HH:mm" : "EEE d", bar.interval.start, calendar) + " · " + dollars(bar.cost)
    }
}
