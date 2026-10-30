import SwiftUI

/// The History page of the panel: what the API would have charged, by stretch of time and by
/// project, and within a project by session. It stands where the list was, as the settings do,
/// on the panel's own scroll.
struct HistoryPage: View {
    @ObservedObject var ledger: UsageLedger
    @Binding var pick: HistoryPick
    /// Back to the agents.
    let back: () -> Void
    private let calendar: Calendar
    private let home: String
    @State private var slice = LedgerSlice()
    /// Worked out when the pick or the answers change, not at every drawing.
    @State private var report: HistoryReport
    @State private var exportProblem: String?

    init(ledger: UsageLedger, pick: Binding<HistoryPick>, calendar: Calendar = HistoryReport.calendar(), home: String = NSHomeDirectory(),
         back: @escaping () -> Void) {
        self.ledger = ledger
        _pick = pick
        self.back = back
        self.calendar = calendar
        self.home = home
        _report = State(initialValue: HistoryReport.make(LedgerSlice(), pick: pick.wrappedValue, calendar: calendar, home: home))
    }

    /// What has to be read again from the ledger: another stretch, or more written to it.
    private struct Load: Equatable {
        let interval: DateInterval
        let revision: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if pick.project != nil {
                    // One level up. The day or hour picked stays.
                    BackToAgents(title: Format.allProjects) { pick.project = nil }
                } else {
                    BackToAgents(action: back)
                }
                Spacer(minLength: 0)
                // At the top, not at the foot: a month of every project runs to a long scroll.
                exportButton
                ChoiceBar(title: "Span", choices: Span.allCases, label: { $0.rawValue }, selection: Binding(get: { pick.span }, set: { span in
                    // Another span: the project stays, and it shows the day that was.
                    pick = HistoryPick(span: span, anchor: pick.day ?? pick.anchor, project: pick.project)
                }))
            }
            if let problem = ledger.problem { ProblemLine(text: problem) }
            if let exportProblem { ProblemLine(text: exportProblem) }
            if let reading = ledger.reading {
                Text(verbatim: Format.readingHistory(reading)).foregroundStyle(.white.opacity(0.6))
            } else {
                stretch
                if let project = report.projectName {
                    Text(verbatim: project).bold().lineLimit(1)
                }
                if report.ready {
                    bars
                    if pick.project == nil { everyProject } else { oneProject }
                } else {
                    HistorySkeleton(bars: report.bars, hourly: pick.span == .day, calendar: calendar, project: pick.project != nil)
                }
                Text(verbatim: Format.historyFoot(since: slice.since, calendar: calendar))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .onChange(of: pick) {
            exportProblem = nil
            rebuild()
        }
        .task(id: Load(interval: report.interval, revision: ledger.revision)) {
            ledger.load(report.interval) { slice in
                self.slice = slice
                rebuild()
            }
        }
    }

    private func rebuild() {
        report = HistoryReport.make(slice, pick: pick, calendar: calendar, home: home)
    }

    // MARK: - The report

