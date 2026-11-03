import CryptoKit
import Foundation

/// The three moments of a crew member that Claude Code's terminal shows.
enum CrewPose: Int, CaseIterable {
    case working, needsYou, done
}

/// The crew's faces as characters of a colour font, for Claude Code's status line and sub-agent
/// rows. Every face is one wide character of the unassigned end of Plane 3, so every terminal
/// gives it two cells. The cells come from `MascotView.pose`, the same ones the notch draws.
enum CrewFont {
    static let family = "AgentValley Crew"
    static let fileName = "AgentValleyCrew.ttf"
    static let firstScalar: UInt32 = 0x3F000

    /// The end of the block the font keeps to, and Ghostty's font line maps.
    static let lastScalar: UInt32 = 0x3F7FF

    struct Face {
        let scalar: UInt32
        let person: Person
        let pose: CrewPose
        /// At work with this in hand, as the notch draws it standing still.
        var holding: Activity?
    }

    private static let crew: [MascotKind] = [.general, .explore, .plan, .other(shirt: 0), .other(shirt: 1), .other(shirt: 2), .other(shirt: 3)]
    private static let leadCount = Person.leads.count * Person.leadHair.count * Person.leadShirts.count

    /// The crew first, three poses each, then every look a session's own agent can have, in
    /// the working pose only; then all of them at work with each thing in hand, crew first.
    /// The order is fixed: fonts already shipped refer to it, so new faces only ever go at the end.
    static let faces: [Face] = {
        var all = crew.flatMap { kind in CrewPose.allCases.map { Face(scalar: 0, person: kind.person, pose: $0) } }
        var leads: [Person] = []
        for face in 0..<Person.leads.count {
            for hair in 0..<Person.leadHair.count {
                for shirt in 0..<Person.leadShirts.count {
                    leads.append(MascotKind.lead(LeadLook(face: face, hair: hair, shirt: shirt)).person)
                }
            }
        }
        all += leads.map { Face(scalar: 0, person: $0, pose: .working) }
        all += (crew.map(\.person) + leads).flatMap { person in
            Activity.allCases.map { Face(scalar: 0, person: person, pose: .working, holding: $0) }
        }
        return all.enumerated().map { Face(scalar: firstScalar + UInt32($0.offset), person: $0.element.person, pose: $0.element.pose, holding: $0.element.holding) }
    }()

    /// The bar's pictures, standing still, after every face so no code a font already shipped
    /// moves: the mug while the app has given a session no lead, the fish and the van while a
    /// plan limit has run out.
    enum Picture: UInt32, CaseIterable {
        case mug, fish, van

        var scalar: UInt32 { CrewFont.faces.last!.scalar + 1 + rawValue }
        var character: String { String(UnicodeScalar(scalar)!) }

        var cells: [[Character]] {
            switch self {
            case .mug: Mug.frames[0].map(Array.init)
            case .fish: Fish.frames[0].map(Array.init)
            case .van: Van.frames[0].map(Array.init)
            }
        }

        func hex(_ cell: Character) -> UInt32? {
            switch self {
            case .mug: Mug.hex(cell)
            case .fish: Fish.hex(cell)
            case .van: Van.hex(cell)
            }
        }
    }

    /// The marks the panel puts by a session's folder and branch, and after a worktree's branch,
    /// drawn after its SF Symbols (`folder`, `arrow.triangle.branch`, `square.on.square`) so a
    /// row in the terminal reads like the same row in the panel. After the pictures. Plain
    /// outlines with no colour of their own: the terminal draws them in the text's colour, as
    /// the panel draws its symbols in the text's.
    enum Mark: UInt32, CaseIterable {
        case folder, branch, worktree

        var scalar: UInt32 { Picture.van.scalar + 1 + rawValue }
        var character: String { String(UnicodeScalar(scalar)!) }

        typealias Point = (x: Double, y: Double)

        /// The symbols' semibold line, in symbol units: 1 is the symbol's point size.
        private static let line = 0.104

