import AppKit
import SwiftUI
import XCTest
@testable import AgentValley

/// The made-up month the site's report motion is drawn from, and the pictures, PDFs and totals
/// drawn from it. The writing is skipped unless `testing/site.sh report` runs it.
@MainActor
final class ReportMotionAssetsTests: XCTestCase {
    /// A month already over, so the History page draws no day as still to come, whenever this runs.
    static let month = HistoryReport.calendar().dateInterval(of: .month, for: day(2026, 9, 15))!
    static let printed = day(2026, 10, 1, hour: 9)

    private static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        HistoryReport.calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// The site's made-up projects (site/lib/history.ts): their sessions, how busy each is, and
    /// how its answers split across models and agents.
    private static let projects: [(name: String, busy: Double, models: [(String, Double)], agents: [(String, Double)], sessions: [String])] = [
        ("shop-web", 1, [("claude-opus-5-5", 0.82), ("claude-sonnet-5-5", 0.15), ("claude-haiku-5-5", 0.03)],
         [("main", 0.76), ("Explore", 0.16), ("Plan", 0.08)],
         ["Refactor checkout flow", "Deploy preview build", "Fix coupon rounding", "Add Apple Pay to checkout"]),
        ("api", 0.7, [("claude-opus-5-5", 0.6), ("claude-sonnet-5-5", 0.4)], [("main", 0.86), ("Explore", 0.14)],
         ["Rate limits for the public API", "Move auth to sessions", "Fix the slow orders query"]),
        ("mobile-app", 0.45, [("claude-sonnet-5-5", 0.9), ("claude-haiku-5-5", 0.1)], [("main", 0.9), ("general-purpose", 0.1)],
         ["Push notifications on Android", "Offline cart"]),
        ("docs", 0.25, [("claude-sonnet-5-5", 0.7), ("claude-haiku-5-5", 0.3)], [("main", 1)],
         ["Rewrite the install guide", "API reference from OpenAPI"]),
    ]

    /// Picks from shares by a number in 0..<1.
    private static func pick(_ shares: [(String, Double)], at u: Double) -> String {
        var sum = 0.0
        for (name, share) in shares {
            sum += share
            if u < sum { return name }
        }
        return shares.last!.0
    }

