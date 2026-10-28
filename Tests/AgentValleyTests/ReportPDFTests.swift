import PDFKit
import SwiftUI
import XCTest
@testable import AgentValley

@MainActor
final class ReportPDFTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date { TranscriptReader.date(from: text)! }

    /// One project's report, a session for each title, the first the costliest.
    private func report(_ titles: [String]) throws -> HistoryDocument {
        let anchor = date("2026-10-15T12:00:00.000Z")
        let answers = titles.indices.map { index in
            LedgerAnswer(id: "\(index)", at: date("2026-10-12T10:00:00.000Z").addingTimeInterval(Double(index) * 60), folder: "/Users/me/app",
                         session: "s\(index)", model: "claude-opus-5-5", output: (titles.count - index) * 50_000)
        }
        let slice = LedgerSlice(answers: answers, titles: Dictionary(uniqueKeysWithValues: titles.indices.map { ("s\($0)", titles[$0]) }),
                                interval: HistoryReport.interval(of: .month, around: anchor, calendar: utc))
        return try XCTUnwrap(HistoryDocument.make(slice, pick: HistoryPick(span: .month, anchor: anchor, project: "/Users/me/app"), calendar: utc,
                                                  home: "/Users/me", printed: date("2026-10-17T08:00:00.000Z")))
    }

    /// One session of `project` in October, an answer of 50,000 tokens out for each agent and model given.
    private func work(_ answers: [(agent: String, model: String)], project: String = "app") throws -> HistoryDocument {
        let anchor = date("2026-10-15T12:00:00.000Z")
        let list = answers.indices.map { index in
            LedgerAnswer(id: "\(index)", at: date("2026-10-12T10:00:00.000Z").addingTimeInterval(Double(index) * 60),
                         folder: "/Users/me/\(project)", session: "s0", agent: answers[index].agent, model: answers[index].model, output: 50_000)
        }
        let slice = LedgerSlice(answers: list, titles: ["s0": "One"], interval: HistoryReport.interval(of: .month, around: anchor, calendar: utc))
        return try XCTUnwrap(HistoryDocument.make(slice, pick: HistoryPick(span: .month, anchor: anchor, project: "/Users/me/\(project)"), calendar: utc,
                                                  home: "/Users/me", printed: date("2026-10-17T08:00:00.000Z")))
    }

    private func text(_ document: HistoryDocument, page: Int? = nil) throws -> String {
        let pdf = try XCTUnwrap(PDFDocument(data: ReportPDF.data(document, calendar: utc)))
        return try XCTUnwrap(page.map { pdf.page(at: $0)?.string } ?? pdf.string)
    }

    private func pages(_ document: HistoryDocument) -> Int {
        HistoryDocument.pages(lines: document.lines.count, first: ReportPDF.firstRows, later: ReportPDF.laterRows).count
    }

    func testEveryLineIsInThePDF() throws {
        let document = try report((1...60).map { String(format: "Task %02d", $0) })
        let pdf = try XCTUnwrap(PDFDocument(data: ReportPDF.data(document, calendar: utc)))
        XCTAssertGreaterThan(pages(document), 1)
        XCTAssertEqual(pdf.pageCount, pages(document))
        let text = try XCTUnwrap(pdf.string)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Statement of work"))
        for word in ["Task 01", "Task 60", "Total", "$1,830.00"] {
            XCTAssertTrue(text.contains(word), word)
        }
        // The total is on the last page.
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: pdf.pageCount - 1)?.string).contains("Total"))
    }

    func testALongThaiTitleStaysOnItsRow() throws {
        let long = String(repeating: "งานปรับหน้า History ให้แสดงต้นทุนแยกตามโปรเจกต์และ session ", count: 5)
        let document = try report([long] + (1...30).map { "Short \($0)" })
        let pdf = try XCTUnwrap(PDFDocument(data: ReportPDF.data(document, calendar: utc)))
        XCTAssertEqual(pdf.pageCount, pages(document))
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: 0)?.string).contains("งานปรับหน้า"))
        // Cut on its row, not wrapped onto the next.
        XCTAssertFalse(try XCTUnwrap(pdf.string).contains(long))
    }

    /// What a client reads, and nothing of the crew: no names, no faces' row, no old labels.
    func testTheSheetSaysWhatAClientReads() throws {
        // A sentence that wraps comes out of the PDF with a line break where it wrapped.
        let text = try text(work([("main", "claude-opus-5-5"), ("Explore", "claude-haiku-5-5"), ("Plan", "claude-sonnet-5-5")]))
            .replacingOccurrences(of: "\n", with: " ")
        // `Caps` writes its labels in capitals, so labels are looked for without case.
        for word in ["Statement of work", "Total at API prices", "By agent", "Main sessions", "Explore", "Plan", "By model",
                     "Oct 1 – 31, 2026", "October 2026",
                     "Amounts are what Anthropic's API would charge for the same tokens, at API prices of \(Pricing.checkedOn). Printed Sat, Oct 17, 2026.",
                     "Page 1 of 1"] {
            XCTAssertTrue(text.localizedCaseInsensitiveContains(word), word)
        }
        // With case: "Printed" stays in the note, the old field label was "PRINTED".
        for gone in ["Sunny", "Walt", "Norm", "Pearl", "Judy", "Faye", "Felix", "Prepared by the crew", "WHO DID THE WORK", "PRINTED", "PRICED AT"] {
            XCTAssertFalse(text.contains(gone), gone)
        }
    }

    /// The tallest first page a report has: every kind of agent, three models and tokens with no
    /// price over the chart; then lines enough to fill the later pages too.
    private func crowded(_ count: Int) throws -> HistoryDocument {
        let agents = ["main", "general-purpose", "Explore", "Plan", "code-reviewer"]
        let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
        let anchor = date("2026-10-15T12:00:00.000Z")
        let start = date("2026-10-12T10:00:00.000Z")
        var answers = (0..<count).map { index in
            LedgerAnswer(id: "\(index)", at: start.addingTimeInterval(Double(index) * 60), folder: "/Users/me/app", session: "s\(index)",
                         agent: agents[index % agents.count], model: models[index % models.count], output: 1_000 * (count - index + 1))
        }
        answers.append(LedgerAnswer(id: "u", at: start, folder: "/Users/me/app", session: "s0", model: "claude-made-up-1", output: 10))
        let slice = LedgerSlice(answers: answers, titles: Dictionary(uniqueKeysWithValues: (0..<count).map { ("s\($0)", String(format: "Task %03d", $0 + 1)) }),
                                interval: HistoryReport.interval(of: .month, around: anchor, calendar: utc))
        return try XCTUnwrap(HistoryDocument.make(slice, pick: HistoryPick(span: .month, anchor: anchor, project: "/Users/me/app"), calendar: utc,
                                                  home: "/Users/me", printed: date("2026-10-17T08:00:00.000Z")))
    }

    /// On every page the last row ends above the foot's note, full pages too, and the total is on
    /// the last page.
    func testFootDoesNotCoverAnyRow() throws {
        let document = try crowded(ReportPDF.firstRows + 2 * ReportPDF.laterRows)
        XCTAssertEqual(document.crew.count, 5)
        XCTAssertEqual(document.models.count, 3)
        XCTAssertGreaterThan(document.unpriced, 0)
        let pdf = try XCTUnwrap(PDFDocument(data: ReportPDF.data(document, calendar: utc)))
        let ranges = HistoryDocument.pages(lines: document.lines.count, first: ReportPDF.firstRows, later: ReportPDF.laterRows)
        // The first two pages are full; the total goes over to a page of its own.
        XCTAssertEqual(ranges.map(\.count), [ReportPDF.firstRows, ReportPDF.laterRows, ReportPDF.laterRows, 0])
        XCTAssertEqual(pdf.pageCount, ranges.count)
        // Full or not, every page keeps the margins of a sheet with one line on it: a page too
        // full spills over both edges.
        func words(_ page: PDFPage) throws -> CGRect {
            try XCTUnwrap(page.selection(for: page.bounds(for: .mediaBox))).bounds(for: page)
        }
        let short = try XCTUnwrap(PDFDocument(data: ReportPDF.data(try work([("main", "claude-opus-5-5")]), calendar: utc))?.page(at: 0))
        let margins = try words(short)
        for index in ranges.indices {
            let all = try words(try XCTUnwrap(pdf.page(at: index)))
            XCTAssertGreaterThanOrEqual(all.minY, margins.minY - 1, "page \(index + 1)")
            XCTAssertLessThanOrEqual(all.maxY, margins.maxY + 1, "page \(index + 1)")
        }
        for (index, range) in ranges.enumerated() where !range.isEmpty {
            let page = try XCTUnwrap(pdf.page(at: index))
            func box(_ words: String) throws -> CGRect {
                try XCTUnwrap(pdf.findString(words, withOptions: []).first { $0.pages.contains(page) }, words).bounds(for: page)
            }
            let last = try box(document.lines[range.upperBound - 1].name)
            let note = try box("Amounts are what")
            // PDF space grows upwards.
            XCTAssertGreaterThan(last.minY, note.maxY + 4, "page \(index + 1)")
            XCTAssertTrue(try XCTUnwrap(page.string).contains(Format.pageLabel(index + 1, of: ranges.count)), "page \(index + 1)")
        }
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: ranges.count - 1)?.string).contains("Total"))
    }

    /// A project's name too long for its row is cut there, and the period beside it stays whole.
    func testALongThaiProjectNameLeavesThePeriod() throws {
        let project = String(repeating: "โปรเจกต์ร้านค้าออนไลน์ของลูกค้า ", count: 6).trimmingCharacters(in: .whitespaces)
        let first = try text(work([("main", "claude-opus-5-5")], project: project), page: 0)
        XCTAssertTrue(first.contains("Oct 1 – 31, 2026"))
        XCTAssertTrue(first.contains("โปรเจกต์ร้านค้า"))
        XCTAssertFalse(first.contains(project))
    }

    func testUnpricedTokensAreStillSaid() throws {
        XCTAssertTrue(try text(work([("main", "claude-opus-5-5"), ("main", "claude-made-up-1")])).contains("tokens with no price"))
    }

    func testPageLabel() {
        XCTAssertEqual(Format.pageLabel(1, of: 1), "Page 1 of 1")
        XCTAssertEqual(Format.pageLabel(2, of: 3), "Page 2 of 3")
    }

    func testAPeriodAsAStatementGivesIt() {
        func period(_ span: Span, _ at: String, _ calendar: Calendar) -> String {
            Format.reportPeriod(HistoryReport.interval(of: span, around: date(at), calendar: calendar), calendar: calendar)
        }
        var monday = utc
        monday.firstWeekday = 2
        XCTAssertEqual(period(.month, "2026-10-15T12:00:00.000Z", utc), "Oct 1 – 31, 2026")
        XCTAssertEqual(period(.week, "2026-10-14T12:00:00.000Z", monday), "Oct 12 – 18, 2026")
        XCTAssertEqual(period(.week, "2026-10-01T12:00:00.000Z", monday), "Sep 28 – Oct 4, 2026")
        XCTAssertEqual(period(.day, "2026-10-12T12:00:00.000Z", utc), "Mon, Oct 12, 2026")
    }

    /// The words over the costliest bar start at it near the left edge and end at it near the
    /// right, so they never hang out into the margin.
    func testAPeakLabelStaysOverTheChart() {
        XCTAssertEqual(ReportPDF.peakAlignment(0, of: 31), .topLeading)
        XCTAssertEqual(ReportPDF.peakAlignment(15, of: 31), .top)
        XCTAssertEqual(ReportPDF.peakAlignment(30, of: 31), .topTrailing)
        XCTAssertEqual(ReportPDF.peakAlignment(0, of: 7), .topLeading)
        XCTAssertEqual(ReportPDF.peakAlignment(3, of: 7), .top)
        XCTAssertEqual(ReportPDF.peakAlignment(6, of: 7), .topTrailing)
        XCTAssertEqual(ReportPDF.peakAlignment(23, of: 24), .topTrailing)
    }

    func testAWriteReplacesTheFileOfTheSameName() throws {
        let document = try report(["One", "Two"])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try ReportPDF.write(document, calendar: utc, folder: folder)
        let second = try ReportPDF.write(document, calendar: utc, folder: folder)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "app October 2026.pdf")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["app October 2026.pdf"])
        XCTAssertNotNil(PDFDocument(url: second))
    }

    // The app's folder is closed to other accounts (the answers socket refuses one that is not),
    // and a report may be the first thing to make it: it and every folder made with it stay private.
    func testTheReportsFolderIsPrivate() throws {
        let document = try report(["One"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("AgentValley/Reports")
        _ = try ReportPDF.write(document, calendar: utc, folder: folder)
        for url in [folder, folder.deletingLastPathComponent()] {
            let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
            XCTAssertEqual(mode & 0o077, 0, url.path)
        }
    }
}
