import Combine
import Foundation

/// The requests waiting for the person, and the only place a decision is sent from.
/// A decision leaves through `answer` alone, which the panel's buttons call. Every other way a
/// request ends hands the hook nothing, and Claude Code goes on asking in the terminal.
/// All state lives on the main thread.
final class AnswerStore: ObservableObject {
    struct Pending: Identifiable, Equatable {
        let id: UUID
        let ask: Ask
        let receivedAt: Date
        /// The row whose tool call this is about, once a transcript shows that call.
        var row: String?
        /// Put away by the person. It still waits, and its row still says so, but nothing
        /// here answers it any more: that is done in the terminal.
        var hidden = false
        /// Its hook was let go, so the terminal asks: a sub-agent's request put away, or one the
        /// panel cannot answer. It stays, put away, until the transcript shows it answered.
        var released = false
    }

    /// How long the plugin's hook waits for an answer (its timeout in hooks.json).
    static let hookLimit: TimeInterval = 600

    /// How a request ended, when that is known. A hook that goes away without a word was denied
    /// in the terminal, timed out or lost its session, and a call can leave the transcript's
    /// open calls through an interrupt; which one is not known, so nothing is said.
    enum Outcome: Equatable {
        /// The person's answer here, taken by the hook.
        case answered(Answer)
        /// The transcript shows the call got its result while the request stood here.
        case inTerminal
        /// The person answered here and the hook did not take it: the terminal is still asking.
        case notTaken
    }

    /// An ended request, shown where it stood.
    struct Settled: Identifiable, Equatable {
        let id: UUID
        let session: String
        let row: String?
        let outcome: Outcome
        /// The tool the request was for, as the request named it.
        var tool = ""
        let until: Date
    }

    /// How long an outcome stays up in a panel that is left open. Long enough to work through
    /// the other requests first: the line leaving moves the list, and that makes their buttons
    /// dead for a moment. A panel that shuts takes its outcomes with it.
    static let settledFor: TimeInterval = 30

    enum State: Equatable {
        case off
        case listening(lastRequest: Date?)
        case failed(String)

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    /// Buttons take a click only this long after the panel opened and after the request appeared:
    /// a click already on its way when either happens was not meant for them.
    static let armAfter: TimeInterval = 0.6

    @Published private(set) var pending: [Pending] = []
    @Published private(set) var state = State.off
    @Published private(set) var settled: [Settled] = []

    private let directory: URL
    private let now: () -> Date
    private var server: AnswerServer?
    private var replies: [UUID: (Data?) -> Bool] = [:]

    /// Where a Stop hook goes. Unset, it is answered with nothing at once and Claude ends its turn.
    var onStop: ((StopWait, AnswerConnection) -> Void)?

    /// The plugin points at an older copy of the app, so Allow and Deny cannot reach this one.
    @Published private(set) var pluginLost = false
    /// Claude Code has the plugin, whether or not the switch is on. Until it does, a card that
    /// waits on the person points the way to put it in.
    @Published private(set) var pluginInstalled = false

