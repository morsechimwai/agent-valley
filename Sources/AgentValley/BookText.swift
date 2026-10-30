import AppKit

/// A hand-back's Markdown as the text of a printed page: headings, bold, lists and code look
/// like what they are, and none of the marks that made them are left. Paper only: dark on white.
enum BookText {
    static let ink = paperColor(0x1D1D1F)
    private static let chip = paperColor(0xF1F1F1)

    /// New York, the Mac's own serif; the system font where a Mac lacks it.
    static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return font.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    }

    /// Markdown as paper text: no marks left, paths cut to their file name. `font` and `color` are
    /// the plain paragraphs'; headings, code and lists are sized from them.
    static func attributed(_ markdown: String, font: NSFont = serif(11.5), color: NSColor = ink) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        if let parsed = try? AttributedString(markdown: markdown, options: options) {
            write(parsed, into: out, font: font, color: color)
        } else {
            out.append(NSAttributedString(string: markdown, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style(font)]))
        }
        cutPaths(out, size: font.pointSize)
        out.removeAttribute(written, range: NSRange(location: 0, length: out.length))
        return out
    }

    /// Marks a code block's text while paths are cut: a command is copied as written.
    private static let written = NSAttributedString.Key("AgentValley.BookText.written")

    // MARK: - Blocks

    private static func write(_ parsed: AttributedString, into out: NSMutableAttributedString, font: NSFont, color: NSColor) {
        var block: Int?, row: Int?
        var items = Set<Int>()
        var boxes: [Int: NSTextBlock] = [:]
        var last: [NSAttributedString.Key: Any] = [:]
        var code = false, gap: CGFloat = 0
        var table: Int?
        /// The last row of a table leaves a paragraph's room under it, as a paragraph does.
        func endTable() {
            guard out.length > 0 else { return }
            let row = (out.string as NSString).paragraphRange(for: NSRange(location: out.length - 1, length: 0))
            out.enumerateAttribute(.paragraphStyle, in: row) { value, range, _ in
                guard let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
                paragraph.paragraphSpacing = style(font).paragraphSpacing
                out.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
            last[.paragraphStyle] = out.attribute(.paragraphStyle, at: out.length - 1, effectiveRange: nil)
        }
        for run in parsed.runs {
            let parts = run.presentationIntent?.components ?? []
            let inner = parts.first
            let isCode = if case .codeBlock = inner?.kind { true } else { false }
            let inTable = parts.first { if case .table = $0.kind { true } else { false } }?.identity
            var text = String(parsed[run.range].characters)
            var attributes = blockAttributes(parts, font: font, color: color, boxes: &boxes)
            let sameRow = if case .tableCell = inner?.kind, parts.count > 1, parts[1].identity == row { true } else { false }
            // A box paints its own margins, so the room under a code block is the next paragraph's.
            if inner?.identity != block, !sameRow { gap = code && !isCode ? font.pointSize * 0.6 : 0 }
            (attributes[.paragraphStyle] as? NSMutableParagraphStyle)?.paragraphSpacingBefore += gap
            if inner?.identity != block {
                if sameRow {
                    out.append(NSAttributedString(string: "  ", attributes: attributes))
                } else {
                    if table != nil, table != inTable { endTable() }
                    if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: last)) }
                    out.append(NSAttributedString(string: bullet(parts, seen: &items), attributes: attributes))
                }
                block = inner?.identity
                row = parts.count > 1 ? parts[1].identity : nil
                code = isCode
                table = inTable
            }
            if isCode, text.hasSuffix("\n") { text.removeLast() }
            if isCode { attributes[written] = true }
            inline(run.inlinePresentationIntent, &attributes, &text)
            out.append(NSAttributedString(string: text, attributes: attributes))
            // The break after a run carries its paragraph, not its chip or strike.
            last = attributes.filter { $0.key != .backgroundColor && $0.key != .strikethroughStyle }
        }
        if table != nil { endTable() }
    }

    /// A paragraph's look from the blocks it sits in, innermost first.
    private static func blockAttributes(_ parts: [PresentationIntent.IntentType], font base: NSFont, color: NSColor,
                                        boxes: inout [Int: NSTextBlock]) -> [NSAttributedString.Key: Any] {
        let size = base.pointSize
        var font = base, ink = color
        let paragraph = style(base)
        let lists = parts.filter { if case .listItem = $0.kind { true } else { false } }.count
        let quotes = parts.filter { if case .blockQuote = $0.kind { true } else { false } }.count
        let indent = CGFloat(lists) * 16 + CGFloat(quotes) * 12
        paragraph.headIndent = indent
        paragraph.firstLineHeadIndent = lists > 0 ? indent - 16 : indent
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
        if quotes > 0 { ink = color.withAlphaComponent(0.7) }
        if lists > 0 { paragraph.paragraphSpacing = size * 0.25 }
        switch parts.first?.kind {
        case .header(let level):
            font = bold(level == 1 ? base.withSize(size * 1.35) : level == 2 ? base.withSize(size * 1.2) : base.withSize(size * 1.08))
            paragraph.paragraphSpacingBefore = size * 0.5
            paragraph.paragraphSpacing = size * 0.25
        case .codeBlock:
            font = .monospacedSystemFont(ofSize: size * 0.85, weight: .regular)
            paragraph.lineHeightMultiple = 1.15
            paragraph.paragraphSpacing = 0
            paragraph.headIndent = 0
            paragraph.firstLineHeadIndent = 0
            let id = parts[0].identity
            let box = boxes[id] ?? block()
            if boxes[id] == nil {
                box.backgroundColor = chip
                box.setWidth(8, type: .absoluteValueType, for: .padding)
                box.setWidth(indent, type: .absoluteValueType, for: .margin, edge: .minX)
                boxes[id] = box
            }
            paragraph.textBlocks = [box]
        case .tableCell:
            font = .monospacedSystemFont(ofSize: size * 0.85, weight: parts.contains { $0.kind == .tableHeaderRow } ? .semibold : .regular)
            paragraph.paragraphSpacing = size * 0.15
        case .thematicBreak:
            paragraph.alignment = .center
            ink = color.withAlphaComponent(0.4)
        default:
            break
        }
        return [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
    }

    /// "•" or "3." before the first paragraph of a list item, then a tab to the text's edge.
    private static func bullet(_ parts: [PresentationIntent.IntentType], seen: inout Set<Int>) -> String {
        guard let index = parts.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }),
              seen.insert(parts[index].identity).inserted, case .listItem(let ordinal) = parts[index].kind else { return "" }
        let ordered = parts.indices.contains(index + 1) && parts[index + 1].kind == .orderedList
        return (ordered ? "\(ordinal)." : "•") + "\t"
    }

    // MARK: - Inline

    private static func inline(_ intent: InlinePresentationIntent?, _ attributes: inout [NSAttributedString.Key: Any], _ text: inout String) {
        guard let intent, var font = attributes[.font] as? NSFont else { return }
        if intent.contains(.stronglyEmphasized) { font = bold(font) }
        if intent.contains(.emphasized) { font = trait(font, .italic) }
        if intent.contains(.code) {
            font = .monospacedSystemFont(ofSize: font.pointSize * 0.85, weight: .regular)
            attributes[.backgroundColor] = chip
        }
        if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        // A hard break stays inside its paragraph.
        if intent.contains(.lineBreak) { text = "\u{2028}" }
        attributes[.font] = font
    }

    // MARK: - Paths

    /// An absolute or home path with at least two "/" in it, starting a word; a full stop or
    /// comma after it ends the sentence, not the name.
    private static let path = try! NSRegularExpression(pattern: #"(?<![^\s(\[{<"'`*_])~?(?:/[^/\s`'"()\[\]{}<>*|]+){2,}(?<![.,;:!?])"#)

    /// Every path shows its file name alone, in a grey chip; a code block's stay whole.
    private static func cutPaths(_ text: NSMutableAttributedString, size: CGFloat) {
        let whole = NSRange(location: 0, length: text.length)
        for match in path.matches(in: text.string, range: whole).reversed()
        where text.attribute(written, at: match.range.location, effectiveRange: nil) == nil {
            let found = (text.string as NSString).substring(with: match.range)
            let name = (found as NSString).lastPathComponent
            var attributes = text.attributes(at: match.range.location, effectiveRange: nil)
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: size * 0.85, weight: .regular)
            attributes[.backgroundColor] = chip
            text.replaceCharacters(in: match.range, with: NSAttributedString(string: name, attributes: attributes))
        }
    }

    // MARK: - Type

    /// A box as wide as the room it is in. Without a width set, a box laid out outside a text
    /// view holds only its first paragraph and draws nothing.
    static func block() -> NSTextBlock {
        let box = NSTextBlock()
        box.setValue(100, type: .percentageValueType, for: .width)
        return box
    }

    /// A plain paragraph: book leading, a gap under it.
    static func style(_ font: NSFont) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.3
        paragraph.paragraphSpacing = font.pointSize * 0.6
        return paragraph
    }

    private static func bold(_ font: NSFont) -> NSFont { trait(font, .bold) }

    private static func trait(_ font: NSFont, _ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}

/// A colour of the printed page, the same in light and dark mode.
func paperColor(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
