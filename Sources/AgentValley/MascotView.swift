import SwiftUI

/// Who an agent is drawn as. Each kind of agent Claude Code ships is a person of its own; any
/// other type is the general-purpose person, in a shirt picked by the type's name.
enum MascotKind: Equatable {
    /// Each session's own agent has a look of its own: whoever `Roster` seated in it.
    case lead(LeadLook)
    case general, explore, plan
    /// An index into `Person.otherShirts`.
    case other(shirt: Int)

    /// The agent types Claude Code ships get a fixed person. Any other type takes a shirt from the
    /// pool by its name, so the same type always looks the same. `look`: the session's own agent's.
    init(type: String, look: LeadLook = LeadLook()) {
        switch type.lowercased() {
        case "main": self = .lead(look)
        case "", "general-purpose": self = .general
        case "explore": self = .explore
        case "plan": self = .plan
        default: self = .other(shirt: Int(Self.hash(type) % UInt32(Person.otherShirts.count)))
        }
    }

    /// FNV-1a, not `hashValue`: that one changes on every launch and would recolour the shirts.
    static func hash(_ text: String) -> UInt32 {
        text.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
    }

    var person: Person {
        switch self {
        case .lead(let look):
            Person.leads[look.face % Person.leads.count].wearing(Person.leadShirts[look.shirt % Person.leadShirts.count],
                                                                 hair: Person.leadHair[look.hair % Person.leadHair.count])
        case .general: .beatnik
        case .explore: .afro
        case .plan: .coder
        case .other(let shirt): Person.beatnik.wearing(Person.otherShirts[shirt % Person.otherShirts.count])
        }
    }
}

/// How a session's own agent looks: which of `Person.leads`, in which of `Person.leadHair` and
/// `Person.leadShirts`. As it stands, the session's own agent as it first was.
struct LeadLook: Equatable, Codable {
    var face = 0, hair = 0, shirt = 0
}

/// A head and shoulders, twelve rows of twelve: computer people of 1969, each with glasses and
/// hair of their own. `.` is empty and every other letter a colour (`colour(_:)`): `o` an eye,
/// `m` the mouth, `s` skin, `h` hair, `c` the shirt and `C` its paler dye.
struct Person: Equatable {
    let rows: [String]
    /// Colours as 0xRRGGBB. The shirt is the person's own: it does not say the model.
    let skin: UInt32, skinShade: UInt32, hair: UInt32, shirt: UInt32
    /// What an eye leaves behind when it shuts or turns: skin, or the glass in front of it.
    let underEyes: Character

    /// The shirts of the types Claude Code does not ship. Not the general-purpose teal: those
    /// would pass for general-purpose agents.
    static let otherShirts: [UInt32] = [0xD9B341, 0xE889B5, 0x8A9A4A, 0xB07A4A]
    /// The shirts of the sessions' own agents, the first the guru's own orange. No red: that is
    /// "needs you".
    static let leadShirts: [UInt32] = [0xE07B39, 0xE5B630, 0x4FAE5A, 0x3FA7D9, 0xE0679F, 0x8C6BD9, 0x9CC43F]
    /// Their hair, and their beards with it: the guru's own brown first, then black, dark brown,
    /// auburn, ginger, blonde.
    static let leadHair: [UInt32] = [0x7A5233, 0x2B2420, 0x4E3426, 0x8E3F22, 0xC0622A, 0xD8B26A]
    /// Who a session's own agent can be.
    static let leads: [Person] = [.guru, .walrus, .engineer, .pearls]

    func wearing(_ shirt: UInt32, hair: UInt32? = nil) -> Person {
        Person(rows: rows, skin: skin, skinShade: skinShade, hair: hair ?? self.hair, shirt: shirt, underEyes: underEyes)
    }

    /// Whether two colours are too close to tell apart where they meet, as a beard does the shirt
    /// under it: nearer than 70 in red, green and blue together.
    static func close(_ one: UInt32, _ other: UInt32) -> Bool {
        let apart = [16, 8, 0].map { Double(Int((one >> $0) & 0xFF) - Int((other >> $0) & 0xFF)) }
        return apart.map { $0 * $0 }.reduce(0, +).squareRoot() < 70
    }

