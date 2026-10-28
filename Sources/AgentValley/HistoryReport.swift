import Foundation

/// The stretch of time the History page shows at once.
enum Span: String, CaseIterable {
    case day = "Day", week = "Week", month = "Month"

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    /// What each of its bars stands for.
    var bar: Calendar.Component { self == .day ? .hour : .day }
}

/// What the person has picked on the History page.
struct HistoryPick: Equatable {
    var span = Span.month
    /// Any moment of the stretch shown.
    var anchor = Date()
    /// The start of a day picked from a week's or a month's bars.
    var day: Date?
    /// The start of an hour picked.
    var hour: Date?
    /// The key of the project picked: `Projects.Place.key`.
    var project: String?
}

/// A sum of money and what it went on: a project, a session, a model, a kind of agent.
struct CostLine: Equatable, Identifiable {
    /// A session's id; for the rest, the name shown. "others" for what is folded together.
    let id: String
    let name: String
    var cost = 0.0
    /// Tokens of answers the price table does not know.
    var unpriced = 0
    var answers = 0
    /// Sessions apart.
    var sessions = 0
    /// When its first and its last answer were given.
    var first: Date?
    var last: Date?
}

/// One bar: a stretch of time, and what was spent in it.
struct CostBar: Equatable, Identifiable {
    let interval: DateInterval
    var cost = 0.0
    var id: Date { interval.start }
}

/// Everything the History page shows, worked out from the answers of what is picked. No disk
/// and no clock here: everything is handed in.
struct HistoryReport: Equatable {
    var interval = DateInterval()
    /// Worked out from the answers of its own stretch. Stepped to another, the answers are the
    /// last stretch's until the new ones are read, and its sums are not to be shown.
    var ready = false
    var total = 0.0
    var unpriced = 0
    var bars: [CostBar] = []
    /// The hours of a day picked in a week or a month.
    var hours: [CostBar] = []
    /// What is picked: the hour, else the day, else the whole stretch.
    var focus = DateInterval()
    var focusCost = 0.0
    /// Each line's id is the project's key.
    var projects: [CostLine] = []
    /// The name of the project picked, as its line says it.
    var projectName: String?
    /// With a project picked, every one of its sessions. None on the level of every project.
    var sessions: [CostLine] = []
    var models: [CostLine] = []
    var agents: [CostLine] = []

    /// A split names this many parts, and puts the rest together as "others": the panel is narrow.
    static let named = 2

    struct Priced {
        let answer: LedgerAnswer
        let cost: Double?
        /// The project's key.
        let project: String
        let name: String
    }

    /// The calendar History counts by: the common era's years, as its English words and the
    /// date of its prices do, in the Mac's time zone and with the Mac's first day of the week.
    static func calendar(from mac: Calendar = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = mac.timeZone
        calendar.firstWeekday = mac.firstWeekday
        calendar.minimumDaysInFirstWeek = mac.minimumDaysInFirstWeek
        return calendar
    }

