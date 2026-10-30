import CoreServices
import Foundation

struct TrackedFile: Equatable {
    var session: String
    var isMain: Bool
    var info = AgentInfo()
    var offset: UInt64 = 0
    var modified = Date.distantPast
    var metaLoaded = false
    /// When the person last saw this file's hand-back. Memory only.
    var seenAt: Date?

    /// When the agent last did something. The file's own time stands in until a conversation line carries one.
    var activity: Date { info.lastActivity ?? modified }
}

struct AgentRow: Identifiable, Equatable {
    let id: String
    let info: AgentInfo
    let status: AgentStatus
    let elapsed: TimeInterval
    /// How long since the row last moved, or since its session began waiting on the person.
    /// 0 for a finished row.
    var quietFor: TimeInterval = 0
    /// Shown as quiet although Claude Code calls it busy: nothing has been written for so long
    /// that nobody can say it works. The line under the row says that much and no more.
    var calledBusy = false
    /// When the person last saw this row's hand-back.
    var handBackSeenAt: Date?
    /// What it ended its turn to wait on, as its step says it: work of its own, which wakes it when done.
    var waitingOn: String?

    /// Finished and handed something back to its lead.
    var handsBack: Bool { status == .done && info.handedBackAt != nil }

    /// A hand-back the person has not looked at yet, or one that came again after the look.
    var awaitsLook: Bool {
        guard handsBack, let back = info.handedBackAt else { return false }
        return handBackSeenAt.map { $0 < back } ?? true
    }

    /// Quiet or asking: the person may have to do something before this agent moves again.
    var mayNeedPerson: Bool { status == .quiet || status == .needsYou }

    /// The step as the row shows it. While the row waits on the person with no words of its
    /// own, as when Claude Code asks leave to run a command, the step by what it runs: the
    /// person came to see what is asked. While it works with no call open, where it is headed.
    /// At any other time, by what it is called.
    var step: String {
        if let waitingOn { return waitingOn }
        if status == .needsYou, !info.asking, !info.lastStepAsRun.isEmpty { return info.lastStepAsRun }
        if status == .working, info.openTools.isEmpty, !info.thought.isEmpty || !info.lastStep.isEmpty { return info.betweenCalls }
        return info.lastStep
    }

    /// Waiting on a question it wrote down, which the row can show. A wait Claude Code only
    /// reports, such as a prompt for permission, leaves no words of its own.
    var asksInWords: Bool { status == .needsYou && info.asking }

    /// Called busy by Claude Code, with nothing written for as long as would otherwise make it
    /// quiet: a long command, or a hung one.
    var isStalled: Bool { status == .working && quietFor >= TranscriptReader.quietAfter }

    /// What it is doing while it works, by its newest call without a result.
    var activity: Activity? {
        guard status == .working else { return nil }
        // A job runs in a terminal of its own, whatever kind it is.
        return waitingOn == nil ? Activity(tool: info.openTools.last?.tool) : .running
    }
}

/// The number on the collapsed bar. Agents that may need the person are their own state: they
/// must not look the same as everything having finished.
enum BarState: Equatable {
    /// This many agents have a question or a request up. It comes before everything else, and
    /// the count of those still working stays beside it.
    case needsYou(Int, working: Int)
    case working(Int)
    /// Nothing is working; this many are quiet or need the person.
    case quiet(Int)
    case idle
}

extension BarState {
    /// How many agents wait on the person.
    var waiting: Int {
        if case .needsYou(let count, _) = self { return count }
        return 0
    }

}

/// Whether the person has looked since someone last started to wait. Opening the panel is how
/// they say "seen": the bar stops beating then, and the red count stays.
struct WaitWatch: Equatable {
    /// How many times the panel had been looked at when the wait began, less one if the pointer
    /// was on the open panel at that moment: then it was seen as it happened. A look is an
    /// opening that lasted: a pointer brushing the bar on its way to a menu is not one.
    private var looksAtArrival = 0

    mutating func arrived(looks: Int, lookingNow: Bool) {
        looksAtArrival = lookingNow ? looks - 1 : looks
    }

    func seen(looks: Int) -> Bool {
        looks > looksAtArrival
    }

    /// Whether one more agent has started to wait on the person: the one event the bar marks
    /// as it happens. Everything else it shows is a state to be found at a glance. Told by
    /// which sessions wait and how many rows in each, not by one count for all: a session
    /// answered as another starts leaves that count as it was. Not by the rows themselves: a
    /// request moves from the session's own row to its sub-agent's once that is known, and that
    /// is the same wait.
    static func arrived(from old: [String: Int], to new: [String: Int]) -> Bool {
        new.contains { $0.value > old[$0.key, default: 0] }
    }

    /// The first card, in list order, with more rows waiting than before: the one whose lead
    /// speaks for an arrival.
    static func risen(from old: [String: Int], to new: [String: Int], in cards: [SessionCard]) -> SessionCard? {
        cards.first { new[$0.id, default: 0] > old[$0.id, default: 0] }
    }

    /// Whether the person is at the panel as a wait begins: it has been open under the pointer
    /// long enough to count as a look. An opening younger than that may be a pointer passing,
    /// and may never count. A pinned panel is open with nobody at it.
    /// `inView`: the list is showing and whoever waits is not past its edge. Open on the
    /// settings the person is looking at something else.
    static func looking(openFor: TimeInterval?, pinned: Bool, inView: Bool) -> Bool {
        !pinned && inView && (openFor ?? 0) >= EntryWatch.look
    }

    /// Whether whoever has started to wait is where the person can see them: the list is
    /// showing, and none of them is past its bottom edge. In a list grouped by status a card
    /// goes to the head of the list as it starts to wait, so there the list has to be at its
    /// top as well: scrolled down, the card has gone above what is in view.
    static func inView(showingList: Bool, pastEdge: Bool, grouping: Grouping, atTop: Bool) -> Bool {
        showingList && !pastEdge && (grouping == .projects || atTop)
    }
}

/// Where a folder sits in git: the top of the worktree it is in, and the checkout that worktree
/// came from. The two are one folder unless the worktree is one of the checkout's own others.
struct GitPlace: Equatable {
    let worktree: String
    let checkout: String
}

struct SessionCard: Identifiable, Equatable {
    let id: String
    let project: String
    let branch: String
    var main: AgentRow?
    var agents: [AgentRow]
    let startedAt: Date
    /// The session's own title, or empty when Claude Code has not named it.
    var title = ""
    /// The app the session's terminal runs in, when Claude Code's record says which process the session is.
    var owner: OwnerApp?
    /// The session is in a worktree of its own, not in the repository's checkout.
    var worktree = false
    /// Who sits in the session, as `Roster` seated it: nil until the store has.
    var look: LeadLook?
    /// The project the session belongs to, as History names it from the folder it started in:
    /// a worktree goes with its repository. Empty when the transcript gave no folder.
    var repo = ""
    /// Where the session's folder sits in git, while git can tell.
    var git: GitPlace?
    /// Background jobs the session still has running, oldest first.
    var jobs: [BackgroundJob] = []
    /// Listed only because it has jobs: its agents are old enough that it would be gone without them.
    var onlyForJobs = false
    /// The machine keeps records of live sessions, and this one has none: its terminal is closed.
    var closed = false
}

extension SessionCard {
    var rows: [AgentRow] { [main].compactMap { $0 } + agents }

    /// The project the list puts the session under: its folder when it knows no other.
    var belongsTo: String { repo.isEmpty ? project : repo }

