import Combine
import XCTest
@testable import AgentValley

final class AnswerStoreTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var store: AnswerStore!
    /// Every body handed back to a hook, in order. nil is "no decision".
    private var replies: [Data?] = []
    private var home: URL!

    override func setUpWithError() throws {
        home = try shortTempFolder()
        store = AnswerStore(directory: home.appendingPathComponent("AV"), now: { [unowned self] in self.clock })
    }

    override func tearDown() {
        store.setEnabled(false)
        try? FileManager.default.removeItem(at: home)
    }

    private func ask(_ command: String = "ls", tool: String = "Bash", session: String = "/r/p/s1", agent: String? = nil) -> Ask {
        let input: [String: Any] = tool == "Bash" ? ["command": command] : ["questions": [["question": command, "multiSelect": false, "options": [["label": "Red"], ["label": "Blue"]]]]]
        var hook: [String: Any] = ["tool_name": tool, "tool_input": input, "transcript_path": session + ".jsonl"]
        hook["agent_id"] = agent
        return Ask(hookInput: try! JSONSerialization.data(withJSONObject: hook))!
    }

    /// A command too long for the panel to show: it can only be agreed to in the terminal.
    private let nine = Array(repeating: "ls", count: 9).joined(separator: "\n")

    @discardableResult
    private func add(_ ask: Ask) -> UUID {
        store.add(ask) { [unowned self] in self.replies.append($0); return true }
    }

    private func row(_ id: String, open commands: [String] = [], closed: [(String, Date)] = [], status: AgentStatus = .working) -> AgentRow {
        var info = AgentInfo()
        info.openTools = commands.enumerated().map { OpenTool(id: "\(id)-t\($0.offset)", tool: "Bash", input: ["command": $0.element]) }
        info.closedTools = closed.enumerated().map { ClosedTool(tool: OpenTool(id: "\(id)-c\($0.offset)", tool: "Bash", input: ["command": $0.element.0]), at: $0.element.1) }
        return AgentRow(id: id, info: info, status: status, elapsed: 0)
    }

    /// A click a second later, with the panel open for a while: one that counts.
    private func click(_ id: UUID, _ answer: Answer) {
        clock += 1
        store.answer(id, answer, clickAt: clock, panelOpenedAt: clock.addingTimeInterval(-5))
    }

    private func card(_ id: String = "/r/p/s1", main: AgentRow?, agents: [AgentRow] = []) -> SessionCard {
        SessionCard(id: id, project: "p", branch: "main", main: main, agents: agents, startedAt: clock)
    }

    private func behavior(_ data: Data?) -> String? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return ((object["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])?["behavior"] as? String
    }

    // MARK: answering

    // The request leaves, and for a moment a line in its place says what became of it.
    // Installed again in /Applications after 0.1, the plugin still names the old app: Allow and Deny would stop
    // with nothing said. Looked at only while the switch is on.
    func testPluginLostIsCheckedWhenTurnedOn() throws {
        let registry = home.appendingPathComponent("known_marketplaces.json")
        let plugin = URL(fileURLWithPath: "/Applications/AgentValley.app/Contents/Resources/claude-plugin")
        try PluginPlaceTests.registry(agentValleyAt: PluginPlaceTests.gone).write(to: registry)
        store.checkPlugin(registry: registry, plugin: plugin)
        XCTAssertFalse(store.pluginLost, "switched off: not looked at")
        store.setEnabled(true)
        store.checkPlugin(registry: registry, plugin: plugin)
        XCTAssertTrue(store.pluginLost)
        try PluginPlaceTests.registry(agentValleyAt: plugin.path).write(to: registry)
        store.checkPlugin(registry: registry, plugin: plugin)
        XCTAssertFalse(store.pluginLost)
        try PluginPlaceTests.registry(agentValleyAt: "/old").write(to: registry)
        store.checkPlugin(registry: registry, plugin: plugin)
        store.setEnabled(false)
        XCTAssertFalse(store.pluginLost, "switched off: the line goes")
    }

    // Whether the plugin is in is looked at with the switch off too: until it is, cards point the way.
    func testPluginInstalledIsCheckedWithTheSwitchOff() throws {
        let list = home.appendingPathComponent("installed_plugins.json")
        let registry = home.appendingPathComponent("known_marketplaces.json")
        store.checkPlugin(registry: registry, installedList: list)
        XCTAssertFalse(store.pluginInstalled, "no list yet")
        try PluginPlaceTests.installedList(scope: "user").write(to: list)
        store.checkPlugin(registry: registry, installedList: list)
        XCTAssertTrue(store.pluginInstalled)
        try PluginPlaceTests.installedList().write(to: list)
        store.checkPlugin(registry: registry, installedList: list)
        XCTAssertFalse(store.pluginInstalled, "taken out again")
    }

    // Installed while the app runs, the switch turns on, once: turned on in the same send, the two
    // sinks called each other until the stack ran out.
    func testAPluginPutInTurnsTheSwitchOn() throws {
        let settings = Settings(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        let list = home.appendingPathComponent("installed_plugins.json")
        let watches = store.follow(settings, installedList: list)
        XCTAssertFalse(settings.answers)
        try PluginPlaceTests.installedList(scope: "user").write(to: list)
        store.checkPlugin(installedList: list)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(settings.answers)
        XCTAssertTrue(store.pluginInstalled)
        // Install itself turns the switch on as well: no loop either.
        try PluginPlaceTests.installedList().write(to: list)
        store.checkPlugin(installedList: list)
        settings.answers = false
        try PluginPlaceTests.installedList(scope: "user").write(to: list)
        settings.answers = true
        store.checkPlugin(installedList: list)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(settings.answers)
        withExtendedLifetime(watches) {}
        store.setEnabled(false)
    }

    // Already in at launch with the switch off: the person switched it off, and it stays off.
    func testAPluginAlreadyInLeavesTheSwitchAlone() throws {
        let settings = Settings(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
        let list = home.appendingPathComponent("installed_plugins.json")
        try PluginPlaceTests.installedList(scope: "user").write(to: list)
        let watches = store.follow(settings, installedList: list)
        store.checkPlugin(installedList: list)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(settings.answers)
        XCTAssertTrue(store.pluginInstalled)
        withExtendedLifetime(watches) {}
    }

    func testAnAnswerLeavesItsOutcomeForAMoment() {
        let id = add(ask())
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["ls"]))])
        click(id, .allow)
        let shown = card(main: row("/r/p/s1.jsonl"))
        XCTAssertEqual(store.settled(forRow: "/r/p/s1.jsonl", in: shown).map(\.outcome), [.answered(.allow)])
        XCTAssertTrue(store.settled(forRow: "/r/p/s1.jsonl", in: card("/r/p/s2", main: row("/r/p/s2.jsonl"))).isEmpty)
        clock += AnswerStore.settledFor - 0.1
        store.dropSettled()
        XCTAssertEqual(store.settled.count, 1)
        clock += 0.2
        let before = store.changedAt
        store.dropSettled()
        XCTAssertTrue(store.settled.isEmpty)
        // The line going away moves what stands below, like a request leaving does.
        XCTAssertGreaterThan(store.changedAt, before)
    }

    // The line used to leave a second and a half after the answer, which moved the list and
    // made the buttons of the next request dead a second time. It stays while the next ones
    // are worked through, and goes when the panel shuts.
    func testAnOutcomeStaysWhileTheOtherRequestsAreAnswered() {
        XCTAssertGreaterThanOrEqual(AnswerStore.settledFor, 20)
        let first = add(ask("ls"))
        let second = add(ask("pwd"))
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["ls", "pwd"]))])
        click(first, .allow)
        XCTAssertEqual(store.settled.map(\.outcome), [.answered(.allow)])
        // One line under a row: the newer outcome takes the older one's place.
        click(second, .deny)
        XCTAssertEqual(store.settled.map(\.outcome), [.answered(.deny)])
        XCTAssertEqual(store.settledSessions, ["s1"])
        // Ten seconds on, with the panel still open, it is still there.
        clock += 10
        store.dropSettled()
        XCTAssertEqual(store.settled.map(\.outcome), [.answered(.deny)])
        // Shut, the panel has nothing to say about what was answered while it was open.
        clock += 1
        let before = store.changedAt
        store.clearSettled()
        XCTAssertTrue(store.settled.isEmpty)
        XCTAssertGreaterThan(store.changedAt, before)
        // With nothing to take away, nothing is said to have moved.
        let after = store.changedAt
        clock += 1
        store.clearSettled()
        XCTAssertEqual(store.changedAt, after)
    }

    // "Not delivered" is the one outcome that asks something of the person: the terminal is
    // still waiting. It is not pushed out by the next answer under the same row, and it is
    // still there when the panel is opened again. It goes when its time is up.
    func testAnAnswerThatDidNotArriveStaysToBeRead() {
        let lost = store.add(ask("ls")) { _ in false }
        let next = add(ask("pwd"))
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["ls", "pwd"]))])
        click(lost, .allow)
        click(next, .allow)
        XCTAssertEqual(store.settled.map(\.outcome), [.notTaken, .answered(.allow)])
        store.clearSettled()
        XCTAssertEqual(store.settled.map(\.outcome), [.notTaken])
        clock += AnswerStore.settledFor + 1
        store.dropSettled()
        XCTAssertTrue(store.settled.isEmpty)
    }

    // A request's buttons are dead for a moment after the request itself has moved: a click
    // on its way was aimed at whatever stood there before. Only then. A row finishing in some
    // other card used to kill every button in the panel, and with a dozen agents at work that
    // was most of the time.
    func testARequestIsDisarmedByItsOwnMoveAndNotByAnothers() {
        let moved = add(ask("ls"))
        let still = add(ask("pwd", session: "/r/p/s2"))
        clock += 5
        let opened = clock.addingTimeInterval(-5)
        store.noteMoved(moved)
        clock += 0.3
        XCTAssertEqual(store.armsAt(store.pending[0], panelOpenedAt: opened)?.timeIntervalSince(clock) ?? 0, 0.3, accuracy: 0.001)
        XCTAssertFalse(store.answer(moved, .allow, clickAt: clock, panelOpenedAt: opened))
        // The press that came too soon starts that request's wait over.
        XCTAssertEqual(store.armsAt(store.pending[0], panelOpenedAt: opened)?.timeIntervalSince(clock) ?? 0, AnswerStore.armAfter, accuracy: 0.001)
        // The other one stood still, and takes the same click.
        XCTAssertTrue(store.answer(still, .allow, clickAt: clock, panelOpenedAt: opened))
        // A request leaving still disarms the rest for a moment, as it always has: the store
        // cannot know which of them it stood above.
        clock += 0.7
        XCTAssertTrue(store.answer(moved, .allow, clickAt: clock, panelOpenedAt: opened))
    }

    // The keys answer one request: the first one waiting on the session they are on.
    func testTheKeysAnswerTheFirstRequestOfTheChosenSession() {
        let first = add(ask("ls"))
        add(ask("pwd"))
        add(ask("id", session: "/r/p/s2"))
        let shown = card(main: row("/r/p/s1.jsonl", open: ["ls", "pwd"]))
        store.reconcile(with: [shown])
        XCTAssertEqual(store.keyTarget(in: shown)?.id, first)
        XCTAssertNil(store.keyTarget(in: card("/r/p/s3", main: row("/r/p/s3.jsonl"))))
    }

    // A key answers at the moment it is pressed, the first request of the session it was
    // pressed on, by the path a click takes. It is not kept: a key that found nothing to answer
    // must never answer the request the arrow keys reach next.
    func testAKeyAnswersWhenItIsPressedAndIsNotKept() {
        let empty = card("/r/p/s2", main: row("/r/p/s2.jsonl"))
        let first = add(ask("ls"))
        let shown = card(main: row("/r/p/s1.jsonl", open: ["ls"]))
        store.reconcile(with: [shown])
        clock += 5
        let opened = clock.addingTimeInterval(-5)
        // Nothing to answer on that session: nothing is sent, now or later.
        XCTAssertEqual(store.answer(byKey: .allow, at: clock, in: empty, whole: { _ in true }, panelOpenedAt: opened), .none)
        XCTAssertTrue(replies.isEmpty)
        XCTAssertEqual(store.pending.map(\.id), [first])
        // Not all in view: not read, so not answered, and the list is asked to show it.
        XCTAssertEqual(store.answer(byKey: .allow, at: clock, in: shown, whole: { _ in false }, panelOpenedAt: opened), .refused(first, cut: true))
        XCTAssertTrue(replies.isEmpty)
        // Too soon after it moved.
        store.noteMoved(first)
        XCTAssertEqual(store.answer(byKey: .allow, at: clock, in: shown, whole: { _ in true }, panelOpenedAt: opened), .refused(first, cut: false))
        XCTAssertTrue(replies.isEmpty)
        // A key the request does not offer.
        clock += 1
        XCTAssertEqual(store.answer(byKey: .option(1), at: clock, in: shown, whole: { _ in true }, panelOpenedAt: opened), .none)
        XCTAssertEqual(store.answer(byKey: .go, at: clock, in: shown, whole: { _ in true }, panelOpenedAt: opened), .none)
        XCTAssertTrue(replies.isEmpty)
        // In view, settled, and offered: sent once.
        XCTAssertEqual(store.answer(byKey: .allow, at: clock, in: shown, whole: { _ in true }, panelOpenedAt: opened), .counted(first))
        XCTAssertEqual(replies.map(behavior), ["allow"])
        // The panel shut: no key answers.
        let again = add(ask("pwd"))
        clock += 5
        XCTAssertEqual(store.answer(byKey: .allow, at: clock, in: shown, whole: { _ in true }, panelOpenedAt: nil), .refused(again, cut: false))
        XCTAssertEqual(replies.count, 1)
    }

    // What a key may answer depends on what the request is. A request that cannot be shown in
    // full cannot be allowed by a key any more than by a click.
    func testAKeyAnswersOnlyWhatTheRequestOffers() {
        let bash = ask("ls").kind
        XCTAssertEqual(bash.answer(for: .allow), .allow)
        XCTAssertEqual(bash.answer(for: .deny), .deny)
        XCTAssertNil(bash.answer(for: .option(1)))
        let question = ask("Which?", tool: "AskUserQuestion").kind
        XCTAssertEqual(question.answer(for: .option(2)), .option("Blue"))
        XCTAssertNil(question.answer(for: .option(3)))
        XCTAssertNil(question.answer(for: .allow))
        // The key that denies a tool call leaves a question unanswered.
        XCTAssertEqual(question.answer(for: .deny), .skip)
        let hidden = Ask.Kind.permissionHidden(Ask.Partial(fields: [], missing: ["new_string"]))
        XCTAssertNil(hidden.answer(for: .allow))
        XCTAssertEqual(hidden.answer(for: .deny), Answer.deny)
        XCTAssertNil(Ask.Kind.terminalOnly(text: "Plan").answer(for: .allow))
        XCTAssertNil(bash.answer(for: .go))
    }

    // Put away, a request is answered in the terminal and nowhere else. The hook is told
    // nothing and goes on waiting, and the row goes on saying it needs the person.
    func testARequestPutAwayTakesNoAnswerAndStillWaits() {
        let first = add(ask("ls"))
        let second = add(ask("pwd"))
        let shown = card(main: row("/r/p/s1.jsonl", open: ["ls", "pwd"]))
        store.reconcile(with: [shown])
        let opened = clock.addingTimeInterval(-5)
        // A click on its way before the request stood there puts nothing away, and neither
        // does one with the panel shut: put away, a request does not come back.
        XCTAssertFalse(store.hide(first, clickAt: clock.addingTimeInterval(AnswerStore.armAfter - 0.1), panelOpenedAt: opened))
        XCTAssertFalse(store.hide(first, clickAt: clock.addingTimeInterval(5), panelOpenedAt: nil))
        XCTAssertEqual(store.pending.map(\.hidden), [false, false])
        clock += 5
        let before = store.changedAt
        XCTAssertTrue(store.hide(first, clickAt: clock, panelOpenedAt: opened))
        // Its buttons go, so what stood below has moved.
        XCTAssertGreaterThan(store.changedAt, before)
        XCTAssertEqual(store.pending.map(\.hidden), [true, false])
        XCTAssertTrue(replies.isEmpty)
        XCTAssertEqual(store.overlay([shown])[0].main?.status, .needsYou)
        click(first, .allow)
        click(first, .deny)
        XCTAssertTrue(replies.isEmpty)
        // The keys pass it by for the next request of the session.
        XCTAssertEqual(store.keyTarget(in: shown)?.id, second)
        // Answered in the terminal, it ends as any other request does.
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["pwd"], closed: [("ls", clock)]))])
        XCTAssertEqual(store.pending.map(\.id), [second])
        XCTAssertEqual(store.settled.map(\.outcome), [.inTerminal])
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies[0])
    }

    // A click that did not count has to be told apart from one that did: the button says so.
    func testAnAnswerSaysWhetherTheClickCounted() {
        let id = add(ask())
        // Too soon after the panel opened.
        XCTAssertFalse(store.answer(id, .allow, clickAt: clock, panelOpenedAt: clock))
        XCTAssertTrue(replies.isEmpty)
        clock += 1
        XCTAssertTrue(store.answer(id, .allow, clickAt: clock, panelOpenedAt: clock.addingTimeInterval(-5)))
        // Gone already: nothing to answer.
        XCTAssertFalse(store.answer(id, .allow, clickAt: clock, panelOpenedAt: clock.addingTimeInterval(-5)))
    }

    func testOnlyAnEndingThatIsKnownLeavesAnOutcome() {
        // Answered in the terminal: the transcript shows the call got its result.
        let proven = add(ask())
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["ls"]))])
        clock += 3
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", closed: [("ls", clock)]))])
        XCTAssertFalse(store.pending.contains { $0.id == proven })
        XCTAssertEqual(store.settled.map(\.outcome), [.inTerminal])
        // The call is gone with no result on record, as after an interrupt: over, but not answered.
        let interrupted = add(ask("sleep 9"))
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["sleep 9"]))])
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl"))])
        XCTAssertFalse(store.pending.contains { $0.id == interrupted })
        XCTAssertEqual(store.settled.map(\.outcome), [.inTerminal])
        // The hook went away without a word: denied in the terminal, timed out or closed. Unknown, so nothing is claimed.
        store.withdraw(add(ask("pwd")))
        XCTAssertEqual(store.settled.map(\.outcome), [.inTerminal])
        // A click that did not count leaves nothing either.
        let early = add(ask("id"))
        store.answer(early, .allow, clickAt: clock, panelOpenedAt: clock)
        XCTAssertEqual(store.settled.count, 1)
        XCTAssertTrue(store.pending.contains { $0.id == early })
    }

    // An answer the hook never took did not count. The panel must not claim it, and must not
    // let the request vanish as if it had been answered: the terminal is still asking.
    func testAnAnswerThatDidNotReachTheHookSaysSo() {
        let id = store.add(ask()) { _ in false }
        click(id, .allow)
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.settled.map(\.outcome), [.notTaken])
    }

    // The model can send the very same command again right after an answer. A call that closed
    // before this request came in is the earlier one, and says nothing about this one.
    func testACallThatClosedBeforeTheRequestCameInDoesNotWithdrawIt() {
        let closed = clock
        clock += 1
        add(ask("rm -rf dist"))
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", closed: [("rm -rf dist", closed)]))])
        XCTAssertEqual(store.pending.count, 1)
        XCTAssertTrue(replies.isEmpty)
        XCTAssertTrue(store.settled.isEmpty)
        // The hook takes a moment to reach the app: a result just ahead of the request is its own.
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", closed: [("rm -rf dist", clock.addingTimeInterval(-0.3))]))])
        XCTAssertTrue(store.pending.isEmpty)
    }

    // The buttons dim while a click would not count. The panel must hear when that begins.
    func testTheStoreAnnouncesWhenButtonsStopTakingClicks() {
        add(ask())
        var announced = 0
        let watch = store.objectWillChange.sink { announced += 1 }
        defer { watch.cancel() }
        store.noteLayoutChange()
        XCTAssertEqual(announced, 1)
    }

    func testARowWithARequestKeepsItsSessionsApp() {
        add(ask())
        var shown = card(main: row("/r/p/s1.jsonl"))
        let superset = OwnerApp(bundle: URL(fileURLWithPath: "/Applications/Superset.app"), name: "Superset")
        shown.owner = superset
        XCTAssertEqual(store.overlay([shown]).first?.owner, superset)
        XCTAssertEqual(store.overlay([shown]).first?.main?.status, .needsYou)
    }

    func testAnAnswerReachesTheHookOnce() {
        let id = add(ask())
        click(id, .allow)
        XCTAssertEqual(replies.map(behavior), ["allow"])
        XCTAssertTrue(store.pending.isEmpty)
        click(id, .deny)
        XCTAssertEqual(replies.count, 1)
    }

    func testAnAnswerTheRequestCannotTakeChangesNothing() {
        let id = add(ask(String(repeating: "a", count: 700)))
        click(id, .allow)
        XCTAssertTrue(replies.isEmpty)
        XCTAssertEqual(store.pending.map(\.id), [id])
        click(id, .deny)
        XCTAssertEqual(replies.map(behavior), ["deny"])
    }

    // The one rule that must never break: nothing but the person's click produces a decision.
    func testOnlyAnAnswerEverProducesADecision() {
        let closed = add(ask("one"))
        add(ask("two"))
        let resolved = add(ask("three"))
        store.withdraw(closed)
        store.withdraw(closed)
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["three"]))])
        XCTAssertEqual(store.pending.first { $0.id == resolved }?.row, "/r/p/s1.jsonl")
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl"))])
        store.setEnabled(false)
        XCTAssertEqual(replies.count, 3)
        XCTAssertTrue(replies.allSatisfy { $0 == nil })
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.state, .off)
    }

    // MARK: whose request it is, and when it is over

    func testARequestFindsTheAgentWhoseToolCallIsWaiting() {
        let id = add(ask("npm test"))
        let sessions = [card(main: row("/r/p/s1.jsonl", open: ["ls"]), agents: [row("/r/p/s1/a1.jsonl", open: ["npm test"]), row("/r/p/s1/a2.jsonl")])]
        store.reconcile(with: sessions)
        XCTAssertEqual(store.pending.first?.row, "/r/p/s1/a1.jsonl")
        XCTAssertEqual(store.requests(forRow: "/r/p/s1/a1.jsonl", in: sessions[0]).map(\.id), [id])
        XCTAssertTrue(store.requests(forRow: "/r/p/s1.jsonl", in: sessions[0]).isEmpty)
    }

    // The transcript trails the hook by a moment; until it catches up the request sits on the session.
    func testARequestNotYetMatchedShowsOnTheMainRow() {
        let id = add(ask("npm test"))
        let waiting = card(main: row("/r/p/s1.jsonl"), agents: [row("/r/p/s1/a1.jsonl")])
        store.reconcile(with: [waiting])
        XCTAssertNil(store.pending.first?.row)
        XCTAssertEqual(store.requests(forRow: "/r/p/s1.jsonl", in: waiting).map(\.id), [id])
        XCTAssertTrue(store.requests(forRow: "/r/p/s1/a1.jsonl", in: waiting).isEmpty)
        let headless = card(main: nil, agents: [row("/r/p/s1/a1.jsonl")])
        XCTAssertEqual(store.requests(forRow: "/r/p/s1/a1.jsonl", in: headless).map(\.id), [id])
        XCTAssertTrue(store.requests(forRow: "/r/p/s1.jsonl", in: card("/r/p/other", main: row("/r/p/s1.jsonl"))).isEmpty)
        XCTAssertTrue(replies.isEmpty)
    }

    // Two agents waiting on the very same call cannot be told apart from their transcripts, so a
    // result arriving for one must not take the other's buttons away. Each ends with its own hook.
    func testTwoAgentsWithTheSameCallKeepTheirRequestsUntilTheirHooksEnd() {
        let first = add(ask("npm test"))
        clock += 1
        let second = add(ask("npm test"))
        var sessions = [card(main: row("/r/p/s1.jsonl"), agents: [row("/r/p/s1/a1.jsonl", open: ["npm test"]), row("/r/p/s1/a2.jsonl", open: ["npm test"])])]
        store.reconcile(with: sessions)
        XCTAssertEqual(store.pending.map(\.row), ["/r/p/s1/a1.jsonl", "/r/p/s1/a2.jsonl"])
        sessions = [card(main: row("/r/p/s1.jsonl"), agents: [row("/r/p/s1/a1.jsonl", open: ["npm test"]), row("/r/p/s1/a2.jsonl", closed: [("npm test", clock)])])]
        store.reconcile(with: sessions)
        XCTAssertEqual(store.pending.map(\.id), [first, second])
        XCTAssertTrue(replies.isEmpty)
        store.withdraw(second)
        XCTAssertEqual(store.pending.map(\.id), [first])
    }

    // A quick "Yes" in the terminal can put the call and its result in the transcript before the
    // app has read either. The request never sees its call open, and must still go.
    func testACallAnsweredBeforeItWasSeenOpenWithdrawsItsRequest() {
        add(ask("npm test"))
        let earlier = clock.addingTimeInterval(-60)
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", closed: [("npm test", earlier), ("ls", clock)]))])
        XCTAssertEqual(store.pending.count, 1, "the same command finished a minute before the request, or another command, says nothing")
        clock += 3
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", closed: [("npm test", clock)]))])
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies[0])
    }

    // Past its limit a row no longer lists every open call, so a missing one proves nothing.
    func testARowAtItsLimitOfOpenCallsWithdrawsNothing() {
        add(ask("npm test"))
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["npm test"]))])
        XCTAssertEqual(store.pending.first?.row, "/r/p/s1.jsonl")
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: (0..<TranscriptReader.openToolLimit).map { "other \($0)" }))])
        XCTAssertEqual(store.pending.count, 1)
        XCTAssertTrue(replies.isEmpty)
    }

    func testAnsweringInTheTerminalWithdrawsTheRequest() {
        add(ask("npm test"))
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["npm test"]))])
        XCTAssertEqual(store.pending.count, 1)
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", open: ["git status"]))])
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies[0])
    }

    // MARK: what the panel shows

    func testARowWithARequestNeedsThePerson() {
        add(ask("npm test"))
        clock += 90
        let sessions = [card(main: row("/r/p/s1.jsonl", status: .done), agents: [row("/r/p/s1/a1.jsonl", open: ["npm test"])]), card("/r/p/s2", main: row("/r/p/s2.jsonl"))]
        store.reconcile(with: sessions)
        let shown = store.overlay(sessions)
        XCTAssertEqual(shown[0].agents[0].status, .needsYou)
        XCTAssertEqual(shown[0].agents[0].quietFor, 90, accuracy: 0.001)
        XCTAssertEqual(shown[0].main?.status, .done)
        XCTAssertEqual(shown[1], sessions[1])
        XCTAssertEqual(AgentStore.count(.needsYou, in: shown), 1)
        XCTAssertEqual(AgentStore.count(.working, in: shown), 1)
    }

    // A click that lands as the panel opens under the cursor, or as a request appears, is not an answer.
    func testButtonsArmOnlyAfterAMoment() {
        let received = clock
        func accepts(open: TimeInterval?, age: TimeInterval, changed: TimeInterval = 100) -> Bool {
            let click = received.addingTimeInterval(age)
            return AnswerStore.accepts(clickAt: click, panelOpenedAt: open.map { click.addingTimeInterval(-$0) }, receivedAt: received, changedAt: click.addingTimeInterval(-changed))
        }
        XCTAssertFalse(accepts(open: 0.5, age: 10))
        XCTAssertFalse(accepts(open: 10, age: 0.5))
        XCTAssertFalse(accepts(open: nil, age: 10))
        XCTAssertFalse(accepts(open: 10, age: 10, changed: 0.5))
        XCTAssertTrue(accepts(open: 0.6, age: 0.6, changed: 0.6))
    }

    // The rule is enforced where the answer is sent, not only where the button is drawn.
    func testAClickTooEarlyOrWithThePanelShutSendsNothing() {
        let id = add(ask())
        store.answer(id, .allow, clickAt: clock.addingTimeInterval(0.3), panelOpenedAt: clock.addingTimeInterval(-5))
        store.answer(id, .allow, clickAt: clock.addingTimeInterval(5), panelOpenedAt: nil)
        store.answer(id, .allow, clickAt: clock.addingTimeInterval(5), panelOpenedAt: clock.addingTimeInterval(4.8))
        XCTAssertTrue(replies.isEmpty)
        XCTAssertEqual(store.pending.count, 1)
    }

    // Answering one request moves the next into its place, already under the cursor: a double
    // click, or a mouse button that bounces, must not answer both.
    func testASecondClickRightAfterAnAnswerIsNotTaken() {
        let first = add(ask("one"))
        let second = add(ask("two"))
        clock += 5
        let opened = clock.addingTimeInterval(-5)
        store.answer(first, .allow, clickAt: clock, panelOpenedAt: opened)
        store.answer(second, .allow, clickAt: clock.addingTimeInterval(0.2), panelOpenedAt: opened)
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(store.pending.map(\.id), [second])
        // Nor a third that follows the second as closely: the wait counts from the last press.
        store.answer(second, .allow, clickAt: clock.addingTimeInterval(0.7), panelOpenedAt: opened)
        XCTAssertEqual(replies.count, 1)
        store.answer(second, .allow, clickAt: clock.addingTimeInterval(1.4), panelOpenedAt: opened)
        XCTAssertEqual(replies.count, 2)
    }

    // A chord pressed four times a second allowed a request 0.86 s after it appeared: each
    // press that came too soon was refused, and the first one past the wait counted, as blind
    // as the rest. A tester did it with the keys; a key held down does the same. Every press
    // that comes too soon starts the wait over, so only a press after a pause counts.
    func testPressingOverAndOverNeverAnswersARequestThatHasJustArrived() {
        let opened = clock.addingTimeInterval(-5)
        let shown = card(main: row("/r/p/s1.jsonl", open: ["ls"]))
        func whole(_: UUID) -> Bool { true }
        // Nothing to answer yet: the presses find no request, and none is kept for later.
        for _ in 0..<4 {
            clock += 0.25
            XCTAssertEqual(store.answer(byKey: .allow, at: clock, in: shown, whole: whole, panelOpenedAt: opened), .none)
        }
        let id = add(ask("ls"))
        store.reconcile(with: [shown])
        for _ in 0..<20 {
            clock += 0.25
            XCTAssertEqual(store.answer(byKey: .allow, at: clock, in: shown, whole: whole, panelOpenedAt: opened), .refused(id, cut: false))
        }
        XCTAssertTrue(replies.isEmpty)
        // As fast as a held key repeats.
        for _ in 0..<50 {
            clock += 0.03
            XCTAssertFalse(store.answer(id, .allow, clickAt: clock, panelOpenedAt: opened))
        }
        XCTAssertTrue(replies.isEmpty)
        // The buttons stay dim until the wait from the last press is over.
        XCTAssertEqual(store.armsAt(store.pending[0], panelOpenedAt: opened)?.timeIntervalSince(clock) ?? 0, AnswerStore.armAfter, accuracy: 0.001)
        // The hand stops, and the next press is one that was aimed.
        clock += AnswerStore.armAfter
        XCTAssertEqual(store.answer(byKey: .allow, at: clock, in: shown, whole: whole, panelOpenedAt: opened), .counted(id))
        XCTAssertEqual(replies.count, 1)
    }

    // The same for putting a request away, which cannot be taken back either. And with the
    // panel shut a press is not a press at anything: it starts no wait.
    func testAPressTooSoonToHideStartsTheWaitOverAndOneWithThePanelShutDoesNot() {
        let id = add(ask())
        let opened = clock.addingTimeInterval(-5)
        XCTAssertFalse(store.hide(id, clickAt: clock.addingTimeInterval(0.3), panelOpenedAt: opened))
        XCTAssertFalse(store.hide(id, clickAt: clock.addingTimeInterval(0.7), panelOpenedAt: opened))
        XCTAssertFalse(store.answer(id, .allow, clickAt: clock.addingTimeInterval(5), panelOpenedAt: nil))
        XCTAssertTrue(store.hide(id, clickAt: clock.addingTimeInterval(5.1), panelOpenedAt: opened))
    }

    // Answered, a request gives up its place and the next session's name comes up under the
    // pointer. Eight of thirteen testers saw it there: a second click would have taken them to
    // another app. A click that leaves for a session's app waits out the same moment.
    func testAClickThatLeavesForAnAppIsNotTakenRightAfterTheListMoved() {
        XCTAssertTrue(store.goes(clickAt: clock), "nothing has moved yet")
        let id = add(ask())
        XCTAssertFalse(store.goes(clickAt: clock.addingTimeInterval(0.3)), "a request just arrived and pushed the cards down")
        XCTAssertTrue(store.goes(clickAt: clock.addingTimeInterval(AnswerStore.armAfter)))
        click(id, .allow)
        XCTAssertEqual(replies.count, 1)
        XCTAssertFalse(store.goes(clickAt: clock))
        XCTAssertFalse(store.goes(clickAt: clock.addingTimeInterval(0.2)), "the double click")
        XCTAssertTrue(store.goes(clickAt: clock.addingTimeInterval(0.7)))
        // The line that says how it ended goes, and the cards move up once more.
        clock += AnswerStore.settledFor + 1
        store.dropSettled()
        XCTAssertFalse(store.goes(clickAt: clock.addingTimeInterval(0.3)))
        // So does anything else the list reports as having moved.
        clock += 5
        XCTAssertTrue(store.goes(clickAt: clock))
        store.noteLayoutChange()
        XCTAssertFalse(store.goes(clickAt: clock.addingTimeInterval(0.3)))
        XCTAssertTrue(store.goes(clickAt: clock.addingTimeInterval(1)))
    }

    // Whenever the buttons may have moved (a request arrived, found its row, or the list changed)
    // they stop taking clicks for a moment.
    func testButtonsThatMayHaveMovedAreNotArmedAtOnce() {
        let id = add(ask("npm test"))
        clock += 5
        let opened = clock.addingTimeInterval(-5)
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl"), agents: [row("/r/p/s1/a1.jsonl", open: ["npm test"])])])
        XCTAssertEqual(store.pending.first?.row, "/r/p/s1/a1.jsonl")
        store.answer(id, .allow, clickAt: clock.addingTimeInterval(0.3), panelOpenedAt: opened)
        XCTAssertTrue(replies.isEmpty, "it just moved from the session's row to the agent's")
        clock += 5
        add(ask("another"))
        store.answer(id, .allow, clickAt: clock.addingTimeInterval(0.3), panelOpenedAt: opened)
        XCTAssertTrue(replies.isEmpty, "a request just arrived and pushed things down")
        clock += 5
        store.noteLayoutChange()
        store.answer(id, .allow, clickAt: clock.addingTimeInterval(0.3), panelOpenedAt: opened)
        XCTAssertTrue(replies.isEmpty, "the list of cards just changed")
        // Counted from that press, which came too soon.
        store.answer(id, .allow, clickAt: clock.addingTimeInterval(0.9), panelOpenedAt: opened)
        XCTAssertEqual(replies.count, 1)
    }

    // MARK: the switch

    func testTheSwitchOpensAndClosesTheSocket() {
        let socket = home.appendingPathComponent("AV/answers.sock").path
        XCTAssertEqual(store.state, .off)
        store.setEnabled(true)
        XCTAssertEqual(store.state, .listening(lastRequest: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: socket))
        add(ask())
        XCTAssertEqual(store.state, .listening(lastRequest: clock))
        store.setEnabled(false)
        XCTAssertEqual(store.state, .off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: socket))
    }

    // Off means no socket file, even one that a killed run left behind. A live one is another copy's.
    func testTurningOffRemovesASocketLeftBehindButNotALiveOne() throws {
        let folder = home.appendingPathComponent("AV")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = folder.appendingPathComponent("answers.sock").path
        makeStaleSocket(at: path)
        store.setEnabled(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))

        let other = AnswerServer(directory: folder) { _, _ in }
        try other.start()
        defer { other.stop() }
        store.setEnabled(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        // Only a socket is ever removed: a file someone put under that name is not the app's to delete.
        other.stop()
        try Data("x".utf8).write(to: URL(fileURLWithPath: path))
        store.setEnabled(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testAFolderThatIsNotPrivateIsReportedNotUsed() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent("AV"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        store.setEnabled(true)
        XCTAssertEqual(store.state, .failed("its folder is open to other accounts"))
    }


    // MARK: a sub-agent's request

    // Claude Code shows a sub-agent's prompt in the terminal only once every hook is done. One
    // this panel cannot answer is let go at once, so the terminal asks now, and stays here, put
    // away, until the transcript shows it answered.
    func testASubAgentsRequestThePanelCannotAnswerIsLetGoAtOnce() {
        let id = add(ask(nine, agent: "a1"))
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies[0])
        XCTAssertEqual(store.pending.map(\.hidden), [true])
        let waiting = card(main: row("/r/p/s1.jsonl", status: .done), agents: [row("/r/p/s1/a1.jsonl", open: [nine])])
        store.reconcile(with: [waiting])
        XCTAssertEqual(store.overlay([waiting])[0].agents[0].status, .needsYou)
        click(id, .deny)
        XCTAssertEqual(replies.count, 1)
        store.reconcile(with: [card(main: row("/r/p/s1.jsonl", status: .done), agents: [row("/r/p/s1/a1.jsonl", closed: [(nine, clock)])])])
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.settled.map(\.outcome), [.inTerminal])
        XCTAssertEqual(replies.count, 1)
    }

    // One the panel can answer is held: answered here, it never waits in the terminal. Put away,
    // it is let go, so the terminal asks. A main session's prompt shows while its hook waits, so
    // its requests are held whatever the panel can do with them.
    func testASubAgentsRequestIsHeldOnlyWhileThePanelCanAnswerIt() {
        let main = add(ask(nine))
        let agent = add(ask("ls", agent: "a1"))
        XCTAssertTrue(replies.isEmpty)
        clock += 5
        XCTAssertTrue(store.hide(agent, clickAt: clock, panelOpenedAt: clock.addingTimeInterval(-5)))
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies[0])
        clock += 5
        XCTAssertTrue(store.hide(main, clickAt: clock, panelOpenedAt: clock.addingTimeInterval(-5)))
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(store.pending.map(\.id), [main, agent])
    }

    // Let go, it has no hook left to end it: it goes when the hook would have given up.
    func testASubAgentsRequestLetGoEndsWhenItsHookWouldHave() {
        add(ask(nine, agent: "a1"))
        clock += AnswerStore.hookLimit - 1
        store.reconcile(with: [])
        XCTAssertEqual(store.pending.count, 1)
        clock += 1
        store.reconcile(with: [])
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertTrue(store.settled.isEmpty)
        XCTAssertEqual(replies.count, 1)
    }
}