    static func interval(of span: Span, around date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: span.component, for: date) ?? DateInterval(start: date, duration: 0)
    }

    /// One slot per hour or per day across `interval`, by the calendar: a day the clocks change
    /// has 23 hours or 25.
    static func slots(_ interval: DateInterval, by component: Calendar.Component, calendar: Calendar) -> [DateInterval] {
        var slots: [DateInterval] = []
        var start = interval.start
        while start < interval.end, let slot = calendar.dateInterval(of: component, for: start), slot.end > start {
            slots.append(slot)
            start = slot.end
        }
        return slots
    }

    static func make(_ slice: LedgerSlice, pick: HistoryPick, calendar: Calendar, home: String) -> HistoryReport {
        var report = HistoryReport()
        let stretch = interval(of: pick.span, around: pick.anchor, calendar: calendar)
        report.interval = stretch
        report.ready = slice.interval == stretch
        let (priced, names) = placed(slice, in: stretch, home: home)
        report.projectName = pick.project.map { names[$0] ?? ($0 as NSString).lastPathComponent }
        // In a project its own answers make the totals and the bars. The list of projects stays
        // the whole stretch's, for the level above.
        let scope = pick.project.map { project in priced.filter { $0.project == project } } ?? priced
        report.total = sum(scope)
        report.unpriced = scope.reduce(0) { $0 + ($1.cost == nil ? $1.answer.tokens : 0) }
        // Each answer added to its slot in one pass: the slots are in order, so its slot is found by halves.
        func bars(_ slots: [DateInterval]) -> [CostBar] {
            var costs = [Double](repeating: 0, count: slots.count)
            for item in scope {
                guard let cost = item.cost else { continue }
                var low = 0
                var high = slots.count
                while low < high {
                    let middle = (low + high) / 2
                    if slots[middle].end <= item.answer.at { low = middle + 1 } else { high = middle }
                }
                if low < slots.count, slots[low].start <= item.answer.at { costs[low] += cost }
            }
            return zip(slots, costs).map { CostBar(interval: $0, cost: $1) }
        }
        report.bars = bars(slots(stretch, by: pick.span.bar, calendar: calendar))
        let day = pick.span == .day ? nil : pick.day.flatMap { calendar.dateInterval(of: .day, for: $0) }
        if let day { report.hours = bars(slots(day, by: .hour, calendar: calendar)) }
        let focus = pick.hour.flatMap { calendar.dateInterval(of: .hour, for: $0) } ?? day ?? stretch
        report.focus = focus
        let inFocus = { (item: Priced) in focus.start <= item.answer.at && item.answer.at < focus.end }
        let focused = scope.filter(inFocus)
        report.focusCost = sum(focused)
        report.projects = lines(priced.filter(inFocus), by: \.project, name: { _, group in group[0].name })
        if pick.project != nil {
            report.sessions = lines(focused, by: \.answer.session, name: { id, group in
                slice.titles[id] ?? untitled(group, calendar: calendar)
            })
        }
        report.models = folded(lines(focused, by: { Format.model($0.answer.model) }))
        report.agents = folded(lines(focused, by: { agentName($0.answer.agent) }))
        return report
    }

    /// The answers given in `stretch`, each priced once, and each folder placed once.
    static func priced(_ slice: LedgerSlice, in stretch: DateInterval, home: String) -> [Priced] {
        placed(slice, in: stretch, home: home).priced
    }

    /// `priced`, and the name of every project in the history by its key. A project goes by the
    /// name of the folder last worked in, so a checkout renamed goes by its new name back to its
    /// first day. Two in the stretch of one name say the folder each is in: "app · work".
    static func placed(_ slice: LedgerSlice, in stretch: DateInterval, home: String) -> (priced: [Priced], names: [String: String]) {
        let known = Projects.known(slice.folders)
        func place(_ folder: String, start: String?) -> Projects.Place {
            Projects.place(of: folder, start: start, home: home, known: known, checkouts: slice.checkouts, remotes: slice.remotes,
                           moves: slice.moves)
        }
        var newest: [String: (at: Date, place: Projects.Place)] = [:]
        for folder in slice.folders {
            let place = place(folder, start: nil)
            let at = slice.lastUsed[folder] ?? .distantPast
            if newest[place.key].map({ at > $0.at }) ?? true { newest[place.key] = (at, place) }
        }
        var places: [String: Projects.Place] = [:]
        var items: [(answer: LedgerAnswer, place: Projects.Place)] = []
        for answer in slice.answers where stretch.start <= answer.at && answer.at < stretch.end {
            let start = slice.starts[answer.session]
            let id = answer.folder + "\u{0}" + (start ?? "")
            let found = places[id] ?? place(answer.folder, start: start)
            places[id] = found
            items.append((answer, found))
        }
        var named = newest.mapValues(\.place)
        for item in items where named[item.place.key] == nil { named[item.place.key] = item.place }
        var names = named.mapValues(\.name)
        // ponytail: two of one name in one parent's name stay alike; the parent's parent would tell them apart.
        let alike = Dictionary(grouping: Set(items.map(\.place.key)), by: { named[$0]?.name ?? "" })
        for (_, keys) in alike where keys.count > 1 {
            for key in keys {
                if let place = named[key], !place.parent.isEmpty { names[key] = place.name + " · " + place.parent }
            }
        }
        let priced = items.map { Priced(answer: $0.answer, cost: Pricing.cost(of: $0.answer), project: $0.place.key, name: names[$0.place.key] ?? $0.place.name) }
        return (priced, names)
    }

    /// The rest of the parts past the first `named` put together as "others", when that is more than one part.
    static func folded(_ lines: [CostLine]) -> [CostLine] {
        guard lines.count > named + 1 else { return lines }
        let rest = lines.dropFirst(named)
        return Array(lines.prefix(named))
            + [CostLine(id: "others", name: "others", cost: rest.reduce(0) { $0 + $1.cost }, unpriced: rest.reduce(0) { $0 + $1.unpriced },
                        answers: rest.reduce(0) { $0 + $1.answers }, sessions: rest.reduce(0) { $0 + $1.sessions })]
    }

    /// A plugin's agent type goes without the plugin's name, as on the panel's rows.
    static func agentName(_ type: String) -> String {
        type.split(separator: ":").last.map(String.init) ?? type
    }

    static func sum(_ priced: [Priced]) -> Double {
        priced.reduce(0) { $0 + ($1.cost ?? 0) }
    }

    /// Grouped by `key`, each group added up, costliest first. A group is shown by its key
    /// unless `name` names it from its answers.
    static func lines(_ priced: [Priced], by key: (Priced) -> String,
                      name: (String, [Priced]) -> String = { id, _ in id }) -> [CostLine] {
        Dictionary(grouping: priced, by: key).map { id, group in
            var line = CostLine(id: id, name: name(id, group), answers: group.count)
            var sessions = Set<String>()
            for item in group {
                line.cost += item.cost ?? 0
                if item.cost == nil { line.unpriced += item.answer.tokens }
                sessions.insert(item.answer.session)
                line.first = min(line.first ?? item.answer.at, item.answer.at)
                line.last = max(line.last ?? item.answer.at, item.answer.at)
            }
            line.sessions = sessions.count
            return line
        }
        .sorted { $0.cost != $1.cost ? $0.cost > $1.cost : $0.name < $1.name }
    }

    /// A session Claude Code gave no name: its project, and the day of its first answer here.
    static func untitled(_ group: [Priced], calendar: Calendar) -> String {
        let first = group.map(\.answer.at).min() ?? Date()
        return "\(group[0].name) · \(Format.pickTitle(DateInterval(start: first, duration: 0), hourly: false, calendar: calendar))"
    }
}

