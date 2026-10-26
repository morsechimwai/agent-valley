import SwiftUI

/// The pixel lines inside a card, from the session's own agent down to each sub-agent: two
/// points wide, on even points so they stay sharp, with a one-block step at the corner.
enum CrewTree {
    /// How far right the sub-agents stand of the lead's left edge: 14 points past the trunk.
    static let indent: CGFloat = 24
    /// Solid, not see-through white: where branches share the trunk it is no brighter.
    static let gray = Color(white: 0.30)

    struct Branch: Equatable {
        let id: String
        /// The middle of the sub-agent's mascot.
        let y: CGFloat
        /// Where the line stops: 3 points short of the mascot.
        let endX: CGFloat
        /// Red: this sub-agent waits on the person.
        let hot: Bool
    }

    /// To the nearest even point.
    static func snap(_ v: CGFloat) -> CGFloat { (v / 2).rounded() * 2 }

    /// Down the trunk to just above the child's middle, one block in, then across to it.
    static func rects(trunkX: CGFloat, top: CGFloat, to branch: Branch) -> [CGRect] {
        let x0 = snap(trunkX), top = snap(top), cy = snap(branch.y), endX = snap(branch.endX)
        return [CGRect(x: x0 - 1, y: top, width: 2, height: cy - 3 - top),
                CGRect(x: x0 + 1, y: cy - 3, width: 2, height: 2),
                CGRect(x: x0 + 3, y: cy - 1, width: max(0, endX - x0 - 3), height: 2)]
    }

    /// The path a packet runs down a branch: the top, the corner, the end.
    static func route(trunkX: CGFloat, top: CGFloat, to branch: Branch) -> [CGPoint] {
        let x0 = snap(trunkX), top = snap(top), cy = snap(branch.y), endX = snap(branch.endX)
        return [CGPoint(x: x0, y: top), CGPoint(x: x0, y: cy - 2), CGPoint(x: x0 + 2, y: cy), CGPoint(x: endX, y: cy)]
    }

    /// A sub-agent that waits on the person, by its status or by a request under its row.
    static func hot(_ row: AgentRow, requests: Int) -> Bool {
        row.status == .needsYou || requests > 0
    }

    /// How long a packet runs along a branch, and how long the lead lights up once one is back.
    static let run: TimeInterval = 0.8
    static let flash: TimeInterval = 0.5

    /// Each card's sub-agents and how they are doing, to compare with the next.
    static func snapshot(_ cards: [SessionCard]) -> [String: [String: AgentStatus]] {
        Dictionary(cards.map { card in (card.id, Dictionary(card.agents.map { ($0.id, $0.status) }) { $1 }) }) { $1 }
    }

    /// What happened between two snapshots: a sub-agent that came and is not done started, one
    /// that turned done finished. A card new to the list, or a row gone from it, says nothing.
    static func events(old: [String: [String: AgentStatus]], new: [String: [String: AgentStatus]]) -> [CrewEvent] {
        new.flatMap { card, agents -> [CrewEvent] in
            guard let before = old[card] else { return [] }
            return agents.compactMap { agent, status in
                switch (before[agent], status) {
                case (nil, let now) where now != .done: .started(card: card, agent: agent)
                case (let was?, .done) where was != .done: .finished(card: card, agent: agent)
                default: nil
                }
            }
        }
    }

    /// The packets those events send, none on their way yet: only while the panel is open and
    /// motion is not reduced, and none in a card left out (folded to one line, or out of view).
    static func pulses(old: [String: [String: AgentStatus]], new: [String: [String: AgentStatus]],
                       open: Bool, reduced: Bool, leftOut: Set<String>, now: Date = Date()) -> [CrewPulse] {
        guard open, !reduced else { return [] }
        return events(old: old, new: new).compactMap { event in
            let (card, agent, up) = switch event {
            case .started(let card, let agent): (card, agent, false)
            case .finished(let card, let agent): (card, agent, true)
            }
            guard !leftOut.contains(card) else { return nil }
            return CrewPulse(id: UUID(), card: card, agent: agent, up: up, start: now, arrived: false)
        }
    }

    /// How far along its run a packet is, eased in and out; nil once it is over.
    static func progress(start: Date, now: Date) -> Double? {
        let t = max(0, now.timeIntervalSince(start)) / run
        guard t <= 1 else { return nil }
        return t < 0.5 ? 2 * t * t : 1 - pow(2 - 2 * t, 2) / 2
    }

