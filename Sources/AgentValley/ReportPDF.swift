import AppKit
import SwiftUI

/// A History report as A4 pages of PDF: a statement of work from the crew, on the printout
/// paper of the website. Each page is a SwiftUI view drawn into a PDF context, so its words stay
/// words: they can be picked out and searched.
enum ReportPDF {
    static let page = CGSize(width: 595, height: 842)
    /// Lines of the table on the first page, under the summary, and on each page after it. Rows
    /// are one line each and all as tall, so this is known before anything is drawn: the most
    /// that keep a page inside its margins with every By agent and model row in the summary
    /// (tested; one more and the page spills over its top and bottom edges).
    static let firstRows = 23
    static let laterRows = 43
    static let row: CGFloat = 16

    /// Where the words over the costliest bar sit: from the bar rightwards in the first quarter of
    /// the chart, leftwards in the last, centred between.
    static func peakAlignment(_ index: Int, of count: Int) -> Alignment {
        let edge = max(1, count / 4)
        return index < edge ? .topLeading : index >= count - edge ? .topTrailing : .top
    }

    @MainActor static func data(_ document: HistoryDocument, calendar: Calendar) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let pages = HistoryDocument.pages(lines: document.lines.count, first: firstRows, later: laterRows)
        for (index, lines) in pages.enumerated() {
            let sheet = ReportPage(document: document, calendar: calendar, lines: lines, number: index + 1, of: pages.count)
                .frame(width: page.width, height: page.height)
                .environment(\.colorScheme, .light)
                // Fine enough that every cell of the logo and the faces lands on the same grid.
                .environment(\.displayScale, 8)
            let renderer = ImageRenderer(content: sheet)
            renderer.proposedSize = ProposedViewSize(page)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    /// Writes the report as `document.fileName` in `folder`, made if missing. A report of the same
    /// name there is replaced: the folder is the app's own, and one worth keeping has been moved.
    /// Folders made here are closed to other accounts: a report can be the first thing to make the
    /// app's folder, and the answers socket refuses one that others can enter.
    @MainActor static func write(_ document: HistoryDocument, calendar: Calendar,
                                 folder: URL = AnswerServer.defaultDirectory.appendingPathComponent("Reports")) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent(document.fileName(calendar: calendar))
        try data(document, calendar: calendar).write(to: file, options: .atomic)
        return file
    }
}

// MARK: - The paper

/// The website's printout paper and ink.
private enum Ink {
    static let paper = rgb(0xFBF7EE)
    static let type = rgb(0x2A2118)
    static let dim = rgb(0x6B6052)
    static let faint = rgb(0x9A8F80)
    static let rule = rgb(0xD8CDB8)
    /// The costliest bar: the guru's shirt, as what is picked on the panel.
    static let peak = rgb(0xE07B39)
    /// A split's parts by place: amber glass, a darker cream for paper, warm grey.
    static let parts = [rgb(0xE0A030), rgb(0xC9B48A), rgb(0x8C8378)]
}

private extension Font {
    static let paperText = Font.system(size: 9)
    static let figure = Font.system(size: 9, design: .monospaced)
}

/// A small label in capitals, as on a form.
private struct Caps: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text.uppercased())
            .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(Ink.dim)
    }
}

private struct Rule: View {
    var weight: CGFloat = 0.5
    var color = Ink.rule

    var body: some View { Rectangle().fill(color).frame(height: weight) }
}

/// The block-letter name of the website's logo, drawn from its own pixels. A book's pages draw
/// the same cells (`BookPDF`).
struct Wordmark: View {
    let height: CGFloat