extension Format {
    private static let money: NumberFormatter = {
        let format = NumberFormatter()
        format.numberStyle = .currency
        format.currencyCode = "USD"
        format.locale = Locale(identifier: "en_US")
        format.roundingMode = .halfUp
        return format
    }()

    private static let wholeMoney: NumberFormatter = {
        let format = NumberFormatter()
        format.numberStyle = .currency
        format.currencyCode = "USD"
        format.locale = Locale(identifier: "en_US")
        format.maximumFractionDigits = 0
        format.roundingMode = .halfUp
        return format
    }()

    /// "$4,049", for a split's one line, where the cents would not fit. Less than half a dollar,
    /// but more than nothing, is "<$1".
    static func wholeDollars(_ value: Double) -> String {
        if value > 0, value < 0.5 { return "<$1" }
        return wholeMoney.string(from: NSNumber(value: value)) ?? "$0"
    }

    /// A split in one line: "Opus 5.5 $4,049 · Sonnet 5.5 $159 · others $113". A part with no
    /// price has "—", as in a list.
    static func splitLine(_ lines: [CostLine]) -> String {
        lines.map { "\($0.name) \($0.cost == 0 && $0.unpriced > 0 ? "—" : wholeDollars($0.cost))" }.joined(separator: " · ")
    }