        /// The shapes in symbol units, y down from the top. They overlap: the font fills their union.
        var shapes: [[Point]] {
            let h = Self.line / 2
            switch self {
            case .folder:
                let (left, right, top, back, bottom, r) = (h, 1.125 - h, h, h + 0.088, 0.92 - h, 0.15)
                let outline = Self.arc((left + r, top + r), r, 180, 270) + [(0.27, top), (0.33, top + 0.01), (0.42, back - 0.01), (0.48, back)]
                    + Self.arc((right - r, back + r), r, 270, 360) + Self.arc((right - r, bottom - r), r, 0, 90)
                    + Self.arc((left + r, bottom - r), r, 90, 180)
                return Self.stroke(outline, Self.line, closed: true) + Self.stroke([(0.21, 0.31), (0.915, 0.31)], 0.09)
            case .branch:
                let x = 0.49
                var shapes = Self.stroke([(x, 0.93), (x, 0.56)], Self.line)
                for side in [-1.0, 1.0] {
                    let arm = Self.cubic((x, 0.62), (x, 0.42), (x + side * 0.07, 0.31), (x + side * 0.22, 0.20))
                    shapes += Self.stroke(arm, Self.line)
                    // An arrowhead on the arm's end, pointing the way the arm goes.
                    let end = arm[arm.count - 1], before = arm[arm.count - 2]
                    let length = hypot(end.x - before.x, end.y - before.y)
                    let (dx, dy) = ((end.x - before.x) / length, (end.y - before.y) / length)
                    let base = (x: end.x - dx * 0.02, y: end.y - dy * 0.02)
                    let head: [Point] = [(base.x + dx * 0.27, base.y + dy * 0.27), (base.x - dy * 0.15, base.y + dx * 0.15), (base.x + dy * 0.15, base.y - dx * 0.15)]
                    shapes += [head] + Self.stroke(head, 0.05, closed: true)
                }
                return shapes
            case .worktree:
                let (side, offset, r) = (0.83, 0.24, 0.16)
                let (front, frontEnd) = (offset + h, offset + side - h)
                // The square behind shows only where the front one leaves it.
                let back = [(front, side - h)] + Self.arc((h + r, side - h - r), r, 90, 180) + Self.arc((h + r, h + r), r, 180, 270)
                    + Self.arc((side - h - r, h + r), r, 270, 360) + [(side - h, front)]
                let square = Self.arc((front + r, front + r), r, 180, 270) + Self.arc((frontEnd - r, front + r), r, 270, 360)
                    + Self.arc((frontEnd - r, frontEnd - r), r, 0, 90) + Self.arc((front + r, frontEnd - r), r, 90, 180)
                return Self.stroke(back, Self.line) + Self.stroke(square, Self.line, closed: true)
            }
        }

        /// The outlines in font units, each clockwise as TrueType fills them. A folder is about
        /// a capital's height, its middle at half one, as the panel's symbols stand by its text.
        /// Each keeps the panel's gap of 4 points in 11 to the name it marks: the folder and
        /// branch marks to the name after them, the worktree mark to the branch before it.
        var contours: [[(x: Int, y: Int)]] {
            let scale = 1200 * 0.74, middle = 420.0, gap = 1200 * 4.0 / 11
            let points = shapes.flatMap { $0 }
            let (minX, maxX) = (points.map(\.x).min()!, points.map(\.x).max()!)
            let (minY, maxY) = (points.map(\.y).min()!, points.map(\.y).max()!)
            let left = self == .worktree ? gap : 1440 - gap - (maxX - minX) * scale
            return shapes.map { shape in
                let contour = shape.map { point in
                    (x: Int((left + (point.x - minX) * scale).rounded()),
                     y: Int((middle - (point.y - (minY + maxY) / 2) * scale).rounded()))
                }
                let area = zip(contour, contour.dropFirst() + contour.prefix(1)).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }
                return area > 0 ? contour.reversed() : contour
            }
        }

        /// A line `width` wide along `points`, with round ends and joins: a quad for each
        /// stretch and a disc at each point.
        private static func stroke(_ points: [Point], _ width: Double, closed: Bool = false) -> [[Point]] {
            let ends = Array(points.dropFirst()) + (closed ? [points[0]] : [])
            var shapes: [[Point]] = zip(points, ends).compactMap { a, b in
                let length = hypot(b.x - a.x, b.y - a.y)
                guard length > 0 else { return nil }
                let (nx, ny) = (-(b.y - a.y) / length * width / 2, (b.x - a.x) / length * width / 2)
                return [(a.x + nx, a.y + ny), (b.x + nx, b.y + ny), (b.x - nx, b.y - ny), (a.x - nx, a.y - ny)]
            }
            for point in points {
                shapes.append((0..<16).map { i in
                    let angle = Double(i) * .pi / 8
                    return (point.x + width / 2 * cos(angle), point.y + width / 2 * sin(angle))
                })
            }
            return shapes
        }