    static let rows = [
        "d.LLLLLLd.LLLLLLd.LLLLLLd.LLLLLLd.LLLLLLd.LLd.LLd.LLLLLLd.LLd.d.d.LLd.d.d.LLLLLLd.LLd.LL",
        "..LLLLLL..LLLLLL..LLLLLL..LLLLLL..LLLLLL..LL..LL..LLLLLL..LL......LL......LLLLLL..LL..LL",
        ".dLL..LL.dLL.....dLL.....dLL..LL.d..LL...dLL.dLL.dLL..LL.dLL.d.d.dLL.d.d.dLL.....dLL.dLL",
        "..LL..LL..LL......LL......LL..LL....LL....LL..LL..LL..LL..LL......LL......LL......LL..LL",
        "d.LLLLLLd.LLd.LLd.LLLLLLd.LLd.LLd.d.LLd.d..LLLL.d.LLLLLLd.LLd.d.d.LLd.d.d.LLLLLLd.d.LLd.",
        "..LLLLLL..LL..LL..LLLLLL..LL..LL....LL.....LLLL...LLLLLL..LL......LL......LLLLLL....LL..",
        ".dLL..LL.dLL.dLL.dLL.....dLL.dLL.d.dLL.d.d.LLLL..dLL..LL.dLL.d.d.dLL.d.d.dLL.....d.dLL.d",
        "..LL..LL..LL..LL..LL......LL..LL....LL.....LLLL...LL..LL..LL......LL......LL........LL..",
        "d.LLd.LLd.LLLLLLd.LLLLLLd.LLd.LLd.d.LLd.d.d.LLd.d.LLd.LLd.LLLLLLd.LLLLLLd.LLLLLLd.d.LLd.",
        "..LL..LL..LLLLLL..LLLLLL..LL..LL....LL......LL....LL..LL..LLLLLL..LLLLLL..LLLLLL....LL..",
        ".d...d...d.......d.......d...d...d.d...d.d.d...d.d...d...d.......d.......d.......d.d...d",
        "........................................................................................",
    ].map(Array.init)

    var body: some View {
        Pixels(cells: Self.rows, size: height * 88 / 12) { Self.hex($0).map(rgb) }
        .accessibilityLabel(Text(verbatim: "AgentValley"))
    }

    /// The letters, and the shadow they cast.
    static func hex(_ cell: Character) -> UInt32? {
        switch cell {
        case "L": 0x23190F
        case "d": 0xB8A685
        default: nil
        }
    }
}

/// The block-letter logo, small, slanted and faint, in staggered rows over the whole sheet, under
/// the words: two to a row, then three around them, fifteen to a page. A book's pages draw the
/// same marks (`BookPDF`).
struct Watermark: View {
    private static let spots: [CGPoint] = (0..<6).flatMap { row in
        let columns: [CGFloat] = row.isMultiple(of: 2) ? [195, 455] : [65, 325, 585]
        return columns.map { CGPoint(x: $0, y: 32 + CGFloat(row) * 150) }
    }

    /// The letters as one shape, 132 wide and centred on the origin, a run of cells in a row to a
    /// box: drawn a cell at a time, fifteen marks made the file six times the size.
    static let letters: Path = {
        let cell: CGFloat = 1.5
        var path = Path()
        for (y, row) in Wordmark.rows.enumerated() {
            var x = 0
            while x < row.count {
                guard row[x] == "L" else { x += 1; continue }
                let start = x
                while x < row.count, row[x] == "L" { x += 1 }
                path.addRect(CGRect(x: CGFloat(start - 44) * cell, y: CGFloat(y - 6) * cell, width: CGFloat(x - start) * cell, height: cell))
            }
        }
        return path
    }()

    /// Where each mark goes, slanted up to the right, on a page whose top left is the origin.
    static let places = spots.map { CGAffineTransform(rotationAngle: -.pi / 6).concatenating(CGAffineTransform(translationX: $0.x, y: $0.y)) }
    static let opacity = 0.045

    var body: some View {
        Canvas { context, _ in
            for place in Self.places {
                context.fill(Self.letters.applying(place), with: .color(rgb(0x23190F).opacity(Self.opacity)))
            }
        }
    }
}

// MARK: - A page

private struct ReportPage: View {
    let document: HistoryDocument
    let calendar: Calendar
    let lines: Range<Int>
    let number: Int
    let of: Int

