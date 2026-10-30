import PDFKit
import XCTest
@testable import AgentValley

final class BookPDFTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func chapter(_ index: Int, agent: String? = nil, session: String = "s1", title: String? = nil, asked: String = "Look into it.",
                         text: String) -> Chapter {
        Chapter(agent: agent ?? "/tmp/agent-\(index).jsonl", session: session, folder: "/Users/me/app", type: "general-purpose",
                title: title ?? "Task number \(index)", asked: asked, text: text,
                at: Date(timeIntervalSince1970: 1_793_000_000 + Double(index) * 600))
    }

    private func pdf(_ chapters: [Chapter], title: String = "Moving day") throws -> PDFDocument {
        let book = BookDocument(title: title, project: "AgentValley", chapters: chapters)
        return try XCTUnwrap(PDFDocument(data: BookPDF.data(book, calendar: utc)))
    }

    private func outline(_ pdf: PDFDocument) throws -> [PDFOutline] {
        let root = try XCTUnwrap(pdf.outlineRoot)
        return (0..<root.numberOfChildren).compactMap { root.child(at: $0) }
    }

    /// Preview's sidebar is the book's table of contents, and a chapter that shared a page with the last would be hard to find.
    func testEachChapterIsAnOutlineEntryAndStartsAPage() throws {
        let pdf = try pdf((1...3).map { chapter($0, text: "Work \($0) done.") })
        let entries = try outline(pdf)
        XCTAssertEqual(pdf.outlineRoot?.numberOfChildren, 3)
        XCTAssertEqual(entries.map(\.label), ["Task number 1", "Task number 2", "Task number 3"])
        let pages = try entries.map { pdf.index(for: try XCTUnwrap($0.destination?.page)) }
        XCTAssertEqual(pages.first, 0)
        XCTAssertEqual(pages, pages.sorted())
        XCTAssertEqual(Set(pages).count, 3)
    }

    /// Every page wears the costs PDF's faint slanted logos: the empty lower half of a short chapter is not bare white.
    func testEveryPageHasTheWatermark() throws {
        let page = try XCTUnwrap(try pdf([chapter(1, text: "Done.")]).page(at: 0))
        let box = page.bounds(for: .mediaBox)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(box.width), pixelsHigh: Int(box.height),
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap)).cgContext
        page.draw(with: .mediaBox, to: context)
        // Rows 560 to 700 from the top: below the chapter's few lines, above the foot.
        let faint = (560..<700).contains { y in
            (0..<Int(box.width)).contains { x in
                let colour = bitmap.colorAt(x: x, y: y)!
                return colour.redComponent < 0.99 && colour.redComponent > 0.85
            }
        }
        XCTAssertTrue(faint)
    }

    /// A chapter reads top to bottom as the mockup lays it out: where you are, what it was, who and when, the gist, the work, the ask.
    func testAChapterReadsInOrder() throws {
        let first = chapter(1, asked: "Find the slow query.", text: "In short: The page was slow because of one query.\n\nThe index on users was missing.")
        let page = try XCTUnwrap(try pdf([first, chapter(2, text: "Two."), chapter(3, text: "Three.")]).page(at: 0)?.string)
        let parts = ["Moving day · AgentValley", "Chapter 1 of 3", "Task number 1", "Felix", "IN SHORT",
                     "The page was slow because of one query.", "The index on users was missing.", "Asked:", "Find the slow query."]
        var after = page.startIndex
        for part in parts {
            let found = try XCTUnwrap(page.range(of: part, range: after..<page.endIndex), "\(part) missing or out of order in:\n\(page)")
            after = found.upperBound
        }
    }

    /// Hand-backs and asks are kept whole: a long one runs onto more pages instead of losing its end,
    /// boxed code and the ask's ruled block too (a box once ran off its page and lost its lines).
    func testALongChapterFlowsOverPages() throws {
        let code = "```\n" + (1...90).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n```"
        let asked = String(repeating: "## Step\nKeep going.\n\n", count: 60) + "Ask ends here."
        let pdf = try pdf([chapter(1, asked: asked, text: String(repeating: "word ", count: 4_000) + "\n\n" + code + "\n\nThe last line.")])
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let last = try XCTUnwrap(pdf.page(at: pdf.pageCount - 1)?.string)
        XCTAssertTrue(last.contains("Page \(pdf.pageCount) of \(pdf.pageCount)"), last)
        let all = try XCTUnwrap(pdf.string)
        for line in ["let value1 = 1", "let value57 = 57", "let value90 = 90", "The last line.", "Ask ends here."] {
            XCTAssertTrue(all.contains(line), line)
        }
        XCTAssertEqual(all.components(separatedBy: "Keep going.").count - 1, 60)
    }

    /// Readers who don't code should see a printed page, not the Markdown it came from, even when the Markdown is broken.
    func testAwkwardMarkdownRendersWithoutMarks() throws {
        let text = """
        ## What changed
        **Bold** words and a table:

        | File | Lines |
        |---|---|
        | a.swift | 12 |

        \(String(repeating: "long ", count: 600))

        สรุปงานวันนี้ 🎉 <b>html</b>

        ```swift
        let fence = "never closed"
        """
        let pdf = try pdf([chapter(1, text: text)])
        for index in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index)?.string)
            for mark in ["**", "## ", "```", "|---"] { XCTAssertFalse(page.contains(mark), "\(mark) on page \(index + 1)") }
        }
        let all = try XCTUnwrap(pdf.string)
        XCTAssertTrue(all.contains("สรุปงานวันนี้"), all)
        XCTAssertTrue(all.contains("never closed"), all)
    }

    /// A full path is noise to a reader; the file's name is what tells them something, in the work and in the ask alike.
    func testPathsShowOnlyTheirFileName() throws {
        let all = try XCTUnwrap(try pdf([chapter(1, asked: "Read ~/code/app/plan.md first.", text: "Wrote /Users/x/a/b/notes.md today.")]).string)
        XCTAssertTrue(all.contains("notes.md"), all)
        XCTAssertFalse(all.contains("/Users/x/a/b"), all)
        XCTAssertTrue(all.contains("plan.md"), all)
        XCTAssertFalse(all.contains("~/code/app"), all)
    }

    /// A command in a code block is copied as written; cutting its paths would hand the reader a wrong command.
    func testACodeBlockKeepsItsPathsWhileProseIsCut() throws {
        let text = "Ran it from /Users/x/proj/notes.md today.\n\n```\ncd /Users/x/proj/build && rm -rf /tmp/a/b\n```"
        let all = try XCTUnwrap(try pdf([chapter(1, text: text)]).string)
        XCTAssertTrue(all.contains("cd /Users/x/proj/build && rm -rf /tmp/a/b"), all)
        XCTAssertTrue(all.contains("notes.md"), all)
        XCTAssertFalse(all.contains("/Users/x/proj/notes.md"), all)
    }

    /// A table's last row would otherwise sit right on the paragraph under it.
    func testATablesLastRowLeavesAParagraphsRoom() throws {
        let text = BookText.attributed("| A | B |\n|---|---|\n| x | y |\n| last | row |\n\nAfter the table.")
        let spacing = { (word: String) in
            (text.attribute(.paragraphStyle, at: (text.string as NSString).range(of: word).location, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing
        }
        XCTAssertEqual(spacing("last"), spacing("After the table."))
        XCTAssertLessThan(try XCTUnwrap(spacing("x")), try XCTUnwrap(spacing("last")))
    }

    /// This Mac counts years in the Buddhist era (2569); a byline in English must say 2026 without being told the calendar.
    func testTheBylineYearIsGregorianByDefault() throws {
        let book = BookDocument(title: "Moving day", project: "AgentValley", chapters: [chapter(1, text: "Done.")])
        let page = try XCTUnwrap(PDFDocument(data: BookPDF.data(book))?.page(at: 0)?.string)
        XCTAssertTrue(page.contains("2026"), page)
        XCTAssertFalse(page.contains("2569"), page)
    }

    /// Older hand-backs have no plain note, and an empty box would look like something went missing.
    func testNoInShortMeansNoBox() throws {
        let all = try XCTUnwrap(try pdf([chapter(1, text: "Just the work.")]).string)
        XCTAssertFalse(all.localizedCaseInsensitiveContains("In short"), all)
    }

    /// The same crew member handing back again is the same job carried on, so its chapter says so.
    func testALaterHandBackOfTheSameAgentIsContinued() throws {
        let pdf = try pdf([chapter(1, agent: "/tmp/a.jsonl", title: "Fix the login", text: "First."),
                           chapter(2, agent: "/tmp/a.jsonl", title: "Fix the login", text: "Second.")])
        let entries = try outline(pdf)
        XCTAssertEqual(entries.map(\.label), ["Fix the login", "Fix the login (continued)"])
        let page = try XCTUnwrap(entries[1].destination?.page?.string)
        XCTAssertTrue(page.contains("Fix the login (continued)"), page)
    }

    /// A title is the chat's name and can hold "/" or ":", which a file name can't; reopening the book replaces its file.
    func testAWriteNamesTheFileAfterTheBook() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = BookDocument(title: "Plan: login/signup", project: "AgentValley", chapters: [chapter(1, text: "Done.")])
        _ = try BookPDF.write(book, calendar: utc, folder: folder)
        let file = try BookPDF.write(book, calendar: utc, folder: folder)
        XCTAssertEqual(file.lastPathComponent, "Plan- login-signup.pdf")
        XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(PDFDocument(url: file)?.pageCount, 1)
    }

    /// The PDF is kept to open again, but not past a change that shows on it: a renamed project must not open the old head.
    func testAKeptBookIsMadeAgainWhenItsProjectIsRenamed() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let chapters = [chapter(1, text: "Done.")]
        _ = try BookPDF.write(BookDocument(title: "Moving day", project: "Old Name", chapters: chapters), calendar: utc, folder: folder)
        let file = try BookPDF.write(BookDocument(title: "Moving day", project: "New Name", chapters: chapters), calendar: utc, folder: folder)
        let text = PDFDocument(url: file)?.page(at: 0)?.string ?? ""
        XCTAssertTrue(text.contains("New Name"), text)
        XCTAssertFalse(text.contains("Old Name"), text)
    }

    /// A file name holds 255 bytes and a Thai letter takes three, so a long chat name must be cut; a leading dot would hide the file.
    func testALongTitleStillMakesAFileName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let thai = String(repeating: "ก", count: 150)
        let file = try BookPDF.write(BookDocument(title: thai, project: "AgentValley", chapters: [chapter(1, text: "Done.")]), calendar: utc, folder: folder)
        XCTAssertLessThanOrEqual(file.lastPathComponent.utf8.count, 255)
        XCTAssertTrue(file.lastPathComponent.hasPrefix("ก") && file.lastPathComponent.hasSuffix(".pdf"), file.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let hidden = try BookPDF.write(BookDocument(title: "..notes", project: "AgentValley", chapters: [chapter(1, text: "Done.")]), calendar: utc, folder: folder)
        XCTAssertEqual(hidden.lastPathComponent, "notes.pdf")
    }

    /// A big book takes seconds to make, and the panel must not freeze meanwhile: it has to be made off the main thread.
    func testABookCanBeMadeOffTheMainThread() throws {
        let book = BookDocument(title: "Moving day", project: "AgentValley", chapters: (1...3).map { chapter($0, text: "Work \($0) done.") })
        let calendar = utc
        var made = Data()
        var onMain = true
        let done = expectation(description: "made")
        DispatchQueue.global(qos: .userInitiated).async {
            onMain = Thread.isMainThread
            made = BookPDF.data(book, calendar: calendar)
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        XCTAssertFalse(onMain)
        XCTAssertEqual(PDFDocument(data: made)?.outlineRoot?.numberOfChildren, 3)
    }

    /// Opened again unchanged, a book comes straight up; a new chapter, or another chat's book of the same title, makes it again.
    func testAWriteRemakesTheFileOnlyWhenTheBookChanged() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = BookDocument(title: "Moving day", project: "AgentValley", chapters: [chapter(1, text: "One.")])
        let two = BookDocument(title: "Moving day", project: "AgentValley", chapters: [chapter(1, text: "One."), chapter(2, text: "Two.")])
        let other = BookDocument(title: "Moving day", project: "AgentValley", chapters: [chapter(1, session: "s2", text: "One."), chapter(2, session: "s2", text: "Two.")])
        let file = try BookPDF.write(one, calendar: utc, folder: folder)
        // A day after every chapter here: anything else on the file means it was written again.
        let stamp = Date(timeIntervalSince1970: 1_793_086_400)
        func touch(_ date: Date = stamp) throws { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path) }
        func written() throws -> Bool {
            try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) != stamp
        }
        try touch()
        _ = try BookPDF.write(one, calendar: utc, folder: folder)
        XCTAssertFalse(try written())
        _ = try BookPDF.write(two, calendar: utc, folder: folder)
        XCTAssertTrue(try written())
        XCTAssertEqual(PDFDocument(url: file)?.outlineRoot?.numberOfChildren, 2)
        try touch()
        _ = try BookPDF.write(other, calendar: utc, folder: folder)
        XCTAssertTrue(try written())
        // Made before the book's last chapter: a chapter of the same count that came since must be in it.
        try touch(Date(timeIntervalSince1970: 1_793_000_000))
        _ = try BookPDF.write(other, calendar: utc, folder: folder)
        XCTAssertTrue(try written())
    }
}
