import AppKit
import SwiftUI
import XCTest
@testable import AgentValley

/// The made-up sessions the site's needs-you motion is drawn from, and the four pictures of the
/// panel drawn from them. The drawing is skipped unless `testing/site.sh needs-you` runs it.
@MainActor
final class NeedsYouMotionAssetsTests: XCTestCase {
    /// Three sessions at work, as on the site: each one's project, title, model and the step it is on.
    private static let sessions: [(project: String, title: String, model: String, tool: String, input: [String: Any])] = [
        ("shop-web", "Refactor checkout flow", "claude-opus-5-5", "Edit", ["file_path": "/Users/demo/shop-web/src/checkout/payment.ts"]),
        ("shop-web", "Deploy preview build", "claude-sonnet-5-5", "Bash", ["command": "npm run build", "description": "Build the storefront"]),
        ("api", "Rate limits for the public API", "claude-opus-5-5", "Grep", ["pattern": "rateLimit\\("]),
    ]
    /// What "Deploy preview build" asks to run, and what it does once allowed.
    private static let push: [String: Any] = ["command": "git push origin preview", "description": "Push the preview branch"]
    private static let after: [String: Any] = ["command": "npm run smoke -- --url preview", "description": "Check the preview build"]

    private static func id(_ index: Int) -> String { "00000000-0000-4000-8000-00000000000\(index + 1)" }

