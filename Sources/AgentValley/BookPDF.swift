import AppKit
import PDFKit

/// One Library book: a session's hand-backs, oldest first, under the session's title.
struct BookDocument: Equatable {
    let title: String
    let project: String
    let chapters: [Chapter]
}

/// A book as A4 pages of PDF that read like a printed book: every chapter starts a page and runs
/// on over as many as its hand-back needs, and Preview lists the chapters in its sidebar. The
/// words stay words, so they can be picked out and searched. Made on any one thread: TextKit and
/// Core Graphics only, no SwiftUI, so a big book is made off the main thread.
enum BookPDF {
    static let page = CGSize(width: 595, height: 842)
    private static let side: CGFloat = 56
    /// Where a chapter's text goes on every page, between the running head and the foot.
    private static let body = CGRect(x: side, y: 68, width: page.width - side * 2, height: 714)

    static func data(_ book: BookDocument, calendar: Calendar = HistoryReport.calendar()) -> Data {
        // Laid out first: every foot says how many pages there are.
        let chapters = book.chapters.indices.map { lay(book, $0, calendar: calendar) }
        let total = chapters.reduce(0) { $0 + $1.pages.count }
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return Data() }
        var starts: [Int] = []
        var number = 0
        for (index, chapter) in chapters.enumerated() {
            starts.append(number)
            for (sheet, slice) in chapter.pages.enumerated() {
                number += 1
                context.beginPDFPage(nil)
                onPage(context) {
                    watermark(in: context)
                    head(book, chapter: index + 1, of: chapters.count, in: context)
                    // The page's stretch of the chapter's column, cut clean: a box running on to
                    // the next page stops at this one's last line.
                    let origin = CGPoint(x: body.minX, y: body.minY - slice.top)
                    context.saveGState()
                    context.clip(to: CGRect(x: 0, y: body.minY, width: page.width, height: slice.bottom - slice.top))
                    chapter.manager.drawBackground(forGlyphRange: slice.glyphs, at: origin)
                    chapter.manager.drawGlyphs(forGlyphRange: slice.glyphs, at: origin)
                    context.restoreGState()
                    if sheet == 0 { face(chapter, in: context) }
                    foot(number, of: total, in: context)
                }
                context.endPDFPage()
            }
        }
        context.closePDF()
        // The pages go into a new document for the outline: PDFKit saves none on a document read
        // from a PDF context's bytes (macOS 27), and an outline added to a loose root is dropped.
        guard let drawn = PDFDocument(data: data as Data) else { return data as Data }
        let pdf = PDFDocument()
        for index in 0..<drawn.pageCount {
            if let sheet = drawn.page(at: index)?.copy() as? PDFPage { pdf.insert(sheet, at: index) }
        }
        pdf.documentAttributes = [PDFDocumentAttribute.titleAttribute: book.title, PDFDocumentAttribute.creatorAttribute: "AgentValley"]
        let outline = PDFOutline()
        pdf.outlineRoot = outline
        for (index, chapter) in chapters.enumerated() {
            guard let first = pdf.page(at: starts[index]) else { continue }
            let entry = PDFOutline()
            entry.label = chapter.heading
            entry.destination = PDFDestination(page: first, at: CGPoint(x: 0, y: page.height))
            outline.insertChild(entry, at: outline.numberOfChildren)
        }
        return pdf.dataRepresentation() ?? data as Data
    }

    /// Writes the book as its title in `folder`, made if missing. A file of the same name is
    /// replaced, unless it is this book as it stands, which is handed back as it is: opening the
    /// book again brings it up to date. Folders made here are closed to other accounts, as
    /// `ReportPDF.write` makes them.
    static func write(_ book: BookDocument, calendar: Calendar = HistoryReport.calendar(),
                      folder: URL = AnswerServer.defaultDirectory.appendingPathComponent("Reports")) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // No leading dot (a hidden file), and at most 200 bytes of the 255 a file name holds: a Thai
        // letter takes three. Cut on whole characters.
        var name = String(book.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .drop { $0 == "." || $0.isWhitespace })
        while name.utf8.count > 200 { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let file = folder.appendingPathComponent((name.isEmpty ? "Book" : name) + ".pdf")
        // The app build too: an update that changes the look makes the book again.
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
        let which = "\(book.chapters.first?.session ?? "") \(book.chapters.count) \(book.project) \(build)"
        // Made after the last chapter came, of this chat and as many chapters: nothing to add.
        if let last = book.chapters.map(\.at).max(),
           let made = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date, made > last,
           mark(of: file) == which {
            return file
        }
        try data(book, calendar: calendar).write(to: file, options: .atomic)
        _ = which.withCString { setxattr(file.path, markName, $0, strlen($0), 0, 0) }
        return file
    }

    /// Which chat's book a file holds and how many chapters, beside the file and not in it: a PDF
    /// sent on carries no session id. Two chats can share a title, and so a file name.
    private static let markName = "app.agentvalley.book"

    private static func mark(of file: URL) -> String? {
        var bytes = [CChar](repeating: 0, count: 256)
        let count = getxattr(file.path, markName, &bytes, bytes.count - 1, 0, 0)
        return count > 0 ? String(cString: bytes) : nil
    }

    // MARK: - A chapter

    /// A chapter's text laid out as one tall column, and where its pages cut it.
    private struct Laid {
        let heading: String
        let person: Person
        /// Held here: a layout manager keeps its text storage only weakly.
        let storage: NSTextStorage
        let manager: NSLayoutManager
        let pages: [Slice]
        /// Where the byline starts, for the face drawn before it.
        let byline: Int
    }

    private static func lay(_ book: BookDocument, _ index: Int, calendar: Calendar) -> Laid {
        let chapter = book.chapters[index]
        let title = chapter.title.isEmpty ? Format.handedBack(type: chapter.type) : chapter.title
        let heading = book.chapters[..<index].contains { $0.agent == chapter.agent } ? "\(title) (continued)" : title
        let text = NSMutableAttributedString()

        text.append(NSAttributedString(string: heading, attributes: [
            .font: BookText.serif(19, weight: .bold), .foregroundColor: BookText.ink, .paragraphStyle: spaced(after: 6, lines: 1.1),
        ]))
        let byline = text.length + 1
        let by = spaced(after: 14)
        by.firstLineHeadIndent = 17
        add(NSAttributedString(string: "\(Format.crewName(type: chapter.type)) · \(Format.date("MMM d, yyyy, HH:mm", chapter.at, calendar))",
                               attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: paperColor(0x777777), .paragraphStyle: by]),
            to: text)

        let (short, rest) = InShort.split(chapter.text)
        if let short {
            let part = NSMutableAttributedString(string: "IN SHORT\n", attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold), .kern: 0.72, .foregroundColor: paperColor(0xA07A3A),
                .paragraphStyle: spaced(after: 3),
            ])
            part.append(BookText.attributed(short, font: BookText.serif(12.5)))
            let box = BookText.block()
            box.backgroundColor = paperColor(0xF3EEE2)
            box.setWidth(9, type: .absoluteValueType, for: .padding, edge: .minY)
            box.setWidth(9, type: .absoluteValueType, for: .padding, edge: .maxY)
            box.setWidth(11, type: .absoluteValueType, for: .padding, edge: .minX)
            box.setWidth(11, type: .absoluteValueType, for: .padding, edge: .maxX)
            add(boxed(part, in: box), to: text)
        }
        // A box paints its own margins, so the room under In short is the next paragraph's.
        let gap: CGFloat = short == nil ? 0 : 14
        let work = !rest.allSatisfy(\.isWhitespace)
        if work { add(BookText.attributed(rest), to: text, before: gap) }

        if !chapter.asked.allSatisfy(\.isWhitespace) {
            let font = NSFont.systemFont(ofSize: 10), grey = paperColor(0x888888)
            let part = NSMutableAttributedString(string: "Asked: ", attributes: [.font: font, .foregroundColor: grey, .paragraphStyle: BookText.style(font)])
            part.append(BookText.attributed(chapter.asked, font: font, color: grey))
            // A thin rule over the ask, as the mockup's border-top.
            let box = BookText.block()
            box.setBorderColor(paperColor(0xEEEEEE), for: .minY)
            box.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
            box.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minY)
            // Unfilled, so its margin shows as room above the rule.
            box.setWidth(work ? 6 : max(gap, 6), type: .absoluteValueType, for: .margin, edge: .minY)
            add(boxed(part, in: box), to: text)
        }

        // One column cut into pages, not a text container a page: a box (code, In short, the ask)
        // laid over containers runs off the bottom of one and its lines are never drawn.
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let column = NSTextContainer(size: CGSize(width: body.width, height: .greatestFiniteMagnitude))
        column.lineFragmentPadding = 0
        manager.addTextContainer(column)
        manager.ensureLayout(for: column)
        return Laid(heading: heading, person: MascotKind(type: chapter.type).person, storage: storage, manager: manager,
                    pages: pages(manager), byline: byline)
    }

    /// A page's whole lines: their glyphs, and the stretch of the column from the last page's
    /// bottom to its own last line, so a gap before a line (a box's padding) goes with it.
    private struct Slice {
        let glyphs: NSRange
        let top: CGFloat
        let bottom: CGFloat
    }

    /// As many whole lines on each page as fit. A line taller than a page has one to itself.
    private static func pages(_ manager: NSLayoutManager) -> [Slice] {
        var lines: [(rect: CGRect, glyphs: NSRange)] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { rect, _, _, glyphs, _ in
            lines.append((rect, glyphs))
        }
        var pages: [Slice] = []
        var first = 0, top: CGFloat = 0
        func close(_ end: Int) {
            let start = lines[first].glyphs.location
            pages.append(Slice(glyphs: NSRange(location: start, length: NSMaxRange(lines[end - 1].glyphs) - start), top: top,
                               bottom: lines[end - 1].rect.maxY))
            top = lines[end - 1].rect.maxY
            first = end
        }
        for index in lines.indices where index > first && lines[index].rect.maxY - top > body.height { close(index) }
        if first < lines.count { close(lines.count) }
        return pages
    }

    /// `part` as the next paragraph of `text`, its first paragraph `before` lower.
    private static func add(_ part: NSAttributedString, to text: NSMutableAttributedString, before: CGFloat = 0) {
        guard part.length > 0 else { return }
        if text.length > 0 {
            var end = text.attributes(at: text.length - 1, effectiveRange: nil)
            end[.backgroundColor] = nil
            text.append(NSAttributedString(string: "\n", attributes: end))
        }
        let part = NSMutableAttributedString(attributedString: part)
        let first = (part.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        part.enumerateAttribute(.paragraphStyle, in: first) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.paragraphSpacingBefore += before
            part.addAttribute(.paragraphStyle, value: style, range: range)
        }
        text.append(part)
    }

    /// Every paragraph of `part` inside `box`, around any box of its own (a code block's). The last
    /// leaves no gap of its own: the box's padding is the same all round.
    private static func boxed(_ part: NSMutableAttributedString, in box: NSTextBlock) -> NSAttributedString {
        part.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: part.length)) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.textBlocks = [box] + style.textBlocks
            if NSMaxRange(range) == part.length { style.paragraphSpacing = 0 }
            part.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return part
    }

    private static func spaced(after: CGFloat, lines: CGFloat = 1) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = after
        style.lineHeightMultiple = lines
        return style
    }

    // MARK: - Drawing

    /// Draws on a white page in a flipped context: top left is the origin, as TextKit lays out.
    private static func onPage(_ context: CGContext, _ draw: () -> Void) {
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: page))
        context.translateBy(x: 0, y: page.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    /// The costs PDF's faint slanted logos, under the words.
    private static func watermark(in context: CGContext) {
        context.setFillColor(paperColor(0x23190F).withAlphaComponent(Watermark.opacity).cgColor)
        for place in Watermark.places {
            context.addPath(Watermark.letters.applying(place).cgPath)
        }
        context.fillPath()
    }

    /// "‹title› · ‹project›" on the left, cut short before it meets "Chapter n of m" on the right.
    private static func head(_ book: BookDocument, chapter: Int, of count: Int, in context: CGContext) {
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: paperColor(0x999999)]
        let right = NSAttributedString(string: "Chapter \(chapter) of \(count)", attributes: label)
        let width = right.size().width
        right.draw(at: CGPoint(x: body.maxX - width, y: 34))
        let cut = NSMutableParagraphStyle()
        cut.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: "\(book.title) · \(book.project)", attributes: label.merging([.paragraphStyle: cut]) { $1 })
            .draw(with: CGRect(x: body.minX, y: 34, width: body.width - width - 16, height: 14), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        context.setFillColor(paperColor(0xEEEEEE).cgColor)
        context.fill(CGRect(x: body.minX, y: 50, width: body.width, height: 1))
    }

    /// "Page x of y" on the left, the wordmark of the costs PDF in the corner.
    private static func foot(_ number: Int, of total: Int, in context: CGContext) {
        NSAttributedString(string: Format.pageLabel(number, of: total),
                           attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: paperColor(0xAAAAAA)])
            .draw(at: CGPoint(x: body.minX, y: 806))
        let cell: CGFloat = 9.0 / 12
        cells(Wordmark.rows, size: cell, at: CGPoint(x: body.maxX - cell * 88, y: 808), in: context, hex: Wordmark.hex)
    }

    /// The crew member's face, 12 pt, in the room left before the byline.
    private static func face(_ chapter: Laid, in context: CGContext) {
        let glyph = chapter.manager.glyphIndexForCharacter(at: chapter.byline)
        let line = chapter.manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = chapter.manager.location(forGlyphAt: glyph).y
        cells(chapter.person.rows.map(Array.init), size: 1, at: CGPoint(x: body.minX, y: body.minY + line.minY + baseline - 10),
              in: context, hex: chapter.person.hex)
    }

    /// Pixel rows as filled squares, a row's run of one colour as one rectangle so no seams show.
    private static func cells(_ rows: [[Character]], size: CGFloat, at origin: CGPoint, in context: CGContext, hex: (Character) -> UInt32?) {
        for (y, row) in rows.enumerated() {
            var x = 0
            while x < row.count {
                var end = x + 1
                while end < row.count, row[end] == row[x] { end += 1 }
                if let colour = hex(row[x]) {
                    context.setFillColor(paperColor(colour).cgColor)
                    context.fill(CGRect(x: origin.x + CGFloat(x) * size, y: origin.y + CGFloat(y) * size, width: CGFloat(end - x) * size, height: size))
                }
                x = end
            }
        }
    }
}