    /// The transcripts of September in `folder`/projects, read into a ledger at `folder`/history.sqlite.
    /// Nothing random: the n-th answer's model and agent come from n, so every run makes the same month.
    static func madeUpLedger(in folder: String) throws -> UsageLedger {
        let root = URL(fileURLWithPath: folder + "/projects")
        let calendar = HistoryReport.calendar()
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var serial = 0
        for (p, project) in projects.enumerated() {
            // Each session's own lines, and its sub-agents' by type.
            var main = project.sessions.map { [#"{"type":"ai-title","aiTitle":"\#($0)","sessionId":"s-\#(p)-\#(project.sessions.firstIndex(of: $0)!)"}"#] }
            var sub = project.sessions.map { _ in [String: [String]]() }
            var day = month.start
            var d = 0
            while day < month.end {
                let weekend = calendar.isDateInWeekend(day)
                // In steps with their types written: one expression was too much for CI's compiler.
                let perDay: Double = weekend ? 30 : 104
                let step = (d * 7 + p * 3) % 5
                let variation: Double = 0.75 + 0.5 * Double(step) / 4
                let count = Int((project.busy * perDay * variation).rounded())
                // A session runs for a few days, then the next one takes over.
                let s = (d / 4 + p) % project.sessions.count
                // From nine in the morning, spread over ten hours.
                let gap: Double = 36_000 / Double(max(count, 1))
                for n in 0..<count {
                    serial += 1
                    let at = day.addingTimeInterval(32_400 + Double(n) * gap)
                    let model = pick(project.models, at: (Double(serial) * 0.618_033_988_7).truncatingRemainder(dividingBy: 1))
                    let agent = pick(project.agents, at: (Double(serial) * 0.414_213_562_4).truncatingRemainder(dividingBy: 1))
                    let output = 3_000 + (serial * 7919) % 7_000
                    let line = #"{"type":"assistant","timestamp":"\#(stamp.string(from: at))","cwd":"/Users/demo/\#(project.name)","sessionId":"s-\#(p)-\#(s)","message":{"id":"m\#(serial)","model":"\#(model)","usage":{"input_tokens":20,"cache_creation_input_tokens":25000,"cache_read_input_tokens":300000,"output_tokens":\#(output)}}}"#
                    if agent == "main" { main[s].append(line) } else { sub[s][agent, default: []].append(line) }
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
                d += 1
            }
            for s in project.sessions.indices {
                let id = "s-\(p)-\(s)"
                let file = root.appendingPathComponent("p\(p)/\(id).jsonl")
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try (main[s].joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
                for (a, (type, lines)) in sub[s].sorted(by: { $0.key < $1.key }).enumerated() {
                    let agents = root.appendingPathComponent("p\(p)/\(id)/subagents")
                    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
                    try (lines.joined(separator: "\n") + "\n").write(to: agents.appendingPathComponent("agent-a\(a).jsonl"), atomically: true, encoding: .utf8)
                    try #"{"agentType":"\#(type)","description":"Help"}"#.write(to: agents.appendingPathComponent("agent-a\(a).meta.json"), atomically: true, encoding: .utf8)
                }
            }
        }
        let ledger = UsageLedger(root: root, database: URL(fileURLWithPath: folder + "/history.sqlite"))
        _ = ledger.scan(now: printed, calendar: calendar)
        return ledger
    }

    private func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Writes into REPORT_MOTION_OUT the History page drawn off the screen, all projects and
    /// shop-web, the two PDFs Export PDF makes of them, and their totals as totals.json.
    func testWriteReportMotionAssets() throws {
        guard let out = ProcessInfo.processInfo.environment["REPORT_MOTION_OUT"] else { throw XCTSkip("Run by testing/site.sh report.") }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let base = out + "/data"
        try? FileManager.default.removeItem(atPath: base)
        let ledger = try Self.madeUpLedger(in: base)
        let calendar = HistoryReport.calendar()
        let anchor = Self.day(2026, 9, 15)

        var slice = try ledger.slice(Self.month)
        slice.interval = Self.month
        var totals: [String] = []
        for (name, project) in [("all", nil), ("shop-web", "/Users/demo/shop-web")] as [(String, String?)] {
            let document = try XCTUnwrap(HistoryDocument.make(slice, pick: HistoryPick(span: .month, anchor: anchor, project: project),
                                                              calendar: calendar, home: "/Users/demo", printed: Self.printed))
            try ReportPDF.data(document, calendar: calendar).write(to: URL(fileURLWithPath: "\(out)/report-\(name).pdf"))
            totals.append(String(format: "\"%@\": %.2f", name, document.total))
        }
        // In cents as the PDF prints them; JSONSerialization would write 1414.6600000000001.
        try "{\(totals.joined(separator: ", "))}\n".write(toFile: "\(out)/totals.json", atomically: true, encoding: .utf8)

        // The page in the panel, off the screen, as PanelPicturesTests draws it.
        let empty = URL(fileURLWithPath: base + "/none")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let store = AgentStore(root: empty, sessions: empty)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "report-motion-\(UUID().uuidString)"))
        let settings = Settings(defaults: defaults)
        let state = NotchState()
        state.screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        state.barHeight = 38
        state.notchWidth = 200
        store.start()
        let host = NSHostingView(rootView: PanelView(store: store, state: state, settings: settings, limits: PlanLimitsClient(),
                                                     answers: AnswerStore(directory: URL(fileURLWithPath: base + "/answers")),
                                                     sound: SoundPlayer(settings: settings), usage: ledger, updates: Updates(info: [:])))
        let window = NSWindow(contentRect: CGRect(x: -4000, y: 0, width: 600, height: 960), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        for (name, project) in [("all", nil), ("shop-web", "/Users/demo/shop-web")] as [(String, String?)] {
            state.showingHistory = true
            state.historyPick = HistoryPick(span: .month, anchor: anchor, project: project)
            state.expanded = true
            state.openedAt = Date()
            state.opens += 1
            pump(2)
            host.layoutSubtreeIfNeeded()
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "\(out)/history-\(name).png"))
        }
    }

    func testMadeUpSeptemberLooksLikeTheSite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let ledger = try Self.madeUpLedger(in: folder)
        let calendar = HistoryReport.calendar()
        var slice = try ledger.slice(Self.month)
        slice.interval = Self.month
        let all = try XCTUnwrap(HistoryDocument.make(slice, pick: HistoryPick(span: .month, anchor: Self.month.start, project: nil),
                                                     calendar: calendar, home: "/Users/demo", printed: Self.printed))
        let shop = try XCTUnwrap(HistoryDocument.make(slice, pick: HistoryPick(span: .month, anchor: Self.month.start, project: "/Users/demo/shop-web"),
                                                      calendar: calendar, home: "/Users/demo", printed: Self.printed))
        XCTAssert((1_000...2_000).contains(all.total), "\(all.total)")
        XCTAssert(shop.total > 0 && shop.total < all.total)
        XCTAssertEqual(all.projects, 4)
        XCTAssertEqual(Set(slice.titles.values), [
            "Refactor checkout flow", "Deploy preview build", "Fix coupon rounding", "Add Apple Pay to checkout",
            "Rate limits for the public API", "Move auth to sessions", "Fix the slow orders query",
            "Push notifications on Android", "Offline cart", "Rewrite the install guide", "API reference from OpenAPI",
        ])
        XCTAssert(slice.answers.allSatisfy { Self.month.contains($0.at) })
        XCTAssert(Set(slice.answers.map(\.agent)).isSuperset(of: ["main", "Explore", "Plan", "general-purpose"]))
    }
}