    private var exportButton: some View {
        Button(action: export) {
            // As "← Agents" across from it.
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc").font(.system(size: 10, weight: .semibold))
                Text(verbatim: Format.exportPDF)
            }
            .foregroundStyle(.white.opacity(report.exportable ? 0.8 : 0.25))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
            .hoverFill()
        }
        .buttonStyle(.plain)
        .disabled(!report.exportable)
        .accessibilityLabel(Text(verbatim: Format.exportPDF))
        .accessibilityHint(Text(verbatim: Format.exportPDFHint))
    }

    /// The whole stretch on the page, to a PDF the default app opens. Made only here, on the
    /// press: it reads the whole stretch again.
    private func export() {
        guard let document = HistoryDocument.make(slice, pick: pick, calendar: calendar, home: home, printed: Date()) else { return }
        do {
            NSWorkspace.shared.open(try ReportPDF.write(document, calendar: calendar))
            exportProblem = nil
        } catch {
            exportProblem = Format.couldNotMakePDF(error.localizedDescription)
        }
    }

    // MARK: - The stretch and its bars

    /// ‹ the stretch ›, and what it came to.
    private var stretch: some View {
        let earlier = slice.since.map { report.interval.start > $0 } ?? false
        let later = report.interval.end <= Date()
        return HStack(alignment: .top, spacing: 4) {
            Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 18, height: 18).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .disabled(!earlier)
                .opacity(earlier ? 0.8 : 0.25)
                .accessibilityLabel(Text(verbatim: "Earlier"))
            Text(verbatim: Format.spanTitle(pick.span, report.interval, calendar: calendar)).bold().lineLimit(1)
            Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 18, height: 18).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .disabled(!later)
                .opacity(later ? 0.8 : 0.25)
                .accessibilityLabel(Text(verbatim: "Later"))
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                if report.ready {
                    Text(verbatim: Format.dollars(report.total)).font(.system(size: 16, weight: .bold, design: .monospaced))
                } else {
                    // Not $0.00 while another stretch is read.
                    Block(width: 96).frame(height: 19).shimmer()
                }
                Text(verbatim: Format.atAPIPrices).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                if report.ready, report.unpriced > 0 {
                    Text(verbatim: Format.unpriced(report.unpriced)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    @ViewBuilder private var bars: some View {
        let hourly = pick.span == .day
        CostBars(bars: report.bars, picked: hourly ? pick.hour : pick.day, height: 64, hourly: hourly, calendar: calendar) { bar in
            if hourly {
                pick.hour = pick.hour == bar.interval.start ? nil : bar.interval.start
            } else {
                pick.hour = nil
                pick.day = pick.day == bar.interval.start ? nil : bar.interval.start
            }
        }
        if report.focus != report.interval {
            HStack(spacing: 6) {
                Text(verbatim: Format.pickTitle(report.focus, hourly: pick.hour != nil, calendar: calendar) + " · " + Format.dollars(report.focusCost))
                Button(action: backOut) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: Format.showAll(backTitle)))
            }
            .foregroundStyle(pickedColor)
        }
        if !report.hours.isEmpty {
            CostBars(bars: report.hours, picked: pick.hour, height: 34, hourly: true, calendar: calendar) { bar in
                pick.hour = pick.hour == bar.interval.start ? nil : bar.interval.start
            }
        }
        if pick.project == nil ? report.projects.isEmpty : report.sessions.isEmpty {
            Text(verbatim: Format.noUse).foregroundStyle(.white.opacity(0.6))
        }
    }

    /// What ✕ goes back to: from an hour, its day; from a day, the whole stretch.
    private var backTitle: String {
        if pick.hour != nil, pick.span != .day, let day = pick.day, let interval = calendar.dateInterval(of: .day, for: day) {
            return Format.pickTitle(interval, hourly: false, calendar: calendar)
        }
        return Format.spanTitle(pick.span, report.interval, calendar: calendar)
    }

    private func backOut() {
        if pick.hour != nil, pick.span != .day, pick.day != nil {
            pick.hour = nil
        } else {
            pick.day = nil
            pick.hour = nil
        }
    }

    /// ‹ and ›: the stretch before or after. The project stays; the day and hour picked go.
    private func step(_ by: Int) {
        let anchor = calendar.date(byAdding: pick.span.component, value: by, to: report.interval.start) ?? pick.anchor
        pick = HistoryPick(span: pick.span, anchor: anchor, project: pick.project)
    }

    // MARK: - The two levels

    @ViewBuilder private var everyProject: some View {
        SplitLine(lines: report.models)
        SplitLine(lines: report.agents)
        Heading("Projects")
        VStack(spacing: 0) {
            ForEach(report.projects) { line in
                Button { pick.project = line.id } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: line.name).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                        Spacer(minLength: 8)
                        Text(verbatim: Format.dollars(line))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                    .hoverFill(radius: 5)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -6)
                .accessibilityLabel(Text(verbatim: "\(line.name), \(Format.dollars(line))"))
                .accessibilityHint(Text(verbatim: Format.showsSessions))
            }
        }
    }

    @ViewBuilder private var oneProject: some View {
        Heading("Sessions")
        VStack(alignment: .leading, spacing: 0) {
            ForEach(report.sessions) { line in
                HStack(spacing: 6) {
                    Text(verbatim: line.name).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: Format.dollars(line))
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(line.name), \(Format.dollars(line))"))
            }
        }
        SplitLine(lines: report.models)
        SplitLine(lines: report.agents)
    }
}

/// What went wrong on a page, as History and the Library say it. Not orange: orange is what is picked.
struct ProblemLine: View {
    let text: String

    var body: some View {
        Label { Text(verbatim: text).foregroundStyle(.white.opacity(0.8)) } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LimitMeter.color(.critical))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// What is picked, and nothing else: the guru's shirt and the mug's rim.
private let pickedColor = rgb(0xE07B39)

/// Bars of what was spent, each a button for its stretch: it picks the stretch, and picks it
/// off again. One still to come cannot be picked, and is not read out.
private struct CostBars: View {
    let bars: [CostBar]
    let picked: Date?
    let height: CGFloat
    let hourly: Bool
    let calendar: Calendar
    let pick: (CostBar) -> Void

