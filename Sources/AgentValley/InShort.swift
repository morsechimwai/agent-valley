import Foundation

/// The plain summary a sub-agent opens its report with (asked for by `CrewIntro.inShortNote`).
/// The library lifts it into a box at the top of the chapter. Pure.
enum InShort {
    /// The first paragraph when it starts "In short:" (also "**In short:**"), label removed; the rest unchanged.
    /// Without that paragraph: `(nil, text)`, byte for byte.
    static func split(_ text: String) -> (short: String?, rest: String) {
        let lines = text.drop(while: \.isWhitespace).components(separatedBy: "\n")
        let blank: (String) -> Bool = { $0.allSatisfy(\.isWhitespace) }
        let end = lines.firstIndex(where: blank) ?? lines.endIndex
        let paragraph = lines[..<end].joined(separator: "\n")
        guard let label = ["In short:", "**In short:**", "**In short**:"].first(where: paragraph.hasPrefix) else { return (nil, text) }
        let short = paragraph.dropFirst(label.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !short.isEmpty else { return (nil, text) }
        return (short, lines[end...].drop(while: blank).joined(separator: "\n"))
    }
}