    /// A cell's colour as 0xRRGGBB, a dye's paler half already mixed toward white. The website
    /// draws its people from these same numbers.
    func hex(_ cell: Character) -> UInt32? {
        let base: UInt32? = switch cell {
        case "s": skin
        case "S": skinShade
        case "h": hair
        case "c", "C": shirt
        case "o": 0x2B1D16  // an eye
        case "m": 0xA2473E  // the mouth
        case "M": 0x3A1414  // the mouth, open
        case "p": 0xF0918F  // a cheek
        case "w": 0xEFEFEF  // a collar, a pendant
        case "K": 0x1E1E1E  // black frames
        case "l": 0xD6E9F2  // clear glass
        case "T": 0xE0A030  // amber glass
        case "B": 0x6B3F1F  // tortoiseshell frames
        // What a person at work holds: `MascotView.hold`.
        case "q": 0xF4F1E6  // printout paper, the dots of a thought
        case "Q": 0xBFE0B5  // the printout's green bar
        case "x": 0x6A6A6A  // print on it
        case "z": 0xA0A0A0  // its sprocket holes
        case "k": 0xE8E0CC  // a key
        case "d": 0x5E5850  // the keyboard between keys
        case "v": 0xCFC6A8  // a terminal's case
        case "e": 0x0E2A12  // its screen
        case "g": 0x5BE37D  // output on it
        case "G": 0xC9A227  // a magnifying glass's rim
        case "L": 0xBFE3F0  // its glass
        case "n": 0x4A2E1A  // its handle
        case "r": 0xEFE6D0  // a telephone receiver, ivory
        case "R": 0xB8AE96  // its cord
        default: nil
        }
        guard let base else { return nil }
        return cell == "C" ? paler(base, by: 0.45) : base
    }

    func colour(_ cell: Character) -> Color? {
        hex(cell).map(rgb)
    }

    /// The session's own agent: long hair, a full beard, round amber glasses, a tie-dyed shirt.
    static let guru = Person(rows: [
        "............",
        "...hhhhhh...",
        "..hhhhhhhh..",
        ".hhsssssshh.",
        ".hsTTssTTsh.",
        ".hsTossoTsh.",
        ".hspsssspsh.",
        ".hhhhmmhhhh.",
        ".hhhhhhhhhh.",
        "..hhhhhhhh..",
        ".cCccwwccCc.",
        "ccCcCccCcCcc",
    ], skin: 0xF2C39B, skinShade: 0xD99B72, hair: 0x7A5233, shirt: 0xE07B39, underEyes: "T")

    /// A session's own agent: hair parted at the side, a walrus moustache and long sideburns,
    /// square black glasses, a shirt with a white collar.
    static let walrus = Person(rows: [
        "............",
        "..hhhhhhh...",
        ".hhhhhhhhhh.",
        ".hhsssssshh.",
        ".hKKKKKKKKh.",
        ".hKolKKolKh.",
        ".hKKKssKKKh.",
        ".hshhhhhhsh.",
        ".hhhsmmshhh.",
        "...ssssss...",
        ".ccwwccwwcc.",
        "cccccccccccc",
    ], skin: 0xF2C39B, skinShade: 0xD99B72, hair: 0x4E3426, shirt: 0x3FA7D9, underEyes: "l")

    /// A session's own agent, from mission control: a flat-top, tortoiseshell glasses, a thin
    /// moustache, a sweater vest over a white shirt and a dark tie.
    static let engineer = Person(rows: [
        "............",
        "..hhhhhhhh..",
        "..hhhhhhhh..",
        ".hssssssssh.",
        ".hBBBssBBBh.",
        ".hBolBBolBh.",
        ".sBBBssBBBs.",
        ".ssshhhhsss.",
        "..sssmmsss..",
        "...ssssss...",
        ".ccwwKKwwcc.",
        "ccccwKKwcccc",
    ], skin: 0xF2C39B, skinShade: 0xD99B72, hair: 0x4E3426, shirt: 0xE5B630, underEyes: "l")

    /// A session's own agent: short set curls, cat-eye glasses, a string of pearls.
    static let pearls = Person(rows: [
        "............",
        "..hhhhhhhh..",
        ".hhhhhhhhhh.",
        ".KhsssssshK.",
        ".KKKKssKKKK.",
        ".hlolsslolh.",
        ".hsKKssKKsh.",
        ".hspsssspsh.",
        "..sssmmsss..",
        "...ssssss...",
        ".ccwcwwcwcc.",
        "cccccccccccc",
    ], skin: 0x7A4A30, skinShade: 0x5E3722, hair: 0x2B2420, shirt: 0xE0679F, underEyes: "l")