    /// Where the packet's three squares stand, head first: 4 points apart along the route, on
    /// even points. Up runs from the end back to the top.
    static func packet(route: [CGPoint], progress: Double, up: Bool) -> [CGPoint] {
        let length = zip(route, route.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        let head = length * CGFloat(up ? 1 - progress : progress)
        return (0..<3).map { i in
            let p = point(on: route, at: min(length, max(0, head + CGFloat(i) * (up ? 4 : -4))))
            return CGPoint(x: snap(p.x), y: snap(p.y))
        }
    }

    /// A branch as far as a packet running down it has come: the branch's own blocks, cut at
    /// the head, so it is the still line exactly once the packet is there.
    static func trail(route: [CGPoint], progress: Double) -> [CGRect] {
        guard let start = route.first, let end = route.last else { return [] }
        let head = packet(route: route, progress: progress, up: false)[0]
        // Down, then right: whatever lies up and left of the head's block is behind it.
        return rects(trunkX: start.x, top: start.y, to: Branch(id: "", y: end.y, endX: end.x, hot: false)).compactMap { r in
            let width = min(r.maxX, head.x + 1) - r.minX, height = min(r.maxY, head.y + 1) - r.minY
            return width > 0 && height > 0 ? CGRect(x: r.minX, y: r.minY, width: width, height: height) : nil
        }
    }

    /// The point a distance along the route.
    private static func point(on route: [CGPoint], at distance: CGFloat) -> CGPoint {
        var left = distance
        for (a, b) in zip(route, route.dropFirst()) {
            let d = hypot(b.x - a.x, b.y - a.y)
            if left <= d {
                let t = d > 0 ? left / d : 0
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            left -= d
        }
        return route.last ?? .zero
    }
}

/// A sub-agent that appeared in a card, or finished.
enum CrewEvent: Hashable {
    case started(card: String, agent: String)
    case finished(card: String, agent: String)
}

/// A white packet on its way down a branch to a new sub-agent, or up from one that finished.
struct CrewPulse: Equatable, Identifiable {
    let id: UUID
    let card: String
    let agent: String
    let up: Bool
    let start: Date
    /// At the end of its run: the new row shows, or the lead lights up.
    var arrived: Bool
}

/// Where the lead's mascot ("lead"), each sub-agent's mascot (its row id) and the done line's
/// triangle ("done") stand in the card.
struct CrewAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Draws a card's branches over it. Decoration only: it takes no clicks and VoiceOver skips it.
struct CrewTreeView: View {
    let anchors: [String: Anchor<CGRect>]
    /// What the trunk runs down from: the lead, or the envelope its finished sub-agents hang off.
    var root = "lead"
    /// The rows with a branch, top to bottom.
    let order: [String]
    let hot: Set<String>
    /// The packets running along this card's branches. None on its way: the timeline stands still.
    var pulses: [CrewPulse] = []

    var body: some View {
        GeometryReader { proxy in
            if let lead = anchors[root].map({ proxy[$0] }), !order.isEmpty {
                let branches = order.compactMap { id in
                    anchors[id].map { proxy[$0] }.map { CrewTree.Branch(id: id, y: $0.midY, endX: $0.minX - 3, hot: hot.contains(id)) }
                }
                let route = { (b: CrewTree.Branch) in CrewTree.route(trunkX: lead.midX, top: lead.maxY + 3, to: b) }
                TimelineView(.animation(paused: pulses.allSatisfy(\.arrived))) { timeline in
                    Canvas { context, _ in
                        // A branch out to a sub-agent that has not shown yet grows behind its packet.
                        let growing = Dictionary(pulses.filter { !$0.up && !$0.arrived }.map { ($0.agent, $0) }) { $1 }
                        // Gray first, red over it: the trunk down to a waiting sub-agent is red all the way.
                        for red in [false, true] {
                            let path = Path { p in
                                for b in branches where b.hot == red {
                                    if let pulse = growing[b.id] {
                                        p.addRects(CrewTree.trail(route: route(b), progress: CrewTree.progress(start: pulse.start, now: timeline.date) ?? 1))
                                    } else {
                                        p.addRects(CrewTree.rects(trunkX: lead.midX, top: lead.maxY + 3, to: b))
                                    }
                                }
                            }
                            context.fill(path, with: .color(red ? MascotFlag.red : CrewTree.gray), style: FillStyle(antialiased: false))
                        }
                        // The packets over the lines: a white head and two fainter squares behind it.
                        for pulse in pulses where !pulse.arrived {
                            guard let b = branches.first(where: { $0.id == pulse.agent }),
                                  let t = CrewTree.progress(start: pulse.start, now: timeline.date) else { continue }
                            for (square, opacity) in zip(CrewTree.packet(route: route(b), progress: t, up: pulse.up), [1, 0.4, 0.2]) {
                                context.fill(Path(CGRect(x: square.x - 1.5, y: square.y - 1.5, width: 3, height: 3)), with: .color(.white.opacity(opacity)),
                                             style: FillStyle(antialiased: false))
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