    private var title: String { Format.spanTitle(document.span, document.interval, calendar: calendar) }
    private var subject: String { document.project ?? "All projects" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if number == 1 { summary } else { runningHead }
            LineTable(document: document, calendar: calendar, lines: lines, last: number == of)
            Spacer(minLength: 0)
            foot
        }
        .padding(.horizontal, 46)
        .padding(.top, 38)
        .padding(.bottom, 32)
        .foregroundStyle(Ink.type)
        .font(.paperText)
        .background { Watermark() }
        .background(Ink.paper)
    }

    // MARK: The first page

    /// What the client looks for first: whose work, which month, how much. The period keeps its
    /// room; a name too long for the rest is cut in the middle.
    @ViewBuilder private var summary: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Caps("Statement of work")
                Text(verbatim: subject).font(.system(size: 22, weight: .bold)).tracking(-0.3).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: title).font(.system(size: 11, weight: .bold, design: .monospaced))
                Text(verbatim: Format.reportPeriod(document.interval, calendar: calendar))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Ink.dim)
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.bottom, 12)
        Rule(weight: 1.5, color: Ink.type)

        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: Format.reportFacts(document))
                if document.unpriced > 0 { Text(verbatim: Format.unpriced(document.unpriced)) }
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(Ink.dim)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Caps("Total at API prices")
                Text(verbatim: Format.dollars(document.total)).font(.system(size: 26, weight: .bold, design: .monospaced)).fixedSize()
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        Rule()

        Chart(document: document, calendar: calendar)
            .padding(.top, 20)
            .padding(.bottom, 16)

        HStack(alignment: .top, spacing: 24) {
            AgentTable(crew: document.crew).frame(maxWidth: .infinity, alignment: .leading)
            ModelTable(models: document.models).frame(width: 196)
        }
        .padding(.bottom, 18)
    }

    // MARK: Later pages

    @ViewBuilder private var runningHead: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(verbatim: subject).font(.system(size: 9, weight: .semibold)).lineLimit(1)
            Spacer()
            Caps("Statement of work · \(title)")
        }
        .padding(.bottom, 8)
        Rule(weight: 1, color: Ink.type)
            .padding(.bottom, 12)
    }

    // MARK: The foot of every page

    /// The note on the amounts, in type a client reads, and the block-letter mark over the page
    /// number in the corner.
    private var foot: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(alignment: .bottom, spacing: 24) {
                Text(verbatim: Format.reportNote(printed: document.printed, calendar: calendar))
                    .font(.system(size: 8))
                    .foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Wordmark(height: 9)
                    Text(verbatim: Format.pageLabel(number, of: of))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Ink.faint)
                }
                .fixedSize()
            }
            .padding(.top, 10)
        }
    }
}

// MARK: - Parts of the first page

/// A bar a day, or an hour on a day's report. The costliest is orange and says what it was.
private struct Chart: View {
    let document: HistoryDocument
    let calendar: Calendar
    private let height: CGFloat = 34

    var body: some View {
        let hourly = document.span == .day
        let top = document.bars.map(\.cost).max() ?? 0
        let peak = top > 0 ? document.bars.firstIndex { $0.cost == top } : nil
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(document.bars.indices, id: \.self) { index in
                    let bar = document.bars[index]
                    let flat = bar.cost <= 0 || bar.interval.start > document.printed
                    Rectangle()
                        .fill(index == peak ? Ink.peak : flat ? Ink.rule : Ink.type)
                        .frame(height: flat ? 1.5 : max(1.5, height * bar.cost / top))
                        .overlay(alignment: ReportPDF.peakAlignment(index, of: document.bars.count)) {
                            if index == peak {
                                Text(verbatim: Format.peakLabel(bar, hourly: hourly, calendar: calendar))
                                    .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Ink.peak)
                                    .fixedSize()
                                    .offset(y: -11)
                            }
                        }
                }
            }
            .frame(height: height, alignment: .bottom)
            if let first = document.bars.first, let last = document.bars.last {
                HStack {
                    Text(verbatim: Format.axisLabel(first, hourly: hourly, calendar: calendar))
                    Spacer()
                    Text(verbatim: Format.axisLabel(last, hourly: hourly, calendar: calendar))
                }
                .font(.system(size: 6.5, design: .monospaced))
                .foregroundStyle(Ink.faint)
            }
        }
    }
}

/// By agent: a line for each kind of agent, its rows level with By model's beside it, under that
/// table's bar.
private struct AgentTable: View {
    let crew: [HistoryCrewLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps("By agent").padding(.bottom, 18)
            ForEach(crew.indices, id: \.self) { index in
                VStack(spacing: 0) {
                    HStack {
                        Text(verbatim: crew[index].name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(verbatim: Format.dollars(crew[index].cost)).font(.figure)
                    }
                    .frame(height: 18)
                    Rule()
                }
            }
        }
    }
}

private struct ModelTable: View {
    let models: [CostLine]