    /// general-purpose, and in other shirts every type Claude Code does not ship: browline
    /// glasses, a goatee, a turtleneck.
    static let beatnik = Person(rows: [
        "............",
        "...hhhhhh...",
        "..hhhhhhhh..",
        "..hhhssssh..",
        "..KKKssKKK..",
        "..ssossoss..",
        ".sssossosss.",
        "..spssssps..",
        "..sssmmsss..",
        "...shhhhs...",
        "..cccccccc..",
        "cccccccccccc",
    ], skin: 0xC98D5E, skinShade: 0xA8703F, hair: 0x5A4636, shirt: 0x3FB3A8, underEyes: "s")

    /// Explore: an afro that stops at her ears, big round glasses.
    static let afro = Person(rows: [
        "...hhhhhh...",
        ".hhhhhhhhhh.",
        "hhhhhhhhhhhh",
        "hhKKKssKKKhh",
        "hKlolKKlolKh",
        "hKlllKKlllKh",
        ".hKKKssKKKh.",
        "..sssmmsss..",
        "...ssssss...",
        "..cccSSccc..",
        ".cCccwwccCc.",
        "ccCcCccCcCcc",
    ], skin: 0x8D5A3B, skinShade: 0x6E4329, hair: 0x5C4033, shirt: 0xA77BD9, underEyes: "l")

    /// Plan: long hair, thick black glasses, a cardigan over a white collar.
    static let coder = Person(rows: [
        "............",
        "...hhhhhh...",
        "..hhhhhhhh..",
        ".hKKKKKKKKh.",
        ".hKlollolKh.",
        ".hKlollolKh.",
        ".hKKKssKKKh.",
        ".hsssmmsssh.",
        ".hhsssssshh.",
        ".hcwwSSwwch.",
        ".ccccwwcccc.",
        "cccccwwccccc",
    ], skin: 0xF2C39B, skinShade: 0xD99B72, hair: 0x9A5B35, shirt: 0x5B9BD5, underEyes: "l")
}

/// `hex` taken `amount` of the way toward white, each channel rounded to a whole step.
func paler(_ hex: UInt32, by amount: Double) -> UInt32 {
    [16, 8, 0].reduce(UInt32(0)) { mixed, shift in
        let value = Double((hex >> UInt32(shift)) & 0xFF)
        return mixed | UInt32((value + (255 - value) * amount).rounded()) << UInt32(shift)
    }
}