    static let atAPIPrices = "at API prices"
    static let noUse = "No token use in this period."
    /// What a screen reader says of the blocks that stand in while a stretch is read.
    static let loadingHistory = "Loading"
    static let opensHistory = "Opens History"
    static let allProjects = "All projects"
    static let showsSessions = "Shows its sessions"
    /// On the band under the History page when it runs past the edge.
    static let historyBelow = "More below"
    static let exportPDF = "Export PDF"
    static let exportPDFHint = "Makes a PDF report of this period and opens it"
    static func couldNotMakePDF(_ reason: String) -> String { "Couldn't make the PDF. " + reason }

    /// "$1,234.56". A sum too small for a cent, but more than nothing, is "<$0.01".
    static func dollars(_ value: Double) -> String {
        if value > 0, value < 0.005 { return "<$0.01" }
        return money.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    /// A line's money, or "—" when all it holds has no price.
    static func dollars(_ line: CostLine) -> String {
        line.cost == 0 && line.unpriced > 0 ? "—" : dollars(line.cost)
    }

    static func date(_ format: String, _ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// "October 2026", "Oct 12 – 18, 2026", "Mon, Oct 12, 2026".
    static func spanTitle(_ span: Span, _ interval: DateInterval, calendar: Calendar) -> String {
        switch span {
        case .month:
            return date("MMMM yyyy", interval.start, calendar)
        case .day:
            return date("EEE, MMM d, yyyy", interval.start, calendar)
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            let sameMonth = calendar.isDate(interval.start, equalTo: last, toGranularity: .month)
            return date("MMM d", interval.start, calendar) + " – " + date(sameMonth ? "d, yyyy" : "MMM d, yyyy", last, calendar)
        }
    }

    /// "Oct 12" for a day picked, "Oct 12, 21:00" for an hour.
    static func pickTitle(_ interval: DateInterval, hourly: Bool, calendar: Calendar) -> String {
        date(hourly ? "MMM d, HH:mm" : "MMM d", interval.start, calendar)
    }

    /// What a bar says to the pointer and to VoiceOver: "Oct 12, $739.25", "21:00, $74.81".
    static func barLabel(_ bar: CostBar, hourly: Bool, calendar: Calendar) -> String {
        axisLabel(bar, hourly: hourly, calendar: calendar) + ", " + dollars(bar.cost)
    }

    /// Under the first and the last bar: "Oct 1", "00:00".
    static func axisLabel(_ bar: CostBar, hourly: Bool, calendar: Calendar) -> String {
        date(hourly ? "HH:mm" : "MMM d", bar.interval.start, calendar)
    }

    /// A split read out whole: "Opus 5.5, $3,990.18; Sonnet 5.5, $186.35".
    static func splitLabel(_ lines: [CostLine]) -> String {
        lines.map { "\($0.name), \(dollars($0))" }.joined(separator: "; ")
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    static func unpriced(_ tokens: Int) -> String { "+ \(count(tokens)) tokens with no price" }

    static func readingHistory(_ progress: ReadingProgress) -> String {
        "Reading history… \(count(progress.done)) of \(count(progress.of)) files"
    }

    /// The foot of the History page: how far back the history goes, and how old its prices are.
    static func historyFoot(since: Date?, calendar: Calendar) -> String {
        let prices = "API prices as of \(Pricing.checkedOn)"
        guard let since else { return prices }
        return "History since \(date("MMM d, yyyy", since, calendar)) · \(prices)"
    }

    /// The ✕ beside what is picked: the step back it takes.
    static func showAll(_ title: String) -> String { "Show all of \(title)" }
}
