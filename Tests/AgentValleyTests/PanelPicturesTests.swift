import AppKit
import SwiftUI
import XCTest
@testable import AgentValley

/// Draws the real panel in a window off the screen and saves what it looks like, and what a
/// screen reader is told of it. Not a test of anything: it passes whatever it draws, and is
/// skipped unless `testing/pictures.sh` runs it, which also makes the sessions it shows.
///
/// For looking at a change while the owner works on this Mac: it moves no pointer, presses no
/// key and puts nothing on the screen. It is not a click or a key on the panel itself, and what
/// was checked this way should be said to have been checked this way.
/// Hands the panel the same plan limits every time it asks.
private struct FixedLimits: PlanLimitsSource {
    let limits: PlanLimits

    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void {
        done(.success(limits))
        return {}
    }
}

@MainActor
final class PanelPicturesTests: XCTestCase {
    private var host: NSHostingView<PanelView>!
    private var out = ""
    private var scene = ""
    private var shots = 0

    /// Lets the panel draw, animate and scroll for a while: all of that happens on this thread.
    private func pump(_ seconds: TimeInterval = 1.2) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func name(_ what: String) -> String {
        shots += 1
        return "\(out)/\(scene)-\(shots)-\(what)"
    }

    private func picture(_ what: String, after wait: TimeInterval = 1.2) {
        pump(wait)
        host.layoutSubtreeIfNeeded()
        guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: image)
        try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name(what) + ".png"))
    }

    /// A click at a point of the panel, measured from its top left in points, sent to its window.
    private func click(atTopLeftOffset point: CGPoint) {
        guard let window = host.window else { return }
        let at = host.convert(NSPoint(x: point.x, y: host.isFlipped ? point.y : host.bounds.height - point.y), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
            pump(0.1)
        }
    }

    /// Scrolls the panel's list, or the page in its place, to its foot, as a wheel would.
    private func scrollToEnd() {
        func find(_ view: NSView) -> NSScrollView? {
            (view as? NSScrollView) ?? view.subviews.lazy.compactMap(find).first
        }
        guard let scroll = find(host), let document = scroll.documentView else { return }
        let end = NSPoint(x: 0, y: document.isFlipped ? max(0, document.frame.height - scroll.contentView.bounds.height) : 0)
        scroll.contentView.scroll(to: end)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// What a screen reader is told, asked from outside as one asks: SwiftUI only builds that
    /// tree for a client that comes through the system. The answers come from this thread, so
    /// it has to keep turning while the tool asks.
    private func spoken(_ what: String) {
        pump()
        guard let tool = ProcessInfo.processInfo.environment["PANEL_PICTURES_AXDUMP"] else { return }
        let path = name(what) + ".txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["\(getpid())"]
        process.standardOutput = FileHandle(forWritingAtPath: path)
        guard (try? process.run()) != nil else { return }
        while process.isRunning { pump(0.05) }
    }

    /// A ledger switched on over one answer of ten minutes ago, with what it has counted already out.
    private func countedLedger(in folder: String) throws -> UsageLedger {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = #"{"type":"assistant","timestamp":"\#(stamp.string(from: Date().addingTimeInterval(-600)))","cwd":"/Users/demo/shop-web","sessionId":"s1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":2000,"cache_creation_input_tokens":420000,"cache_read_input_tokens":3100000,"output_tokens":96400}}}"#
        let file = URL(fileURLWithPath: folder + "/projects/p/s1.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
        let ledger = UsageLedger(root: URL(fileURLWithPath: folder + "/projects"), database: URL(fileURLWithPath: folder + "/history.sqlite"))
        ledger.setEnabled(true)
        for _ in 0..<50 where ledger.summary == nil { pump(0.1) }
        return ledger
    }

    /// A ledger over a made-up month so far: four projects, one with a sub-agent, at steady hours.
    /// A project's name and a session's are too long for the panel, to see them cut.
    private func madeUpLedger(in folder: String) throws -> UsageLedger {
        let root = URL(fileURLWithPath: folder + "/projects")
        let now = Date()
        let start = HistoryReport.calendar().dateInterval(of: .month, for: now)!.start
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let projects = [("shop-web", "Checkout with refunds, webhooks, receipt emails and a retry queue for payments", "claude-opus-5-5"), ("api", "Rate limits for the public API", "claude-opus-5-5"),
                        ("agents-visualizer", "History in the notch", "claude-sonnet-5-5"), ("warehouse-inventory-sync-service-backend-and-admin-dashboard-v2", "Nightly stock import", "claude-haiku-5-5")]
        for (index, project) in projects.enumerated() {
            let session = "session-\(index)"
            var lines = [#"{"type":"ai-title","aiTitle":"\#(project.1)","sessionId":"\#(session)"}"#]
            var sub: [String] = []
            var at = start.addingTimeInterval(Double(9 + index) * 3600)
            var n = 0
            while at < now {
                let output = 20_000 + (n * 7919 + index * 104_729) % 90_000
                let answer = #"{"type":"assistant","timestamp":"\#(stamp.string(from: at))","cwd":"\#(NSHomeDirectory())/.superset/worktrees/\#(project.0)/ws","sessionId":"\#(session)","message":{"id":"m-\#(index)-\#(n)","model":"\#(project.2)","usage":{"input_tokens":12,"cache_read_input_tokens":80000,"output_tokens":\#(output)}}}"#
                if index == 0, n % 3 == 0 { sub.append(answer) } else { lines.append(answer) }
                at = at.addingTimeInterval(Double(5 + (n * 13 + index * 7) % 11) * 3600)
                n += 1
            }
            let file = root.appendingPathComponent("p\(index)/\(session).jsonl")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            if !sub.isEmpty {
                let agent = root.appendingPathComponent("p\(index)/\(session)/subagents/agent-a1.jsonl")
                try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
                try (sub.joined(separator: "\n") + "\n").write(to: agent, atomically: true, encoding: .utf8)
                try #"{"agentType":"Explore","description":"Find the payment code"}"#.write(
                    to: root.appendingPathComponent("p\(index)/\(session)/subagents/agent-a1.meta.json"), atomically: true, encoding: .utf8)
            }
        }
        let ledger = UsageLedger(root: root, database: URL(fileURLWithPath: folder + "/history.sqlite"))
        _ = ledger.scan(now: now)
        return ledger
    }

    /// The crew lines moving, frame by frame: a sub-agent of the checkout starts, then one
    /// finishes. The lines are written into demo.py's transcripts as Claude Code would write
    /// them, the store reads them as it reads any, and frames of the card are taken as the
    /// packet runs. Also `motion.ffconcat`: each frame for as long as it really lasted, with a
    /// hold on the first and last of each event, for pictures.sh to make a video of.
    private func motion(store: AgentStore, state: NotchState, home: String) throws {
        let fm = FileManager.default
        for file in (try? fm.contentsOfDirectory(atPath: out)) ?? [] where file.hasPrefix("motion") {
            try? fm.removeItem(atPath: "\(out)/\(file)")
        }
        // As roomy: the checkout's card whole, its crew lines in sight.
        for card in store.sessions where card.name != "Refactor checkout flow" {
            state.hidden[card.id] = Date()
        }
        state.expanded = true
        state.openedAt = Date()
        state.opens += 1
        pump(2)
        let checkout = try XCTUnwrap(store.sessions.first { $0.name == "Refactor checkout flow" })
        let session = (checkout.id as NSString).lastPathComponent
        let crew = checkout.id + "/subagents/"

        // The lines as demo.py shapes them.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func append(_ path: String, _ lines: [[String: Any]]) throws {
            let text = try lines.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) + "\n" }.joined()
            if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
            let handle = try XCTUnwrap(FileHandle(forWritingAtPath: path))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }
        let usage: [String: Any] = ["input_tokens": 1200, "cache_read_input_tokens": 42_000, "output_tokens": 380]
        func turn(_ content: Any, model: String, stop: String) -> [String: Any] {
            ["type": "assistant", "timestamp": iso.string(from: Date()), "cwd": "/Users/demo/shop-web", "gitBranch": "checkout-refactor", "sessionId": session,
             "message": ["role": "assistant", "model": model, "stop_reason": stop, "usage": usage, "content": content]]
        }

        // The card alone, and a little room under it for the row that comes.
        let crop = CGRect(x: 44, y: 96, width: 512, height: 320)
        let rect = host.isFlipped ? crop : CGRect(x: crop.minX, y: host.bounds.height - crop.maxY, width: crop.width, height: crop.height)
        func grab() -> NSBitmapImageRep? {
            host.layoutSubtreeIfNeeded()
            guard let image = host.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
            host.cacheDisplay(in: rect, to: image)
            return image
        }
        var concat = ["ffconcat version 1.0"]
        var gaps: [TimeInterval] = []

        /// One frame before the lines are written, then frames every ~65ms for 1.8s from the
        /// moment the store has read them.
        func film(_ event: String, write: () throws -> Void, until seen: () -> Bool) throws {
            var frames: [(NSBitmapImageRep, Date)] = []
            if let before = grab() { frames.append((before, Date())) }
            let written = Date()
            try write()
            let deadline = Date().addingTimeInterval(25)
            while !seen(), Date() < deadline { pump(0.01) }
            XCTAssertTrue(seen(), "The store never read the \(event).")
            print("motion \(event): the store read it \(String(format: "%.2f", Date().timeIntervalSince(written)))s after it was written")
            let start = Date()
            for i in 0..<28 {
                RunLoop.main.run(until: start.addingTimeInterval(Double(i) * 0.065))
                if let image = grab() { frames.append((image, Date())) }
            }
            for (i, (image, at)) in frames.enumerated() {
                let file = String(format: "motion-%@-%03d.png", event, i)
                try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(file)"))
                let next = i + 1 < frames.count ? frames[i + 1].1.timeIntervalSince(at) : 0.6
                if i > 0, i + 1 < frames.count { gaps.append(next) }
                concat += ["file '\(file)'", "duration \(i == 0 ? 0.6 : next)"]
                // The last one again: the concat reader drops the last file's duration.
                if i + 1 == frames.count, event == "finish" { concat.append("file '\(file)'") }
            }
        }

        // A sub-agent starts: its meta first, as Claude Code writes it, then its prompt and a call
        // still open.
        let review = crew + "agent-review.jsonl"
        try film("start", write: {
            try #"{"agentType":"general-purpose","description":"Review the refund path"}"#.write(
                toFile: crew + "agent-review.meta.json", atomically: true, encoding: .utf8)
            try append(review, [
                ["type": "user", "timestamp": iso.string(from: Date()), "cwd": "/Users/demo/shop-web", "gitBranch": "checkout-refactor", "entrypoint": "cli",
                 "sessionId": session, "message": ["role": "user", "content": "Review the refund path"]],
                turn([["type": "tool_use", "id": "rv0", "name": "Read", "input": ["file_path": "/Users/demo/shop-web/src/checkout/refund.ts"]]],
                     model: "claude-sonnet-5-5", stop: "tool_use"),
            ])
        }, until: { store.sessions.contains { $0.agents.contains { $0.id.hasSuffix("/agent-review.jsonl") } } })

        // One finishes: "Run the cart tests", which demo.py leaves alone. Its command gets its
        // result and it closes its turn with an answer; ten seconds of quiet later it is done.
        try film("finish", write: {
            try append(crew + "agent-verify.jsonl", [
                ["type": "user", "timestamp": iso.string(from: Date()),
                 "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "v0", "content": "All 48 cart tests pass."]]]],
                turn([["type": "text", "text": "All 48 cart tests pass, coverage 91%."]], model: "claude-sonnet-5-5", stop: "end_turn"),
            ])
        }, until: { store.sessions.contains { $0.agents.contains { $0.id.hasSuffix("/agent-verify.jsonl") && $0.status == .done } } })

        try (concat.joined(separator: "\n") + "\n").write(toFile: "\(out)/motion.ffconcat", atomically: true, encoding: .utf8)
        let mean = gaps.reduce(0, +) / Double(max(1, gaps.count))
        print("motion frames every \(String(format: "%.1f", mean * 1000))ms on average, \(String(format: "%.1f", (gaps.min() ?? 0) * 1000))-\(String(format: "%.1f", (gaps.max() ?? 0) * 1000))ms")
    }

    func testDrawThePanelOffTheScreen() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let home = environment["PANEL_PICTURES_HOME"], let out = environment["PANEL_PICTURES_OUT"] else {
            throw XCTSkip("Run by testing/pictures.sh, which makes the sessions to draw.")
        }
        self.out = out
        scene = environment["PANEL_PICTURES_SCENE"] ?? "list"
        // An app as far as the system is concerned: without that it serves no accessibility tree.
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()

        let root = URL(fileURLWithPath: home + "/.claude/projects")
        let store = AgentStore(root: root)
        let settings = Settings(defaults: throwawayDefaults())
        let answers = AnswerStore(directory: URL(fileURLWithPath: home + "/answers"))
        let state = NotchState()
        // A 14-inch MacBook's screen and notch: the panel sizes itself by them.
        state.screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        state.barHeight = 38
        state.notchWidth = 200
        store.start()
        pump(1.5)
        // The token line shows once something is counted, and demo.py's answers carry no ids: for
        // its scene, a ledger over a made-up answer of its own.
        let usage = scene == "tokens" ? try countedLedger(in: home + "/tokens")
            : scene.hasPrefix("history") ? try madeUpLedger(in: home + "/history")
            : UsageLedger(root: root, database: URL(fileURLWithPath: home + "/history.sqlite"))
        // For the update scene, a release's: its About page has the Updates box. Never started.
        let updates = scene == "update" || scene == "heard" ? Updates(info: ["SUFeedURL": "https://example.invalid/appcast.xml", "SUPublicEDKey": "k"], starts: false)
            : Updates(info: [:])
        // For the fishing scenes, a plan limit that has run out: the 5-hour one, or the weekly one.
        // Their signs' pictures from the repo: here there is no app bundle to find them in.
        let limits: PlanLimitsClient
        if scene.hasPrefix("fishing") {
            SignArt.folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("signs")
            // On the hour, as the plan's windows reset.
            let hour = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / 3600).rounded(.up) * 3600)
            let soon = hour.addingTimeInterval(2 * 3600), later = hour.addingTimeInterval(3 * 86400)
            limits = PlanLimitsClient(source: FixedLimits(limits: scene == "fishing-week"
                ? PlanLimits(fiveHour: PlanLimit(usedPercent: 12, resetsAt: soon), week: PlanLimit(usedPercent: 100, resetsAt: later))
                : PlanLimits(fiveHour: PlanLimit(usedPercent: 100, resetsAt: soon), week: PlanLimit(usedPercent: 64, resetsAt: later))))
            limits.setEnabled(true)
        } else {
            limits = PlanLimitsClient()
        }
        let desk = StopDesk()
        // Its Away flag goes in a folder of its own, never beside the running app's socket.
        let awayFolder = FileManager.default.temporaryDirectory.appendingPathComponent("pictures-away-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: awayFolder) }
        let away = AwayWatch(desk: desk, folder: awayFolder, lastInput: { .distantPast })
        host = NSHostingView(rootView: PanelView(store: store, state: state, settings: settings, limits: limits, answers: answers,
                                                 sound: SoundPlayer(settings: settings), usage: usage, updates: updates,
                                                 away: away, desk: desk))
        // Far to the left of any display. In the window list, so that it draws and animates.
        let window = NSWindow(contentRect: CGRect(x: -4000, y: 0, width: 600, height: 960), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .darkGray
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        func shown() -> [SessionCard] {
            AgentStore.ordered(AgentStore.showing(answers.overlay(store.sessions), hidden: state.hidden), by: settings.grouping)
        }
        func list() -> SessionList {
            AgentStore.arrange(shown(), idle: settings.idleSessions, keeping: answers.settledSessions.union(HandBack.holding(shown(), openedAt: state.openedAt)))
        }
        func walked() -> [String] { list().walked(idleExpanded: state.idleExpanded).map(\.id) }
        func open() {
            state.expanded = true
            state.openedAt = Date()
            state.opens += 1
        }

        /// What the plugin's hook would send for one of the made-up sessions, handed straight to the store.
        @discardableResult
        func ask(_ title: String, tool: String, input: [String: Any]) throws -> SessionCard {
            let card = try XCTUnwrap(store.sessions.first { $0.name == title })
            let hook: [String: Any] = ["tool_name": tool, "tool_input": input, "transcript_path": card.id + ".jsonl"]
            answers.add(try XCTUnwrap(Ask(hookInput: JSONSerialization.data(withJSONObject: hook)))) { _ in true }
            answers.reconcile(with: store.sessions)
            return card
        }
        /// The list's height as ListFit works it out, held against the height the panel measures.
        /// PanelView.foldedRows and the lines it is given are private: its room, the headings,
        /// the lines under the list and the rule for what stays full are repeated here, and
        /// change with it.
        func checkHeight() {
            let list = list()
            let keeping = answers.settledSessions.union(HandBack.holding(shown(), openedAt: state.openedAt))
            let putAway = AgentStore.putAway(answers.overlay(store.sessions), hidden: state.hidden)
            let compact = Format.oneLineRows(liveAgents: list.cards.reduce(0) { $0 + $1.liveAgents().count })
            let headers: Set<String> = list.cards.count + list.folded.count < 2 ? [] : settings.grouping == .projects
                ? Set(AgentStore.projectHeaders(of: list.cards).keys) : Set(AgentStore.headers(of: list.cards, by: settings.grouping).keys)
            let under = ListFit.under(idle: !list.folded.isEmpty, hidden: putAway.count, plain: [
                settings.tokenUse && usage.summary.map { !$0.isEmpty } ?? false, answers.pluginLost, updates.oldCopyLeft, updates.waiting != nil,
                state.keyboard,
            ].filter { $0 }.count)
            let room = NotchGeometry.listRoom(screen: state.screenFrame, barHeight: state.barHeight)
            let fitted = list.cards.map { card in
                let session = AnswerStore.sessionID(of: card)
                let open = state.doneShown[card.id] ?? false
                return ListFit.Entry(
                    id: card.id,
                    full: ListFit.fullHeight(card, header: headers.contains(card.id),
                                             requests: { answers.requests(forRow: $0, in: card).map { ListFit.requestHeight($0.ask.kind, hidden: $0.hidden) } },
                                             settled: { answers.settled(forRow: $0, in: card).count }, hintRow: list.hintRow,
                                             showingDone: open, oneLineAgents: compact,
                                             asked: state.askedOpen, boxes: HandBack.boxes(card, open: open), reading: state.readingAll),
                    row: ListFit.rowHeight(header: headers.contains(card.id)),
                    keepsFull: card.group == .needsYou || answers.pending.contains { $0.ask.session == session } || keeping.contains(session)
                        || open || card.liveAgents().contains { state.askedOpen.contains($0.id) },
                    quiet: card.group == .quiet || card.group == .idle,
                    header: headers.contains(card.id),
                    crew: !card.liveAgents().isEmpty)
            }
            let folded = ListFit.compact(fitted, room: room - ListFit.padding - under)
            let estimate = ListFit.padding + ListFit.height(fitted, folded: folded) + under
            print("estimate \(estimate) measured \(state.contentHeight) room \(room)")
            XCTAssertEqual(estimate, state.contentHeight, accuracy: 12)
        }

        switch scene {
        case "list":
            open()
            picture("open")
            checkHeight()
        case "roomy":
            // The checkout alone: room for its full card, so its crew lines are in sight. The
            // README's card has jobs now and stays listed, so it goes with the rest.
            for card in store.sessions where card.name != "Refactor checkout flow" {
                state.hidden[card.id] = Date()
            }
            open()
            picture("open")
            checkHeight()
            // Its book opened by a click: its finished sub-agents in it, a line from it to each.
            // Then shut again, which folds them all.
            if let checkout = store.sessions.first(where: { $0.name == "Refactor checkout flow" }) {
                state.doneShown[checkout.id] = true
                picture("done-open")
                state.doneShown[checkout.id] = false
                picture("done-folded")
            }
        case "handback":
            // The checkout alone, as roomy. Plan's finished answer comes back to a shut book, "1 new"
            // beside it; the book opened, Plan's document in it; the Asked box of a sub-agent at work;
            // Plan's document read whole; and the panel shut and opened again after a look: the book
            // as the person left it, Plan no longer new. Then the same on the STATUS page.
            for card in store.sessions where card.name != "Refactor checkout flow" {
                state.hidden[card.id] = Date()
            }
            func rowID(_ task: String) throws -> String {
                let checkout = try XCTUnwrap(store.sessions.first { $0.name == "Refactor checkout flow" })
                return try XCTUnwrap(checkout.agents.first { $0.info.task == task }).id
            }
            let plan = try rowID("Plan the tax rounding fix"), map = try rowID("Map payment call sites")
            // demo.py's Plan answered before the app launched, so nobody could have missed it. Each
            // page gets a fresh answer, as one that came in while the store watched.
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            func answers() throws {
                // Markdown, as a sub-agent writes it: the document draws it with its marks faint.
                let answer = "**Round once at the total**, not per line.\n\n## Why\n- Per-line rounding adds up to a cent or two on a cart of twelve cheap items.\n- The payment provider rounds the grand total once, so that is the number to match.\n\n## Files\n- `src/cart/tax.ts` and `src/cart/tax.test.ts`\n- `src/receipt/format.ts` needs no change, see [the receipt notes](https://example.com/receipt)."
                let line: [String: Any] = ["type": "assistant", "timestamp": iso.string(from: Date()),
                    "message": ["role": "assistant", "model": "claude-sonnet-5-5", "stop_reason": "end_turn",
                                "usage": ["input_tokens": 900, "cache_read_input_tokens": 30_000, "output_tokens": 210],
                                "content": [["type": "text", "text": answer]]]]
                let handle = try XCTUnwrap(FileHandle(forWritingAtPath: plan))
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((String(decoding: try JSONSerialization.data(withJSONObject: line), as: UTF8.self) + "\n").utf8))
                // A turn counts as ended after ten quiet seconds.
                pump(12)
            }
            for grouping in [Grouping.projects, .status] {
                settings.grouping = grouping
                let page = grouping == .projects ? "all" : "status"
                state.askedOpen = []
                state.readingAll = []
                let checkout = try XCTUnwrap(store.sessions.first { $0.name == "Refactor checkout flow" }).id
                state.doneShown[checkout] = nil
                // Shut while it comes in: an open panel would see it at once and call it seen.
                state.expanded = false
                try answers()
                open()
                picture("\(page)-open")
                checkHeight()
                state.doneShown[checkout] = true
                picture("\(page)-book")
                checkHeight()
                state.askedOpen = [map]
                picture("\(page)-asked")
                checkHeight()
                state.askedOpen = []
                state.readingAll = [plan]
                picture("\(page)-read-all")
                checkHeight()
                // Seen while open (the time is after the opening), then shut and opened again.
                store.saw([plan], at: Date())
                pump()
                state.readingAll = []
                state.expanded = false
                pump(0.3)
                open()
                picture("\(page)-reopened")
                checkHeight()
            }
            // Run the cart tests sends its coverage run to the background and ends its turn to wait,
            // and Claude Code tells the lead so: still among the working, by the job it waits on, and no box.
            let verify = try rowID("Run the cart tests")
            let lead = try XCTUnwrap(store.sessions.first { $0.name == "Refactor checkout flow" }?.main?.id)
            let lines: [[String: Any]] = [
                ["type": "user", "timestamp": iso.string(from: Date()), "toolUseResult": ["backgroundTaskId": "bcart1"],
                 "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "v0", "content": "Command running in background with ID: bcart1."]]]],
                ["type": "assistant", "timestamp": iso.string(from: Date()),
                 "message": ["role": "assistant", "model": "claude-sonnet-5-5", "stop_reason": "end_turn",
                             "usage": ["input_tokens": 900, "cache_read_input_tokens": 30_000, "output_tokens": 40],
                             "content": [["type": "text", "text": "The coverage run is going in the background. I'll report once it ends."]]]],
            ]
            let notice = "<task-notification>\n<task-id>verify</task-id>\n<status>completed</status>\n"
                + "<summary>Agent \"Run the cart tests\" is waiting on its own background work</summary>\n</task-notification>"
            let told: [String: Any] = ["type": "queue-operation", "operation": "enqueue", "timestamp": iso.string(from: Date().addingTimeInterval(0.2)), "content": notice]
            for (path, written) in [(verify, lines), (lead, [told])] {
                let handle = try XCTUnwrap(FileHandle(forWritingAtPath: path))
                try handle.seekToEnd()
                for line in written {
                    try handle.write(contentsOf: Data((String(decoding: try JSONSerialization.data(withJSONObject: line), as: UTF8.self) + "\n").utf8))
                }
                try handle.close()
            }
            settings.grouping = .projects
            state.expanded = false
            pump(12)
            open()
            picture("all-waiting-on-job")
            checkHeight()
        case "crew":
            // A sub-agent of the checkout asks to run a command: its branch red, the card whole,
            // the sessions around it folded to fit.
            open()
            try ask("Refactor checkout flow", tool: "Bash", input: ["command": "npm run test:cart -- --coverage", "description": "Check cart coverage"])
            picture("waiting")
            checkHeight()
        case "status":
            settings.grouping = .status
            open()
            picture("grouped")
        case "keys":
            // The ring on each session in turn, down the list and back, in both orders.
            for grouping in [Grouping.projects, .status] {
                settings.grouping = grouping
                open()
                state.keyboard = true
                state.selected = KeyCommand.start(in: list().cards)
                picture("\(grouping.rawValue)-start")
                // The line about the keys, over the list, takes room from it too.
                if grouping == .projects { checkHeight() }
                for step in 1...walked().count {
                    state.selected = KeyCommand.move(state.selected, by: 1, in: walked())
                    picture("\(grouping.rawValue)-down\(step)")
                }
                state.selected = KeyCommand.move(state.selected, by: -1, in: walked())
                picture("\(grouping.rawValue)-up")
            }
        case "idle":
            open()
            state.keyboard = true
            state.idleExpanded = true
            pump()
            state.selected = walked().last
            picture("ring-on-idle")
        case "intro":
            state.introducing = true
            open()
            picture("first-launch")
        case "legend":
            open()
            state.showingLegend = true
            for tab in LegendTab.allCases {
                state.legendTab = tab
                picture(tab.rawValue)
            }
        case "settings":
            open()
            // Two displays, the bigger one picked, as in issue #1.
            state.displays = [DisplayChoice(id: "built-in", name: "Built-in Retina Display"), DisplayChoice(id: "dell", name: "DELL U2720Q")]
            settings.display = "dell"
            state.showingSettings = true
            for tab in SettingsTab.allCases {
                state.settingsTab = tab
                picture(tab.rawValue)
            }
            // General at its foot: the Display list.
            state.settingsTab = .general
            pump()
            scrollToEnd()
            picture("general-scrolled")
            // The page the plugin's command is on, with its switch on.
            settings.answers = true
            state.settingsTab = .claudeCode
            picture("claude-code-answering")
            // Scrolled to its foot: the way back and the pages stay at the top.
            scrollToEnd()
            picture("claude-code-scrolled")
            // And a click on a page there still lands on it. A click sent to the window: the
            // pointer does not move.
            click(atTopLeftOffset: CGPoint(x: 518, y: 91))
            picture("about-after-click")
        case "request":
            // What the plugin's hook would send for two of the made-up sessions: a command to
            // allow, then a question with options.
            open()
            let deploy = try ask("Deploy preview build", tool: "Bash", input: ["command": "git push origin preview", "description": "Push the preview branch"])
            picture("command")
            state.keyboard = true
            state.selected = deploy.id
            picture("command-with-keys")
            // A key pressed the moment the list has moved: what the buttons' line says of it.
            answers.noteLayoutChange()
            state.press(.allow, at: Date())
            picture("key-too-soon", after: 0.5)
            pump(2)
            state.press(.allow, at: Date())
            picture("allowed")
            state.keyboard = false
            state.selected = nil
            _ = try ask("Fix flaky login test", tool: "AskUserQuestion", input: ["questions": [[
                "question": "The login test fails only on CI. Which fix do you want?", "header": "Fix", "multiSelect": false,
                "options": [["label": "Retry the request", "description": "Up to three times"], ["label": "Mock the clock", "description": "No real waiting in the test"],
                            ["label": "Skip on CI", "description": "Keep it for local runs"]],
            ]]])
            picture("question")
            checkHeight()
        case "oldcopy":
            // 0.1 from Homebrew left behind: the line in the list, then the page its Fix it opens.
            updates.lookForOldCopy([home])
            // The sessions put away, so that the line at the foot of the list is in sight.
            for card in store.sessions { state.hidden[card.id] = Date() }
            open()
            picture("line")
            state.showingSettings = true
            state.settingsTab = .about
            picture("settings")
        case "update":
            // A version that came in on its own: the dot on the gear, the About tab and its line.
            updates.waiting = "0.3.4"
            open()
            picture("gear")
            spoken("gear")
            state.showingSettings = true
            state.settingsTab = .general
            picture("tabs")
            state.settingsTab = .about
            picture("about")
            spoken("about")
            // Looked at: every dot goes.
            updates.waiting = nil
            picture("about-looked")
        case "heard":
            // A release that counts asks once where the person heard about us. Answered, it goes.
            open()
            picture("ask")
            spoken("ask")
            settings.heardFrom = "Facebook"
            picture("answered")
            spoken("answered")
        case "tokens":
            // The sessions put away, so that the line at the foot of the list is in sight.
            for card in store.sessions { state.hidden[card.id] = Date() }
            open()
            picture("line")
            spoken("line")
        case "history", "history-project":
            state.showingHistory = true
            state.historyPick = HistoryPick(project: scene == "history-project" ? "shop-web" : nil)
            open()
            picture("page")
            spoken("page")
        case "away":
            // One phone message that did not go, through the desk's own path, then Away on.
            _ = desk.deliver(id: UUID(), session: "demo", text: "Run the tests again and tell me what failed. Use `swift test`, not **npm**.")
            desk.release()
            away.phoneLinked = true
            away.buttonShown = true
            away.turnOn(.phoneButton)
            open()
            picture("open")
            spoken("open")
        case "fishing", "fishing-week":
            // Everyone done for now, so that the bar has the fish and the sign hangs over an empty list.
            for card in store.sessions { state.hidden[card.id] = Date() }
            picture("shut")
            open()
            // demo.py may have started more sessions meanwhile: those go too.
            for card in store.sessions { state.hidden[card.id] = Date() }
            picture("open")
            spoken("open")
            // Then over the sessions, back in the list.
            state.hidden = [:]
            picture("over-list")
        case "reader":
            open()
            spoken("list-open")
            state.keyboard = true
            state.selected = walked().dropFirst(2).first
            spoken("ring-on-third")
            state.keyboard = false
            state.selected = nil
            state.showingSettings = true
            spoken("settings-open")
            state.expanded = false
            state.openedAt = nil
            spoken("shut-from-settings")
            state.showingSettings = false
            spoken("shut")
        case "motion":
            try motion(store: store, state: state, home: home)
        default:
            XCTFail("No scene called \(scene). See testing/pictures.sh.")
        }
    }
}