func rgb(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

/// The dot at a mascot's corner. Red is kept for the one state that is certain to need the
/// person; an agent that has only gone quiet may or may not, and gets white.
enum MascotFlag: Equatable {
    case quiet, needsYou

    init?(status: AgentStatus) {
        switch status {
        case .quiet: self = .quiet
        case .needsYou: self = .needsYou
        case .working, .done: return nil
        }
    }

    var color: Color {
        self == .needsYou ? MascotFlag.red : .white
    }

    /// The colour of "needs you", here and on the bar's count.
    static let red = Color(red: 1.0, green: 0.27, blue: 0.23)
}

/// What an agent at work is busy with, by the tool call it has open. Each has a thing to hold.
/// New cases go at the end: the terminal's font counts through them in this order.
enum Activity: Equatable, CaseIterable {
    /// No call open: the model is working out what to say or do next.
    case thinking
    case reading, typing, running, searching, calling

    /// `tool`: the newest call still waiting for its result, nil with none open. A tool with no
    /// picture of its own leaves the hands empty.
    init?(tool: String?) {
        switch tool {
        case nil: self = .thinking
        case "Read", "WebFetch": self = .reading
        case "Edit", "MultiEdit", "Write", "NotebookEdit": self = .typing
        case "Bash", "BashOutput": self = .running
        case "Grep", "Glob", "WebSearch", "ToolSearch": self = .searching
        case "Agent", "Task": self = .calling
        default: return nil
        }
    }
}

/// A pixel person. While its agent works it blinks and holds a thing that says what the agent is
/// doing, or thinks, chin in hand, between things: it never stands bare and bobs, which read as
/// idle. It looks aside and dims while the agent is quiet, opens its mouth and waves while it
/// calls the person, and fades further with its eyes shut once the agent has finished.
struct MascotView: View {
    let status: AgentStatus
    var kind = MascotKind.general
    var size: CGFloat = 20
    /// The dot at the corner, if any. A row passes its own; the bar passes the one for all agents.
    var flag: MascotFlag?
    /// Whether the flag is drawn as a dot. Not on the bar while the red count stands right beside
    /// the mascot: the count is that flag, and the mascot still calls out.
    var dot = true
    /// Its agent is called busy and has written nothing for a long while: it stops moving.
    var still = false
    /// What its agent is doing, when it works and the tool has a picture.
    var activity: Activity? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The activity on show, and since when. It changes no sooner than `minimumHold` after the
    /// last change: a call can be over in under a second, and a thing in hand must not flicker.
    @State private var shown: Activity? = nil
    @State private var shownSince = Date.distantPast

    static let minimumHold: TimeInterval = 2
    /// Of every round from when the activity began, the thing is in hand for the first part and
    /// put down for the rest: nobody holds a thing the whole time.
    static let round: TimeInterval = 8, inHand: TimeInterval = 6
    /// The one moment drawn under Reduce Motion, where every thing shows what it is.
    static let stillTick = 3

    /// Dim while quiet, fainter still once done, in its own colours: who it was still shows.
    /// Under Reduce Motion nothing moves, and this with the eyes has to tell the three apart.
    static func fade(_ status: AgentStatus) -> Double {
        switch status {
        case .quiet: 0.5
        case .done: 0.4
        case .working, .needsYou: 1
        }
    }

    /// `still` is for a row Claude Code calls busy whose transcript has gone silent: it must not
    /// go on moving as if all were well.
    static func animates(_ status: AgentStatus, reduceMotion: Bool, still: Bool = false) -> Bool {
        status == .working && !reduceMotion && !still
    }

    /// The one carrying the red dot calls the person with a hand up. Under Reduce Motion the hand
    /// stays up and does not move.
    static func waves(_ flag: MascotFlag?, reduceMotion: Bool) -> Bool {
        flag == .needsYou && !reduceMotion
    }

    /// The person's cells for one moment. `callsOut`: mouth open and a hand up, which `wave`
    /// moves between two places. `blink` shuts every eye.
    static func pose(_ person: Person, status: AgentStatus, callsOut: Bool, blink: Bool, wave: Int) -> [[Character]] {
        var cells = person.rows.map(Array.init)
        let eyes = cells.indices.flatMap { y in cells[y].indices.filter { cells[y][$0] == "o" }.map { (y, $0) } }
        let under = person.underEyes
        if blink {
            for (y, x) in eyes { cells[y][x] = under }
        } else if status == .done {
            // Asleep, the upper row of each eye closes and a line is left. An eye one cell tall shuts.
            let top = eyes.map(\.0).min()
            for (y, x) in eyes where y == top { cells[y][x] = under }
        } else if status == .quiet {
            // It looks aside.
            turnEyes(&cells, by: 1, under: under)
        }
        if callsOut {
            if let mouth = cells.firstIndex(where: { $0.contains("m") }), mouth + 1 < cells.count {
                for x in cells[mouth].indices where cells[mouth][x] == "m" {
                    cells[mouth][x] = "M"
                    cells[mouth + 1][x] = "M"
                }
            }
            // A hand up on the left, clear of the dot at the right corner, and the arm under it.
            let hand = wave % 2 == 0 ? 3 : 2
            for y in hand...(hand + 1) { cells[y][0] = "s"; cells[y][1] = "s" }
            for y in (hand + 2)...10 { cells[y][0] = "c" }
        }
        return cells
    }

    /// Every eye one cell to the side, as far as its glasses or face leave room to turn.
    static func turnEyes(_ cells: inout [[Character]], by step: Int, under: Character) {
        let eyes = cells.indices.flatMap { y in cells[y].indices.filter { cells[y][$0] == "o" }.map { (y, $0) } }
        for (y, x) in eyes where cells[y].indices.contains(x + step) && cells[y][x + step] == under {
            cells[y][x] = under
            cells[y][x + step] = "o"
        }
    }

    /// What it holds at `date`, by the round that began `since`: the thing for the first part of
    /// the round, then a thought, as it does with no thing to show. Each agent began its activity
    /// at its own time, so they do not all put things down together. Under Reduce Motion the
    /// thing stays in hand. `atWork`: working, not stalled, not calling the person.
    static func inHand(_ activity: Activity?, atWork: Bool, since: Date, at date: Date, reduceMotion: Bool) -> Activity? {
        guard atWork else { return nil }
        guard let activity, reduceMotion || date.timeIntervalSince(since).truncatingRemainder(dividingBy: round) < inHand else { return .thinking }
        return activity
    }

    /// `cells` with the thing for `activity` in hand at `tick`: a page feeding, a key going
    /// down, a line of output, the glass going over things. All of it inside the twelve by
    /// twelve, so a row is no wider for it.
    static func hold(_ activity: Activity, _ cells: [[Character]], under: Character, tick: Int) -> [[Character]] {
        var cells = cells
        func put(_ x: Int, _ y: Int, _ cell: Character) {
            if cells.indices.contains(y), cells[y].indices.contains(x) { cells[y][x] = cell }
        }
        func draw(_ rows: [String], _ left: Int, _ top: Int) {
            for (y, row) in rows.enumerated() { for (x, cell) in row.enumerated() where cell != "." { put(left + x, top + y, cell) } }
        }
        switch activity {
        case .thinking:
            // Chin in hand, looking one way and then the other, the dots of a thought coming.
            turnEyes(&cells, by: tick / 4 % 2 == 0 ? -1 : 1, under: under)
            draw(["SS", "SS", "c"], 2, 8)
            put(1, 11, "c")
            for dot in 0..<min(tick % 6, 3) { put(dot * 2, 0, "q") }
        case .reading:
            // A printout off the line printer, its green bars rolling up as it is read.
            turnEyes(&cells, by: 1, under: under)
            let roll = tick / 2 % 2
            for y in 4...10 { for x in 9...11 { put(x, y, (y + roll) / 2 % 2 == 1 ? "Q" : "q") } }
            for y in [5, 7, 9] { put(11, y, "z") }
            for (x, y) in [(10, 5), (9, 7), (10, 7), (10, 9)] where y - roll >= 4 { put(x, y - roll, "x") }
            draw(["S", "S", ".qQ"], 8, 9)
        case .typing:
            // A keyboard, one finger down at a time.
            draw([".kdkdkdkdkd", ".dkdkdkdkdk"], 0, 10)
            let fingers = [2, 3, 8, 9], down = tick % 4
            for (index, x) in fingers.enumerated() { put(x, index == down ? 10 : 9, "S") }
            put(fingers[down], 11, "w")
        case .running:
            // A terminal at the elbow, output running down its green screen.
            turnEyes(&cells, by: 1, under: under)
            draw(["vvvvv", "veeev", "veeev", "vvvvv", ".vvv."], 7, 7)
            draw([["g.g", "gg."], ["gg.", "g.g"], ["g.g", "g.."], ["gg.", "g.."]][tick % 4], 8, 8)
        case .searching:
            // A magnifying glass going over things, an eye big behind it.
            let step = tick / 2 % 4, left = [5, 6, 6, 5][step], top = [3, 3, 4, 4][step]
            draw([".GGG.", "GLoLG", "GLoLG", "GLLLG", ".GGG.", "....n", ".....n", "......s"], left, top)
        case .calling:
            // On the phone to a helper, talking.
            if tick % 2 == 0 { for y in cells.indices { for x in cells[y].indices where cells[y][x] == "m" { cells[y][x] = "M" } } }
            draw(["rr", "rr", "r.", "rs", "rs", "rr", "rr", "R.", ".R"], 0, 3)
        }
        return cells
    }

    var body: some View {
        let moving = Self.animates(status, reduceMotion: reduceMotion, still: still)
        let waving = Self.waves(flag, reduceMotion: reduceMotion)
        let person = kind.person
        let fade = Self.fade(status)
        // Only at work, and never while it calls the person: the wave must say the most.
        let atWork = status == .working && !still && flag != .needsYou
        TimelineView(.animation(minimumInterval: 0.4, paused: !moving && !waving)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.4)
            let posed = Self.pose(person, status: status, callsOut: flag == .needsYou,
                                  blink: moving && tick % 8 == 0, wave: waving ? tick : 0)
            let holding = Self.inHand(shown, atWork: atWork, since: shownSince, at: context.date, reduceMotion: reduceMotion)
            Pixels(cells: holding.map { Self.hold($0, posed, under: person.underEyes, tick: moving ? tick : Self.stillTick) } ?? posed,
                   size: size, colour: person.colour)
            .opacity(fade)
        }
        .task(id: activity) {
            let wait = Self.minimumHold - Date.now.timeIntervalSince(shownSince)
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            shown = activity
            shownSince = .now
        }
        .overlay(alignment: .topTrailing) {
            if let flag, dot {
                // A black ring keeps the dot apart from the mascot's own colours.
                Circle().fill(flag.color)
                    .frame(width: size * 0.4, height: size * 0.4)
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: size * 0.07))
                    .offset(x: size * 0.25, y: -size * 0.12)
            }
        }
        // The row says the type and the model in words; the person repeats the type.
        .accessibilityHidden(true)
    }
}