        /// A quarter of a circle in six steps, from `from` to `to` degrees, y down.
        private static func arc(_ centre: Point, _ r: Double, _ from: Double, _ to: Double) -> [Point] {
            (0...6).map { i in
                let angle = (from + (to - from) * Double(i) / 6) * .pi / 180
                return (centre.x + r * cos(angle), centre.y + r * sin(angle))
            }
        }

        private static func cubic(_ p0: Point, _ p1: Point, _ p2: Point, _ p3: Point) -> [Point] {
            (0...10).map { i in
                let t = Double(i) / 10, u = 1 - t
                let (a, b, c, d) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
                return (a * p0.x + b * p1.x + c * p2.x + d * p3.x, a * p0.y + b * p1.y + c * p2.y + d * p3.y)
            }
        }
    }

    /// `text` with every character of the font taken out: Claude writes the tags for the terminal,
    /// and the panel and the phone draw no such font. A badge goes with its space before the name;
    /// a badge with no name after it, or an older tag (three characters, the name
    /// drawn in), becomes the name.
    static func untagged(_ text: String) -> String {
        let block = firstScalar...lastScalar
        guard text.unicodeScalars.contains(where: { block.contains($0.value) }) else { return text }
        var kept = String.UnicodeScalarView(), names = Set<String>()
        for scalar in text.unicodeScalars {
            if !block.contains(scalar.value) {
                kept.append(scalar)
            } else if let who = Tag.who(head: scalar.value) {
                kept.append(contentsOf: who.name.unicodeScalars); names.insert(who.name)
            }
        }
        return names.reduce(String(kept)) {
            $0.replacingOccurrences(of: "\($1) **\($1)**", with: "**\($1)**").replacingOccurrences(of: "\($1) \($1)", with: $1)
        }
    }

    /// A name tag for Claude's chat: a badge, the person's face on a pill in their shirt's pale dye,
    /// one wide character, then the name in bold. One character, so Ghostty, which draws each colour
    /// character a little narrower than its cells, leaves no seam in it. After the marks: a badge for
    /// each look in the order of `place`. The colours are the font's, not the terminal's.
    enum Tag {
        static var firstScalar: UInt32 { Mark.worktree.scalar + 1 }
        static var lastScalar: UInt32 { firstScalar + UInt32(kinds.count) - 1 }

        /// Every look a head is drawn for, at its `place`.
        static let kinds: [MascotKind] = crew + (0..<Person.leads.count).flatMap { face in
            (0..<Person.leadHair.count).flatMap { hair in
                (0..<Person.leadShirts.count).map { MascotKind.lead(LeadLook(face: face, hair: hair, shirt: $0)) }
            }
        }

        /// `kind`'s tag as Claude writes it: the badge, a space, the name in bold.
        static func text(_ kind: MascotKind) -> String {
            "\(UnicodeScalar(firstScalar + UInt32(place(kind)))!) **\(who(kind).name)**"
        }

        /// Whose name the tag shows.
        static func who(_ kind: MascotKind) -> Crew {
            switch kind {
            case .lead(let look): Crew.lead(look)
            case .plan: .judy
            case .explore: .faye
            case .general, .other: .felix
            }
        }

        /// Whose badge a character is; nil for any other character.
        static func who(head scalar: UInt32) -> Crew? {
            guard scalar >= firstScalar, scalar < firstScalar + UInt32(kinds.count) else { return nil }
            return who(kinds[Int(scalar - firstScalar)])
        }

        /// Behind the face, and the line around it.
        static func colours(_ kind: MascotKind) -> (fill: UInt32, edge: UInt32) {
            let shirt = kind.person.shirt
            return (paler(shirt, by: 0.78), paler(shirt, by: 0.55))
        }
    }

    /// The plan's name on a pill in Claude's orange, as the panel's status row draws it: the fill
    /// faint, the letters a lighter orange. After the tags. Only the plans Claude sells: any other name stays
    /// plain text. Several characters, but on so faint a fill Ghostty's seams do not show.
    enum Badge: String, CaseIterable {
        case free = "Free", pro = "Pro", max = "Max", ultra = "Ultra", team = "Team", enterprise = "Enterprise"

        static let orange: UInt32 = 0xD97757
        /// The fill, over whatever the terminal's background is.
        static let fillOpacity = 0.22
        /// iTerm leaves a hairline between wide characters, so it gets a set of its own after the
        /// rings: the fill solid and carried on under the next part, each letter whole on the last part
        /// it touches. Ghostty shrinks a part drawn past its cells, so other terminals keep the first set.
        /// ponytail: solid = the faint fill over a #22272E background; a light iTerm theme gets a dark pill.
        static let solid: UInt32 = 0x4A3937
        /// The letters: a lighter orange, to read on the faint fill over a dark background.
        /// ponytail: on a light background they read weakly; a second set of badges if anyone uses one.
        static let ink: UInt32 = 0xEE9A7D

        init?(plan: String) {
            guard let badge = Self.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(plan) == .orderedSame }) else { return nil }
            self = badge
        }

        /// Wide characters the pill takes, so its letters are as big as the text's capitals' half
        /// and have room at the round ends.
        var parts: Int { rawValue.count <= 4 ? 2 : rawValue.count <= 7 ? 3 : 4 }

        var firstScalar: UInt32 {
            Self.allCases.prefix { $0 != self }.reduce(Tag.lastScalar + 1) { $0 + UInt32($1.parts) }
        }

        static var lastScalar: UInt32 { enterprise.firstScalar + UInt32(enterprise.parts) - 1 }

        /// The solid set's first character, as far past the rings as the first set is past the tags.
        func firstScalar(solid: Bool) -> UInt32 { firstScalar + (solid ? Bar.lastScalar - Tag.lastScalar : 0) }

        var text: String { text(solid: false) }
        func text(solid: Bool) -> String {
            (0..<UInt32(parts)).map { String(UnicodeScalar(firstScalar(solid: solid) + $0)!) }.joined()
        }
    }

    /// A limit as a ring, filled clockwise from the top: the used part in the text's colour, the
    /// rest a faint track over the terminal's background. One character of two cells, so no
    /// terminal shows a seam in it. After the badges.
    enum Bar {
        /// Steps from empty to full: one a 5%.
        static let levels = 21
        static let track: UInt32 = 0x808080
        static let trackOpacity = 0.45

        static var firstScalar: UInt32 { Badge.lastScalar + 1 }
        static var lastScalar: UInt32 { firstScalar + UInt32(levels) - 1 }

        /// Empty at 0% or less, at least one step above it, full at 100%.
        static func text(_ percent: Double) -> String {
            let steps = levels - 1
            let level = percent <= 0 ? 0 : min(steps, max(1, Int((percent / 100 * Double(steps)).rounded())))
            return String(UnicodeScalar(firstScalar + UInt32(level))!)
        }
    }

    /// Where `kind` stands among the looks: the crew first, then every lead look.
    private static func place(_ kind: MascotKind) -> Int {
        switch kind {
        case .general: 0
        case .explore: 1
        case .plan: 2
        case .other(let shirt): 3 + shirt % Person.otherShirts.count
        case .lead(let look):
            crew.count + (look.face % Person.leads.count) * Person.leadHair.count * Person.leadShirts.count
                + (look.hair % Person.leadHair.count) * Person.leadShirts.count + look.shirt % Person.leadShirts.count
        }
    }

    /// The one character that draws `kind` in `pose`, holding what `holding` names while it works.
    /// A session's own agent has working faces only.
    static func character(_ kind: MascotKind, _ pose: CrewPose, holding: Activity? = nil) -> String {
        let place = place(kind)
        let index: Int
        if let holding, pose == .working {
            index = crew.count * 3 + leadCount + place * Activity.allCases.count + Activity.allCases.firstIndex(of: holding)!
        } else if place >= crew.count {
            index = crew.count * 3 + place - crew.count
        } else {
            index = place * 3 + pose.rawValue
        }
        return String(UnicodeScalar(firstScalar + UInt32(index))!)
    }

    /// Every face as text built by hand, not by `JSONSerialization`, so the bytes are the same on
    /// every Mac. `rects` are runs of one colour along a row, on a 12 by 12 grid, `x1` not included.
    static func facesJSON() -> Data {
        let faces = faces.map { face -> String in
            var cells: [[Character]]
            let opacity: Double
            switch face.pose {
            case .working: (cells, opacity) = (MascotView.pose(face.person, status: .working, callsOut: false, blink: false, wave: 0), 1)
            case .needsYou: (cells, opacity) = (MascotView.pose(face.person, status: .needsYou, callsOut: true, blink: false, wave: 0), 1)
            case .done: (cells, opacity) = (MascotView.pose(face.person, status: .done, callsOut: false, blink: false, wave: 0), 0.45)
            }
            if let holding = face.holding {
                cells = MascotView.hold(holding, cells, under: face.person.underEyes, tick: MascotView.stillTick)
            }
            return entry(face.scalar, opacity: opacity, cells: cells, hex: face.person.hex)
        }
        let pictures = Picture.allCases.map { entry($0.scalar, opacity: 1, cells: $0.cells, hex: $0.hex) }
        // Each contour as x, y, x, y… in font units.
        let marks = Mark.allCases.map { mark in
            let contours = mark.contours.map { "[" + $0.map { "\($0.x),\($0.y)" }.joined(separator: ",") + "]" }
            return "{\"codepoint\":\(mark.scalar),\"contours\":[\(contours.joined(separator: ","))]}"
        }
        // Each badge with its colours and face.
        let tags = Tag.kinds.map { kind in
            let (fill, edge) = Tag.colours(kind)
            let face = runs(MascotView.pose(kind.person, status: .working, callsOut: false, blink: false, wave: 0), kind.person.hex)
            return "{\"codepoint\":\(Tag.text(kind).unicodeScalars.first!.value),\"fill\":\"\(String(format: "%06X", fill))\","
                + "\"edge\":\"\(String(format: "%06X", edge))\",\"rects\":[\(face.joined(separator: ","))]}"
        }
        let (orange, ink) = (String(format: "%06X", Badge.orange), String(format: "%06X", Badge.ink))
        let badges = [false, true].flatMap { solid in
            Badge.allCases.flatMap { badge in
                (0..<badge.parts).map { part in
                    "{\"codepoint\":\(badge.firstScalar(solid: solid) + UInt32(part)),\"part\":\(part),\"parts\":\(badge.parts),\"name\":\"\(badge.rawValue)\","
                        + "\"colour\":\"\(orange)\",\"fill\":\(String(format: "%.2f", Badge.fillOpacity)),\"ink\":\"\(ink)\""
                        + (solid ? ",\"solid\":\"\(String(format: "%06X", Badge.solid))\"}" : "}")
                }
            }
        }
        let bars = (0..<Bar.levels).map { level in
            "{\"codepoint\":\(Bar.firstScalar + UInt32(level)),\"level\":\(level),\"levels\":\(Bar.levels),"
                + "\"track\":\"\(String(format: "%06X", Bar.track))\",\"opacity\":\(String(format: "%.2f", Bar.trackOpacity))}"
        }
        return Data(("{\"family\":\"\(family)\",\"faces\":[\((faces + pictures).joined(separator: ","))],\"marks\":[\(marks.joined(separator: ","))],"
            + "\"tags\":[\(tags.joined(separator: ","))],\"badges\":[\(badges.joined(separator: ","))],\"bars\":[\(bars.joined(separator: ","))]}").utf8)
    }

    private static func entry(_ scalar: UInt32, opacity: Double, cells: [[Character]], hex colour: (Character) -> UInt32?) -> String {
        "{\"codepoint\":\(scalar),\"opacity\":\(String(format: "%.2f", opacity)),\"rects\":[\(runs(cells, colour).joined(separator: ","))]}"
    }

    /// Runs of one colour along each row, as `[x0, x1, y, "RRGGBB"]`, `x1` not included.
    private static func runs(_ cells: [[Character]], _ colour: (Character) -> UInt32?) -> [String] {
        var rects: [String] = []
        for (y, row) in cells.enumerated() {
            var x = 0
            while x < row.count {
                guard let hex = colour(row[x]) else { x += 1; continue }
                var end = x + 1
                while end < row.count, colour(row[end]) == hex { end += 1 }
                rects.append("[\(x),\(end),\(y),\"\(String(format: "%06X", hex))\"]")
                x = end
            }
        }
        return rects
    }

    /// Says which faces a font was built from, so a font that is behind the code can be told.
    static var facesHash: String {
        SHA256.hash(data: facesJSON()).map { String(format: "%02x", $0) }.joined()
    }

    static var uniqueName: String { "AgentValleyCrew-" + facesHash }
}
