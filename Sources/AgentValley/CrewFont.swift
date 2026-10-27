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

    /// The one character that draws `kind` in `pose`, holding what `holding` names while it works.
    /// A session's own agent has working faces only.
    static func character(_ kind: MascotKind, _ pose: CrewPose, holding: Activity? = nil) -> String {
        let place: Int
        switch kind {
        case .general: place = 0
        case .explore: place = 1
        case .plan: place = 2
        case .other(let shirt): place = 3 + shirt % Person.otherShirts.count
        case .lead(let look):
            place = crew.count + (look.face % Person.leads.count) * 42 + (look.hair % Person.leadHair.count) * 7 + look.shirt % Person.leadShirts.count
        }
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
        return Data("{\"family\":\"\(family)\",\"faces\":[\((faces + pictures).joined(separator: ","))],\"marks\":[\(marks.joined(separator: ","))]}".utf8)
    }

    private static func entry(_ scalar: UInt32, opacity: Double, cells: [[Character]], hex colour: (Character) -> UInt32?) -> String {
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
        return "{\"codepoint\":\(scalar),\"opacity\":\(String(format: "%.2f", opacity)),\"rects\":[\(rects.joined(separator: ","))]}"
    }

    /// Says which faces a font was built from, so a font that is behind the code can be told.
    static var facesHash: String {
        SHA256.hash(data: facesJSON()).map { String(format: "%02x", $0) }.joined()
    }

    static var uniqueName: String { "AgentValleyCrew-" + facesHash }
}
