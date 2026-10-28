import CoreServices
import XCTest
@testable import AgentValley

final class AgentStoreTests: XCTestCase {
    private var store: AgentStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let superset = OwnerApp(bundle: URL(fileURLWithPath: "/Applications/Superset.app"), name: "Superset")
    private let toolUse = #"{"type":"assistant","timestamp":"2026-10-12T02:00:05.000Z","cwd":"/Users/me/web-app","gitBranch":"main","message":{"model":"claude-haiku-5-5","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/login.ts"}}]}}"#

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-valley-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = AgentStore(root: root)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(atPath: store.root)
    }

    @discardableResult
    private func write(_ text: String, to relative: String, append: Bool = false) throws -> String {
        let path = store.root + "/" + relative
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if append, let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        } else {
            try Data(text.utf8).write(to: URL(fileURLWithPath: path))
        }
        return path
    }

    /// A transcript last written `idle` seconds ago. `spoken`: it has carried a conversation
    /// line, then. One that has not is a stub, or not a transcript at all.
    private func tracked(_ session: String, main: Bool = false, idle: TimeInterval, started: TimeInterval = 0, spoken: Bool = true) -> TrackedFile {
        var file = TrackedFile(session: session, isMain: main)
        file.modified = now.addingTimeInterval(-idle)
        if spoken { file.info.lastActivity = file.modified }
        file.info.startedAt = now.addingTimeInterval(-started)
        file.info.cwd = "/Users/me/" + (session as NSString).lastPathComponent
        return file
    }

    private func card(_ id: String, main: AgentStatus?, agents: [AgentStatus] = [], repo: String = "", folder: String? = nil,
                      git: GitPlace? = nil) -> SessionCard {
        func row(_ name: String, _ status: AgentStatus) -> AgentRow {
            AgentRow(id: id + name, info: AgentInfo(), status: status, elapsed: 0)
        }
        var card = SessionCard(
            id: id, project: folder ?? id, branch: "",
            main: main.map { row("/main", $0) },
            agents: agents.enumerated().map { row("/agent\($0.offset)", $0.element) },
            startedAt: now
        )
        card.repo = repo
        card.git = git
        return card
    }

    // A worktree's `.git` is a file that points into the repository's `worktrees`. The
    // repository's own checkout has a folder there, and a submodule a file that points elsewhere.
    func testAWorktreeIsToldFromTheCheckoutAndFromASubmodule() throws {
        try FileManager.default.createDirectory(atPath: store.root + "/repo/.git/worktrees/side", withIntermediateDirectories: true)
        try write("gitdir: \(store.root)/repo/.git/worktrees/side\n", to: "side/.git")
        try write("", to: "side/packages/api/x.ts")
        try write("gitdir: ../.git/modules/vendor\n", to: "repo/vendor/.git")
        XCTAssertTrue(AgentStore.isWorktree(store.root + "/side"))
        // The session may have gone into a folder of the worktree.
        XCTAssertTrue(AgentStore.isWorktree(store.root + "/side/packages/api"))
        XCTAssertFalse(AgentStore.isWorktree(store.root + "/repo"))
        XCTAssertFalse(AgentStore.isWorktree(store.root + "/repo/vendor"))
        XCTAssertFalse(AgentStore.isWorktree(""))
    }

    // A session goes under the folder of the repository it works in. A worktree's `.git` names
    // the checkout it came from, wherever the worktree lives and whatever its parent folder is
    // called, and a folder inside a checkout goes with that checkout.
    func testAFolderKnowsItsWorktreeAndItsCheckout() throws {
        try FileManager.default.createDirectory(atPath: store.root + "/agent-valley/.git/worktrees/ws", withIntermediateDirectories: true)
        try write("", to: "agent-valley/site/x.ts")
        try write("gitdir: \(store.root)/agent-valley/.git/worktrees/ws\n", to: "AgentValley/ws/.git")
        try write("gitdir: ../../agent-valley/.git/worktrees/near\n", to: "AgentValley/near/.git")
        try write("gitdir: ../.git/modules/vendor\n", to: "agent-valley/vendor/.git")
        try write("", to: "loose/x.ts")
        let root = store.root
        XCTAssertEqual(AgentStore.gitPlace(of: root + "/AgentValley/ws"), GitPlace(worktree: root + "/AgentValley/ws", checkout: root + "/agent-valley"))
        XCTAssertEqual(AgentStore.gitPlace(of: root + "/AgentValley/near"), GitPlace(worktree: root + "/AgentValley/near", checkout: root + "/agent-valley"))
        // A folder inside the checkout is in the checkout's own worktree.
        XCTAssertEqual(AgentStore.gitPlace(of: root + "/agent-valley/site"), GitPlace(worktree: root + "/agent-valley", checkout: root + "/agent-valley"))
        // A submodule is a checkout of its own.
        XCTAssertEqual(AgentStore.gitPlace(of: root + "/agent-valley/vendor"), GitPlace(worktree: root + "/agent-valley/vendor", checkout: root + "/agent-valley/vendor"))
        XCTAssertNil(AgentStore.gitPlace(of: root + "/loose"))
        XCTAssertNil(AgentStore.gitPlace(of: ""))
    }

    // Superset keeps its worktrees under the name the project has in Superset, which need not
    // be the repository's folder: the card goes by the folder the worktree came from.
    func testACardInAWorktreeGoesUnderItsRepositorysFolder() {
        var file = tracked("/r/p/s1", main: true, idle: 5)
        file.info.cwd = "/Users/me/.superset/worktrees/AgentValley/ws"
        let place = GitPlace(worktree: "/Users/me/.superset/worktrees/AgentValley/ws", checkout: "/Users/me/projects/agent-valley")
        let cards = AgentStore.cards(from: ["/r/p/s1.jsonl": file], now: now, home: "/Users/me",
                                     git: { $0 == place.worktree ? place : nil })
        XCTAssertEqual(cards.map(\.repo), ["agent-valley"])
        XCTAssertEqual(cards.map(\.git), [place])
    }

    // A home folder kept in git, for the settings in it, is no project: a folder in it that is
    // no checkout of its own is named by its path.
    func testAHomeFolderInGitIsNoProject() {
        var file = tracked("/r/p/s1", main: true, idle: 5)
        file.info.cwd = "/Users/me/notes"
        let cards = AgentStore.cards(from: ["/r/p/s1.jsonl": file], now: now, home: "/Users/me",
                                     git: { _ in GitPlace(worktree: "/Users/me", checkout: "/Users/me") })
        XCTAssertEqual(cards.map(\.repo), ["notes"])
        XCTAssertEqual(cards.map(\.git), [nil])
    }

    // The folder is a checkout nobody vouches for. Its `.git` is read only when it is a plain
    // file, and only from the start: a link could lead to a pipe or to a device that never ends.
    func testAWorktreesFileIsReadOnlyAsAPlainFileAndOnlyItsStart() throws {
        let real = try write("gitdir: /x/repo/.git/worktrees/side\n", to: "real")
        try FileManager.default.createDirectory(atPath: store.root + "/linked", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: store.root + "/linked/.git", withDestinationPath: real)
        XCTAssertFalse(AgentStore.isWorktree(store.root + "/linked"))
        try FileManager.default.createDirectory(atPath: store.root + "/endless", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: store.root + "/endless/.git", withDestinationPath: "/dev/zero")
        XCTAssertFalse(AgentStore.isWorktree(store.root + "/endless"))
        // Past the first bytes nothing is read, whatever it says.
        try write(String(repeating: "x", count: 5000) + "/worktrees/", to: "long/.git")
        XCTAssertFalse(AgentStore.isWorktree(store.root + "/long"))
        XCTAssertEqual(AgentStore.head(ofPlainFile: store.root + "/long/.git").count, 4096)
        XCTAssertEqual(AgentStore.head(ofPlainFile: real), "gitdir: /x/repo/.git/worktrees/side\n")
    }

    // The card's branch is the branch of the folder the session is in now, so that folder is the one asked about.
    func testACardSaysWhetherItsSessionIsInAWorktreeNow() {
        var file = tracked("/r/p/s1", main: true, idle: 5)
        file.info.branch = "worktree-side"
        file.info.folder = "/Users/me/s1/.claude/worktrees/side"
        let cards = AgentStore.cards(from: ["/r/p/s1.jsonl": file], now: now, worktree: { $0 == "/Users/me/s1/.claude/worktrees/side" })
        XCTAssertEqual(cards.map(\.worktree), [true])
        XCTAssertEqual(AgentStore.cards(from: ["/r/p/s1.jsonl": file], now: now).map(\.worktree), [false])
    }

    private func state(_ activity: SessionActivity, since: TimeInterval? = nil) -> SessionState {
        SessionState(activity: activity, since: since.map { now.addingTimeInterval(-$0) })
    }

    /// The same file once it has carried a conversation line: only such a transcript can hold a record.
    private func spoken(_ file: TrackedFile) -> TrackedFile {
        var file = file
        file.info.lastActivity = file.modified
        return file
    }

    private func recordJSON(pid: Int, session: String, status: String) -> String {
        #"{"pid":\#(pid),"sessionId":"\#(session)","startedAt":1791787807982,"status":"\#(status)","statusUpdatedAt":1791789998096}"#
    }

    /// A store that reads records from a folder of its own, where only `alive` pids have a process.
    private func storeWithRecords(alive: Set<Int32>) throws -> (store: AgentStore, folder: URL) {
        let folder = URL(fileURLWithPath: store.root).appendingPathComponent("records-under-test")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let reading = AgentStore(root: URL(fileURLWithPath: store.root), sessions: folder,
                                 processStart: { alive.contains($0) ? Date(timeIntervalSince1970: 0) : nil })
        return (reading, folder)
    }

    // MARK: crew names for the plugin's SessionStart and SubagentStart hooks

    private func introduce(_ request: CrewIntroRequest, on other: AgentStore? = nil) -> Data? {
        let replied = expectation(description: "introduce replied")
        var body: Data?
        (other ?? store).introduce(request) { body = $0; replied.fulfill() }
        wait(for: [replied], timeout: 2)
        return body
    }

    private func note(_ data: Data?) -> String? {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return (object?["hookSpecificOutput"] as? [String: Any])?["additionalContext"] as? String
    }

    private func start(_ session: String, in cwd: String? = nil, pid: Int32? = nil) -> CrewIntroRequest {
        CrewIntroRequest(event: "SessionStart", session: session, cwd: cwd ?? store.root + "/work", agentType: "", pid: pid)
    }

    func testSessionStartSeatsAndNamesTheLead() throws {
        let text = try XCTUnwrap(note(introduce(start("s1"))))
        let look = try XCTUnwrap(store.looks["s1"])
        XCTAssertTrue(text.contains("draws this session as \(Crew.lead(look).name)"), text)
    }

    // A sub-agent names its lead only once the lead knows its own name.
    func testASubAgentIsNamedOnlyAfterItsLead() throws {
        let faye = CrewIntroRequest(event: "SubagentStart", session: "s1", cwd: store.root + "/work", agentType: "Explore", pid: nil)
        XCTAssertNil(introduce(faye))
        _ = introduce(start("s1"))
        let text = try XCTUnwrap(note(introduce(faye)))
        XCTAssertTrue(text.contains("draws you as Faye"), text)
        XCTAssertTrue(text.contains("Hand your report back to \(Crew.lead(try XCTUnwrap(store.looks["s1"])).name)"), text)
    }

    // A session that started while the app was closed is seated from its card, but its lead
    // never heard its name: its sub-agents stay unnamed rather than say it first.
    func testASubAgentOfASessionSeatedOnlyByItsCardGetsNoName() throws {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = toolUse.replacingOccurrences(of: "2026-10-12T02:00:05.000Z", with: stamp)
        store.ingest(path: try write(line + "\n", to: "proj/s5.jsonl"))
        store.publish()
        let published = expectation(description: "looks published")
        DispatchQueue.main.async { published.fulfill() }
        wait(for: [published], timeout: 2)
        XCTAssertNotNil(store.looks["s5"])
        XCTAssertNil(introduce(CrewIntroRequest(event: "SubagentStart", session: "s5", cwd: "/w", agentType: "Explore", pid: nil)))
    }

    // Superset opens several worktrees of one checkout at once, before their records are read.
    func testTwoSessionsStartingTogetherGetTwoPeople() throws {
        _ = introduce(start("s1"))
        _ = introduce(start("s2"))
        XCTAssertNotEqual(try XCTUnwrap(store.looks["s1"]).face, try XCTUnwrap(store.looks["s2"]).face)
    }

    // /clear starts a new session in the same terminal, whose record may still name the old one.
    func testClearKeepsTheFaceOfTheTerminal() throws {
        let (reading, folder) = try storeWithRecords(alive: [7])
        try Data(recordJSON(pid: 7, session: "old", status: "idle").utf8).write(to: folder.appendingPathComponent("7.json"))
        reading.readSessions()
        _ = introduce(start("old", pid: 7), on: reading)
        _ = introduce(start("new", pid: 7), on: reading)
        XCTAssertEqual(reading.looks["new"], try XCTUnwrap(reading.looks["old"]))
    }

    // Quit claude and start it again within a minute: the first one is gone, so the regular is back.
    func testAQuickRestartGetsTheRegularBack() throws {
        let (reading, folder) = try storeWithRecords(alive: [7, 8, 9])
        // Another live session elsewhere, so the store goes by records.
        try Data(recordJSON(pid: 9, session: "other", status: "idle").utf8).write(to: folder.appendingPathComponent("9.json"))
        try Data(recordJSON(pid: 7, session: "s1", status: "idle").utf8).write(to: folder.appendingPathComponent("7.json"))
        reading.readSessions()
        _ = introduce(start("s1", pid: 7), on: reading)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("7.json"))
        reading.readSessions()
        _ = introduce(start("s2", pid: 8), on: reading)
        XCTAssertEqual(reading.looks["s2"], try XCTUnwrap(reading.looks["s1"]))
    }

    // /clear in a session's first minute, the record already moved to the new session when the hook lands.
    func testClearAfterTheRecordMovedKeepsTheFace() throws {
        let (reading, folder) = try storeWithRecords(alive: [7])
        try Data(recordJSON(pid: 7, session: "old", status: "idle").utf8).write(to: folder.appendingPathComponent("7.json"))
        reading.readSessions()
        _ = introduce(start("old", pid: 7), on: reading)
        try Data(recordJSON(pid: 7, session: "new", status: "idle").utf8).write(to: folder.appendingPathComponent("7.json"))
        reading.readSessions()
        _ = introduce(start("new", pid: 7), on: reading)
        XCTAssertEqual(reading.looks["new"], try XCTUnwrap(reading.looks["old"]))
    }

    // A home folder kept in git, for its settings, is no project: on the card's path or the hook's.
    func testTheHookAndTheCardShareTheHomeFolderRule() {
        let home = GitPlace(worktree: "/h", checkout: "/h"), repo = GitPlace(worktree: "/h/app", checkout: "/h/app")
        XCTAssertNil(AgentStore.projectPlace(of: "/h/notes", home: "/h", git: { _ in home }))
        XCTAssertEqual(AgentStore.projectPlace(of: "/h/app/src", home: "/h", git: { _ in repo }), repo)
        XCTAssertNil(AgentStore.projectPlace(of: "", home: "/h", git: { _ in repo }))
    }

    func testEmptyOrUnknownInputSeatsNobody() {
        XCTAssertNil(introduce(start("s1", in: "")))
        XCTAssertNil(introduce(CrewIntroRequest(event: "PreToolUse", session: "s2", cwd: store.root + "/work", agentType: "", pid: nil)))
        let settled = expectation(description: "store published")
        store.introduce(start("s3")) { _ in settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertNil(store.looks["s1"])
        XCTAssertNil(store.looks["s2"])
    }

    // A quiet agent may be waiting on the person, so it keeps its session out of the fold.
    func testSessionIsIdleOnlyWhenEveryRowIsDone() {
        XCTAssertTrue(card("a", main: .done).isIdle)
        XCTAssertTrue(card("a", main: .done, agents: [.done, .done]).isIdle)
        XCTAssertTrue(card("a", main: nil, agents: [.done]).isIdle)
        XCTAssertFalse(card("a", main: .done, agents: [.done, .working]).isIdle)
        XCTAssertFalse(card("a", main: .quiet).isIdle)
        XCTAssertFalse(card("a", main: .working).isIdle)
        XCTAssertFalse(card("a", main: nil).isIdle)
    }

    func testArrangeFoldsHidesOrShowsIdleSessions() {
        let busy = card("busy", main: .working)
        let first = card("first", main: .done)
        let second = card("second", main: .done)
        let all = [first, busy, second]
        XCTAssertEqual(AgentStore.arrange(all, idle: .fold), SessionList(cards: [busy], folded: [first, second]))
        XCTAssertEqual(AgentStore.arrange(all, idle: .hide), SessionList(cards: [busy], folded: []))
        XCTAssertEqual(AgentStore.arrange(all, idle: .show), SessionList(cards: all, folded: []))
    }

    // A session whose request has just been answered carries the line that says so. Its agent
    // often stops seconds later, and the card must not fold away or drop out with the line on it.
    // The arrow keys stopped at the last full card. An idle session, unfolded by its key, drew
    // as a card like the rest and could not be reached: a tester pressed down twice and the
    // ring stayed put. Return on it is the only way to its app without the pointer.
    func testTheArrowKeysWalkIdleSessionsWhileTheyAreUnfolded() {
        let list = AgentStore.arrange([card("working", main: .working), card("idle1", main: .done), card("quiet", main: .quiet), card("idle2", main: .done)], idle: .fold)
        XCTAssertEqual(list.walked(idleExpanded: false).map(\.id), ["working", "quiet"])
        XCTAssertEqual(list.walked(idleExpanded: true).map(\.id), ["working", "quiet", "idle1", "idle2"])
        let ids = list.walked(idleExpanded: true).map(\.id)
        XCTAssertEqual(KeyCommand.move("quiet", by: 1, in: ids), "idle1")
        XCTAssertEqual(KeyCommand.move("idle1", by: -1, in: ids), "quiet")
        // Folded again under the ring, the next arrow starts from the end it comes from.
        XCTAssertEqual(KeyCommand.move("idle1", by: -1, in: list.walked(idleExpanded: false).map(\.id)), "quiet")
        // Shown as cards all along, they are in the list already and are not walked twice.
        let shown = AgentStore.arrange([card("working", main: .working), card("idle1", main: .done)], idle: .show)
        XCTAssertEqual(shown.walked(idleExpanded: true).map(\.id), ["working", "idle1"])
        // The keyboard still starts on what may need the person, not on an idle session.
        XCTAssertEqual(KeyCommand.start(in: list.walked(idleExpanded: true)), "quiet")
    }

    func testASessionWithAnOutcomeLineKeepsItsCard() {
        let busy = card("busy", main: .working)
        let answered = card("/r/p/answered", main: .done)
        let idle = card("idle", main: .done)
        let all = [answered, busy, idle]
        XCTAssertEqual(AgentStore.arrange(all, idle: .fold, keeping: ["answered"]), SessionList(cards: [answered, busy], folded: [idle]))
        XCTAssertEqual(AgentStore.arrange(all, idle: .hide, keeping: ["answered"]), SessionList(cards: [answered, busy], folded: []))
    }

    func testKeepFinishedSettingDecidesHowLongASessionStaysVisible() {
        var finished = tracked("/r/p/s1", main: true, idle: 120)
        finished.info.turnEnded = true
        let files = ["/r/p/s1.jsonl": finished]
        XCTAssertEqual(AgentStore.cards(from: files, now: now, visibleFor: 60).count, 0)
        XCTAssertEqual(AgentStore.cards(from: files, now: now, visibleFor: 300).count, 1)
        XCTAssertEqual(AgentStore.cards(from: files, now: now).count, 1)
    }

    // "Keep finished for 1m" must not hide an agent that is ninety seconds into a long command.
    func testAShortWindowHidesOnlyFinishedAgents() {
        var finished = tracked("/r/p/s1", main: true, idle: 90)
        finished.info.turnEnded = true
        let running = tracked("/r/p/s2", main: true, idle: 90)
        let files = ["/r/p/s1.jsonl": finished, "/r/p/s2.jsonl": running]
        XCTAssertEqual(AgentStore.cards(from: files, now: now, visibleFor: 60).map(\.id), ["/r/p/s2"])

        // An agent that never finished still drops out after ten silent minutes, as before.
        let abandoned = tracked("/r/p/s3", main: true, idle: 601)
        XCTAssertEqual(AgentStore.cards(from: ["/r/p/s3.jsonl": abandoned], now: now, visibleFor: 60).count, 0)
        XCTAssertEqual(AgentStore.cards(from: ["/r/p/s3.jsonl": abandoned], now: now, visibleFor: 1800).count, 1)
    }

    // Opening the app with "Keep finished for 1m" must still find an agent that last wrote three minutes ago
    // and is in the middle of a turn.
    func testScanAtLaunchFindsAgentsMidTurnUnderAShortWindow() throws {
        // Under the home folder: the scan compares paths as written, and /var is a symlink.
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("agent-valley-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("proj"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scanning = AgentStore(root: root, visibleFor: 60)
        let path = scanning.root + "/proj/s1.jsonl"
        try Data((toolUse + "\n").utf8).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-180)], ofItemAtPath: path)

        scanning.rescan()
        XCTAssertNotNil(scanning.files[path])
    }

    // A session that has waited on the person for two hours wrote nothing in all that time. Its
    // record says it waits, so opening the app must still find it.
    func testScanAtLaunchFindsASessionItsRecordSaysIsHeldUp() throws {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("agent-valley-tests-" + UUID().uuidString)
        let folder = base.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("projects/proj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let scanning = AgentStore(root: base.appendingPathComponent("projects"), sessions: folder,
                                  processStart: { _ in Date(timeIntervalSince1970: 0) })
        func transcript(_ session: String, hoursOld: Double) throws -> String {
            let path = scanning.root + "/proj/" + session + ".jsonl"
            try Data((toolUse + "\n").utf8).write(to: URL(fileURLWithPath: path))
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-hoursOld * 3600)], ofItemAtPath: path)
            return path
        }
        func record(_ pid: Int, _ session: String, _ status: String) throws {
            try Data(recordJSON(pid: pid, session: session, status: status).utf8).write(to: folder.appendingPathComponent("\(pid).json"))
        }
        let waiting = try transcript("s1", hoursOld: 2)
        let busy = try transcript("s2", hoursOld: 2)
        let idle = try transcript("s3", hoursOld: 2)
        let unknown = try transcript("s4", hoursOld: 2)
        // Past what `forget` keeps: read now, it would be dropped on the next tick.
        let dayOld = try transcript("s5", hoursOld: 30)
        try record(111, "s1", "waiting")
        try record(222, "s2", "busy")
        try record(333, "s3", "idle")
        try record(555, "s5", "waiting")

        scanning.readSessions()
        scanning.rescan()
        XCTAssertEqual(scanning.files.keys.sorted(), [waiting, busy, idle].sorted())
        XCTAssertNotNil(scanning.files[idle])
        XCTAssertNil(scanning.files[unknown])
        XCTAssertNil(scanning.files[dayOld])
        let cards = scanning.cards(now: Date())
        XCTAssertEqual(cards.first { $0.id.hasSuffix("/s1") }?.main?.status, .needsYou)
        // Busy and silent this long may be stuck: listed all the same, as quiet.
        XCTAssertEqual(cards.first { $0.id.hasSuffix("/s2") }?.main?.calledBusy, true)
        // Read, but an idle session with no job is not listed.
        XCTAssertNil(cards.first { $0.id.hasSuffix("/s3") })
        // Nothing dropped a second later.
        scanning.forget(now: Date())
        XCTAssertEqual(scanning.files.count, 3)
    }

    // Exit removes the record. When the last Claude Code closes the folder is empty, and a job it was
    // running is gone with it, not kept for a day.
    func testJobsEndWhenTheLastClaudeCodeClosesAndItsRecordGoes() throws {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("agent-valley-tests-" + UUID().uuidString)
        let folder = base.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("projects/proj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let scanning = AgentStore(root: base.appendingPathComponent("projects"), sessions: folder,
                                  processStart: { _ in Date(timeIntervalSince1970: 0) })
        let path = scanning.root + "/proj/s1.jsonl"
        try Data((JobLines.bash().joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: path))
        scanning.readSessions()
        scanning.rescan()
        XCTAssertNotNil(scanning.files[path])
        let card = scanning.cards(now: Date()).first { $0.id.hasSuffix("/s1") }
        XCTAssertEqual(card?.jobs ?? [], [])
    }

    // The spec's "ตอนเปิดแอป": an open session's files are read back as far as `forget` keeps,
    // sub-agents' too, so a job started long before launch is seen.
    func testScanAtLaunchReadsEveryFileOfAnOpenSessionForItsJobs() throws {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("agent-valley-tests-" + UUID().uuidString)
        let folder = base.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("projects/proj/s1/subagents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let scanning = AgentStore(root: base.appendingPathComponent("projects"), sessions: folder,
                                  processStart: { _ in Date(timeIntervalSince1970: 0) })
        func write(_ lines: [String], _ relative: String) throws -> String {
            let path = scanning.root + "/proj/" + relative
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: path))
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: path)
            return path
        }
        let answer = #"{"type":"assistant","timestamp":"2026-10-24T15:00:10.000Z","message":{"model":"claude-opus-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"Started it."}]}}"#
        let main1 = try write(JobLines.bash() + [answer], "s1.jsonl")
        let sub1 = try write(JobLines.monitor(persistent: true), "s1/subagents/agent-x.jsonl")
        let main2 = try write(JobLines.bash("other"), "s2.jsonl")
        try Data(recordJSON(pid: 111, session: "s1", status: "idle").utf8).write(to: folder.appendingPathComponent("111.json"))

        scanning.readSessions()
        scanning.rescan()
        XCTAssertNotNil(scanning.files[main1])
        XCTAssertNotNil(scanning.files[sub1])
        XCTAssertNil(scanning.files[main2])
        let card = scanning.cards(now: Date()).first { $0.id.hasSuffix("/s1") }
        XCTAssertEqual(card?.jobs.map(\.id), ["bfbr6r6ou", "b66ml5arc"])
        XCTAssertEqual(card?.onlyForJobs, true)
    }

    // Walking the whole folder again is only needed when the window reaches further back than before.
    func testOnlyALongerWindowNeedsAnotherScan() {
        XCTAssertTrue(AgentStore.windowGrew(from: 600, to: 1800))
        XCTAssertFalse(AgentStore.windowGrew(from: 600, to: 600))
        XCTAssertFalse(AgentStore.windowGrew(from: 1800, to: 600))
        XCTAssertFalse(AgentStore.windowGrew(from: 600, to: 60))
        XCTAssertFalse(AgentStore.windowGrew(from: 60, to: 300))
    }

    // The collapsed bar must not look finished while an agent sits silent, perhaps waiting on the person.
    func testBarStateSeparatesQuietFromFinished() {
        XCTAssertEqual(AgentStore.barState([card("a", main: .working, agents: [.working, .quiet, .done])]), .working(2))
        XCTAssertEqual(AgentStore.barState([card("a", main: .done, agents: [.quiet]), card("b", main: .quiet)]), .quiet(2))
        XCTAssertEqual(AgentStore.barState([card("a", main: .done, agents: [.done])]), .idle)
        XCTAssertEqual(AgentStore.barState([]), .idle)
    }

    // A question left on screen for half an hour is exactly what the panel is for.
    func testAnAgentWithAQuestionPendingStaysForAnHour() {
        var asking = tracked("/r/p/s1", main: true, idle: 1800)
        asking.info.asking = true
        XCTAssertEqual(AgentStore.visible(["/r/p/s1.jsonl": asking], now: now).count, 1)
        asking.modified = now.addingTimeInterval(-3700)
        asking.info.lastActivity = asking.modified
        XCTAssertTrue(AgentStore.visible(["/r/p/s1.jsonl": asking], now: now).isEmpty)
        // Without a question the same silence hides it at ten minutes, as before.
        XCTAssertTrue(AgentStore.visible(["/r/p/s1.jsonl": tracked("/r/p/s1", main: true, idle: 1800)], now: now).isEmpty)
    }

    // Something is always working when many agents run, so the working count alone hides the one that waits.
    func testTheBarKnowsAboutAgentsThatMayNeedThePersonWhileOthersWork() {
        // An agent that needs the person comes before everything else the bar could say.
        let busy = card("a", main: .working, agents: [.working, .quiet, .needsYou, .done])
        // The count of those still working stays beside it: with someone waiting, the bar must
        // still tell the rest moving from everything having stopped.
        XCTAssertEqual(AgentStore.barState([busy]), .needsYou(1, working: 2))
        XCTAssertEqual(AgentStore.barState([card("a", main: .needsYou, agents: [.quiet, .needsYou, .done])]), .needsYou(2, working: 0))
        // Then the ones working, then, with nothing working, the ones that have gone quiet.
        XCTAssertEqual(AgentStore.barState([card("a", main: .working, agents: [.working, .quiet])]), .working(2))
        XCTAssertEqual(AgentStore.barState([card("a", main: .done, agents: [.quiet, .quiet])]), .quiet(2))
        // The mark on the mascot: red when someone needs the person, white when someone is only quiet.
        XCTAssertEqual(AgentStore.flag([busy]), .needsYou)
        XCTAssertEqual(AgentStore.flag([card("a", main: .working, agents: [.quiet])]), .quiet)
        XCTAssertNil(AgentStore.flag([card("a", main: .working, agents: [.done])]))
    }

    func testACardCarriesItsSessionTitleAndHowLongAQuestionHasWaited() {
        var main = tracked("/r/p/s1", main: true, idle: 240)
        main.info.title = "Fix checkout rounding"
        main.info.asking = true
        let card = AgentStore.cards(from: ["/r/p/s1.jsonl": main], now: now).first
        XCTAssertEqual(card?.title, "Fix checkout rounding")
        XCTAssertEqual(card?.main?.status, .needsYou)
        XCTAssertEqual(card?.main?.quietFor ?? 0, 240, accuracy: 0.001)
        XCTAssertEqual(card?.isIdle, false)
    }

    // Only a finished agent folds. One that is quiet or needs the person stays a full row.
    func testACardSplitsItsAgentsIntoLiveAndFinished() {
        let mixed = card("a", main: .working, agents: [.done, .working, .quiet, .done, .needsYou])
        XCTAssertEqual(mixed.liveAgents().map(\.status), [.working, .quiet, .needsYou])
        XCTAssertEqual(mixed.doneAgents().map(\.id), ["a/agent0", "a/agent3"])
        // A finished agent with an outcome line under it keeps its row until the line has gone.
        XCTAssertEqual(mixed.liveAgents(holding: ["a/agent0"]).map(\.id), ["a/agent0", "a/agent1", "a/agent2", "a/agent4"])
        XCTAssertEqual(mixed.doneAgents(holding: ["a/agent0"]).map(\.id), ["a/agent3"])
    }

    // A session closed with a question up keeps asking for an hour. The person can put it away,
    // and it stays away until it does something again.
    func testAHiddenSessionStaysAwayUntilItMoves() {
        var quiet = tracked("/r/p/s1", main: true, idle: 300)
        quiet.info.lastActivity = now.addingTimeInterval(-300)
        let cards = AgentStore.cards(from: ["/r/p/s1.jsonl": quiet, "/r/p/s2.jsonl": tracked("/r/p/s2", main: true, idle: 5)], now: now)
        let stuck = cards.first { $0.id == "/r/p/s1" }!
        XCTAssertEqual(stuck.movedAt, now.addingTimeInterval(-300))
        XCTAssertTrue(stuck.canHide)
        XCTAssertFalse(cards.first { $0.id == "/r/p/s2" }!.canHide, "a working session has nothing to put away")
        XCTAssertEqual(AgentStore.showing(cards, hidden: [:]).count, 2)
        XCTAssertEqual(AgentStore.showing(cards, hidden: ["/r/p/s1": now.addingTimeInterval(-300)]).map(\.id), ["/r/p/s2"])
        // It has moved since it was hidden: back it comes.
        XCTAssertEqual(AgentStore.showing(cards, hidden: ["/r/p/s1": now.addingTimeInterval(-900)]).count, 2)
    }

    // A session put away leaves the list, the counts and the bar. It stays listed as hidden, so
    // it can be brought back: one that waits on the person never moves by itself.
    func testSessionsPutAwayAreStillKnownSoTheyCanComeBack() {
        var quiet = tracked("/r/p/s1", main: true, idle: 300)
        quiet.info.lastActivity = now.addingTimeInterval(-300)
        let cards = AgentStore.cards(from: ["/r/p/s1.jsonl": quiet, "/r/p/s2.jsonl": tracked("/r/p/s2", main: true, idle: 5)], now: now)
        XCTAssertTrue(AgentStore.putAway(cards, hidden: [:]).isEmpty)
        XCTAssertEqual(AgentStore.putAway(cards, hidden: ["/r/p/s1": now.addingTimeInterval(-300)]).map(\.id), ["/r/p/s1"])
        // It has moved since: it is back in the list, not among the hidden.
        XCTAssertTrue(AgentStore.putAway(cards, hidden: ["/r/p/s1": now.addingTimeInterval(-900)]).isEmpty)
    }

    func testACardIsCalledByItsTitleOrElseItsFolder() {
        var named = card("web-app", main: .working)
        XCTAssertEqual(named.name, "web-app")
        named.title = "Fix checkout rounding"
        XCTAssertEqual(named.name, "Fix checkout rounding")
    }

    func testRowsCarryHowLongTheyHaveBeenSilent() {
        let files = ["/r/p/s1.jsonl": tracked("/r/p/s1", main: true, idle: 300)]
        let row = AgentStore.cards(from: files, now: now).first?.main
        XCTAssertEqual(row?.status, .quiet)
        XCTAssertEqual(row?.quietFor ?? 0, 300, accuracy: 0.001)
    }

    // A busy record keeps a silent row "working". The row still knows how long it has been silent,
    // and a finished one does not count on.
    func testAWorkingRowCarriesItsSilenceAndAFinishedOneDoesNot() {
        var finished = tracked("/r/p/s1", idle: 300)
        finished.info.turnEnded = true
        let files = [
            "/r/p/s1.jsonl": spoken(tracked("/r/p/s1", main: true, idle: 540)),
            "/r/p/s1/subagents/agent-a.jsonl": finished,
        ]
        let card = AgentStore.cards(from: files, now: now, states: ["s1": state(.busy)]).first
        XCTAssertEqual(card?.main?.status, .working)
        XCTAssertEqual(card?.main?.quietFor ?? 0, 540, accuracy: 0.001)
        // Past ten minutes with nothing else at work in the session, the list shows it as quiet.
        let long = AgentStore.cards(from: ["/r/p/s1.jsonl": spoken(tracked("/r/p/s1", main: true, idle: 840))], now: now, states: ["s1": state(.busy)]).first
        XCTAssertEqual(long?.main?.status, .quiet)
        XCTAssertEqual(long?.main?.quietFor ?? 0, 840, accuracy: 0.001)
        XCTAssertEqual(card?.agents.first?.status, .done)
        XCTAssertEqual(card?.agents.first?.quietFor ?? -1, 0, accuracy: 0.001)
    }

    // A card knows which app its session's terminal runs in, so the panel can take the person there.
    // Only a record says which process a session is, so a card without one names no app.
    func testACardCarriesTheAppOfTheSessionItsRecordSpeaksFor() {
        let files = [
            "/r/p/s1.jsonl": spoken(tracked("/r/p/s1", main: true, idle: 5)),
            "/r/p/s2.jsonl": spoken(tracked("/r/p/s2", main: true, idle: 5)),
        ]
        let cards = AgentStore.cards(from: files, now: now, states: ["s1": state(.busy)], owners: ["s1": superset, "s2": superset])
        XCTAssertEqual(cards.first { $0.id == "/r/p/s1" }?.owner, superset)
        XCTAssertNil(cards.first { $0.id == "/r/p/s2" }?.owner)
    }

    // A found app is kept for as long as its Claude Code process lives, not looked up on every
    // one-second pass. A missing one is looked for again: the app may only have been closed.
    func testTheStoreKeepsAFoundAppAndLooksAgainForAMissingOne() throws {
        var lookups: [Int32] = []
        let app = superset
        var found: [OwnerApp?] = [nil, app]
        let folder = URL(fileURLWithPath: store.root).appendingPathComponent("records-with-owners")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let reading = AgentStore(root: URL(fileURLWithPath: store.root), sessions: folder,
                                 processStart: { _ in Date(timeIntervalSince1970: 0) },
                                 owner: { lookups.append($0); return found.count > 1 ? found.removeFirst() : found[0] })
        try Data(recordJSON(pid: 111, session: "s1", status: "busy").utf8).write(to: folder.appendingPathComponent("111.json"))
        reading.readSessions()
        XCTAssertEqual(reading.owners, [:])
        reading.readSessions()
        reading.readSessions()
        XCTAssertEqual(lookups, [111, 111])
        XCTAssertEqual(reading.owners, ["s1": app])
        // And the card the store draws for that session carries it.
        let path = try write(toolUse + "\n", to: "proj/s1.jsonl")
        reading.ingest(path: path)
        let soon = try XCTUnwrap(reading.files[path]?.info.lastActivity).addingTimeInterval(5)
        XCTAssertEqual(reading.cards(now: soon).first?.owner, app)
        // The record is gone: so is what was known about its process.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("111.json"))
        reading.readSessions()
        XCTAssertEqual(reading.owners, [:])
    }

    // Grouped by status, a card goes to the head of the list as it starts to wait. With the
    // list scrolled down that is above what is in view: the person has not seen it.
    func testAWaitInAGroupedListIsSeenOnlyWithTheListAtItsTop() {
        XCTAssertTrue(WaitWatch.inView(showingList: true, pastEdge: false, grouping: .projects, atTop: false))
        XCTAssertTrue(WaitWatch.inView(showingList: true, pastEdge: false, grouping: .status, atTop: true))
        XCTAssertFalse(WaitWatch.inView(showingList: true, pastEdge: false, grouping: .status, atTop: false))
        XCTAssertFalse(WaitWatch.inView(showingList: false, pastEdge: false, grouping: .projects, atTop: true))
        XCTAssertFalse(WaitWatch.inView(showingList: true, pastEdge: true, grouping: .projects, atTop: true))
    }

    // A session is listed under what is most pressing in it, whichever of its agents that is.
    func testACardIsGroupedByItsMostPressingRow() {
        XCTAssertEqual(card("a", main: .needsYou, agents: [.working]).group, .needsYou)
        XCTAssertEqual(card("b", main: .done, agents: [.needsYou, .working]).group, .needsYou)
        XCTAssertEqual(card("c", main: .working, agents: [.quiet]).group, .working)
        XCTAssertEqual(card("d", main: .done, agents: [.working]).group, .working)
        XCTAssertEqual(card("e", main: .quiet, agents: [.done]).group, .quiet)
        XCTAssertEqual(card("f", main: .done, agents: [.done]).group, .idle)
    }

    // Those that wait on the person first; inside a group the order they came in is kept.
    func testByStatusTheWaitingComeFirstAndEachGroupKeepsItsOrder() {
        let all = [
            card("idle", main: .done), card("working1", main: .working), card("quiet", main: .quiet),
            card("waiting1", main: .needsYou), card("working2", main: .done, agents: [.working]), card("waiting2", main: .working, agents: [.needsYou]),
        ]
        XCTAssertEqual(AgentStore.ordered(all, by: .status).map(\.id), ["waiting1", "waiting2", "working1", "working2", "quiet", "idle"])
    }

    // By status, those that wait on the person are listed the longest wait first: a tester
    // wanted to answer the oldest first. A wait's start does not move, so a card that starts
    // to wait joins the end of the group and those above it stay where they are.
    func testByStatusTheLongestWaitComesFirst() {
        func card(_ id: String, main: AgentStatus, waited: TimeInterval, agents: [(AgentStatus, TimeInterval)] = []) -> SessionCard {
            func row(_ name: String, _ status: AgentStatus, _ waited: TimeInterval) -> AgentRow {
                AgentRow(id: id + name, info: AgentInfo(), status: status, elapsed: 0, quietFor: waited)
            }
            return SessionCard(id: id, project: id, branch: "", main: row("/main", main, waited),
                               agents: agents.enumerated().map { row("/agent\($0.offset)", $0.element.0, $0.element.1) }, startedAt: now)
        }
        let all = [
            card("new", main: .needsYou, waited: 38),
            card("working", main: .working, waited: 900),
            card("old", main: .needsYou, waited: 725),
            // Its own agent is quiet; a sub-agent of it has waited longest of all.
            card("agent", main: .quiet, waited: 2000, agents: [(.needsYou, 1200)]),
            card("tie", main: .needsYou, waited: 38),
        ]
        XCTAssertEqual(AgentStore.ordered(all, by: .status).map(\.id), ["agent", "old", "new", "tie", "working"])
        // By project, the order stays the order they came in.
        XCTAssertEqual(AgentStore.ordered(all, by: .projects).map(\.id), ["new", "working", "old", "agent", "tie"])
    }

    // The bar's time is the longest of the waits on the person, whatever else has gone quiet.
    func testTheLongestWaitIsTheLongestOfThoseOnThePerson() {
        func row(_ status: AgentStatus, _ waited: TimeInterval) -> AgentRow {
            AgentRow(id: UUID().uuidString, info: AgentInfo(), status: status, elapsed: 0, quietFor: waited)
        }
        let sessions = [
            SessionCard(id: "a", project: "a", branch: "", main: row(.needsYou, 90), agents: [row(.needsYou, 400)], startedAt: now),
            SessionCard(id: "b", project: "b", branch: "", main: row(.quiet, 5000), agents: [], startedAt: now),
        ]
        XCTAssertEqual(AgentStore.longestWait(sessions), 400)
        XCTAssertNil(AgentStore.longestWait([sessions[1]]))
    }

    func testAGroupsLineStandsOverItsFirstCard() {
        let listed = AgentStore.ordered([
            card("working1", main: .working), card("waiting", main: .needsYou), card("working2", main: .working), card("idle", main: .done),
        ], by: .status)
        XCTAssertEqual(AgentStore.headers(of: listed, by: .status), [
            "waiting": GroupHeader(group: .needsYou, count: 1, agents: 1),
            "working1": GroupHeader(group: .working, count: 2, agents: 2),
            "idle": GroupHeader(group: .idle, count: 1),
        ])
    }

    // The line under the notch counts agents. A group's line carries how many of its sessions'
    // agents are doing what the group is named for, so the two can be told to agree.
    func testAGroupsLineCarriesHowManyAgentsAreDoingWhatItIsNamedFor() {
        let listed = AgentStore.ordered([
            card("fleet", main: .working, agents: [.working, .working, .done, .quiet]),
            card("alone", main: .working),
            card("asking", main: .working, agents: [.needsYou, .needsYou]),
            card("still", main: .quiet, agents: [.quiet, .done]),
            card("over", main: .done, agents: [.done]),
        ], by: .status)
        let headers = AgentStore.headers(of: listed, by: .status)
        XCTAssertEqual(headers["asking"], GroupHeader(group: .needsYou, count: 1, agents: 2))
        XCTAssertEqual(headers["fleet"], GroupHeader(group: .working, count: 2, agents: 4))
        XCTAssertEqual(headers["still"], GroupHeader(group: .quiet, count: 1, agents: 2))
        // The idle are counted by session alone: the line under the notch does not count them.
        XCTAssertEqual(headers["over"], GroupHeader(group: .idle, count: 1, agents: 0))
        // Every agent that needs the person is in the first group: its number is the red one's.
        XCTAssertEqual(headers["asking"]?.agents, AgentStore.count(.needsYou, in: listed))
    }

    // Idle sessions folded into one line, or left out, are not cards: no line stands over nothing.
    func testFoldedIdleSessionsHaveNoLine() {
        let all = AgentStore.ordered([card("idle", main: .done), card("working", main: .working)], by: .status)
        for idle in [IdleSessions.fold, .hide] {
            let cards = AgentStore.arrange(all, idle: idle).cards
            XCTAssertEqual(AgentStore.headers(of: cards, by: .status), ["working": GroupHeader(group: .working, count: 1, agents: 1)], "\(idle)")
        }
        XCTAssertEqual(AgentStore.headers(of: AgentStore.arrange(all, idle: .show).cards, by: .status).count, 2)
    }

    // A session belongs to the project History names it by, from the folder it started in: a
    // Superset or Claude Code worktree goes with the repository it was made from.
    func testACardKnowsItsProjectByTheFolderItStartedIn() {
        var file = tracked("/r/p/s1", main: true, idle: 5)
        file.info.cwd = "/Users/me/.superset/worktrees/shop-web/fix-coupons"
        let cards = AgentStore.cards(from: ["/r/p/s1.jsonl": file], now: now, home: "/Users/me")
        XCTAssertEqual(cards.map(\.repo), ["shop-web"])
        XCTAssertEqual(cards.map(\.project), ["fix-coupons"])
    }

    // By project, each project's sessions stand together. Projects come in the order of their
    // newest session, and inside one the order the sessions came in is kept, so it holds
    // still while agents work. A card that knows no project goes by its folder.
    func testByProjectEachProjectsSessionsStandTogether() {
        let all = [
            card("w1", main: .working, repo: "web"), card("a1", main: .needsYou, repo: "api"),
            card("w2", main: .done, repo: "web"), card("loose", main: .working), card("a2", main: .working, repo: "api"),
        ]
        XCTAssertEqual(AgentStore.ordered(all, by: .projects).map(\.id), ["w1", "w2", "a1", "a2", "loose"])
        XCTAssertEqual(AgentStore.headers(of: all, by: .projects), [:])
    }

    // A project's line stands over its first card and counts the folders its sessions are in.
    func testAProjectsLineStandsOverItsFirstCardAndCountsItsFolders() {
        let listed = AgentStore.ordered([
            card("w1", main: .working, repo: "web", folder: "web"), card("a1", main: .working, repo: "api", folder: "api"),
            card("w2", main: .done, repo: "web", folder: "fix-x"), card("w3", main: .working, repo: "web", folder: "fix-x"),
        ], by: .projects)
        XCTAssertEqual(AgentStore.projectHeaders(of: listed), [
            "w1": ProjectHeader(project: "web", worktrees: 2, sessions: 3),
            "a1": ProjectHeader(project: "api", worktrees: 1, sessions: 1),
        ])
    }

    // Two checkouts that happen to share a folder name are two projects. A session in a folder
    // inside a checkout is in that checkout's worktree, not in one more.
    func testByProjectACheckoutIsTheProjectNotItsName() {
        let web = GitPlace(worktree: "/a/web", checkout: "/a/web")
        let listed = AgentStore.ordered([
            card("w1", main: .working, repo: "web", folder: "web", git: web),
            card("x1", main: .working, repo: "web", folder: "web", git: GitPlace(worktree: "/b/web", checkout: "/b/web")),
            card("w2", main: .working, repo: "web", folder: "site", git: web),
            card("w3", main: .working, repo: "web", folder: "fix-x", git: GitPlace(worktree: "/a/fix-x", checkout: "/a/web")),
        ], by: .projects)
        XCTAssertEqual(listed.map(\.id), ["w1", "w2", "w3", "x1"])
        XCTAssertEqual(AgentStore.projectHeaders(of: listed), [
            "w1": ProjectHeader(project: "web", worktrees: 2, sessions: 3),
            "x1": ProjectHeader(project: "web", worktrees: 1, sessions: 1),
        ])
    }

    // Off, nothing of a session's process is read for its tab. On, the app a card carries
    // knows the tab; off again, it has forgotten it.
    func testTheStoreLooksForATabOnlyWhileAskedTo() throws {
        var reads = 0
        // Not on disk, so the send route (which asks for a tab of its own) never counts here.
        let ghostty = OwnerApp(bundle: URL(fileURLWithPath: "/nowhere/Ghostty.app"), name: "Ghostty")
        let place = TabPlace(terminal: .ghostty, key: "/work")
        var there = ghostty
        there.tab = place
        let folder = URL(fileURLWithPath: store.root).appendingPathComponent("records-with-tabs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let reading = AgentStore(root: URL(fileURLWithPath: store.root), sessions: folder,
                                 processStart: { _ in Date(timeIntervalSince1970: 0) },
                                 owner: { _ in ghostty },
                                 tab: { _, _ in reads += 1; return place })
        try Data(recordJSON(pid: 111, session: "s1", status: "busy").utf8).write(to: folder.appendingPathComponent("111.json"))
        reading.readSessions()
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(reading.owners, ["s1": ghostty])
        reading.applyTabs(true)
        reading.readSessions()
        XCTAssertEqual(reading.owners, ["s1": there])
        // Kept with the app, not read again on every pass.
        reading.readSessions()
        XCTAssertEqual(reads, 1)
        reading.applyTabs(false)
        reading.readSessions()
        XCTAssertEqual(reading.owners, ["s1": ghostty])
        XCTAssertEqual(reads, 1)
    }

    // An app that has been closed since it was found is still the session's app: looked for
    // again it would not be found, so changing the switch must not look.
    func testChangingTheSwitchKeepsAnAppThatHasSinceBeenClosed() throws {
        var open = true
        let ghostty = OwnerApp(bundle: URL(fileURLWithPath: "/Applications/Ghostty.app"), name: "Ghostty")
        let place = TabPlace(terminal: .ghostty, key: "/work")
        var there = ghostty
        there.tab = place
        let folder = URL(fileURLWithPath: store.root).appendingPathComponent("records-with-a-closed-app")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let reading = AgentStore(root: URL(fileURLWithPath: store.root), sessions: folder,
                                 processStart: { _ in Date(timeIntervalSince1970: 0) },
                                 owner: { _ in open ? ghostty : nil },
                                 tab: { _, _ in place })
        try Data(recordJSON(pid: 111, session: "s1", status: "busy").utf8).write(to: folder.appendingPathComponent("111.json"))
        reading.readSessions()
        XCTAssertEqual(reading.owners, ["s1": ghostty])
        open = false
        reading.applyTabs(true)
        reading.readSessions()
        XCTAssertEqual(reading.owners, ["s1": there])
        reading.applyTabs(false)
        reading.readSessions()
        XCTAssertEqual(reading.owners, ["s1": ghostty])
    }

    // AppKit is asked on the main thread, whichever thread asks. The store reads on a queue of its own.
    func testAppKitIsAskedOnTheMainThread() {
        XCTAssertTrue(AgentStore.onMain { Thread.isMainThread })
        let asked = expectation(description: "asked from another thread")
        DispatchQueue.global().async {
            XCTAssertTrue(AgentStore.onMain { Thread.isMainThread })
            asked.fulfill()
        }
        wait(for: [asked], timeout: 5)
    }

    // The link to the session's app shows on a card where someone waits, and only when the app is known.
    func testACardOffersTheWayToItsAppWhileItNeedsThePerson() {
        var waiting = card("a", main: .working, agents: [.needsYou])
        XCTAssertNil(waiting.goTo)
        waiting.owner = superset
        XCTAssertEqual(waiting.goTo, superset)
        var working = card("a", main: .working, agents: [.working, .quiet])
        working.owner = superset
        XCTAssertNil(working.goTo)
    }

    // A terminal's shells can hang off a helper that the app keeps running outside its own
    // process tree: Superset's sessions do. The helper's place in the app's bundle says whose it is.
    func testAHelperInsideAnAppBundleBelongsToThatApp() {
        XCTAssertEqual(AgentStore.bundle(ofExecutable: "/Applications/Superset.app/Contents/MacOS/Superset"), "/Applications/Superset.app")
        XCTAssertEqual(AgentStore.bundle(ofExecutable: "/Applications/Superset.app/Contents/Frameworks/Superset Helper.app/Contents/MacOS/Superset Helper"), "/Applications/Superset.app")
        XCTAssertNil(AgentStore.bundle(ofExecutable: "/bin/zsh"))
        XCTAssertNil(AgentStore.bundle(ofExecutable: "/opt/homebrew/bin/tmux"))
        XCTAssertNotNil(AgentStore.executable(ofProcess: getpid()))
        XCTAssertNil(AgentStore.executable(ofProcess: 99_999_999))
    }

    // Superset's terminals hang off a helper that outlives the app's own updates, running from
    // the copy the update took away. Seen on 2026-10-15: every Superset card lost its app.
    func testAHelperWhoseProgramIsGoneBelongsToTheAppItsEnvironmentNames() throws {
        // A copy: macOS keeps a system program's environment from other processes. Signed again,
        // or it is killed at launch out of its place.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("helper")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: copy.path)
        let sign = try Process.run(URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["-f", "-s", "-", copy.path])
        sign.waitUntilExit()
        XCTAssertEqual(sign.terminationStatus, 0)
        let helper = Process()
        helper.executableURL = copy
        helper.arguments = ["30"]
        helper.environment = ["__CFBundleIdentifier": "com.apple.finder"]
        try helper.run()
        defer { helper.terminate() }

        XCTAssertEqual(AgentStore.app(ofProcess: helper.processIdentifier, program: { _ in nil })?.bundleIdentifier, "com.apple.finder")
        // A program still on disk outside any app is no app's, whatever its environment says:
        // tmux's server carries the variable of the terminal it was first started in.
        XCTAssertNil(AgentStore.app(ofProcess: helper.processIdentifier))
        XCTAssertNil(AgentStore.app(ofProcess: 99_999_999, program: { _ in nil }))
    }

    func testAProcessHasAParentAndOneThatExitedHasNone() {
        XCTAssertEqual(AgentStore.parent(ofProcess: getpid()), getppid())
        XCTAssertNil(AgentStore.parent(ofProcess: 99_999_999))
    }

    // The bar's mascot used to be whichever agent was first at work, which said nothing. The
    // count of those at work stands beside the red one, so the mascot is free to mean something.
    func testTheBarsMascotIsTheAgentMostWorthALook() {
        // The bar's mascot is the agent most worth a look: one that waits, else one that has
        // gone quiet, else one at work.
        XCTAssertEqual(AgentStore.lead([card("a", main: .working, agents: [.quiet, .needsYou])])?.status, .needsYou)
        XCTAssertEqual(AgentStore.lead([card("a", main: .working, agents: [.quiet, .working])])?.status, .quiet)
        XCTAssertEqual(AgentStore.lead([card("a", main: .working, agents: [.done])])?.status, .working)
        XCTAssertEqual(AgentStore.lead([card("a", main: .needsYou, agents: [.quiet, .done])])?.status, .needsYou)
        XCTAssertEqual(AgentStore.lead([card("a", main: .done, agents: [.quiet])])?.status, .quiet)
        XCTAssertNil(AgentStore.lead([card("a", main: .done)]))
        // The flag still says someone waits, whoever the mascot stands for.
        XCTAssertEqual(AgentStore.flag([card("a", main: .needsYou, agents: [.working])]), .needsYou)
        // Open, everyone not done stands behind it, the most worth a look first.
        XCTAssertEqual(AgentStore.crowd([card("a", main: .working, agents: [.done, .quiet]), card("b", main: .needsYou)]).map(\.status),
                       [.needsYou, .quiet, .working])
    }

    // The app a session runs in tells one card from another only when the list holds more than
    // one app. With every session in Superset, "Superset" on every card said nothing, and the
    // name and the "Go to Superset" button already reach it.
    func testTheAppIsNamedOnACardOnlyWhenTheListHoldsMoreThanOne() {
        let ghostty = OwnerApp(bundle: URL(fileURLWithPath: "/Applications/Ghostty.app"), name: "Ghostty")
        func card(_ id: String, _ owner: OwnerApp?) -> SessionCard {
            var card = SessionCard(id: id, project: id, branch: "", main: AgentRow(id: id + "/main", info: AgentInfo(), status: .working, elapsed: 0),
                                   agents: [], startedAt: Date(timeIntervalSince1970: 0))
            card.owner = owner
            return card
        }
        XCTAssertFalse(SessionList(cards: [card("a", superset), card("b", superset)], folded: []).showsApps)
        XCTAssertFalse(SessionList(cards: [card("a", superset), card("b", nil)], folded: []).showsApps)
        XCTAssertFalse(SessionList(cards: [], folded: []).showsApps)
        XCTAssertTrue(SessionList(cards: [card("a", superset), card("b", ghostty)], folded: []).showsApps)
        // An idle session folded into one line counts: unfolded, it is a card like the rest.
        XCTAssertTrue(SessionList(cards: [card("a", superset)], folded: [card("b", ghostty)]).showsApps)
    }

    // Two sessions at once in one project: the regular and someone else, and the roster on disk.
    func testTheStoreSeatsEachSessionAndKeepsTheRoster() throws {
        let folder = URL(fileURLWithPath: store.root).appendingPathComponent("records-roster")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = URL(fileURLWithPath: store.root).appendingPathComponent("roster.json")
        let reading = AgentStore(root: URL(fileURLWithPath: store.root), sessions: folder,
                                 processStart: { _ in Date(timeIntervalSince1970: 0) }, roster: file)
        for (pid, session) in [(111, "s1"), (222, "s2")] {
            reading.ingest(path: try write(toolUse + "\n", to: "proj/\(session).jsonl"))
            try Data(recordJSON(pid: pid, session: session, status: "busy").utf8).write(to: folder.appendingPathComponent("\(pid).json"))
        }
        reading.readSessions()
        reading.publish()
        let published = expectation(description: "published")
        DispatchQueue.main.async { published.fulfill() }
        wait(for: [published], timeout: 2)
        let looks = reading.sessions.compactMap(\.look)
        XCTAssertEqual(looks.count, 2)
        XCTAssertNotEqual(looks.first, looks.last)
        XCTAssertEqual(Set(reading.looks.values.map { "\($0)" }), Set(looks.map { "\($0)" }))
        XCTAssertEqual(Roster.load(file).seats.mapValues(\.look), reading.looks)
    }

    // Claude Code writes its record's start a second or two after the kernel started the process.
    // The tab guard compares the kernel's own time, so that is the one a session's reach carries.
    func testReachCarriesTheKernelsStartTimeNotTheRecords() throws {
        let kernel = Date(timeIntervalSince1970: 1_791_787_806.5)   // the record says 1_791_787_807.982
        let folder = URL(fileURLWithPath: store.root).appendingPathComponent("records-reach")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let reading = AgentStore(root: URL(fileURLWithPath: store.root), sessions: folder,
                                 processStart: { $0 == 111 ? kernel : nil }, owner: { _ in nil })
        try Data(recordJSON(pid: 111, session: "s1", status: "busy").utf8).write(to: folder.appendingPathComponent("111.json"))
        reading.readSessions()
        reading.publish()
        let published = expectation(description: "published")
        DispatchQueue.main.async { published.fulfill() }
        wait(for: [published], timeout: 2)
        XCTAssertEqual(reading.reach["s1"]?.process, SessionProcess(pid: 111, startedAt: kernel))
    }

    // A prompt that opened since the last reading is seen at once: the record is read from disk.
    func testARecordIsReadFreshForWhetherItWaitsOnThePerson() throws {
        let folder = URL(fileURLWithPath: store.root).appendingPathComponent("records-fresh")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("111.json")
        XCTAssertFalse(AgentStore.recordWaitsOnPerson(pid: 111, sessions: folder.path))
        try Data(recordJSON(pid: 111, session: "s1", status: "waiting").utf8).write(to: file)
        XCTAssertTrue(AgentStore.recordWaitsOnPerson(pid: 111, sessions: folder.path))
        XCTAssertFalse(AgentStore.recordWaitsOnPerson(pid: 222, sessions: folder.path))
        try Data(recordJSON(pid: 111, session: "s1", status: "busy").utf8).write(to: file)
        XCTAssertFalse(AgentStore.recordWaitsOnPerson(pid: 111, sessions: folder.path))
        try Data("{\"pid\":111,".utf8).write(to: file)
        XCTAssertFalse(AgentStore.recordWaitsOnPerson(pid: 111, sessions: folder.path))
    }

    // An agent starting to wait on the person is the one event the bar must not let slip by.
    // It is told by which sessions wait and how many rows in each, not by one count for all:
    // a session answered as another starts to wait leaves that count as it was.
    func testTheBarMarksTheMomentSomeoneStartsToWait() {
        XCTAssertTrue(WaitWatch.arrived(from: [:], to: ["a": 1]))
        XCTAssertTrue(WaitWatch.arrived(from: ["a": 1], to: ["a": 1, "b": 1]))
        XCTAssertTrue(WaitWatch.arrived(from: ["a": 1], to: ["b": 1]))
        XCTAssertTrue(WaitWatch.arrived(from: ["a": 1], to: ["a": 2]))
        XCTAssertFalse(WaitWatch.arrived(from: ["a": 1, "b": 1], to: ["a": 1]))
        XCTAssertFalse(WaitWatch.arrived(from: ["a": 2], to: ["a": 1]))
        XCTAssertFalse(WaitWatch.arrived(from: ["a": 1], to: ["a": 1]))
        XCTAssertFalse(WaitWatch.arrived(from: ["a": 1], to: [:]))
        XCTAssertEqual(AgentStore.waiting([card("a", main: .needsYou, agents: [.working, .needsYou]), card("b", main: .quiet)]), ["a": 2])
        // A request is shown under the session's own row until its sub-agent's row is known,
        // and then under that one. The same wait in the same session: not a second arrival.
        let before = AgentStore.waiting([card("a", main: .needsYou, agents: [.working])])
        let after = AgentStore.waiting([card("a", main: .working, agents: [.needsYou])])
        XCTAssertFalse(WaitWatch.arrived(from: before, to: after))
    }

    // "Go to Superset" used to land on the app, and the person had to find the session among
    // its workspaces. Superset tells each terminal which workspace it is in, in one variable
    // of the process's environment, and opens a workspace from a link. That one variable is
    // read and nothing else of the environment, which holds secrets.
    func testASessionsSupersetWorkspaceIsReadFromItsProcessAndNothingElse() {
        // As the system hands a process's arguments over: how many, the program's path,
        // padding, the arguments, then the environment.
        func block(args: [String], env: [String]) -> [UInt8] {
            var bytes = withUnsafeBytes(of: Int32(args.count)) { Array($0) }
            bytes += Array("/usr/local/bin/claude".utf8) + [0, 0, 0]
            for item in args + env { bytes += Array(item.utf8) + [0] }
            return bytes + [0]
        }
        let id = "0123a4bc-5678-4d90-b1c2-d34e56789012"
        let buffer = block(args: ["claude", "--resume"], env: ["PATH=/bin", "SECRET_TOKEN=abc", "SUPERSET_WORKSPACE_ID=\(id)", "HOME=/Users/me"])
        XCTAssertEqual(AgentStore.environmentValue("SUPERSET_WORKSPACE_ID", inProcessArguments: buffer), id)
        XCTAssertNil(AgentStore.environmentValue("MISSING", inProcessArguments: buffer))
        // An argument that looks like the variable is not the environment.
        XCTAssertNil(AgentStore.environmentValue("SUPERSET_WORKSPACE_ID", inProcessArguments: block(args: ["claude", "SUPERSET_WORKSPACE_ID=other"], env: ["PATH=/bin"])))
        XCTAssertNil(AgentStore.environmentValue("X", inProcessArguments: []))
        XCTAssertNil(AgentStore.environmentValue("X", inProcessArguments: [9, 9]))
        // A count that cannot be right, or data that ends early: nothing, and nothing read past the end.
        var negative = buffer
        negative.replaceSubrange(0..<4, with: withUnsafeBytes(of: Int32(-1)) { Array($0) })
        XCTAssertNil(AgentStore.environmentValue("SUPERSET_WORKSPACE_ID", inProcessArguments: negative))
        var tooMany = buffer
        tooMany.replaceSubrange(0..<4, with: withUnsafeBytes(of: Int32(900)) { Array($0) })
        XCTAssertNil(AgentStore.environmentValue("SUPERSET_WORKSPACE_ID", inProcessArguments: tooMany))
        XCTAssertNil(AgentStore.environmentValue("SUPERSET_WORKSPACE_ID", inProcessArguments: Array(buffer.prefix(30))))
        // Only something that is an id makes a link: the value goes into an address.
        XCTAssertEqual(OwnerApp.supersetLink(workspace: id)?.absoluteString, "superset://v2-workspace/\(id)")
        XCTAssertNil(OwnerApp.supersetLink(workspace: "../settings"))
        XCTAssertNil(OwnerApp.supersetLink(workspace: "0123a4bc-5678-4d90-b1c2-d34e56789012/x"))
        XCTAssertNil(OwnerApp.supersetLink(workspace: ""))
        // What is left of the buffer after the environment is padding: read as the end.
        XCTAssertEqual(AgentStore.environmentValue("SUPERSET_WORKSPACE_ID", inProcessArguments: buffer + [UInt8](repeating: 0, count: 64)), id)
        XCTAssertNil(AgentStore.environmentValue("MISSING", inProcessArguments: buffer + [UInt8](repeating: 0, count: 64)))
        // Out of a real process, this one: one variable that is no secret, and none for a process that is not there.
        XCTAssertEqual(AgentStore.environmentValue("HOME", ofProcess: getpid()), ProcessInfo.processInfo.environment["HOME"])
        XCTAssertNil(AgentStore.environmentValue("HOME", ofProcess: 99_999_999))
        // The address is handed to the app the session runs in and to no other: any app can
        // tell the system it opens addresses of this kind.
        let superset = URL(fileURLWithPath: "/Applications/Superset.app")
        XCTAssertTrue(OwnerApp.isOwn(opener: URL(fileURLWithPath: "/Applications/Superset.app/"), of: superset))
        XCTAssertFalse(OwnerApp.isOwn(opener: URL(fileURLWithPath: "/Applications/Other.app"), of: superset))
        XCTAssertFalse(OwnerApp.isOwn(opener: nil, of: superset))
    }

    // The first row that needs the person, in the order the list is drawn: where every way
    // into the panel leads, by pointer or by keys.
    func testTheListKnowsItsFirstRowThatNeedsThePerson() {
        let list = SessionList(cards: [card("a", main: .working, agents: [.quiet]), card("b", main: .working, agents: [.working, .needsYou]), card("c", main: .needsYou)], folded: [])
        XCTAssertEqual(list.firstWaiting?.row.id, "b/agent1")
        XCTAssertEqual(list.firstWaiting?.card.id, "b")
        XCTAssertNil(SessionList(cards: [card("a", main: .quiet)], folded: [card("z", main: .done)]).firstWaiting)
        // To the card when it is the session's own row that waits, to the row itself when a
        // sub-agent's: that one can sit far down a tall card.
        XCTAssertEqual(ScrollTarget.to(list.firstWaiting!.row, on: list.firstWaiting!.card), .row("b/agent1"))
        let own = SessionList(cards: [card("c", main: .needsYou, agents: [.needsYou])], folded: []).firstWaiting!
        XCTAssertEqual(ScrollTarget.to(own.row, on: own.card), .card("c"))
    }

    // What the band at the bottom counts as waiting below: every such row of a card that
    // starts under the edge, and the rows under the edge of a card that starts above it.
    func testTheBandCountsEveryRowThatWaitsBelowTheEdge() {
        let cards = [card("a", main: .working, agents: [.needsYou, .needsYou]), card("b", main: .needsYou, agents: [.needsYou, .working])]
        XCTAssertEqual(AgentStore.waitingBelow(cards, cards: ["b"], rows: ["a/agent1", "b/agent0"]).map(\.id), ["a/agent1", "b/main", "b/agent0"])
        XCTAssertEqual(AgentStore.waitingBelow(cards, cards: [], rows: []).map(\.id), [])
        // A row that no longer waits is not counted, whatever was last said of where it sits.
        XCTAssertEqual(AgentStore.waitingBelow([card("a", main: .working, agents: [.working])], cards: [], rows: ["a/agent0"]).map(\.id), [])
    }

    // The bar goes on beating until the person has looked: opening the panel is saying "seen".
    // After that the red count stays, and only one more agent starting to wait beats again.
    func testTheBarStopsBeatingOnceThePanelHasBeenOpened() {
        var watch = WaitWatch()
        // Someone starts to wait with the panel shut, which has been opened four times so far.
        watch.arrived(looks: 4, lookingNow: false)
        XCTAssertFalse(watch.seen(looks: 4))
        XCTAssertTrue(watch.seen(looks: 5))
        // Another starts to wait: unseen again until the next opening.
        watch.arrived(looks: 5, lookingNow: false)
        XCTAssertFalse(watch.seen(looks: 5))
        XCTAssertTrue(watch.seen(looks: 6))
        // The pointer is on the open panel as the wait begins: it is seen as it happens.
        watch.arrived(looks: 6, lookingNow: true)
        XCTAssertTrue(watch.seen(looks: 6))
    }

    // "On the open panel" has to mean an opening that has lasted. One that began half a second
    // ago may be a pointer on its way to a menu, and that opening may never count as a look.
    // A pinned panel is open with nobody at it: it is looked at when the pointer rests in it.
    func testAWaitIsSeenAsItBeginsOnlyByAnOpeningThatHasLasted() {
        XCTAssertFalse(WaitWatch.looking(openFor: 0.5, pinned: false, inView: true))
        XCTAssertTrue(WaitWatch.looking(openFor: 1, pinned: false, inView: true))
        XCTAssertFalse(WaitWatch.looking(openFor: 30, pinned: true, inView: true))
        XCTAssertFalse(WaitWatch.looking(openFor: nil, pinned: false, inView: true))
        // Open on the settings, or with the row that waits past the edge, the person is not
        // looking at it: the bar still has to say so once the panel has shut.
        XCTAssertFalse(WaitWatch.looking(openFor: 30, pinned: false, inView: false))
    }

    // The bar's mascot stands for work that is moving, not for a row that has gone silent.
    func testTheBarsMascotPrefersARowThatMovedLately() {
        func row(_ id: String, silentFor: TimeInterval) -> AgentRow {
            AgentRow(id: id, info: AgentInfo(), status: .working, elapsed: 0, quietFor: silentFor)
        }
        func card(_ rows: [AgentRow]) -> SessionCard {
            SessionCard(id: "c", project: "c", branch: "", main: rows[0], agents: Array(rows.dropFirst()), startedAt: now)
        }
        XCTAssertEqual(AgentStore.lead([card([row("stalled", silentFor: 900), row("moving", silentFor: 3)])])?.id, "moving")
        // All of them silent: one still stands for them.
        XCTAssertEqual(AgentStore.lead([card([row("stalled", silentFor: 900)])])?.id, "stalled")
        XCTAssertTrue(row("stalled", silentFor: 900).isStalled)
        XCTAssertFalse(row("moving", silentFor: 3).isStalled)
    }

    // The hint under a quiet row says the same thing each time. Once in the list is enough.
    func testOnlyTheFirstQuietRowOfTheListCarriesTheHint() {
        func list(_ cards: [SessionCard]) -> SessionList { SessionList(cards: cards, folded: []) }
        XCTAssertEqual(list([card("a", main: .working, agents: [.quiet, .working, .quiet])]).hintRow, "a/agent0")
        XCTAssertEqual(list([card("a", main: .quiet, agents: [.quiet])]).hintRow, "a/main")
        XCTAssertNil(list([card("a", main: .working, agents: [.working])]).hintRow)
        let two = list([card("a", main: .working, agents: [.quiet]), card("b", main: .quiet)])
        XCTAssertEqual(two.hintRow, "a/agent0")
    }

    // Claude Code calls a session busy through a long command and through a hung one alike.
    // Ten silent minutes from every row it calls busy, and the panel shows those rows as quiet:
    // no activity is all that is known, and "quiet" is the one word the panel has for that.
    // One row at work is enough to say the session moves: a main agent is silent as a matter
    // of course while the agents it started work.
    func testASessionWhoseBusyRowsHaveAllGoneSilentIsShownAsQuiet() {
        func row(_ id: String, _ status: AgentStatus, silentFor: TimeInterval) -> AgentRow {
            AgentRow(id: id, info: AgentInfo(), status: status, elapsed: 0, quietFor: silentFor)
        }
        func card(_ rows: [AgentRow]) -> SessionCard {
            SessionCard(id: "c", project: "c", branch: "", main: rows[0], agents: Array(rows.dropFirst()), startedAt: now)
        }
        let stuck = card([row("main", .working, silentFor: 900), row("sub", .working, silentFor: 600)])
        XCTAssertTrue(stuck.isStuck)
        XCTAssertFalse(card([row("main", .working, silentFor: 900), row("sub", .working, silentFor: 30)]).isStuck)
        XCTAssertFalse(card([row("main", .working, silentFor: 599)]).isStuck)
        XCTAssertFalse(card([row("main", .done, silentFor: 0)]).isStuck)
        XCTAssertEqual(stuck.asShown.rows.map(\.status), [.quiet, .quiet])
        // How long it has been stays with the row.
        XCTAssertEqual(stuck.asShown.rows.map(\.quietFor), [900, 600])
        // And what is known of why: Claude Code calls it busy. The line under it says that,
        // not that it may be waiting for the person.
        XCTAssertEqual(stuck.asShown.rows.map(\.calledBusy), [true, true])
        XCTAssertEqual(stuck.rows.map(\.calledBusy), [false, false])
        let moving = card([row("main", .working, silentFor: 900), row("sub", .working, silentFor: 30)])
        XCTAssertEqual(moving.asShown, moving)
        // And so everywhere that counts: the bar, its dot, the hide button.
        XCTAssertEqual(AgentStore.barState([stuck.asShown]), .quiet(2))
        XCTAssertEqual(AgentStore.flag([stuck.asShown]), .quiet)
        XCTAssertTrue(stuck.asShown.canHide)
    }

    func testAMainAgentThatEndedIsAwakeWhileItsAgentsWork() {
        XCTAssertEqual(card("a", main: .done, agents: [.working, .done, .working]).workingAfterMain, 2)
        XCTAssertEqual(card("a", main: .done, agents: [.quiet, .needsYou, .done]).workingAfterMain, 0)
        XCTAssertEqual(card("a", main: .working, agents: [.working]).workingAfterMain, 0)
        XCTAssertEqual(card("a", main: nil, agents: [.working]).workingAfterMain, 0)
    }

    func testClassify() {
        let root = "/r"
        XCTAssertEqual(AgentStore.classify("/r/proj/abc.jsonl", root: root), .main(session: "/r/proj/abc"))
        XCTAssertEqual(AgentStore.classify("/r/proj/abc/subagents/agent-a1.jsonl", root: root), .sub(session: "/r/proj/abc"))
        XCTAssertEqual(AgentStore.classify("/r/proj/abc/subagents/workflows/wf_1/agent-a2.jsonl", root: root), .sub(session: "/r/proj/abc"))
        XCTAssertNil(AgentStore.classify("/r/proj/abc/subagents/workflows/wf_1/journal.jsonl", root: root))
        XCTAssertNil(AgentStore.classify("/r/proj/abc/tool-results/out.jsonl", root: root))
        XCTAssertNil(AgentStore.classify("/r/proj/abc/subagents/agent-a1.meta.json", root: root))
        XCTAssertNil(AgentStore.classify("/r/top.jsonl", root: root))
        XCTAssertNil(AgentStore.classify("/elsewhere/proj/abc.jsonl", root: root))
    }

    // FSEvents can leave out an append that follows another closely, and a session that then waits
    // on the person writes nothing more to cause another event. The once-a-second pass reads it.
    func testAnAppendThatWasNeverReportedIsReadOnTheNextPass() throws {
        let relative = "proj/s1.jsonl"
        let path = try write(toolUse + "\n", to: relative)
        store.ingest(path: path)
        XCTAssertEqual(store.files[path]?.info.steps, 1)
        try write(toolUse + "\n", to: relative, append: true)
        XCTAssertEqual(store.files[path]?.info.steps, 1)
        store.refresh(now: Date())
        XCTAssertEqual(store.files[path]?.info.steps, 2)
    }

    func testIngestReadsOnlyCompleteLinesAndResumes() throws {
        let relative = "proj/s1/subagents/agent-a1.jsonl"
        let path = try write(String(toolUse.prefix(60)), to: relative)
        store.ingest(path: path)
        XCTAssertEqual(store.files[path]?.info.steps, 0)
        try write(String(toolUse.dropFirst(60)) + "\n", to: relative, append: true)
        store.ingest(path: path)
        XCTAssertEqual(store.files[path]?.info.steps, 1)
        store.ingest(path: path)
        XCTAssertEqual(store.files[path]?.info.steps, 1)
    }

    func testIngestLoadsMetaAndParentTranscript() throws {
        try write(toolUse + "\n", to: "proj/s1.jsonl")
        let path = try write(toolUse + "\n", to: "proj/s1/subagents/agent-a1.jsonl")
        try write(#"{"agentType":"Explore","description":"Find auth files"}"#, to: "proj/s1/subagents/agent-a1.meta.json")
        store.ingest(path: path)
        XCTAssertEqual(store.files[path]?.info.type, "Explore")
        XCTAssertEqual(store.files[path]?.info.task, "Find auth files")
        XCTAssertEqual(store.files[store.root + "/proj/s1.jsonl"]?.info.type, "main")
    }

    func testIngestRereadsTruncatedFileAndForgetsDeletedFile() throws {
        let relative = "proj/s1/subagents/agent-a1.jsonl"
        let path = try write(toolUse + "\n" + toolUse + "\n", to: relative)
        store.ingest(path: path)
        XCTAssertEqual(store.files[path]?.info.steps, 2)
        try write(toolUse + "\n", to: relative)
        store.ingest(path: path)
        XCTAssertEqual(store.files[path]?.info.steps, 1)
        try FileManager.default.removeItem(atPath: path)
        store.ingest(path: path)
        XCTAssertNil(store.files[path])
    }

    func testCardKeepsSilentParentWhileSubagentIsActive() {
        let files = [
            "/r/p/s1.jsonl": tracked("/r/p/s1", main: true, idle: 3600),
            "/r/p/s1/subagents/agent-a.jsonl": tracked("/r/p/s1", idle: 5),
        ]
        let cards = AgentStore.cards(from: files, now: now)
        XCTAssertEqual(cards.count, 1)
        XCTAssertNotNil(cards[0].main)
        XCTAssertEqual(cards[0].project, "s1")
        XCTAssertEqual(cards[0].agents.map(\.id), ["/r/p/s1/subagents/agent-a.jsonl"])
    }

    func testCardsHideStaleAgentsAndDeadSessions() {
        let files = [
            "/r/p/s1.jsonl": tracked("/r/p/s1", main: true, idle: 5),
            "/r/p/s1/subagents/agent-old.jsonl": tracked("/r/p/s1", idle: 601),
            "/r/p/s1/subagents/agent-new.jsonl": tracked("/r/p/s1", idle: 599),
            "/r/p/s2.jsonl": tracked("/r/p/s2", main: true, idle: 700),
            "/r/p/s2/subagents/agent-x.jsonl": tracked("/r/p/s2", idle: 700),
        ]
        let cards = AgentStore.cards(from: files, now: now)
        XCTAssertEqual(cards.map(\.id), ["/r/p/s1"])
        XCTAssertEqual(cards[0].agents.map(\.id), ["/r/p/s1/subagents/agent-new.jsonl"])
    }

    // A housekeeping line touched the file a moment ago; the last message was nine hours back.
    func testSessionWithOldConversationIsHiddenThoughItsFileJustChanged() {
        var stale = tracked("/r/p/s1", main: true, idle: 5)
        stale.info.lastActivity = now.addingTimeInterval(-9 * 3600)
        var live = tracked("/r/p/s2", main: true, idle: 5)
        live.info.lastActivity = now.addingTimeInterval(-30)
        let cards = AgentStore.cards(from: ["/r/p/s1.jsonl": stale, "/r/p/s2.jsonl": live], now: now)
        XCTAssertEqual(cards.map(\.id), ["/r/p/s2"])
    }

    func testStatusCountsFromTheLastConversationLineNotTheLastWrite() {
        var idle = tracked("/r/p/s1", main: true, idle: 1)
        idle.info.turnEnded = true
        idle.info.lastActivity = now.addingTimeInterval(-300)
        let cards = AgentStore.cards(from: ["/r/p/s1.jsonl": idle], now: now)
        XCTAssertEqual(cards.first?.main?.status, .done)
    }

    // Hooks, plugins and reviewers start their own headless sessions through the SDK. Nobody asked
    // for those agents by hand, and they outnumber the real ones.
    func testCardsHideHeadlessSdkSessions() {
        var headlessMain = tracked("/r/p/s1", main: true, idle: 5)
        headlessMain.info.entrypoint = "sdk-py"
        var headlessSub = tracked("/r/p/s1", idle: 5)
        headlessSub.info.entrypoint = "sdk-py"
        var interactive = tracked("/r/p/s2", main: true, idle: 5)
        interactive.info.entrypoint = "cli"
        let files = [
            "/r/p/s1.jsonl": headlessMain,
            "/r/p/s1/subagents/agent-a.jsonl": headlessSub,
            "/r/p/s2.jsonl": interactive,
        ]
        XCTAssertEqual(AgentStore.cards(from: files, now: now).map(\.id), ["/r/p/s2"])
    }

    // Sorting by latest activity made cards swap places every time a file moved.
    func testCardsKeepAStableOrderByNewestSessionStart() {
        let files = [
            "/r/p/s1.jsonl": tracked("/r/p/s1", main: true, idle: 5, started: 1000),
            "/r/p/s2.jsonl": tracked("/r/p/s2", main: true, idle: 50, started: 100),
            "/r/p/s1/subagents/agent-b.jsonl": tracked("/r/p/s1", idle: 60, started: 100),
            "/r/p/s1/subagents/agent-a.jsonl": tracked("/r/p/s1", idle: 70, started: 300),
        ]
        let cards = AgentStore.cards(from: files, now: now)
        XCTAssertEqual(cards.map(\.id), ["/r/p/s2", "/r/p/s1"])
        XCTAssertEqual(cards[1].agents.map(\.id), ["/r/p/s1/subagents/agent-a.jsonl", "/r/p/s1/subagents/agent-b.jsonl"])
    }

    func testIngestRetriesMetaThatWasHalfWritten() throws {
        let path = try write(toolUse + "\n", to: "proj/s1/subagents/agent-a1.jsonl")
        try write(#"{"agentType":"Expl"#, to: "proj/s1/subagents/agent-a1.meta.json")
        store.ingest(path: path)
        XCTAssertEqual(store.files[path]?.info.type, "agent")
        try write(#"{"agentType":"Explore","description":"Find auth files"}"#, to: "proj/s1/subagents/agent-a1.meta.json")
        store.ingest(path: path)
        XCTAssertEqual(store.files[path]?.info.type, "Explore")
    }

    // Losing the read position meant re-reading a whole transcript, up to 100 MB, when it resumed.
    func testForgetKeepsReadPositionsThroughAQuietSpell() throws {
        let path = try write(toolUse + "\n", to: "proj/s1.jsonl")
        store.ingest(path: path)
        let modified = try XCTUnwrap(store.files[path]?.modified)
        let offset = try XCTUnwrap(store.files[path]?.offset)
        store.forget(now: modified.addingTimeInterval(11 * 60))
        XCTAssertEqual(store.files[path]?.offset, offset)
        store.forget(now: modified.addingTimeInterval(25 * 3600))
        XCTAssertNil(store.files[path])
    }

    // Forgetting a long-silent parent while its subagent still writes would re-read it on every event.
    func testForgetKeepsAnOldParentWhileItsSubagentIsLive() throws {
        let parent = try write(toolUse + "\n", to: "proj/s1.jsonl")
        let old = Date().addingTimeInterval(-30 * 3600)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: parent)
        let child = try write(toolUse + "\n", to: "proj/s1/subagents/agent-a1.jsonl")
        store.ingest(path: child)
        store.forget(now: Date())
        XCTAssertNotNil(store.files[parent])
        XCTAssertNotNil(store.files[child])
    }

    func testNeedsRescanWhenTheSystemDroppedEvents() {
        let modified = FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        let mustScan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        let dropped = FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagMustScanSubDirs)
        XCTAssertFalse(AgentStore.needsRescan([]))
        XCTAssertFalse(AgentStore.needsRescan([modified]))
        XCTAssertTrue(AgentStore.needsRescan([modified, mustScan]))
        XCTAssertTrue(AgentStore.needsRescan([dropped]))
    }

    // Thinking and long commands leave the transcript silent; Claude Code's record says the session is at work.
    func testABusyRecordKeepsEveryUnfinishedRowOfItsSessionWorking() {
        var finished = tracked("/r/p/s1", idle: 300)
        finished.info.turnEnded = true
        let files = [
            "/r/p/s1.jsonl": spoken(tracked("/r/p/s1", main: true, idle: 300)),
            "/r/p/s1/subagents/agent-a.jsonl": tracked("/r/p/s1", idle: 300),
            "/r/p/s1/subagents/agent-b.jsonl": finished,
            "/r/p/s2.jsonl": tracked("/r/p/s2", main: true, idle: 300),
        ]
        let cards = AgentStore.cards(from: files, now: now, states: ["s1": state(.busy)])
        let s1 = cards.first { $0.id == "/r/p/s1" }
        XCTAssertEqual(s1?.main?.status, .working)
        XCTAssertEqual(s1?.agents.map(\.status), [.working, .done])
        // No record for s2: nothing is known, so it reads quiet.
        XCTAssertEqual(cards.first { $0.id == "/r/p/s2" }?.main?.status, .quiet)
    }

    // The record says the person is being waited on, not which agent waits: only the main row takes it.
    func testAWaitingRecordFlagsTheMainRowAndCountsFromWhenTheWaitBegan() {
        var ended = spoken(tracked("/r/p/s1", main: true, idle: 900))
        ended.info.turnEnded = true
        let files = [
            "/r/p/s1.jsonl": ended,
            "/r/p/s1/subagents/agent-a.jsonl": tracked("/r/p/s1", idle: 300),
        ]
        func waiting(since: TimeInterval?) -> SessionCard? {
            AgentStore.cards(from: files, now: now, states: ["s1": state(.waiting, since: since)]).first
        }
        XCTAssertEqual(waiting(since: 45)?.main?.status, .needsYou)
        XCTAssertEqual(waiting(since: 45)?.main?.quietFor ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(waiting(since: 45)?.agents.first?.status, .quiet)
        XCTAssertEqual(waiting(since: 45)?.agents.first?.quietFor ?? 0, 300, accuracy: 0.001)
        // No time in the record: count from the last transcript line.
        XCTAssertEqual(waiting(since: nil)?.main?.quietFor ?? 0, 900, accuracy: 0.001)
        // A time ahead of the clock: never negative.
        XCTAssertEqual(waiting(since: -30)?.main?.quietFor ?? -1, 0, accuracy: 0.001)
    }

    // A long command, or a prompt nobody has seen yet, must not make the session drop off the panel.
    func testASessionStaysListedWhileItsRecordSaysBusyOrWaiting() {
        let files = [
            "/r/p/s1.jsonl": spoken(tracked("/r/p/s1", main: true, idle: 7200)),
            "/r/p/s1/subagents/agent-a.jsonl": tracked("/r/p/s1", idle: 7200),
        ]
        func listed(_ states: [String: SessionState]) -> [String] {
            AgentStore.cards(from: files, now: now, states: states).flatMap { $0.rows.map(\.id) }
        }
        // Sub-agent rows still go by their own age.
        XCTAssertEqual(listed(["s1": state(.busy)]), ["/r/p/s1.jsonl"])
        XCTAssertEqual(listed(["s1": state(.waiting)]), ["/r/p/s1.jsonl"])
        XCTAssertEqual(listed(["s1": state(.idle)]), [])
        XCTAssertEqual(listed([:]), [])
        XCTAssertEqual(listed(["other": state(.busy)]), [])
    }

    // Claude Code can leave a stub with the same session id in a second project folder. The record
    // speaks for the transcript that carries the conversation, or a ghost card would sit there working.
    func testARecordSpeaksForOneTranscriptOfItsSessionId() {
        var real = tracked("/r/p/s1", main: true, idle: 300)
        real.info.lastActivity = now.addingTimeInterval(-300)
        let stub = tracked("/r/q/s1", main: true, idle: 700, spoken: false)
        let files = ["/r/p/s1.jsonl": real, "/r/q/s1.jsonl": stub]
        let cards = AgentStore.cards(from: files, now: now, states: ["s1": state(.busy)])
        XCTAssertEqual(cards.map(\.id), ["/r/p/s1"])
        XCTAssertEqual(cards.first?.main?.status, .working)
        XCTAssertEqual(AgentStore.claims(["s1": state(.busy)], files: files), ["/r/p/s1": state(.busy)])
        XCTAssertEqual(AgentStore.claims([:], files: files), [:])
    }

    func testSessionRecordsLiveBesideTheTranscriptFolder() {
        XCTAssertEqual(AgentStore(root: URL(fileURLWithPath: "/nowhere/.claude/projects")).sessionsFolder, "/nowhere/.claude/sessions")
    }

    func testProcessStartTimeComesFromTheSystem() {
        let mine = AgentStore.startTime(ofProcess: getpid())
        XCTAssertNotNil(mine)
        XCTAssertLessThanOrEqual(mine ?? .distantFuture, Date())
        XCTAssertNil(AgentStore.startTime(ofProcess: 999_999))
        XCTAssertNil(AgentStore.startTime(ofProcess: -5))
    }

    func testStoreReadsOnlyPidNamedRecordsOfLiveProcesses() throws {
        let (reading, folder) = try storeWithRecords(alive: [111, 333])
        func put(_ text: String, _ name: String) throws { try Data(text.utf8).write(to: folder.appendingPathComponent(name)) }
        try put(recordJSON(pid: 111, session: "s1", status: "busy"), "111.json")
        try put(recordJSON(pid: 222, session: "s2", status: "busy"), "222.json")     // its process is gone
        try put(recordJSON(pid: 333, session: "s3", status: "busy"), "notes.json")   // not a record's name
        try put(recordJSON(pid: 333, session: "s4", status: "busy"), "333.abc.key")  // a secret's name
        reading.readSessions()
        XCTAssertEqual(reading.states.keys.sorted(), ["s1"])
        XCTAssertEqual(reading.states["s1"]?.activity, .busy)

        // Claude Code rewrites a record in place: one caught empty or cut short keeps its last whole reading.
        try put("", "111.json")
        reading.readSessions()
        XCTAssertEqual(reading.states["s1"]?.activity, .busy)
        try put(#"{"pid":111,"sessionId":"s1","sta"#, "111.json")
        reading.readSessions()
        XCTAssertEqual(reading.states["s1"]?.activity, .busy)
        try put(recordJSON(pid: 111, session: "s1", status: "idle"), "111.json")
        reading.readSessions()
        XCTAssertEqual(reading.states["s1"]?.activity, .idle)

        // Claude Code removes the record when it exits: the session is idle from then on.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("111.json"))
        reading.readSessions()
        XCTAssertEqual(reading.states, ["s1": SessionState(activity: .idle)])
        reading.readSessions()
        XCTAssertEqual(reading.states, ["s1": SessionState(activity: .idle)])
        // Resumed, a record holds it again.
        try put(recordJSON(pid: 111, session: "s1", status: "busy"), "111.json")
        reading.readSessions()
        XCTAssertEqual(reading.states["s1"]?.activity, .busy)
    }

    // /clear mid-turn: the record moves to a new session id, and the old transcript ends on a
    // prompt nobody answers. It is over, not at work: the bar's mascot stood for it while the
    // terminal showed the new session's face.
    func testAClearedSessionIsDoneNotAtWork() throws {
        let (reading, folder) = try storeWithRecords(alive: [111])
        let path = try write(toolUse + "\n", to: "proj/s1.jsonl")
        reading.ingest(path: path)
        let aMinuteOn = try XCTUnwrap(reading.files[path]?.info.lastActivity).addingTimeInterval(60)
        let record = folder.appendingPathComponent("111.json")
        try Data(recordJSON(pid: 111, session: "s1", status: "busy").utf8).write(to: record)
        reading.readSessions()
        XCTAssertEqual(AgentStore.cards(from: reading.files, now: aMinuteOn, states: reading.states).first?.main?.status, .working)
        try Data(recordJSON(pid: 111, session: "s2", status: "idle").utf8).write(to: record)
        reading.readSessions()
        XCTAssertEqual(AgentStore.cards(from: reading.files, now: aMinuteOn, states: reading.states).first?.main?.status, .done)
    }

    // An older Claude Code writes no records: everything falls back to the transcript rules.
    func testStoreWithoutASessionsFolderHasNoStates() throws {
        let reading = AgentStore(root: URL(fileURLWithPath: store.root), sessions: URL(fileURLWithPath: store.root + "/no-such-folder"))
        reading.readSessions()
        XCTAssertEqual(reading.states, [:])
        let path = try write(toolUse + "\n", to: "proj/s1.jsonl")
        reading.ingest(path: path)
        let later = try XCTUnwrap(reading.files[path]?.info.lastActivity).addingTimeInterval(300)
        XCTAssertEqual(AgentStore.cards(from: reading.files, now: later, states: reading.states).first?.main?.status, .quiet)
    }

    func testALiveBusyRecordTurnsASilentTranscriptIntoWork() throws {
        let (reading, folder) = try storeWithRecords(alive: [111])
        let path = try write(toolUse + "\n", to: "proj/s1.jsonl")
        reading.ingest(path: path)
        let fiveMinutesOn = try XCTUnwrap(reading.files[path]?.info.lastActivity).addingTimeInterval(300)
        func mainStatus() -> AgentStatus? {
            reading.readSessions()
            return AgentStore.cards(from: reading.files, now: fiveMinutesOn, states: reading.states).first?.main?.status
        }
        XCTAssertEqual(mainStatus(), .quiet)
        let record = folder.appendingPathComponent("111.json")
        try Data(recordJSON(pid: 111, session: "s1", status: "busy").utf8).write(to: record)
        XCTAssertEqual(mainStatus(), .working)
        // Its Claude Code exited mid-turn: nothing runs it any more.
        try FileManager.default.removeItem(at: record)
        XCTAssertEqual(mainStatus(), .done)
    }

    // A transcript that never carried a conversation line cannot hold a session's record, even when
    // it is the only one the app has read: the real one may have been silent since before launch.
    func testAStubAloneDoesNotTakeItsSessionsRecord() {
        let files = ["/r/q/s1.jsonl": tracked("/r/q/s1", main: true, idle: 3 * 3600, spoken: false)]
        XCTAssertEqual(AgentStore.claims(["s1": state(.busy)], files: files), [:])
        XCTAssertEqual(AgentStore.cards(from: files, now: now, states: ["s1": state(.busy)]).count, 0)
    }

    // A tester put an empty file, a megabyte of noise, five million braces and two lines of
    // made-up JSON under the folder, each named like a transcript. The panel said "5 working"
    // and listed four cards called "Claude Code". A file with no conversation line is no agent.
    func testAFileWithNoConversationLineIsNotAnAgent() throws {
        try write("", to: "proj/a.jsonl")
        try write(String(repeating: "\u{FFFD}x\u{1B}", count: 2000) + "\n", to: "proj/b.jsonl")
        try write(String(repeating: "{", count: 100_000) + "\n", to: "proj/c.jsonl")
        try write(#"{"type":"message","text":"hello"}"# + "\n" + #"{"role":"assistant","content":"hi"}"# + "\n", to: "proj/d.jsonl")
        try FileManager.default.createDirectory(atPath: store.root + "/proj/e.jsonl", withIntermediateDirectories: true)
        let real = try write(toolUse + "\n", to: "proj/s1.jsonl")
        for name in ["a", "b", "c", "d", "e", "s1"] { store.ingest(path: store.root + "/proj/" + name + ".jsonl") }
        let moment = try XCTUnwrap(store.files[real]?.info.lastActivity).addingTimeInterval(5)
        // Read at the moment they were written, when their own time used to make them fresh.
        var files = store.files
        for path in files.keys where path != real { files[path]?.modified = moment }
        let cards = AgentStore.cards(from: files, now: moment)
        XCTAssertEqual(cards.map(\.id), [store.root + "/proj/s1"])
        XCTAssertEqual(AgentStore.count(.working, in: cards), 1)
        // A sub-agent that has spoken still has its card, whatever stands where its parent's
        // transcript should: the card is headed by the sub-agent then.
        let orphan = ["/r/p/s9.jsonl": tracked("/r/p/s9", main: true, idle: 5, spoken: false), "/r/p/s9/subagents/agent-a.jsonl": tracked("/r/p/s9", idle: 5)]
        let headed = AgentStore.cards(from: orphan, now: now).first
        XCTAssertNil(headed?.main)
        XCTAssertEqual(headed?.agents.count, 1)
    }

    // Only a read that lands mid-rewrite may lean on the reading before it. A record that stays
    // unreadable, or is whole but says something this app does not know, is no record.
    func testAReadingIsNotKeptOnceItsRecordStaysUnreadable() throws {
        let (reading, folder) = try storeWithRecords(alive: [111])
        func put(_ text: String) throws { try Data(text.utf8).write(to: folder.appendingPathComponent("111.json")) }
        func readFiveTimes() { for _ in 0..<5 { reading.readSessions() } }
        try put(recordJSON(pid: 111, session: "s1", status: "waiting"))
        reading.readSessions()
        XCTAssertEqual(reading.states["s1"]?.activity, .waiting)
        try put(recordJSON(pid: 111, session: "s1", status: "compacting"))
        readFiveTimes()
        XCTAssertEqual(reading.states, [:])
        // A whole reading counts again from the start.
        try put(recordJSON(pid: 111, session: "s1", status: "busy"))
        reading.readSessions()
        try put("")
        reading.readSessions()
        XCTAssertEqual(reading.states["s1"]?.activity, .busy)
        readFiveTimes()
        XCTAssertEqual(reading.states, [:])
        // A record caught missing is a session that ended, not one this app can't read.
        try put(recordJSON(pid: 111, session: "s1", status: "busy"))
        reading.readSessions()
        try FileManager.default.removeItem(at: folder.appendingPathComponent("111.json"))
        reading.readSessions()
        XCTAssertEqual(reading.states, ["s1": SessionState(activity: .idle)])
    }

    // A killed Claude Code leaves its record behind, and stays in the process table until its
    // parent collects it. It is not running.
    func testAProcessThatHasExitedHasNoStartTime() {
        var pid: pid_t = 0
        var arguments: [UnsafeMutablePointer<CChar>?] = [strdup("/usr/bin/true"), nil]
        defer { free(arguments[0]) }
        XCTAssertEqual(posix_spawn(&pid, "/usr/bin/true", nil, nil, &arguments, nil), 0)
        // Waits for the exit without collecting the child, which is what leaves it in the table.
        var exited = siginfo_t()
        XCTAssertEqual(waitid(P_PID, id_t(pid), &exited, WEXITED | WNOWAIT), 0)
        XCTAssertNil(AgentStore.startTime(ofProcess: pid))
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }

    private var job: BackgroundJob { BackgroundJob(id: "j", kind: .shell, name: "npm run dev", startedAt: now - 60, endsBy: nil) }

    func testACardWithJobsOutlivesVisibleForAndSaysSo() {
        var main = tracked("/p/s", main: true, idle: 3600)
        main.info.turnEnded = true
        XCTAssertTrue(AgentStore.cards(from: ["/p/s.jsonl": main], now: now).isEmpty)
        main.info.jobs = [job]
        let card = AgentStore.cards(from: ["/p/s.jsonl": main], now: now).first
        XCTAssertEqual(card?.jobs, [job])
        XCTAssertEqual(card?.onlyForJobs, true)
        XCTAssertEqual(card?.isIdle, true)
    }
    func testAFreshCardWithJobsIsNotOnlyForJobs() {
        var main = tracked("/p/s", main: true, idle: 60)
        main.info.turnEnded = true
        main.info.jobs = [job]
        XCTAssertEqual(AgentStore.cards(from: ["/p/s.jsonl": main], now: now).first?.onlyForJobs, false)
    }
    func testACardKnowsWhenItsSessionIsClosed() {
        let main = tracked("/p/s", main: true, idle: 60)
        XCTAssertEqual(AgentStore.cards(from: ["/p/s.jsonl": main], now: now, running: [:]).first?.closed, true)
        XCTAssertEqual(AgentStore.cards(from: ["/p/s.jsonl": main], now: now, running: ["s": now - 600]).first?.closed, false)
        XCTAssertEqual(AgentStore.cards(from: ["/p/s.jsonl": main], now: now).first?.closed, false)
    }
    func testASessionWithJobsIsNeitherFoldedNorHidden() {
        var busy = card("jobs", main: .done)
        busy.jobs = [job]
        let plain = card("plain", main: .done)
        for idle in [IdleSessions.fold, .hide] {
            let list = AgentStore.arrange([busy, plain], idle: idle)
            XCTAssertEqual(list.cards.map(\.id), ["jobs"], "\(idle)")
        }
    }
    func testAStuckCardKeepsItsJobs() {
        var stuck = SessionCard(id: "a", project: "a", branch: "",
                                main: AgentRow(id: "a/main", info: AgentInfo(), status: .working, elapsed: 0, quietFor: AgentStore.stuckAfter + 1),
                                agents: [], startedAt: now)
        stuck.jobs = [job]
        XCTAssertEqual(stuck.asShown.main?.status, .quiet)
        XCTAssertEqual(stuck.asShown.jobs, [job])
    }

    // Back while nobody looked: listed past the keep setting, for a day at most.
    func testAnUnseenHandBackOutstaysTheKeepSetting() {
        var sub = tracked("/r/p/s1", idle: 3600)
        sub.info.turnEnded = true
        sub.info.handedBackAt = sub.activity
        let files = ["/r/p/s1.jsonl": tracked("/r/p/s1", main: true, idle: 3600), "/r/p/s1/subagents/agent-a.jsonl": sub]
        XCTAssertEqual(AgentStore.visible(files, now: now).count, 2)
        // Seen: the keep setting counts from the look.
        var seen = files
        seen["/r/p/s1/subagents/agent-a.jsonl"]!.seenAt = now.addingTimeInterval(-60)
        XCTAssertEqual(AgentStore.visible(seen, now: now).count, 2)
        seen["/r/p/s1/subagents/agent-a.jsonl"]!.seenAt = now.addingTimeInterval(-700)
        XCTAssertTrue(AgentStore.visible(seen, now: now).isEmpty)
        // A day on, unseen or not, it goes.
        var old = files
        old["/r/p/s1/subagents/agent-a.jsonl"]!.info.handedBackAt = now.addingTimeInterval(-HandBack.hold - 1)
        XCTAssertTrue(AgentStore.visible(old, now: now).isEmpty)
    }

    func testAHandBackAfterTheLookAwaitsAnotherLook() {
        var info = AgentInfo()
        info.handedBackAt = now
        var row = AgentRow(id: "a", info: info, status: .done, elapsed: 0)
        XCTAssertTrue(row.awaitsLook)
        row.handBackSeenAt = now.addingTimeInterval(1)
        XCTAssertFalse(row.awaitsLook)
        // The lead continued it and it came back again.
        row.handBackSeenAt = now.addingTimeInterval(-1)
        XCTAssertTrue(row.awaitsLook)
        XCTAssertFalse(AgentRow(id: "b", info: AgentInfo(), status: .done, elapsed: 0).handsBack)
    }

    // Relaunching, or a wider keep setting rescanning old files, pops nothing up.
    func testAHandBackFromBeforeTheLaunchIsSeen() {
        var file = tracked("/r/p/s1", idle: 7200)
        file.info.handedBackAt = file.activity
        XCTAssertEqual(HandBack.seenBeforeLaunch(file, launchedAt: now).seenAt, file.info.handedBackAt)
        file.info.handedBackAt = now.addingTimeInterval(10)
        XCTAssertNil(HandBack.seenBeforeLaunch(file, launchedAt: now).seenAt)
    }

    func testASessionWithAnUnseenHandBackIsHeld() {
        var c = card("s1", main: .done, agents: [.done])
        var info = AgentInfo()
        info.handedBackAt = now
        c.agents[0] = AgentRow(id: c.agents[0].id, info: info, status: .done, elapsed: 0)
        XCTAssertEqual(HandBack.awaiting([c]), [c.agents[0].id])
        XCTAssertEqual(HandBack.holding([c], openedAt: nil), [AnswerStore.sessionID(of: c)])
        XCTAssertEqual(AgentStore.arrange([c], idle: .fold, keeping: HandBack.holding([c], openedAt: nil)).cards.count, 1)
    }

    // A box seen in this opening holds its card until the panel shuts: an idle card does not
    // fold into "N idle", or leave the list, under the person's eyes.
    func testABoxSeenInThisOpeningHoldsItsCardUntilTheShut() {
        var c = card("s1", main: .done, agents: [.done])
        var info = AgentInfo()
        info.handedBackAt = now.addingTimeInterval(-30)
        var row = AgentRow(id: c.agents[0].id, info: info, status: .done, elapsed: 0)
        row.handBackSeenAt = now
        c.agents[0] = row
        XCTAssertTrue(HandBack.awaiting([c]).isEmpty)
        let opened = now.addingTimeInterval(-1)
        XCTAssertEqual(AgentStore.arrange([c], idle: .fold, keeping: HandBack.holding([c], openedAt: opened)).cards.count, 1)
        XCTAssertEqual(AgentStore.arrange([c], idle: .hide, keeping: HandBack.holding([c], openedAt: opened)).cards.count, 1)
        XCTAssertEqual(AgentStore.arrange([c], idle: .fold, keeping: HandBack.holding([c], openedAt: now)).cards.count, 1)
        // Shut, or opened again after the look: the old rules.
        XCTAssertEqual(AgentStore.arrange([c], idle: .fold, keeping: HandBack.holding([c], openedAt: nil)).folded.count, 1)
        XCTAssertEqual(AgentStore.arrange([c], idle: .fold, keeping: HandBack.holding([c], openedAt: now.addingTimeInterval(60))).folded.count, 1)
    }

    // A lead's own turn ending is no hand-back: a session without sub-agents folds as it always did.
    func testALeadsEndedTurnHoldsNothing() {
        var c = card("s1", main: .done)
        var info = AgentInfo()
        info.handedBackAt = now
        c.main = AgentRow(id: c.main!.id, info: info, status: .done, elapsed: 0)
        XCTAssertEqual(HandBack.awaiting([c]), [])
        XCTAssertEqual(HandBack.holding([c], openedAt: nil), [])
        XCTAssertEqual(AgentStore.arrange([c], idle: .fold, keeping: HandBack.holding([c], openedAt: nil)).folded.count, 1)
    }

    // A day on, an unseen hand-back counts as seen, though its card is listed for other reasons.
    func testADayOldHandBackNoLongerAwaitsALook() {
        var sub = tracked("/r/p/s1", idle: 60)
        sub.info.turnEnded = true
        sub.info.handedBackAt = now.addingTimeInterval(-HandBack.hold - 60)
        let files = ["/r/p/s1.jsonl": tracked("/r/p/s1", main: true, idle: 30), "/r/p/s1/subagents/agent-a.jsonl": sub]
        let rows = AgentStore.cards(from: files, now: now, home: "/Users/me").flatMap(\.agents)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].handsBack)
        XCTAssertFalse(rows[0].awaitsLook)
    }

    // A resumed sub-agent that died mid-turn is not held by its earlier hand-back.
    func testAMidTurnResumedAgentIsNotHeldByAnOldHandBack() {
        var sub = tracked("/r/p/s1", idle: 3 * 3600)
        sub.info.handedBackAt = sub.activity
        let files = ["/r/p/s1.jsonl": tracked("/r/p/s1", main: true, idle: 3 * 3600), "/r/p/s1/subagents/agent-a.jsonl": sub]
        XCTAssertTrue(AgentStore.visible(files, now: now).isEmpty)
    }

    // The cap holds for a hand-back that came again after a look.
    func testADayOldSecondHandBackNoLongerAwaitsALook() {
        var sub = tracked("/r/p/s1", idle: 60)
        sub.info.turnEnded = true
        sub.info.handedBackAt = now.addingTimeInterval(-HandBack.hold - 60)
        sub.seenAt = now.addingTimeInterval(-HandBack.hold - 120)
        let files = ["/r/p/s1.jsonl": tracked("/r/p/s1", main: true, idle: 30), "/r/p/s1/subagents/agent-a.jsonl": sub]
        let rows = AgentStore.cards(from: files, now: now, home: "/Users/me").flatMap(\.agents)
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].awaitsLook)
    }

    private func subRows(_ files: [String: TrackedFile], running: [String: Date]? = nil, states: [String: SessionState] = [:]) -> [AgentRow] {
        AgentStore.cards(from: files, now: now, states: states, home: "/Users/me", running: running).flatMap(\.agents)
    }
    private let subPath = "/r/p/s1/subagents/agent-a.jsonl"
    /// A sub-agent that ended its turn while its job runs on, and the lead's file with Claude Code's word that it waits.
    private func waitingFiles(idle: TimeInterval = 1200) -> [String: TrackedFile] {
        var sub = tracked("/r/p/s1", idle: idle, started: idle + 300)
        sub.info.turnEnded = true
        sub.info.handedBack = "The sleep runs in the background. I'll reply once it ends."
        sub.info.handedBackAt = sub.activity
        sub.info.jobs = [BackgroundJob(id: "j", kind: .shell, name: "npm run dev", startedAt: sub.activity - 1, endsBy: nil)]
        var main = tracked("/r/p/s1", main: true, idle: idle)
        main.info.waitingAgents = ["a": sub.activity + 0.2]
        return ["/r/p/s1.jsonl": main, subPath: sub]
    }

    // Claude Code said so: it ended its turn to wait on work of its own, and wakes when that ends.
    func testASubAgentClaudeCodeSaysWaitsIsAtWork() {
        let files = waitingFiles()
        let row = subRows(files).first
        XCTAssertEqual(row?.status, .working)
        XCTAssertEqual(row?.step, "Waiting on npm run dev")
        XCTAssertEqual(row?.activity, .running)
        XCTAssertEqual(row?.isStalled, false)
        XCTAssertEqual(row?.handsBack, false)
        XCTAssertEqual(row?.elapsed, 1500)
        // Its job's end already read, or its start never: what it waits on goes unnamed.
        var unnamed = files
        unnamed[subPath]!.info.jobs = []
        XCTAssertEqual(subRows(unnamed).first?.step, "Waiting on its background work")
    }

    // Woken by its work's end, it goes by the usual rules and its own step, but its interim words
    // never pass for a hand-back: not done until it answers.
    func testAWokenSubAgentIsNotDoneUntilItAnswers() {
        var woken = waitingFiles()
        woken[subPath]!.info.turnEnded = false
        woken[subPath]!.info.lastStep = "Read cart.ts"
        woken[subPath]!.info.lastActivity = now.addingTimeInterval(-30)
        // The lead's record says idle, which would call a row silent ten seconds done.
        let idle = ["s1": SessionState(activity: .idle)]
        XCTAssertEqual(subRows(woken, states: idle).first?.status, .working)
        XCTAssertEqual(subRows(woken).first?.step, "Read cart.ts")
        woken[subPath]!.info.lastActivity = now.addingTimeInterval(-200)
        XCTAssertEqual(subRows(woken).first?.status, .quiet)
        woken[subPath]!.info.asking = true
        XCTAssertEqual(subRows(woken).first?.status, .needsYou)
    }

    func testASubAgentStopsWaitingOnceItIsBack() {
        // Claude Code said it finished: what it said is its hand-back.
        var finished = waitingFiles()
        finished["/r/p/s1.jsonl"]!.info.waitingAgents = [:]
        XCTAssertEqual(subRows(finished).first?.status, .done)
        XCTAssertEqual(subRows(finished).first?.handsBack, true)
        // It answered after the notice: back, whether or not the next notice was read.
        var answered = waitingFiles()
        answered[subPath]!.info.handedBackAt = answered[subPath]!.activity + 1
        XCTAssertEqual(subRows(answered).first?.status, .done)
        // Thirty minutes on, the work is taken for something left running on purpose.
        XCTAssertEqual(subRows(waitingFiles(idle: BackgroundJobs.longAfter + 60)).first?.status, .done)
        // A closed session wakes nobody.
        XCTAssertEqual(subRows(waitingFiles(), running: [:]).first?.status, .done)
        XCTAssertEqual(subRows(waitingFiles(), running: ["s1": now - 3600]).first?.status, .working)
    }

    // Still waiting past the keep setting, its interim words seen before the launch: it stays listed.
    func testASubAgentWaitingOutstaysTheKeepSetting() {
        var files = waitingFiles()
        files[subPath]!.seenAt = files[subPath]!.activity
        XCTAssertEqual(subRows(files).map(\.status), [.working])
    }

    // A job the lead started is the lead's: a finished sub-agent beside it has handed back.
    func testAJobOfTheLeadKeepsNoSubAgentWaiting() {
        var main = tracked("/r/p/s1", main: true, idle: 60)
        main.info.jobs = [job]
        var sub = tracked("/r/p/s1", idle: 60)
        sub.info.turnEnded = true
        sub.info.handedBackAt = sub.activity
        let files = ["/r/p/s1.jsonl": main, "/r/p/s1/subagents/agent-a.jsonl": sub]
        let row = AgentStore.cards(from: files, now: now, home: "/Users/me").flatMap(\.agents).first
        XCTAssertEqual(row?.status, .done)
        XCTAssertNil(row?.waitingOn)
    }
}