    /// What tells one project from another: its checkout, as two may share a name. Its name
    /// when git cannot tell.
    var projectKey: String { git?.checkout ?? belongsTo }

    /// What the session is called: its own title, or its folder until Claude Code has named it.
    var name: String { title.isEmpty ? project : title }

    /// Every agent has finished. A quiet one may be waiting on the person, so it does not count.
    var isIdle: Bool { !rows.isEmpty && rows.allSatisfy { $0.status == .done } }

    /// Subagents that are not finished: each keeps a row of its own. So does a finished one in
    /// `holding`: it has a line under it that would be lost in the fold.
    func liveAgents(holding: Set<String> = []) -> [AgentRow] { agents.filter { $0.status != .done || holding.contains($0.id) } }

    /// Finished subagents, folded into one line so they do not push live work off the panel.
    func doneAgents(holding: Set<String> = []) -> [AgentRow] { agents.filter { $0.status == .done && !holding.contains($0.id) } }

    /// How many subagents work on after the main agent ended its turn. The session is not idle then.
    var workingAfterMain: Int { main?.status == .done ? agents.filter { $0.status == .working }.count : 0 }

    /// When any agent of the session last did something.
    var movedAt: Date? { rows.compactMap(\.info.lastActivity).max() }

    /// Nothing is working and something is quiet or asking: a session that may have been closed
    /// with a question up, which would otherwise keep flagging the bar for up to an hour.
    var canHide: Bool { rows.contains(where: \.mayNeedPerson) && !rows.contains { $0.status == .working } }

    /// The app to send the person to: the session's own, while one of its agents waits on them.
    var goTo: OwnerApp? { rows.contains { $0.status == .needsYou } ? owner : nil }

    /// Claude Code calls it busy, and every row it calls busy has been silent for a long while:
    /// a long command, or a hung one. One row at work is enough to say the session moves: a
    /// main agent is silent as a matter of course while the agents it started work.
    var isStuck: Bool {
        let busy = rows.filter { $0.status == .working }
        return !busy.isEmpty && busy.allSatisfy { $0.quietFor >= AgentStore.stuckAfter }
    }

    /// The card as the panel shows it. In a session that may be stuck the rows called busy are
    /// quiet: no activity is all that is known of them, and "quiet" is the one word the panel
    /// has for that. A second word for it was one more thing to learn. How long stays with the row.
    var asShown: SessionCard {
        guard isStuck else { return self }
        func quiet(_ row: AgentRow) -> AgentRow {
            row.status == .working ? AgentRow(id: row.id, info: row.info, status: .quiet, elapsed: row.elapsed, quietFor: row.quietFor, calledBusy: true) : row
        }
        var card = self
        card.main = main.map(quiet)
        card.agents = agents.map(quiet)
        return card
    }
}

/// The sessions as the panel lists them: full cards, then the idle ones folded into one line.
struct SessionList: Equatable {
    var cards: [SessionCard]
    var folded: [SessionCard]
    /// Cards under a project's line the person has shut, by id: the line stays, they are not drawn.
    var shut: Set<String> = []
}

extension SessionList {
    /// The cards the arrow keys walk, in the order drawn: the full cards, and after them the
    /// idle ones while they are unfolded. Unfolded they are cards like the rest, and Return
    /// on one is the only way to its app that needs no pointer.
    func walked(idleExpanded: Bool) -> [SessionCard] { drawn + (idleExpanded ? folded : []) }

    /// Whether the sessions run in more than one app. Only then does naming a card's app tell
    /// it from the others: the name and the "Go to" button reach the app either way.
    var showsApps: Bool { Set((drawn + folded).compactMap { $0.owner?.name }).count > 1 }

    /// The full cards that are drawn: those under a shut project's line are not.
    var drawn: [SessionCard] { cards.filter { !shut.contains($0.id) } }

    /// The first row that needs the person, in the order the list is drawn, and its card:
    /// where every way into the panel leads.
    var firstWaiting: (card: SessionCard, row: AgentRow)? {
        for card in cards {
            if let row = card.rows.first(where: { $0.status == .needsYou }) { return (card, row) }
        }
        return nil
    }

    /// The one row that carries the line explaining "quiet": the first quiet one in the list.
    /// The line says the same thing each time, and once is enough.
    var hintRow: String? { drawn.lazy.flatMap(\.rows).first { $0.status == .quiet }?.id }
}

/// What a session is doing, for the list that groups by it. In the order the groups are shown.
enum StatusGroup: Int, CaseIterable {
    case needsYou, working, quiet, idle

    /// What an agent is doing when it is what puts its session in this group. None for the
    /// idle: a session is idle for what none of its agents is doing.
    var status: AgentStatus? {
        switch self {
        case .needsYou: return .needsYou
        case .working: return .working
        case .quiet: return .quiet
        case .idle: return nil
        }
    }
}

extension SessionCard {
    /// The group the session is listed under: by the most pressing of its rows, whichever
    /// agent's that is.
    var group: StatusGroup {
        if rows.contains(where: { $0.status == .needsYou }) { return .needsYou }
        if rows.contains(where: { $0.status == .working }) { return .working }
        if rows.contains(where: { $0.status == .quiet }) { return .quiet }
        return .idle
    }
}

/// The line over the first card of a group: which group, and how many sessions it holds.
struct GroupHeader: Equatable {
    let group: StatusGroup
    let count: Int
    /// How many agents in those sessions are doing what the group is named for, which is what
    /// the line under the notch counts. At least one to a session, and none for the idle.
    var agents = 0
}

/// The line over a project's first card: the project, how many folders its sessions are in,
/// and how many sessions.
struct ProjectHeader: Equatable {
    let project: String
    let worktrees: Int
    let sessions: Int
}

enum TranscriptPath: Equatable {
    case main(session: String)
    case sub(session: String)
}

/// The only place that reads the disk, the clock and the process table. Only ever reads under
/// `root` and the session records beside it, and never writes.
final class AgentStore: ObservableObject {
    static let defaultVisibleFor: TimeInterval = 600
    /// An agent with a question on screen stays listed this long: being found late is the point.
    static let askingVisibleFor: TimeInterval = 3600
    static let forgetAfter: TimeInterval = 24 * 3600
    /// A read can land while Claude Code rewrites a record in place. Past this many failed reads in
    /// a row the record is unreadable for good, or says something this app does not know: no record.
    static let staleReadLimit = 3

    @Published private(set) var sessions: [SessionCard] = []
    /// Who sits in each session, by session id, sessions no longer listed included.
    @Published private(set) var looks: [String: LeadLook] = [:]
    @Published private(set) var rootMissing = false
    /// False until the first scan has been published: an empty list before that means "not read yet".
    @Published private(set) var loaded = false