    init(directory: URL = AnswerServer.defaultDirectory, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    /// Off means no socket exists and nothing is waiting.
    func setEnabled(_ on: Bool) {
        guard on else {
            for item in pending { withdraw(item.id) }
            settled = []
            server?.stop()
            server = nil
            AnswerServer.removeStaleSocket(in: directory)
            state = .off
            pluginLost = false
            return
        }
        guard server == nil else { return }
        let server = AnswerServer(directory: directory) { [weak self] ask, connection in
            guard let self else { connection.reply(nil); return }
            let id = self.add(ask) { connection.reply($0) }
            connection.onClose = { [weak self] in self?.withdraw(id) }
        } onStop: { [weak self] stop, connection in
            guard let handler = self?.onStop else { connection.reply(nil); return }
            handler(stop, connection)
        }
        do {
            try server.start()
            self.server = server
            state = .listening(lastRequest: nil)
        } catch {
            state = .failed((error as? AnswerServerError)?.message ?? error.localizedDescription)
        }
    }

    /// Looks again whether the plugin is in, and whether it points here. The second only while
    /// the switch is on: off, nobody expects Allow and Deny in the notch.
    func checkPlugin(registry: URL = PluginPlace.registry, plugin: URL = PluginPlace.here, installedList: URL = PluginPlace.installedList) {
        let lost = server != nil && PluginPlace.lost(try? Data(contentsOf: registry), plugin: plugin)
        if lost != pluginLost { pluginLost = lost }
        let installed = PluginPlace.installed(try? Data(contentsOf: installedList))
        if installed != pluginInstalled { pluginInstalled = installed }
    }

    /// The switch and the plugin, tied together. The switch opens and shuts the socket. A plugin put
    /// in since the app started, by Install or by the command run in a terminal, turns the switch on;
    /// one already in at launch does not: with the switch off, the person switched it off.
    func follow(_ settings: Settings, installedList: URL = PluginPlace.installedList) -> Set<AnyCancellable> {
        [settings.$answers.sink { [weak self] on in self?.setEnabled(on); self?.checkPlugin(installedList: installedList) },
         // A turn of the run loop later. Sent from inside the plugin's own send, the new value is
         // not stored yet: the switch's sink looked again, found it unchanged, sent again, and so
         // on until the stack ran out (the test copy, 2026-10-26).
         $pluginInstalled.dropFirst().filter { $0 }.receive(on: RunLoop.main)
            .sink { _ in if !settings.answers { settings.answers = true } }]
    }

    /// When the buttons last may have moved on screen: a request arrived, left or found its row,
    /// or the list around them changed. A click sooner than `armAfter` after that was aimed at
    /// whatever stood there before.
    /// Published: the buttons dim while a click would not count, and the panel has to hear of it.
    @Published private(set) var changedAt = Date.distantPast
    /// How far ahead of a request its own call may have closed: the hook takes a moment to reach
    /// the app. No longer than that, or the result of an earlier, identical call would pass for
    /// an answer to a command the model has just sent again.
    static let clockSlack: TimeInterval = 0.5

    /// The panel's list changed shape, so buttons may sit somewhere else than a moment ago.
    func noteLayoutChange() {
        changedAt = now()
    }

    /// When each request last moved in the list, as its own view reports it. A request that
    /// has just moved takes no click, and one that stood still does: a row finishing in some
    /// other card is no reason to refuse a click on this one. Not published: it changes on
    /// every scrolled frame, and each request's view keeps its own count of the moment.
    private var movedAt: [UUID: Date] = [:]

    func noteMoved(_ id: UUID) {
        guard pending.contains(where: { $0.id == id }) else { return }
        movedAt[id] = now()
    }

    /// What became of a key pressed to answer.
    enum KeyOutcome: Equatable {
        /// The session has no request this key answers. Nothing was sent, and nothing will be.
        case none
        case counted(UUID)
        /// Not sent. `cut`: the request was not all in view. Else it had just moved or arrived.
        case refused(UUID, cut: Bool)
    }

    /// A key's answer to the first request of the session it was pressed on, at the moment it
    /// was pressed, by the path a click takes. The key is not kept: one that found nothing to
    /// answer never answers the request the arrow keys reach next. `whole` says whether a
    /// request is all in view, which only the list knows.
    func answer(byKey key: KeyCommand, at: Date, in card: SessionCard, whole: (UUID) -> Bool, panelOpenedAt: Date?) -> KeyOutcome {
        guard let item = keyTarget(in: card), let choice = item.ask.kind.answer(for: key) else { return .none }
        guard whole(item.id) else { return .refused(item.id, cut: true) }
        return answer(item.id, choice, clickAt: at, panelOpenedAt: panelOpenedAt) ? .counted(item.id) : .refused(item.id, cut: false)
    }

    /// The request the keys answer on a session: the first one waiting there, in the order drawn.
    func keyTarget(in card: SessionCard) -> Pending? {
        card.rows.lazy.flatMap { self.requests(forRow: $0.id, in: card) }.first { !$0.hidden }
    }

    @discardableResult
    func add(_ ask: Ask, reply: @escaping (Data?) -> Bool) -> UUID {
        let item = Pending(id: UUID(), ask: ask, receivedAt: now())
        replies[item.id] = reply
        pending.append(item)
        changedAt = item.receivedAt
        if case .listening = state { state = .listening(lastRequest: item.receivedAt) }
        if ask.agent != nil, !ask.kind.isAnswerable { release(item.id) }
        return item.id
    }

    /// Hands a sub-agent's hook no decision, so Claude Code asks in the terminal at once: until
    /// the hook is done, the terminal shows nothing for it. The request stays, put away.
    private func release(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }), let reply = replies[id] else { return }
        pending[index].hidden = true
        pending[index].released = true
        replies[id] = { _ in false }
        _ = reply(nil)
    }

    /// The person's click, with when it was made and when the panel opened. Sends nothing, and
    /// leaves the request as it is, when the click came too soon to have been aimed at this
    /// button or the request cannot take this answer. Says whether the click counted, so the
    /// button can say so when it did not.
    @discardableResult
    func answer(_ id: UUID, _ answer: Answer, clickAt: Date, panelOpenedAt: Date?) -> Bool {
        guard let item = pending.first(where: { $0.id == id }), !item.hidden else { return false }
        guard Self.accepts(clickAt: clickAt, panelOpenedAt: panelOpenedAt, receivedAt: item.receivedAt, changedAt: max(changedAt, movedAt[id] ?? .distantPast)) else {
            tooSoon(id, clickAt, panelOpenedAt: panelOpenedAt)
            return false
        }
        guard let body = item.ask.reply(answer) else { return false }
        finish(id, with: body, outcome: .answered(answer))
        return true
    }