    private static func line(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    private static func call(_ index: Int, _ tool: String, _ input: [String: Any], id callID: String, at: Date) throws -> String {
        let session = sessions[index]
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Typed a part at a time: one literal of it all was too much for CI's compiler.
        let usage: [String: Any] = ["input_tokens": 1200, "cache_read_input_tokens": 42_000, "output_tokens": 380]
        let use: [String: Any] = ["type": "tool_use", "id": callID, "name": tool, "input": input]
        let message: [String: Any] = ["role": "assistant", "model": session.model, "stop_reason": "tool_use", "usage": usage, "content": [use]]
        let object: [String: Any] = ["type": "assistant", "timestamp": stamp.string(from: at), "cwd": "/Users/demo/\(session.project)",
                                     "sessionId": id(index), "message": message]
        return try line(object)
    }

    private static func result(_ callID: String, at: Date) throws -> String {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try line(["type": "user", "timestamp": stamp.string(from: at),
                         "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": callID, "content": "ok"]]]])
    }

    private static func transcript(_ root: URL, _ index: Int) -> URL {
        root.appendingPathComponent("-Users-demo-\(sessions[index].project)/\(id(index)).jsonl")
    }

    /// The three transcripts under `root`, each a few seconds old at `now`, so all three are at work.
    /// "Deploy preview build" has just written the push it is about to ask for.
    static func madeUpProjects(in root: URL, now: Date) throws {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (index, session) in sessions.enumerated() {
            let file = transcript(root, index)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let title: [String: Any] = ["type": "ai-title", "aiTitle": session.title, "sessionId": id(index)]
            let said: [String: Any] = ["role": "user", "content": session.title + "."]
            let prompt: [String: Any] = ["type": "user", "timestamp": stamp.string(from: now.addingTimeInterval(-90)),
                                         "cwd": "/Users/demo/\(session.project)", "sessionId": id(index), "message": said]
            let ago: TimeInterval = -Double(20 + index * 7)
            var lines: [String] = [try line(title), try line(prompt), try call(index, session.tool, session.input, id: "c\(index)", at: now.addingTimeInterval(ago))]
            if session.title == "Deploy preview build" {
                lines.append(try result("c\(index)", at: now.addingTimeInterval(-8)))
                lines.append(try call(index, "Bash", push, id: "push", at: now.addingTimeInterval(-4)))
            }
            let text: String = lines.joined(separator: "\n") + "\n"
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// What the plugin's hook sends when "Deploy preview build" asks to push, handed to `answers`.
    static func askToPush(_ answers: AnswerStore, root: URL, store: AgentStore) throws {
        let hook: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": id(1), "transcript_path": transcript(root, 1).path,
                                   "cwd": "/Users/demo/shop-web", "tool_name": "Bash", "tool_input": push]
        _ = answers.add(try XCTUnwrap(Ask(hookInput: JSONSerialization.data(withJSONObject: hook)))) { _ in true }
        answers.reconcile(with: store.sessions)
    }

    /// What Claude Code writes once the push is allowed: its result, and the next step.
    static func pushed(root: URL, now: Date) throws {
        let handle = try FileHandle(forWritingTo: transcript(root, 1))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((try result("push", at: now) + "\n" + call(1, "Bash", after, id: "smoke", at: now) + "\n").utf8))
    }

    /// Under the home folder: the store compares paths as written, and the temporary folder's /var is a link.
    private static func scratch() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("agent-valley-needs-you-" + UUID().uuidString)
    }

    private func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func started(_ root: URL, sessions: URL) -> AgentStore {
        let store = AgentStore(root: root, sessions: sessions)
        store.start()
        for _ in 0..<40 where store.sessions.count < Self.sessions.count { pump(0.1) }
        return store
    }

    /// Writes into NEEDS_YOU_MOTION_OUT the panel drawn off the screen at four moments: shut while
    /// the three work, shut with the red 1, open on the request, and open once the push is allowed.
    func testWriteNeedsYouMotionPictures() throws {
        guard let out = ProcessInfo.processInfo.environment["NEEDS_YOU_MOTION_OUT"] else { throw XCTSkip("Run by testing/site.sh needs-you.") }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let folder = Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("projects")
        try Self.madeUpProjects(in: root, now: Date())
        // No records folder: the store goes by the transcripts alone. An empty one would call the
        // made-up sessions closed, and closed in folders that are not there, they have no card.
        let store = started(root, sessions: folder.appendingPathComponent("none"))
        let settings = Settings(defaults: try XCTUnwrap(UserDefaults(suiteName: "needs-you-motion-\(UUID().uuidString)")))
        let answers = AnswerStore(directory: folder.appendingPathComponent("answers"))
        let state = NotchState()
        // A 14-inch MacBook's screen and notch, as PanelPicturesTests draws it.
        state.screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        state.barHeight = 38
        state.notchWidth = 200
        let host = NSHostingView(rootView: PanelView(store: store, state: state, settings: settings, limits: PlanLimitsClient(), answers: answers,
                                                     sound: SoundPlayer(settings: settings),
                                                     usage: UsageLedger(root: root, database: folder.appendingPathComponent("history.sqlite")), updates: Updates(info: [:])))
        let window = NSWindow(contentRect: CGRect(x: -4000, y: 0, width: 600, height: 960), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        func picture(_ name: String) throws {
            pump(1.5)
            host.layoutSubtreeIfNeeded()
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }

        try picture("shut-working")
        try Self.askToPush(answers, root: root, store: store)
        try picture("shut-asking")
        state.expanded = true
        state.openedAt = Date()
        state.opens += 1
        try picture("open-asking")
        // Allowed by its key, as PanelPicturesTests' request scene does; the motion draws the pointer.
        state.keyboard = true
        state.selected = try XCTUnwrap(store.sessions.first { $0.name == "Deploy preview build" }).id
        pump(2)
        state.press(.allow, at: Date())
        pump(0.5)
        state.keyboard = false
        state.selected = nil
        try Self.pushed(root: root, now: Date())
        try picture("open-allowed")
    }

    func testMadeUpSessionsWorkUntilOneAsks() throws {
        let folder = Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("projects")
        try Self.madeUpProjects(in: root, now: Date())
        // No records folder: the store goes by the transcripts alone. An empty one would call the
        // made-up sessions closed, and closed in folders that are not there, they have no card.
        let store = started(root, sessions: folder.appendingPathComponent("none"))
        XCTAssertEqual(Set(store.sessions.map(\.name)), ["Refactor checkout flow", "Deploy preview build", "Rate limits for the public API"])
        XCTAssertEqual(AgentStore.count(.working, in: store.sessions), 3)

        let answers = AnswerStore(directory: folder.appendingPathComponent("answers"))
        try Self.askToPush(answers, root: root, store: store)
        let shown = answers.overlay(store.sessions)
        XCTAssertEqual(AgentStore.count(.needsYou, in: shown), 1)
        let deploy = shown.first { $0.name == "Deploy preview build" }
        XCTAssertEqual(deploy?.rows.first?.status, .needsYou)
    }
}