    var body: some View {
        let total = models.reduce(0) { $0 + $1.cost }
        VStack(alignment: .leading, spacing: 0) {
            Caps("By model").padding(.bottom, 9)
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(models.indices, id: \.self) { index in
                        Rectangle().fill(Ink.parts[min(index, Ink.parts.count - 1)])
                            .frame(width: total > 0 ? geometry.size.width * models[index].cost / total : 0)
                    }
                }
            }
            .frame(height: 5)
            .clipShape(RoundedRectangle(cornerRadius: 2.5))
            .padding(.bottom, 4)
            ForEach(models.indices, id: \.self) { index in
                VStack(spacing: 0) {
                    HStack {
                        Text(verbatim: models[index].name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(verbatim: Format.dollars(models[index])).font(.figure)
                    }
                    .frame(height: 18)
                    Rule()
                }
            }
        }
    }
}

// MARK: - The lines

/// The lines of the statement on one page, costliest first, a thin rule under each; on the last
/// page, the total under them.
private struct LineTable: View {
    let document: HistoryDocument
    let calendar: Calendar
    let lines: Range<Int>
    let last: Bool

    private var sessions: Bool { document.project != nil }
    private var hourly: Bool { document.span == .day }

    var body: some View {
        VStack(spacing: 0) {
            row(index: "", name: Caps(sessions ? "Session" : "Project"),
                middle: Caps(sessions ? (hourly ? "Time" : "Days") : "Sessions"),
                answers: Caps("Answers"), amount: Caps("Amount"))
            ForEach(Array(lines), id: \.self) { index in
                let line = document.lines[index]
                row(index: String(format: "%02d", index + 1),
                    name: Text(verbatim: line.name),
                    middle: sessions
                        ? Text(verbatim: Format.reportDays(line, hourly: hourly, calendar: calendar)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Ink.dim)
                        : Text(verbatim: Format.count(line.sessions)).font(.figure).foregroundStyle(Ink.type),
                    answers: Text(verbatim: Format.count(line.answers)).font(.figure),
                    amount: Text(verbatim: Format.dollars(line)).font(.figure))
                    .overlay(alignment: .bottom) { Rule() }
            }
            if last {
                Rule(weight: 1, color: Ink.type)
                row(index: "", name: Text(verbatim: "Total").bold(),
                    middle: sessions ? Text(verbatim: "") : Text(verbatim: Format.count(document.sessions)).font(.figure.bold()),
                    answers: Text(verbatim: Format.count(document.answers)).font(.figure.bold()),
                    amount: Text(verbatim: Format.dollars(document.total)).font(.figure.bold()))
            }
        }
    }

    private func row(index: String, name: some View, middle: some View, answers: some View, amount: some View) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: index).font(.system(size: 8, design: .monospaced)).foregroundStyle(Ink.faint)
                .frame(width: 24, alignment: .leading)
            name.lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            middle.lineLimit(1).frame(width: sessions ? 78 : 60, alignment: sessions ? .leading : .trailing)
            answers.lineLimit(1).frame(width: 60, alignment: .trailing)
            amount.lineLimit(1).frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 5)
        .frame(height: ReportPDF.row)
    }
}

extension Format {
    /// "Page 2 of 3".
    static func pageLabel(_ number: Int, of count: Int) -> String { "Page \(number) of \(count)" }

    /// The foot's note: what the amounts are, the prices they come from, and the day printed.
    static func reportNote(printed: Date, calendar: Calendar) -> String {
        "Amounts are what Anthropic's API would charge for the same tokens, at API prices of \(Pricing.checkedOn). "
            + "Printed \(date("EEE, MMM d, yyyy", printed, calendar))."
    }

    /// The whole stretch, as a statement gives its period: "Oct 1 – 31, 2026", "Oct 12 – 18, 2026",
    /// "Sep 28 – Oct 4, 2026", "Mon, Oct 12, 2026".
    static func reportPeriod(_ interval: DateInterval, calendar: Calendar) -> String {
        let last = interval.end.addingTimeInterval(-1)
        if calendar.isDate(interval.start, inSameDayAs: last) { return date("EEE, MMM d, yyyy", interval.start, calendar) }
        let sameMonth = calendar.isDate(interval.start, equalTo: last, toGranularity: .month)
        return date("MMM d", interval.start, calendar) + " – " + date(sameMonth ? "d, yyyy" : "MMM d, yyyy", last, calendar)
    }
}