    /// A press that came too soon was not aimed at what it landed on, and neither is the next
    /// one of a hand that goes on pressing: that request's wait starts over from it. A chord
    /// pressed four times a second used to allow a request under a second after it appeared,
    /// the first press after the wait being as blind as the ones refused before it. A key held
    /// down is the same hand. Only that request's wait: one that stood still elsewhere takes a
    /// click as before. With the panel shut nothing was pressed at anything.
    private func tooSoon(_ id: UUID, _ pressedAt: Date, panelOpenedAt: Date?) {
        guard panelOpenedAt != nil else { return }
        movedAt[id] = max(movedAt[id] ?? .distantPast, pressedAt)
    }

    /// Puts a request away. The hook is told nothing and goes on waiting, as the terminal does.
    /// It cannot be brought back here, so the click is judged as an answer's is: one that came
    /// too soon was aimed at whatever stood there before. Says whether it counted.
    @discardableResult
    func hide(_ id: UUID, clickAt: Date, panelOpenedAt: Date?) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }), !pending[index].hidden else { return false }
        guard Self.accepts(clickAt: clickAt, panelOpenedAt: panelOpenedAt, receivedAt: pending[index].receivedAt, changedAt: max(changedAt, movedAt[id] ?? .distantPast)) else {
            tooSoon(id, clickAt, panelOpenedAt: panelOpenedAt)
            return false
        }
        pending[index].hidden = true
        // Its buttons go, and whatever stood below moves up.
        changedAt = now()
        if pending[index].ask.agent != nil { release(id) }
        return true
    }

    /// The request is over without the person answering here.
    func withdraw(_ id: UUID) {
        finish(id, with: nil)
    }

    private func finish(_ id: UUID, with body: Data?, outcome: Outcome? = nil) {
        guard let reply = replies.removeValue(forKey: id) else { return }
        movedAt[id] = nil
        let item = pending.first { $0.id == id }
        pending.removeAll { $0.id == id }
        // Whatever stood below moves up into this request's place.
        changedAt = now()
        let delivered = reply(body)
        guard var outcome, let item else { return }
        // An answer the hook never took did not count, and the request must not vanish as if it
        // had: the terminal is still the one asking, and the line says so.
        if case .answered = outcome, !delivered { outcome = .notTaken }
        // One line under a row: this outcome takes the place of the one before it. Not of an
        // answer that never arrived: the terminal still waits for that one.
        settled.removeAll { $0.session == item.ask.session && $0.row == item.row && $0.outcome != .notTaken }
        settled.append(Settled(id: id, session: item.ask.session, row: item.row, outcome: outcome, tool: item.ask.toolTitle, until: now().addingTimeInterval(Self.settledFor)))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settledFor + 0.05) { [weak self] in self?.dropSettled() }
    }

    /// The name of a card's transcript file: what a request's `session` is compared with.
    static func sessionID(of card: SessionCard) -> String {
        (card.id as NSString).lastPathComponent
    }

    /// Ties each request to the row whose transcript shows the same tool call waiting, and
    /// withdraws a request once that call has its result: it was answered in the terminal.
    func reconcile(with sessions: [SessionCard]) {
        // Let go, a request has no hook left to end it: it goes when the hook would have given up.
        for item in pending where item.released && now().timeIntervalSince(item.receivedAt) >= Self.hookLimit { withdraw(item.id) }
        guard !pending.isEmpty else { return }
        var matched = pending
        /// The requests that are over, and whether a result on record proves each was answered.
        var over: [(id: UUID, proven: Bool)] = []
        for card in sessions {
            let session = Self.sessionID(of: card)
            let digests = Set(matched.filter { $0.ask.session == session }.map(\.ask.digest))
            for digest in digests {
                let indices = matched.indices.filter { matched[$0].ask.session == session && matched[$0].ask.digest == digest }
                // Several requests for the very same call cannot be told apart from the transcripts,
                // so none of them is withdrawn on that evidence. Each ends when its own hook does.
                let certain = indices.count == 1
                // How many calls with this digest each row still has open.
                var open: [String: Int] = [:]
                for row in card.rows {
                    let count = row.info.openTools.filter { $0.digest == digest }.count
                    if count > 0 { open[row.id] = count }
                }
                for index in indices {
                    guard let row = matched[index].row, let owner = card.rows.first(where: { $0.id == row }) else { continue }
                    if open[row, default: 0] > 0 {
                        open[row, default: 0] -= 1
                    } else if certain, owner.info.openTools.count < TranscriptReader.openToolLimit {
                        // A row at its limit no longer lists every open call; a missing one proves nothing.
                        // Gone without a result on record, the call was interrupted, not answered.
                        let since = matched[index].receivedAt.addingTimeInterval(-Self.clockSlack)
                        over.append((matched[index].id, owner.info.closedTools.contains { $0.at >= since && $0.tool.digest == digest }))
                    }
                }
                for index in indices where matched[index].row == nil {
                    if let row = card.rows.first(where: { open[$0.id, default: 0] > 0 }) {
                        matched[index].row = row.id
                        open[row.id, default: 0] -= 1
                    } else if certain {
                        // Never seen open: the call and its result were read together. If it closed
                        // after the request came in, the request was answered in the terminal.
                        let since = matched[index].receivedAt.addingTimeInterval(-Self.clockSlack)
                        let closed = card.rows.contains { row in row.info.closedTools.contains { $0.at >= since && $0.tool.digest == digest } }
                        if closed { over.append((matched[index].id, true)) }
                    }
                }
            }
        }
        if matched != pending {
            pending = matched
            changedAt = now()
        }
        for request in over { finish(request.id, with: nil, outcome: request.proven ? .inTerminal : nil) }
    }

    /// Takes away the outcomes that have been up long enough.
    func dropSettled() {
        let time = now()
        guard settled.contains(where: { $0.until <= time }) else { return }
        settled.removeAll { $0.until <= time }
        // The line going away moves up whatever stands below it.
        changedAt = time
    }

    /// Takes away the outcomes. For when the panel shuts: nobody is looking, and the next
    /// opening should not start with a line about last time. An answer that never arrived
    /// stays its time: that line is still news, and shutting the panel is how most answers end.
    func clearSettled() {
        guard settled.contains(where: { $0.outcome != .notTaken }) else { return }
        settled.removeAll { $0.outcome != .notTaken }
        changedAt = now()
    }

    /// The sessions, by the name of their transcript, that have an outcome up.
    var settledSessions: Set<String> { Set(settled.map(\.session)) }

    /// Whether something of a session shows under this row of a card. What is tied to no row yet,
    /// or to one the card no longer has, sits on the session's main row.
    private func shows(session: String, owner: String?, under row: String, in card: SessionCard) -> Bool {
        guard session == Self.sessionID(of: card) else { return false }
        if let owner, card.rows.contains(where: { $0.id == owner }) { return owner == row }
        return row == card.main?.id ?? card.agents.first?.id
    }

    /// The requests to show under a row.
    func requests(forRow row: String, in card: SessionCard) -> [Pending] {
        pending.filter { shows(session: $0.ask.session, owner: $0.row, under: row, in: card) }
    }

    /// The outcomes to show under a row.
    func settled(forRow row: String, in card: SessionCard) -> [Settled] {
        settled.filter { shows(session: $0.session, owner: $0.row, under: row, in: card) }
    }

    /// The sessions as the panel should count and draw them: a row with a request waiting needs
    /// the person, whatever its transcript suggests.
    func overlay(_ sessions: [SessionCard]) -> [SessionCard] {
        guard !pending.isEmpty else { return sessions }
        let time = now()
        return sessions.map { card in
            let session = Self.sessionID(of: card)
            guard pending.contains(where: { $0.ask.session == session }) else { return card }
            func shown(_ row: AgentRow) -> AgentRow {
                guard let first = requests(forRow: row.id, in: card).map(\.receivedAt).min() else { return row }
                return AgentRow(id: row.id, info: row.info, status: .needsYou, elapsed: row.elapsed, quietFor: time.timeIntervalSince(first))
            }
            var card = card
            card.main = card.main.map(shown)
            card.agents = card.agents.map(shown)
            return card
        }
    }

    /// When a request's buttons start taking clicks, or nil while the panel is shut.
    func armsAt(_ item: Pending, panelOpenedAt: Date?) -> Date? {
        panelOpenedAt.map { max($0, item.receivedAt, changedAt, movedAt[item.id] ?? .distantPast).addingTimeInterval(Self.armAfter) }
    }

    static func accepts(clickAt: Date, panelOpenedAt: Date?, receivedAt: Date, changedAt: Date) -> Bool {
        guard let panelOpenedAt else { return false }
        return [panelOpenedAt, receivedAt, changedAt].allSatisfy { clickAt.timeIntervalSince($0) >= armAfter }
    }

    /// Whether a click that leaves for a session's app counts, by when it was made. Answered,
    /// a request gives up its place, and the name of the next session comes up to where the
    /// answer was clicked: a second click there was aimed at the button, and would take the
    /// person to an app they did not ask for. The same moment an answer has to wait.
    func goes(clickAt: Date) -> Bool {
        clickAt.timeIntervalSince(changedAt) >= Self.armAfter
    }
}