    var body: some View {
        let top = bars.map(\.cost).max() ?? 0
        let now = Date()
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(bars) { bar in
                    let future = bar.interval.start > now
                    Button { pick(bar) } label: {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(future ? Color.white.opacity(0.1)
                                      : bar.interval.start == picked ? pickedColor : Color.white.opacity(picked == nil ? 0.7 : 0.35))
                                .frame(height: top > 0 && !future ? max(2, height * bar.cost / top) : 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(future)
                    .accessibilityHidden(future)
                    .help(Format.barLabel(bar, hourly: hourly, calendar: calendar))
                    .accessibilityLabel(Text(verbatim: Format.barLabel(bar, hourly: hourly, calendar: calendar)))
                    .accessibilityAddTraits(bar.interval.start == picked ? .isSelected : [])
                }
            }
            if let first = bars.first, let last = bars.last {
                HStack {
                    Text(verbatim: Format.axisLabel(first, hourly: hourly, calendar: calendar))
                    Spacer()
                    Text(verbatim: Format.axisLabel(last, hourly: hourly, calendar: calendar))
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            }
        }
    }
}

/// Stands in for the bars and the lists while a stretch is read: blocks where they will be, in
/// their order, and as tall as a page of a busy month, so that the panel does not shrink and
/// grow again when they come.
private struct HistorySkeleton: View {
    let bars: [CostBar]
    let hourly: Bool
    let calendar: Calendar
    /// One project's level: its sessions, then the splits.
    let project: Bool

    /// The bars' heights, made up and fixed: a month's work, roughly.
    private static let heights: [CGFloat] = [0.35, 0.5, 0.8, 0.6, 0.75, 0.3, 0.45, 0.9, 0.55, 0.7, 0.4, 0.65, 0.85, 0.5, 0.3, 0.6]
    /// The rows' names, as parts of the panel's width.
    private static let names: [CGFloat] = [0.55, 0.4, 0.62, 0.35, 0.48, 0.58, 0.3, 0.44]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 3) {
                let now = Date()
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                        // One still to come is flat, as it will be.
                        Block(radius: 2).frame(height: bar.interval.start > now ? 2 : 64 * Self.heights[index % Self.heights.count])
                    }
                }
                .frame(height: 64, alignment: .bottom)
                if let first = bars.first, let last = bars.last {
                    HStack {
                        Text(verbatim: Format.axisLabel(first, hourly: hourly, calendar: calendar))
                        Spacer()
                        Text(verbatim: Format.axisLabel(last, hourly: hourly, calendar: calendar))
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            if !project { splits }
            Heading(project ? "Sessions" : "Projects")
            VStack(spacing: 0) {
                ForEach(Self.names.indices, id: \.self) { index in
                    HStack {
                        GeometryReader { geometry in
                            Block().frame(width: geometry.size.width * Self.names[index], height: 10)
                                .frame(maxHeight: .infinity)
                        }
                        Block(width: 56).frame(height: 10)
                    }
                    .frame(height: 16)
                    .padding(.vertical, 4)
                }
            }
            if project { splits }
        }
        .shimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Format.loadingHistory))
    }

    private var splits: some View {
        ForEach(0..<2, id: \.self) { index in
            VStack(alignment: .leading, spacing: 3) {
                Block(radius: 3).frame(height: 6)
                Block(width: index == 0 ? 260 : 200).frame(height: 10).padding(.vertical, 1.5)
            }
        }
    }
}

/// A grey block standing in for something not yet read.
private struct Block: View {
    var width: CGFloat?
    var radius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: radius).fill(Color.white.opacity(0.1)).frame(width: width)
    }
}

extension View {
    /// A soft light passing over grey blocks, left to right. It goes by the clock, so that blocks
    /// apart on the page pass it together. None under Reduce Motion: the blocks stand still.
    func shimmer() -> some View { modifier(Shimmer()) }
}

private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let period: TimeInterval = 1.6

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                    GeometryReader { geometry in
                        let band = max(geometry.size.width * 0.5, 120)
                        LinearGradient(colors: [.clear, .white.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + (geometry.size.width + band * 2) * phase)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct Heading: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A split of what was spent: one bar of parts, and under it the parts in one line. The parts
/// go by place, not by name: colour no longer says the model, and the line under it names them.
private struct SplitLine: View {
    let lines: [CostLine]
    /// The mascots' amber glass, the mug's cream, and a warm grey for the rest.
    private static let parts = [rgb(0xE0A030), rgb(0xF2EAD8), rgb(0x8C8378)]

    var body: some View {
        if !lines.isEmpty {
            let total = lines.reduce(0) { $0 + $1.cost }
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            Rectangle()
                                .fill(Self.parts[min(index, Self.parts.count - 1)])
                                .frame(width: total > 0 ? geometry.size.width * line.cost / total : 0)
                        }
                    }
                }
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(verbatim: Format.splitLine(lines))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Format.splitLabel(lines)))
        }
    }
}