/// Rows of cells, each its own colour or none, `size` wide: a mascot's square, or the logo's band.
struct Pixels: View {
    let cells: [[Character]]
    let size: CGFloat
    let colour: (Character) -> Color?
    @Environment(\.displayScale) private var scale

    var body: some View {
        Canvas { graphics, canvasSize in
            let cell = canvasSize.width / CGFloat(columns)
            // Edges on whole device pixels: cells of a fractional size left hairlines between them.
            let snap = { (value: CGFloat) in (value * scale).rounded() / scale }
            for (y, row) in cells.enumerated() {
                for (x, letter) in row.enumerated() {
                    guard let colour = colour(letter) else { continue }
                    let left = snap(CGFloat(x) * cell), top = snap(CGFloat(y) * cell)
                    let rect = CGRect(x: left, y: top, width: snap(CGFloat(x + 1) * cell) - left, height: snap(CGFloat(y + 1) * cell) - top)
                    graphics.fill(Path(rect), with: .color(colour))
                }
            }
        }
        .frame(width: size, height: size * CGFloat(cells.count) / CGFloat(columns))
    }

    private var columns: Int { max(1, cells.first?.count ?? 1) }
}

/// What the bar shows with nothing left to do: a mug of coffee, its steam swaying. Under Reduce
/// Motion the steam holds still.
struct Mug: View {
    var size: CGFloat = 18