    let root: String
    /// Where Claude Code keeps a record of each live session.
    let sessionsFolder: String
    private(set) var files: [String: TrackedFile] = [:]
    /// What Claude Code says each live session is doing, by session id.
    private(set) var states: [String: SessionState] = [:]
    /// The last whole reading of each record file and how many reads in a row have failed since,
    /// by file name. Only touched on `queue`.
    private var records: [String: (record: SessionRecord, misses: Int)] = [:]
    private let processStart: (Int32) -> Date?
    /// The sessions a running Claude Code holds a record of, with when that process started, by session id. Only touched on `queue`.
    private var runningSince: [String: Date] = [:]
    /// Sessions the SessionStart hook seated whose record has not been read yet, and when: they
    /// count as busy for a minute, so sessions started together get two people. Only on `queue`.
    private var introducedAt: [String: Date] = [:]
    /// Whether the sessions folder could be listed. A Claude Code that keeps no records has none; one that removed its last record on exit has the folder, empty. Only touched on `queue`.
    private var keepsRecords = false
    /// Who sits in which session. Only touched on `queue`.
    private var roster: Roster
    /// Where the roster is kept, or nil to keep it in memory only.
    private let rosterFile: URL?
    private let owner: (Int32) -> OwnerApp?
    /// Whether the terminal a Claude Code process runs in can draw the name tags, so the notes can hand them over.
    private let drawsTags: (CrewIntroRequest) -> Bool
    /// Finds the tab of a session's process in its app.
    private let tab: (Int32, OwnerApp) -> TabPlace?
    /// Whether the person has asked for a click to reach a session's own tab. While they have
    /// not, no card is given one; the send route still looks up its own, with no Apple event.
    /// Only touched on `queue`.
    private var tabs = false
    /// The app each live session runs in, by session id.
    private(set) var owners: [String: OwnerApp] = [:]
    /// The app found for each Claude Code process, by pid and when the process began. Only touched on `queue`.
    private var owned: [Int32: (startedAt: Date, app: OwnerApp, route: SendRoute)] = [:]
    /// The way each live session can be told something, by session id. Only touched on `queue`.
    private var reachNow: [String: SessionReach] = [:]
    /// The same, handed to the main thread.
    @Published private(set) var reach: [String: SessionReach] = [:]
    private let queue = DispatchQueue(label: "agent-valley.store")
    private var stream: FSEventStreamRef?
    private var timer: DispatchSourceTimer?
    private var watching = false
    /// Whether the first scan has run. Only touched on `queue`.
    private var scanned = false
    /// How long a finished session or agent stays on screen. Only touched on `queue`.
    private var visibleFor = AgentStore.defaultVisibleFor
    /// Hand-backs older than this launch are not news.
    private let launchedAt = Date()
    /// Every hand-back kept for good, and when each was last seen. Nil when the database would not open.
    let library: LibraryStore?
    /// The seen marks the library held when first asked, kept current by `saw`. Only touched on `queue`.
    private lazy var marks: [String: Date] = library?.seenMarks() ?? [:]
    /// The sub-agent folders whose git place the library was given this run. Only touched on `queue`.
    private var learned = Set<String>()
    /// When the library was last told the app is running. Only touched on `queue`.
    private var aliveAt = Date.distantPast
    /// The launch's catch-up has run. Until then no stamp: a quit mid catch-up must not skip what it had left to read.
    private var caughtUp = false

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
         visibleFor: TimeInterval = AgentStore.defaultVisibleFor,
         sessions: URL? = nil,
         processStart: @escaping (Int32) -> Date? = AgentStore.startTime(ofProcess:),
         owner: @escaping (Int32) -> OwnerApp? = AgentStore.ownerApp(ofProcess:),
         tab: @escaping (Int32, OwnerApp) -> TabPlace? = AgentStore.tabPlace(ofProcess:in:),
         roster: URL? = nil,
         library: LibraryStore? = nil,
         drawsTags: @escaping (CrewIntroRequest) -> Bool = { AgentStore.terminalDrawsTags($0) }) {
        self.library = library
        self.rosterFile = roster
        self.drawsTags = drawsTags
        self.roster = roster.map(Roster.load) ?? Roster()
        self.owner = owner
        self.tab = tab
        self.root = root.resolvingSymlinksInPath().path
        self.visibleFor = visibleFor
        self.sessionsFolder = (sessions ?? root.deletingLastPathComponent().appendingPathComponent("sessions")).path
        self.processStart = processStart
    }

    var quietCount: Int {
        sessions.reduce(0) { count, card in count + card.rows.filter { $0.status == .quiet }.count }
    }

    var needsYouCount: Int {
        sessions.reduce(0) { count, card in count + card.rows.filter { $0.status == .needsYou }.count }
    }

    var workingCount: Int {
        sessions.reduce(0) { count, card in count + card.rows.filter { $0.status == .working }.count }
    }

    func start() {
        queue.async { [self] in
            // The records first: they say which silent transcripts the scan still has to read.
            readSessions()
            scan()
            scanned = true
            publish()
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    /// The person has looked at the hand-backs of these rows (file paths). `then` runs on the main
    /// thread once the library has it too, for a page that reads the library again.
    func saw(_ ids: Set<String>, at time: Date, then: (() -> Void)? = nil) {
        // Each look and each rest on a pinned panel calls this, mostly with nothing seen.
        guard !ids.isEmpty else { return }
        queue.async { [self] in
            for id in ids {
                files[id]?.seenAt = time
                marks[id] = max(marks[id] ?? .distantPast, time)
            }
            library?.saw(agents: ids, at: time)
            publish()
            if let then { DispatchQueue.main.async(execute: then) }
        }
    }

    /// Applies the "Keep finished for" setting. The folder is walked again only once it is being
    /// watched and the window has grown; before that, `start` does the first walk.
    func setVisibleFor(_ seconds: TimeInterval) {
        queue.async { [self] in
            let grew = Self.windowGrew(from: visibleFor, to: seconds)
            visibleFor = seconds
            if grew && watching { rescan() }
            publish()
        }
    }

    /// Applies the "Go to the session's tab" setting.
    func setTabs(_ on: Bool) {
        queue.async { [self] in applyTabs(on) }
    }

    /// The same, on the caller's own thread. Each app already found gains or loses its tab
    /// where it stands: looked for again, one that has been closed since would not be found.
    func applyTabs(_ on: Bool) {
        guard tabs != on else { return }
        tabs = on
        for (pid, known) in owned {
            var app = known.app
            app.tab = on ? tab(pid, app) : nil
            owned[pid] = (known.startedAt, app, known.route)
        }
    }

    /// Whether a scan now has to look further back than the last one did. A window under the
    /// default scans the default anyway, for agents that are mid-turn.
    static func windowGrew(from old: TimeInterval, to new: TimeInterval) -> Bool {
        max(new, defaultVisibleFor) > max(old, defaultVisibleFor)
    }

    static func count(_ status: AgentStatus, in sessions: [SessionCard]) -> Int {
        sessions.reduce(0) { count, card in count + card.rows.filter { $0.status == status }.count }
    }

    /// Whoever the bar's mascot stands for: the agent most worth a look. One that waits on the
    /// person, else one gone quiet, else one at work, and of those one that has moved lately
    /// before one gone silent. The count of those at work stands beside the red one, so the
    /// mascot need not be the thing that says work goes on.
    static func lead(_ sessions: [SessionCard]) -> AgentRow? {
        crowd(sessions).first
    }

    /// Who sits in each session, by the id of its main row.
    static func looks(_ sessions: [SessionCard]) -> [String: LeadLook] {
        Dictionary(sessions.compactMap { card in card.main.flatMap { main in card.look.map { (main.id, $0) } } }) { first, _ in first }
    }

    /// Every agent not yet done, in the order the lead is picked by: the crowd that stands
    /// behind the bar's mascot while the panel is open.
    static func crowd(_ sessions: [SessionCard]) -> [AgentRow] {
        let rows = sessions.flatMap(\.rows)
        return rows.filter { $0.status == .needsYou } + rows.filter { $0.status == .quiet }
            + rows.filter { $0.status == .working && !$0.isStalled } + rows.filter { $0.status == .working && $0.isStalled }
    }

    /// How long the longest of the waits on the person has run, nil with nobody waiting.
    static func longestWait(_ sessions: [SessionCard]) -> TimeInterval? {
        sessions.flatMap(\.rows).filter { $0.status == .needsYou }.map(\.quietFor).max()
    }

    /// The row that started waiting last, with its card: the one the island's alert is about.
    static func newestWait(_ sessions: [SessionCard]) -> (card: SessionCard, row: AgentRow)? {
        sessions.flatMap { card in card.rows.filter { $0.status == .needsYou }.map { (card: card, row: $0) } }
            .min { $0.row.quietFor < $1.row.quietFor }
    }

    /// How many rows wait on the person in each session that has any.
    static func waiting(_ sessions: [SessionCard]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.rows.filter { $0.status == .needsYou }.count) }.filter { $0.1 > 0 })
    }

    /// The rows that wait on the person below the list's bottom edge: every such row of a card
    /// that starts under the edge, and those under the edge in a card that starts above it.
    static func waitingBelow(_ sessions: [SessionCard], cards: Set<String>, rows: Set<String>) -> [AgentRow] {
        sessions.flatMap { card in
            card.rows.filter { $0.status == .needsYou && (cards.contains(card.id) || rows.contains($0.id)) }
        }
    }

    static func barState(_ sessions: [SessionCard]) -> BarState {
        let rows = sessions.flatMap(\.rows)
        let waiting = rows.filter { $0.status == .needsYou }.count
        let working = rows.filter { $0.status == .working }.count
        if waiting > 0 { return .needsYou(waiting, working: working) }
        if working > 0 { return .working(working) }
        let quiet = rows.filter { $0.status == .quiet }.count
        return quiet > 0 ? .quiet(quiet) : .idle
    }

    /// How long every busy row of a session has to be silent before the session is shown as quiet.
    static let stuckAfter: TimeInterval = 600

    /// The mark on the bar's mascot: red when an agent needs the person, white when one is only quiet.
    static func flag(_ sessions: [SessionCard]) -> MascotFlag? {
        let rows = sessions.flatMap(\.rows)
        if rows.contains(where: { $0.status == .needsYou }) { return .needsYou }
        return rows.contains(where: { $0.status == .quiet }) ? .quiet : nil
    }

    /// Whether the person has put this session away and it has not moved since.
    private static func isAway(_ card: SessionCard, hidden: [String: Date]) -> Bool {
        guard let since = hidden[card.id] else { return false }
        return (card.movedAt ?? .distantPast) <= since
    }

    /// The sessions without those the person has put away. One comes back as soon as it moves.
    static func showing(_ sessions: [SessionCard], hidden: [String: Date]) -> [SessionCard] {
        sessions.filter { !isAway($0, hidden: hidden) }
    }

    /// The sessions the person has put away, so the panel can say so and bring them back: one
    /// that waits on the person does not move by itself.
    static func putAway(_ sessions: [SessionCard], hidden: [String: Date]) -> [SessionCard] {
        sessions.filter { isAway($0, hidden: hidden) }
    }

    /// `keeping`: sessions, by the name of their transcript, that keep their card although
    /// idle. Each has a line on it that says how a request ended, and a folded card has no
    /// place for it.
    /// `shut`: the projects, by `projectKey`, whose line the person has clicked shut.
    static func arrange(_ sessions: [SessionCard], idle: IdleSessions, keeping: Set<String> = [], shut projects: Set<String> = []) -> SessionList {
        func folds(_ card: SessionCard) -> Bool { card.isIdle && card.jobs.isEmpty && !keeping.contains(AnswerStore.sessionID(of: card)) }
        var list: SessionList
        switch idle {
        case .show: list = SessionList(cards: sessions, folded: [])
        case .hide: list = SessionList(cards: sessions.filter { !folds($0) }, folded: [])
        case .fold: list = SessionList(cards: sessions.filter { !folds($0) }, folded: sessions.filter(folds))
        }
        // A shut project never hides what needs the person. One session alone has no line, and
        // so nothing to open it again with: it is never shut.
        if list.cards.count + list.folded.count >= 2 {
            list.shut = Set(list.cards.filter { projects.contains($0.projectKey) && $0.group != .needsYou }.map(\.id))
        }
        return list
    }

    /// The sessions in the order the panel lists them. By project, each project's sessions
    /// stand together, the projects in the order their newest session came. By status, those
    /// that wait on the person come first, the longest wait first, then those at work, the quiet
    /// and the idle. Inside the other groups the order they came in is kept.
    static func ordered(_ sessions: [SessionCard], by grouping: Grouping) -> [SessionCard] {
        // Gathered, not sorted: gathering keeps each group in the order it came in, which a
        // sort does not promise, and works out each card's group once.
        switch grouping {
        case .projects:
            var seen = Set<String>()
            let order = sessions.map(\.projectKey).filter { seen.insert($0).inserted }
            let groups = Dictionary(grouping: sessions, by: \.projectKey)
            return order.flatMap { groups[$0] ?? [] }
        case .status:
            let groups = Dictionary(grouping: sessions, by: \.group)
            // The oldest wait is the one to answer first. A wait's start does not move, so one that
            // begins joins the end and those above stay put. Ties keep the order they came in.
            let waiting = (groups[.needsYou] ?? []).enumerated().map { ($0, longestWait([$1]) ?? 0, $1) }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map(\.2)
            return waiting + StatusGroup.allCases.filter { $0 != .needsYou }.flatMap { groups[$0] ?? [] }
        }
    }

    /// The line over each project's first card, by card id. `cards` are the cards drawn, in
    /// the order `ordered` gave them.
    static func projectHeaders(of cards: [SessionCard]) -> [String: ProjectHeader] {
        let groups = Dictionary(grouping: cards, by: \.projectKey)
        return Dictionary(uniqueKeysWithValues: groups.values.compactMap { cards in
            cards.first.map { ($0.id, ProjectHeader(project: $0.belongsTo, worktrees: Set(cards.map { $0.git?.worktree ?? $0.project }).count, sessions: cards.count)) }
        })
    }

    /// The cards a group's line stands over, by card id: the first of each group, with how
    /// many of the cards are in it. None when the list is not grouped. `cards` are the cards
    /// drawn, in the order `ordered` gave them.
    static func headers(of cards: [SessionCard], by grouping: Grouping) -> [String: GroupHeader] {
        guard grouping == .status else { return [:] }
        var first: [StatusGroup: String] = [:]
        var counts: [StatusGroup: Int] = [:]
        var agents: [StatusGroup: Int] = [:]
        for card in cards {
            let group = card.group
            if first[group] == nil { first[group] = card.id }
            counts[group, default: 0] += 1
            agents[group, default: 0] += card.rows.filter { $0.status == group.status }.count
        }
        return Dictionary(uniqueKeysWithValues: first.map { group, id in
            (id, GroupHeader(group: group, count: counts[group] ?? 0, agents: agents[group] ?? 0))
        })
    }

    /// `<project>/<session>.jsonl` is a main transcript; `<project>/<session>/subagents/**/agent-*.jsonl`
    /// is a subagent. Every other file, including a workflow's `journal.jsonl`, is ignored.
    static func classify(_ path: String, root: String) -> TranscriptPath? {
        guard path.hasPrefix(root + "/"), path.hasSuffix(".jsonl") else { return nil }
        let parts = path.dropFirst(root.count + 1).split(separator: "/").map(String.init)
        if parts.count == 2 {
            return .main(session: root + "/" + parts[0] + "/" + String(parts[1].dropLast(".jsonl".count)))
        }
        guard parts.count >= 4, parts[2] == "subagents", parts[parts.count - 1].hasPrefix("agent-") else { return nil }
        return .sub(session: root + "/" + parts[0] + "/" + parts[1])
    }

    /// Reads whatever was appended to `path` since the last call.
    func ingest(path: String) {
        guard let kind = Self.classify(path, root: root) else { return }
        let session: String
        let isMain: Bool
        switch kind {
        case .main(let key): (session, isMain) = (key, true)
        case .sub(let key): (session, isMain) = (key, false)
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else {
            files[path] = nil
            return
        }
        func fresh() -> TrackedFile {
            var file = TrackedFile(session: session, isMain: isMain)
            file.seenAt = marks[path]
            return file
        }
        var file = files[path] ?? fresh()
        if size < file.offset { file = fresh() }
        let titled = file.info.title
        file.modified = modified
        // ponytail: the first read parses the whole transcript, a piece at a time; seek to a tail
        // window if a huge main transcript ever makes launch slow.
        if size > file.offset, let handle = FileHandle(forReadingAtPath: path) {
            defer { try? handle.close() }
            if (try? handle.seek(toOffset: file.offset)) != nil {
                file.offset += TranscriptReader.readLines(from: handle) { TranscriptReader.apply(line: $0, to: &file.info) }
            }
        }
        if isMain {
            file.info.type = "main"
        } else if !file.metaLoaded,
                  let meta = FileManager.default.contents(atPath: String(path.dropLast(".jsonl".count)) + ".meta.json") {
            // A meta file caught half-written is read again on the next event.
            file.metaLoaded = TranscriptReader.applyMeta(meta, to: &file.info)
        }
        var held = false
        if let library {
            let book = (session as NSString).lastPathComponent
            if isMain {
                if !file.info.title.isEmpty, file.info.title != titled { library.title(session: book, file.info.title) }
            } else if !file.info.records.isEmpty {
                // A write that fails keeps them for the next read to try again.
                held = !library.add(Chapter.from(file.info, agent: path, session: book))
                // Asked while the folder stands: a worktree removed later still sits on its checkout's shelf.
                if !held, learned.insert(file.info.cwd).inserted { library.learn(gitFolder: file.info.cwd) }
            }
        }
        if !held { file.info.records = [] }
        files[path] = HandBack.seenBeforeLaunch(file, launchedAt: library?.since ?? launchedAt)
        // A subagent can keep writing long after its parent's last write; the card header needs the parent.
        if !isMain, files[session + ".jsonl"] == nil { ingest(path: session + ".jsonl") }
    }

    /// What the system knows of the process with this pid, or nil when no such process is running.
    private static func info(ofProcess pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        // Exited, and only waiting for its parent to collect it: not running.
        return info.kp_proc.p_stat == CChar(SZOMB) ? nil : info
    }

    private static func startDate(_ info: kinfo_proc) -> Date {
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    private static func ttyPath(_ info: kinfo_proc) -> String? {
        let device = info.kp_eproc.e_tdev
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// When the process with this pid started, or nil when no such process is running.
    static func startTime(ofProcess pid: Int32) -> Date? {
        info(ofProcess: pid).map(startDate)
    }

    /// The process that started this one, or nil when no such process is running.
    static func parent(ofProcess pid: Int32) -> Int32? {
        info(ofProcess: pid)?.kp_eproc.e_ppid
    }

    /// The terminal device a process is attached to, such as "/dev/ttys012", or nil when it
    /// has none or no such process is running.
    static func tty(ofProcess pid: Int32) -> String? {
        info(ofProcess: pid).flatMap(ttyPath)
    }

    /// Terminal, process groups and start time of a process from one reading, or nil when no
    /// such process is running.
    static func facts(ofProcess pid: Int32) -> ProcessFacts? {
        guard let info = info(ofProcess: pid) else { return nil }
        return ProcessFacts(tty: ttyPath(info), group: info.kp_eproc.e_pgid, ttyGroup: info.kp_eproc.e_tpgid, startedAt: startDate(info))
    }

    /// Whether the record a pid holds says its session waits on the person, read from disk now:
    /// the store's own reading can be a second old, and a prompt may have opened since.
    static func recordWaitsOnPerson(pid: Int32, sessions folder: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: folder + "/\(pid).json") else { return false }
        return SessionRecords.parse(data)?.state.activity == .waiting
    }

    /// Reads Claude Code's own record of each live session. Only files named `<pid>.json` are opened.
    // ponytail: read on the one-second tick, a handful of small files; watch the folder if it ever shows in a profile.
    func readSessions() {
        let listing = try? FileManager.default.contentsOfDirectory(atPath: sessionsFolder)
        keepsRecords = listing != nil
        let names = (listing ?? []).filter(SessionRecords.isRecordName)
        var read: [String: (record: SessionRecord, misses: Int)] = [:]
        for name in names {
            guard let data = FileManager.default.contents(atPath: sessionsFolder + "/" + name) else { continue }
            if let record = SessionRecords.parse(data) {
                read[name] = (record, 0)
            } else if let last = records[name], last.misses < Self.staleReadLimit {
                // Claude Code rewrites a record in place: one caught empty or cut short keeps its last whole reading.
                read[name] = (last.record, last.misses + 1)
            }
        }
        let last = records
        records = read
        let live = SessionRecords.live(from: read.values.map(\.record), processStart: processStart)
        // A session whose record went away is run by no Claude Code: /clear moves the record to a
        // new session id, and exit removes it or leaves it to a dead pid. Its transcript can stop
        // mid-turn, and would read as at work for ten minutes, the bar's mascot standing for it.
        // Idle until a record holds it again. A record still there that can't be read says
        // nothing, as before: it may be a state this app does not know yet.
        // ponytail: grows by one id per session closed while the app runs; a restart clears it.
        let unread = Set(names.filter { read[$0] == nil }.compactMap { last[$0]?.record.sessionId })
        let gone = Set(states.keys).subtracting(live.keys).subtracting(unread).map { ($0, SessionState(activity: .idle)) }
        states = live.mapValues(\.state).merging(gone) { held, _ in held }
        runningSince = live.mapValues(\.startedAt)
        // Once its record is read, the record speaks for a session the hook seated.
        let readAt = Date()
        introducedAt = introducedAt.filter { live[$0.key] == nil && readAt.timeIntervalSince($0.value) < 60 }
        // A process keeps its ancestors: an app once found is kept, and forgotten with its record.
        // One not found is looked for again, as the app may only be closed for now.
        var found: [Int32: (startedAt: Date, app: OwnerApp, route: SendRoute)] = [:]
        for record in live.values {
            if let known = owned[record.pid], known.startedAt == record.startedAt {
                found[record.pid] = known
            } else if var app = owner(record.pid) {
                if tabs { app.tab = tab(record.pid, app) }
                // The route's own tab lookup does not depend on the setting: it sends no Apple event.
                let route = SendRoute.route(bundleID: Bundle(url: app.bundle)?.bundleIdentifier,
                                            environment: { Self.environmentValue($0, ofProcess: record.pid) },
                                            tab: { [app] in self.tab(record.pid, app) })
                found[record.pid] = (record.startedAt, app, route)
            }
        }
        owned = found
        owners = live.compactMapValues { found[$0.pid]?.app }
        // An app not found is the stop hook's, and looked for again on the next read. The process
        // carries the kernel's start time, which the tab guard compares: the record's own is a
        // second or two later.
        reachNow = live.compactMapValues { record in
            processStart(record.pid).map {
                SessionReach(process: SessionProcess(pid: record.pid, startedAt: $0),
                             route: found[record.pid]?.route ?? .stopHook,
                             waitingOnPerson: record.state.activity == .waiting)
            }
        }
    }

    /// The record states for the transcripts they speak for, keyed like `TrackedFile.session`.
    /// Claude Code can leave a stub with the same session id in a second project folder; the record
    /// belongs to the transcript that last carried conversation.
    static func claims(_ states: [String: SessionState], files: [String: TrackedFile]) -> [String: SessionState] {
        guard !states.isEmpty else { return [:] }
        var holders: [String: (session: String, at: Date)] = [:]
        for file in files.values where file.isMain {
            let id = (file.session as NSString).lastPathComponent
            // A stub has no conversation line. It must not take the record when the real transcript
            // is one the app has not read, silent since before launch.
            guard states[id] != nil, let at = file.info.lastActivity else { continue }
            if let other = holders[id], (other.at, other.session) >= (at, file.session) { continue }
            holders[id] = (file.session, at)
        }
        var claimed: [String: SessionState] = [:]
        for (id, holder) in holders { claimed[holder.session] = states[id] }
        return claimed
    }

    /// What a session's record says about one of its rows. "Waiting" goes to the main row only:
    /// the record does not say which agent the person is holding up.
    static func signal(for file: TrackedFile, in claimed: [String: SessionState]) -> SessionState? {
        guard let state = claimed[file.session] else { return nil }
        return file.isMain || state.activity != .waiting ? state : nil
    }

    /// Applies the visibility rule: subagents by their own age, a main transcript for as long as
    /// anything in its session is fresh. `visibleFor` is for agents that have finished; one still
    /// in the middle of a turn keeps at least the default window, or a long command would hide it.
    static func visible(_ files: [String: TrackedFile], now: Date, visibleFor: TimeInterval = AgentStore.defaultVisibleFor,
                        claimed: [String: SessionState] = [:], holding: Set<String> = [], waiting: Set<String> = []) -> [String: TrackedFile] {
        // A file with no conversation line is not an agent anyone ran: some other program's
        // file under the folder, a stub Claude Code left behind, or one cut off before its first
        // line ended. Its own time used to stand in, and each such file was listed as an agent
        // at work, by the name "Claude Code".
        let files = files.filter { $0.value.info.lastActivity != nil }
        let fresh = files.filter {
            // Claude Code says the session is at work or waiting on the person: its card stays,
            // however long the transcript has been silent.
            // ponytail: a suspended Claude Code keeps saying busy, so its card stays until `forget` drops it after a day.
            if $0.value.isMain, holding.contains($0.value.session) { return true }
            if $0.value.isMain, let activity = claimed[$0.value.session]?.activity, activity != .idle { return true }
            // A sub-agent waiting on a job of its own is at work, however long the job runs.
            if waiting.contains($0.key) { return true }
            let info = $0.value.info
            // A hand-back nobody looked at stays for a day, past the keep setting; a seen one counts the keep setting from the look.
            var last = $0.value.activity
            if !$0.value.isMain, info.finished, let back = info.handedBackAt {
                if let seen = $0.value.seenAt, seen >= back { last = max(last, seen) }
                else if now.timeIntervalSince(back) < HandBack.hold { return true }
            }
            let midTurn = max(visibleFor, info.asking ? askingVisibleFor : defaultVisibleFor)
            return now.timeIntervalSince(last) < (info.finished ? visibleFor : midTurn)
        }
        let alive = Set(fresh.values.map(\.session))
        return files.filter { $0.value.isMain ? alive.contains($0.value.session) : fresh[$0.key] != nil }
    }

    /// Whether a folder lies in a linked worktree and not in the repository's own checkout:
    /// there `.git` is a file that points into the repository's `worktrees`, here a folder.
    /// A submodule's `.git` is a file as well, and points somewhere else.
    /// The folder is whatever a session was run in, a checkout nobody vouches for among them:
    /// only a plain file is read, and only its first bytes. A link is not followed, so one that
    /// leads to a pipe or to a device that never ends cannot hold the store up.
    static func isWorktree(_ folder: String) -> Bool {
        guard folder.hasPrefix("/") else { return false }
        var url = URL(fileURLWithPath: folder)
        while url.path != "/" {
            let git = url.appendingPathComponent(".git").path
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: git, isDirectory: &isFolder) {
                return !isFolder.boolValue && head(ofPlainFile: git).contains("/worktrees/")
            }
            url.deleteLastPathComponent()
        }
        return false
    }

    /// Where a folder sits in git: the worktree is the folder that holds the first `.git` on the
    /// way up, the checkout that folder, or for a worktree the checkout its `.git` file names.
    /// nil when there is no `.git`, or one that is neither a folder nor a plain file that says
    /// where its repository is. Read as `isWorktree` reads it.
    /// The git place a session in `cwd` counts as, or nil when it is in none. A home folder kept
    /// in git, for its settings, is no project. The card and the SessionStart hook both ask this.
    static func projectPlace(of cwd: String, home: String, git: (String) -> GitPlace?) -> GitPlace? {
        cwd.isEmpty ? nil : git(cwd).flatMap { $0.checkout == home ? nil : $0 }
    }

    static func gitPlace(of folder: String) -> GitPlace? {
        guard folder.hasPrefix("/") else { return nil }
        var url = URL(fileURLWithPath: folder)
        while url.path != "/" {
            let git = url.appendingPathComponent(".git").path
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: git, isDirectory: &isFolder) {
                if isFolder.boolValue { return GitPlace(worktree: url.path, checkout: url.path) }
                let text = head(ofPlainFile: git)
                guard text.hasPrefix("gitdir: ") else { return nil }
                let named = text.dropFirst("gitdir: ".count).prefix { $0 != "\n" && $0 != "\r" }
                // Written out in full, or from the worktree's own folder.
                let target = URL(fileURLWithPath: String(named), relativeTo: URL(fileURLWithPath: url.path, isDirectory: true)).standardizedFileURL.path
                // A submodule's points elsewhere: it is a checkout of its own.
                guard let worktrees = target.range(of: "/.git/worktrees/") else { return GitPlace(worktree: url.path, checkout: url.path) }
                return GitPlace(worktree: url.path, checkout: String(target[..<worktrees.lowerBound]))
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// The first bytes of a file, or nothing when the path is a link, a pipe or a device.
    /// `limit` is well past the longest path a `gitdir:` line can name.
    static func head(ofPlainFile path: String, limit: Int = 4096) -> String {
        // Not through a link, and without waiting on a pipe nobody writes to.
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return "" }
        defer { close(descriptor) }
        // Asked of the open file itself: what the path names cannot change under it.
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return "" }
        var bytes = [UInt8](repeating: 0, count: limit)
        let count = read(descriptor, &bytes, limit)
        return count > 0 ? String(decoding: bytes[..<count], as: UTF8.self) : ""
    }

    /// `states` is what Claude Code's records say, by session id; empty when there are none.
    /// `worktree` says whether a folder is in one: asked of the disk, so handed in.
    static func cards(from files: [String: TrackedFile], now: Date, visibleFor: TimeInterval = AgentStore.defaultVisibleFor,
                      states: [String: SessionState] = [:], owners: [String: OwnerApp] = [:],
                      worktree: (String) -> Bool = { _ in false }, home: String = NSHomeDirectory(),
                      git: (String) -> GitPlace? = { _ in nil }, running: [String: Date]? = nil) -> [SessionCard] {
        let claimed = claims(states, files: files)
        let jobs = BackgroundJobs.bySession(files, now: now, running: running)
        let holding = Set(jobs.filter { !$0.value.isEmpty }.keys)
        // A sub-agent that ended its turn with work of its own still running has not handed back:
        // Claude Code says so in its lead's file, and wakes it when the work ends. Until it answers
        // again, or Claude Code says it finished. After as long as a job is taken for one left
        // running on purpose, it is done, and in a closed session nobody wakes it.
        let told = Dictionary(files.values.filter(\.isMain).map { ($0.session, $0.info.waitingAgents) }, uniquingKeysWith: { $0.merging($1, uniquingKeysWith: max) })
        func isWaiting(_ path: String, _ file: TrackedFile) -> Bool {
            let agent = String(((path as NSString).lastPathComponent as NSString).deletingPathExtension.dropFirst("agent-".count))
            guard !file.isMain, let since = told[file.session]?[agent] else { return false }
            return now.timeIntervalSince(since) < BackgroundJobs.longAfter
                && (file.info.handedBackAt ?? .distantPast) <= since
                && running.map({ $0[(file.session as NSString).lastPathComponent] != nil }) ?? true
        }
        func waitingOn(_ file: TrackedFile) -> String {
            guard let job = jobs[file.session]?.first(where: { job in file.info.jobs.contains { $0.id == job.id } }) else {
                return "Waiting on its background work"
            }
            return "Waiting on " + (job.name.isEmpty ? (job.kind == .shell ? "a shell" : "a monitor") : job.name)
        }
        let waiting = Set(files.filter { isWaiting($0.key, $0.value) }.keys)
        let withoutJobs = Set(visible(files, now: now, visibleFor: visibleFor, claimed: claimed, waiting: waiting).values.map(\.session))
        // A hand-back a day old counts as seen, even when its card is still listed for other reasons.
        func seen(_ file: TrackedFile) -> Date? {
            if let back = file.info.handedBackAt, file.seenAt.map({ $0 < back }) ?? true, now.timeIntervalSince(back) >= HandBack.hold { return back }
            return file.seenAt
        }
        func row(_ path: String, _ file: TrackedFile) -> AgentRow {
            let state = signal(for: file, in: claimed)
            let waits = isWaiting(path, file)
            // Still idle after its interim words; once woken it shows its own steps.
            let asleep = waits && file.info.finished
            let status = TranscriptReader.status(of: file.info, lastActivity: file.activity, now: now, session: state?.activity, waits: waits)
            // A waiting record says since when; the transcript only knows its last line.
            let since = state?.activity == .waiting ? state?.since ?? file.activity : file.activity
            return AgentRow(
                id: path,
                info: file.info,
                status: status,
                elapsed: TranscriptReader.elapsed(of: file.info, lastActivity: file.activity, now: now, session: state?.activity, waits: waits),
                // Waiting on a job is no silence: nothing is due from it until the job ends.
                quietFor: status == .done || asleep ? 0 : max(0, now.timeIntervalSince(since)),
                handBackSeenAt: seen(file),
                waitingOn: asleep ? waitingOn(file) : nil
            )
        }
        return Dictionary(grouping: visible(files, now: now, visibleFor: visibleFor, claimed: claimed, holding: holding, waiting: waiting), by: { $0.value.session })
            .compactMap { session, entries -> SessionCard? in
                let main = entries.first { $0.value.isMain }
                let subs = entries.filter { !$0.value.isMain }.sorted {
                    ($0.value.info.startedAt ?? .distantFuture, $0.key) < ($1.value.info.startedAt ?? .distantFuture, $1.key)
                }
                let source = main?.value.info ?? subs.first?.value.info ?? AgentInfo()
                // Headless sessions that hooks, plugins and reviewers start through the SDK are not
                // agents anyone asked for, and they outnumber the interactive ones.
                if source.entrypoint.hasPrefix("sdk-") { return nil }
                // The folder's name is drawn, and comes out of the transcript like the rest.
                let project = TranscriptReader.clipped((source.cwd as NSString).lastPathComponent)
                // By the checkout's own folder while it is there to ask; by the path alone, as
                // History names it, once it is gone.
                let place = projectPlace(of: source.cwd, home: home, git: git)
                let repo = source.cwd.isEmpty ? "" : place.map { TranscriptReader.clipped(($0.checkout as NSString).lastPathComponent) }
                    ?? Projects.name(of: source.cwd, home: home)
                return SessionCard(
                    id: session,
                    project: project.isEmpty ? "Claude Code" : project,
                    branch: source.branch,
                    main: main.map { row($0.key, $0.value) },
                    agents: subs.map { row($0.key, $0.value) },
                    startedAt: source.startedAt ?? .distantPast,
                    title: main?.value.info.title ?? "",
                    // Only the transcript the record speaks for is known to run in that process.
                    owner: claimed[session] == nil ? nil : owners[(session as NSString).lastPathComponent],
                    worktree: !source.branch.isEmpty && worktree(source.folder),
                    repo: repo,
                    git: place,
                    jobs: jobs[session] ?? [],
                    onlyForJobs: !withoutJobs.contains(session),
                    closed: running.map { $0[(session as NSString).lastPathComponent] == nil } ?? false
                ).asShown
            }
            // By start, newest first: the order holds still while agents work.
            .sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
    }

    private func tick() {
        if !watching { scan() }
        refresh(now: Date())
        forget(now: Date())
        readSessions()
        publish()
        // The next launch reads what was handed back after this, while the app was not running.
        if let library, caughtUp, Date().timeIntervalSince(aliveAt) >= 60 {
            aliveAt = Date()
            library.markAlive(at: aliveAt)
        }
    }

    /// Reads what FSEvents did not report. An append that lands right behind another can go
    /// unannounced, and a session that then waits on the person writes nothing more, so the row
    /// would stay a line behind for as long as the wait lasts. Costs one `stat` per recent file.
    func refresh(now: Date) {
        for (path, file) in files where now.timeIntervalSince(file.modified) < Self.askingVisibleFor {
            ingest(path: path)
        }
    }

    /// Drops sessions that have been silent for a day, so `files` stays bounded. Read positions
    /// outlive `visibleFor`: a transcript that resumes is not read again from the start.
    /// Judged per session, because a parent forgotten while its subagent still writes would be
    /// re-read in full on every event.
    func forget(now: Date) {
        var latest: [String: Date] = [:]
        for file in files.values { latest[file.session] = max(latest[file.session] ?? .distantPast, file.modified) }
        files = files.filter { now.timeIntervalSince(latest[$0.value.session] ?? .distantPast) < Self.forgetAfter }
    }

    /// FSEvents sets this flag when it dropped events and the folder has to be read again.
    static func needsRescan(_ flags: [FSEventStreamEventFlags]) -> Bool {
        flags.contains { $0 & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 }
    }

    /// Starts watching once the folder exists, then reads what moved recently.
    private func scan() {
        guard FileManager.default.fileExists(atPath: root) else { return }
        watch()
        // ponytail: if the stream cannot start, `tick` falls back to a full rescan every second.
        watching = stream != nil
        rescan()
    }

    /// Reads every transcript that moved recently, and every file, main and sub-agent, of each
    /// session with a live record. Also the recovery path when FSEvents drops events.
    func rescan() {
        let now = Date()
        // As far back as `visible` can still show an agent that is mid-turn.
        // ponytail: not the full hour a pending question stays listed, which would read six times
        // the transcripts at launch. A question in a file untouched for ten minutes, in a session
        // with no record, shows once the file moves.
        let cutoff = now.addingTimeInterval(-max(visibleFor, Self.defaultVisibleFor))
        // A session that waits on the person writes nothing for as long as the wait lasts, and its
        // card is the one the person opened the app to find. Not past what `forget` keeps, or the
        // card would show at launch and go a second later.
        // An open session's idle files too: a background job outlives the turn that started it.
        // ponytail: whole transcripts of every open session at launch; read only job lines of files older than ten minutes if launch slows.
        let held = Set(runningSince.keys)
        let heldCutoff = now.addingTimeInterval(-Self.forgetAfter)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        var walked = Set<String>()
        guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys) else { return }
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate else { continue }
            // A transcript is named after its session, and `ingest` turns away any other file.
            // A sub-agent's file is named for its agent, so the session comes from the path.
            let isHeld: Bool
            switch Self.classify(url.path, root: root) {
            case .main(let key)?, .sub(let key)?:
                isHeld = modified > heldCutoff && held.contains((key as NSString).lastPathComponent)
            case nil:
                isHeld = false
            }
            guard modified > cutoff || isHeld else { continue }
            ingest(path: url.path)
            walked.insert(url.path)
        }
        readUnread(now: now, except: walked)
    }

    /// Reads the files of the hand-backs the library holds unread, as `rescan` does at launch: for
    /// those the launch's catch-up found after it.
    func readUnread() {
        queue.async { [self] in
            caughtUp = true
            readUnread(now: Date())
            publish()
        }
    }

    /// A hand-back nobody has opened is news however old its file: the library knows where to look.
    /// Only called on `queue`.
    private func readUnread(now: Date, except walked: Set<String> = []) {
        for path in library?.unseenAgents(since: now.addingTimeInterval(-HandBack.hold)) ?? [] where !walked.contains(path) {
            ingest(path: path)
        }
    }

    private func watch() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info, let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else { return }
            let store = Unmanaged<AgentStore>.fromOpaque(info).takeUnretainedValue()
            if AgentStore.needsRescan(Array(UnsafeBufferPointer(start: eventFlags, count: count))) {
                store.rescan()
            } else {
                for path in paths { store.ingest(path: path) }
            }
            store.publish()
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [root] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    /// The cards as of `now`, from everything the store has read. Only called on `queue`.
    func cards(now: Date) -> [SessionCard] {
        // ponytail: the disk is asked again for every card on every publish, a stat or two each; keep the answers by folder if that ever shows.
        Self.cards(from: files, now: now, visibleFor: visibleFor, states: states, owners: owners, worktree: Self.isWorktree, git: Self.gitPlace(of:),
                    running: keepsRecords ? runningSince : nil)
    }

    /// Whether someone is at a session, by id: held by a live record of Claude Code's. A Claude
    /// Code that keeps no records leaves only the transcripts to go by: one of `listed` still at work.
    /// Only called on `queue`.
    private func busy(_ listed: [SessionCard]) -> (String) -> Bool {
        let byRecords = !records.isEmpty
        let atWork = Set(listed.filter { !$0.isIdle }.map(AnswerStore.sessionID(of:)))
        return { [runningSince] in byRecords ? runningSince[$0] != nil : atWork.contains($0) }
    }

    /// For the plugin's SessionStart and SubagentStart hooks: seats a session Claude Code is
    /// starting and tells it who it is, or tells a sub-agent of an introduced session who it and
    /// its lead are. `reply` gets the hook's output, or nil for none, on the main thread.
    /// `names` is the Crew names setting: off, a sub-agent still gets the In short request.
    /// `tags`: whether the person has the name tags switched on.
    func introduce(_ request: CrewIntroRequest, names: Bool = true, tags: Bool = true, reply: @escaping (Data?) -> Void) {
        queue.async { [self] in
            let body = introduction(request, names: names, tags: tags, now: Date())
            DispatchQueue.main.async { reply(body) }
        }
    }

    /// Whether the terminal the request's Claude Code runs in can draw the name tags: the font
    /// `crew install` put in place is this app's, the terminal opened after it did and, in
    /// Ghostty, the config has our font line, as the status line asks before it draws the newest faces.
    // ponytail: the app's own XDG_CONFIG_HOME, not the terminal's: a Ghostty config kept there reads as no font line, so plain names. Send it in the hook too if anyone keeps one there.
    // ponytail: inside tmux TERM_PROGRAM is "tmux", so a Ghostty without our line under it still gets tags, and a tmux server started after the font counts as a new terminal; ask tmux for its client's terminal if that bites.
    static func terminalDrawsTags(_ request: CrewIntroRequest, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                  bundled: URL = CrewCommand.bundledFont) -> Bool {
        guard let claude = request.pid else { return false }
        return CrewSetup.drawsThingsInHand(home: home, environment: request.terminal.map { ["TERM_PROGRAM": $0] } ?? [:],
                                           bundled: bundled, terminalStart: CrewCommand.terminalStart(of: claude))
    }

    private func introduction(_ request: CrewIntroRequest, names: Bool, tags withTags: Bool, now: Date) -> Data? {
        switch request.event {
        case "SessionStart":
            guard !request.cwd.isEmpty else { return nil }
            // A worktree sits at its checkout's desk, as its card will.
            let project = Self.projectPlace(of: request.cwd, home: NSHomeDirectory(), git: Self.gitPlace(of:))?.checkout ?? request.cwd
            // After /clear this terminal's record may still name the session it ran until now:
            // that one has let go of its seat.
            let released = request.pid.flatMap { pid in records.values.first { $0.record.pid == pid }?.record.sessionId }
            let held = busy(cards(now: now))
            let before = roster
            // ponytail: a session seated here counts as busy for a minute or until its record is read, so sessions started together get two people; ask the records directly if that ever misfires.
            let fresh = introducedAt
            let look = roster.seat(session: request.session, project: project, busy: { id in
                id != released && (held(id) || fresh[id].map { now.timeIntervalSince($0) < 60 } ?? false)
            }, now: now)
            if runningSince[request.session] == nil { introducedAt[request.session] = now }
            roster.markNamed(request.session)
            if roster != before, let rosterFile { try? roster.save(rosterFile) }
            // The terminal's status line gets the face before the first prompt.
            publish()
            let tags = withTags && drawsTags(request) ? CrewIntro.tags(lead: look) : [:]
            return CrewIntro.body(event: request.event, note: CrewIntro.leadNote(Crew.lead(look), tags: tags))
        case "SubagentStart":
            // A lead that was never told its name would hear it first from its sub-agent.
            guard names, let seat = roster.seats[request.session], seat.named == true else {
                return CrewIntro.body(event: request.event, note: CrewIntro.inShortNote)
            }
            let tags = withTags && drawsTags(request) ? CrewIntro.tags(sub: request.agentType, lead: seat.look) : [:]
            let note = CrewIntro.subNote(Crew.sub(type: request.agentType), lead: Crew.lead(seat.look), tags: tags)
            return CrewIntro.body(event: request.event, note: note + "\n\n" + CrewIntro.inShortNote)
        default:
            return nil
        }
    }

    /// Hands the cards to the main thread. Only called on `queue`, and by tests.
    func publish() {
        let now = Date()
        // Someone is at a session Claude Code runs.
        let listed = cards(now: now)
        let before = roster
        let cards = roster.seat(listed, busy: busy(listed), now: now)
        if roster != before, let rosterFile { try? roster.save(rosterFile) }
        let looks = roster.looks
        let missing = !FileManager.default.fileExists(atPath: root)
        let scanned = scanned
        let reach = reachNow
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.reach != reach { self.reach = reach }
            if self.sessions != cards { self.sessions = cards }
            if self.looks != looks { self.looks = looks }
            if self.rootMissing != missing { self.rootMissing = missing }
            if self.loaded != scanned { self.loaded = scanned }
        }
    }
}