    /// The steam leans one way, then the other. Below it nothing moves.
    static let frames: [[String]] = [[
        "...l..l.....",
        "....l..l....",
        "...l..l.....",
        "....l..l....",
    ], [
        "....l..l....",
        "...l..l.....",
        "....l..l....",
        "...l..l.....",
    ]].map { $0 + [
        "............",
        ".PnnnnnnP...",
        ".ppppppppPP.",
        ".pppppppp.P.",
        ".pppppppp.P.",
        ".ppppppppPP.",
        ".pppppppp...",
        "..PPPPPP....",
    ] }

    static func hex(_ cell: Character) -> UInt32? {
        switch cell {
        case "p": 0xF2EAD8  // the mug, a diner's cream
        case "P": 0xE07B39  // its orange rim, handle and foot
        case "n": 0x4A2C1A  // the coffee
        case "l": 0xFFFFFF  // steam
        default: nil
        }
    }

    static func colour(_ cell: Character) -> Color? {
        hex(cell).map(rgb)
    }

    var body: some View {
        Flipbook(frames: Self.frames, colour: Self.colour, size: size)
    }
}

/// What the bar shows in the mug's place once a plan limit has run out: the crew has gone
/// fishing, and a fish on the line flicks its tail. Under Reduce Motion it holds still.
struct Fish: View {
    var size: CGFloat = 18

    /// The tail up, then down. The line and the body stay put.
    static let frames: [[String]] = [[
        ".l...FF...F.",
        ".l.FFFFF.FF.",
        ".lFffffffFF.",
        ".ffeffffffF.",
        "..wwwwwwwF..",
        "...wwwww....",
        "............",
    ], [
        ".l...FF.....",
        ".l.FFFFF....",
        ".lFffffffF..",
        ".ffeffffffF.",
        "..wwwwwwwFF.",
        "...wwwww.FF.",
        "..........F.",
    ]].map { Array(repeating: ".l..........", count: 5) + $0 }

    static func hex(_ cell: Character) -> UInt32? {
        switch cell {
        case "l": 0xFFFFFF  // the line
        case "F": 0x4F7A8C  // its back, fins and tail
        case "f": 0x8DB6C4  // its silver side
        case "w": 0xE6EEF0  // its belly
        case "e": 0x1C1C1C  // its eye
        default: nil
        }
    }

    static func colour(_ cell: Character) -> Color? {
        hex(cell).map(rgb)
    }

    var body: some View {
        Flipbook(frames: Self.frames, colour: Self.colour, size: size)
    }
}

/// In the fish's place once the weekly limit has run out: the crew took the van, surfboard on
/// the roof, and the road goes by under it. Under Reduce Motion it holds still.
struct Van: View {
    var size: CGFloat = 18

    static let frames: [[String]] = ["g...g...g...", "..g...g...g."].map { road in [
        "............",
        "............",
        "...tttttttt.",
        "..pppppppp..",
        ".pwwpwwpwwp.",
        ".pwwpwwpwwp.",
        ".pppppppppp.",
        ".oooooooooo.",
        ".oooooooooo.",
        ".oKKooooKKo.",
        "..KK....KK..",
        road,
    ] }

    static func hex(_ cell: Character) -> UInt32? {
        switch cell {
        case "p": 0xF2EAD8  // the upper half, the mug's cream
        case "o": 0xE07B39  // the lower half, the mug's orange
        case "w": 0x3A4A58  // windows
        case "t": 0x3E9C9A  // the surfboard
        case "K": 0x222222  // tyres
        case "g": 0x808080  // the road's lines
        default: nil
        }
    }

    static func colour(_ cell: Character) -> Color? {
        hex(cell).map(rgb)
    }

    var body: some View {
        Flipbook(frames: Self.frames, colour: Self.colour, size: size)
    }
}

/// Two frames in turn, a little under a second each. Under Reduce Motion the first, held still.
struct Flipbook: View {
    let frames: [[String]]
    let colour: (Character) -> Color?
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.8, paused: reduceMotion)) { context in
            let frame = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.8) % frames.count
            Pixels(cells: frames[frame].map(Array.init), size: size, colour: colour)
        }
        .accessibilityHidden(true)
    }
}

/// A finished sub-agent's work in the book, before its name: a page with its corner turned down,
/// as a Markdown file is drawn.
struct DocIcon: View {
    /// Cells as big as a 14-point mascot's.
    var size: CGFloat = 8 * 14 / 12

    static let cells: [String] = [
        "pppppF..",
        "pppppFF.",
        "pppppFFF",
        "pppppppp",
        "pttttttp",
        "pppppppp",
        "pttttttp",
        "pppppppp",
        "ptttttpp",
        "pppppppp",
    ]

    var body: some View {
        Pixels(cells: Self.cells.map(Array.init), size: size, colour: { ($0 == "F" ? 0xC9BFA5 : DoneBook.hex($0)).map(rgb) })
            .accessibilityHidden(true)
    }
}

/// Before "N done": the finished work filed in a green ledger, shut until the person opens it to
/// the documents inside. Green is the colour of done: red is for what waits on the person.
struct DoneBook: View {
    /// Whether it is open to its documents.
    var open = false
    /// Cells as big as a 20-point mascot's.
    var size: CGFloat = 20 * 10 / 12

    static let shut: [String] = [
        "SCCCCCCCC.",
        "SCCCCCCCCp",
        "SCLLLLLCCp",
        "SCCCCCCCCp",
        "SCCCCCCCCp",
        "SCCCCCCCCp",
        ".ppppppLpp",
        ".......L..",
    ]

    static let opened: [String] = [
        ".ppp..ppp.",
        "ppppggpppp",
        "pttpggpttp",
        "ppppggpppp",
        "pttpggpttp",
        "ppppggpppp",
        "CCCCLLCCCC",
        "....LL....",
    ]

    static func hex(_ cell: Character) -> UInt32? {
        switch cell {
        case "C": 0x2F7D4A  // the green cloth cover
        case "S": 0x1F5A34  // its spine
        case "L": 0xD9B44A  // the gold label and ribbon
        case "p": 0xEFE6CF  // paper
        case "g": 0xD8CDAF  // the fold between the pages
        case "t": 0x9A8F78  // writing
        default: nil
        }
    }

    var body: some View {
        // "1 done" says it in words, and the line's value says whether its lines show.
        Pixels(cells: (open ? Self.opened : Self.shut).map(Array.init), size: size, colour: { Self.hex($0).map(rgb) })
            .accessibilityHidden(true)
    }
}

