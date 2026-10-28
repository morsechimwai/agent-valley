import AppKit
import Combine

// Claude Code runs `AgentValley crew status` every few seconds: a command answers and exits
// before any of the app is touched, so it stays quick and never puts a second notch on screen.
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "crew" {
    exit(CrewCommand.run(Array(CommandLine.arguments.dropFirst(2))))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let store = AgentStore(roster: CrewSetup.folder(FileManager.default.homeDirectoryForCurrentUser)
        .appendingPathComponent(CrewSetup.rosterName))
    private let limits = PlanLimitsClient()
    private let answers = AnswerStore()
    private let usage = UsageLedger()
    private var updates: Updates!
    private lazy var dailyCount = DailyCount(settings: settings)
    // Held for the life of the app: the desk's callbacks and the timers reach them weakly.
    private let desk = StopDesk()
    private var awayWatch: AwayWatch!
    private var sender: SessionSender!
    private var notch: NotchWindowController?
    private var watches = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First, before the answers socket or anything else of this copy is set up.
        AppPlace.quitOtherCopies()
        AppPlace.quitOlderCopiesThatOpen()
        let misplaced = AppPlace.needsMove()
        if misplaced, AppPlace.offerMove() { return }
        // Both fire once now with the stored value, then again on every change.
        settings.$keepFinishedMinutes
            .sink { [store] minutes in store.setVisibleFor(TimeInterval(minutes * 60)) }
            .store(in: &watches)
        settings.$planLimits
            .sink { [limits] on in limits.setEnabled(on) }
            .store(in: &watches)
        watches.formUnion(answers.follow(settings))
        settings.$goToTab
            .sink { [store] on in store.setTabs(on) }
            .store(in: &watches)
        settings.$tokenUse
            .sink { [usage] on in usage.setEnabled(on) }
            .store(in: &watches)
        // Each time the transcripts move, requests find their rows and answered ones are withdrawn.
        store.$sessions
            .sink { [answers] sessions in answers.reconcile(with: sessions) }
            .store(in: &watches)
        // After an update the font the person installed is replaced with the one in this app,
        // and Ghostty's font line, where install put one, covers all of its faces. Not from a
        // copy that goes with the dmg: it may be older than the one in Applications.
        if !misplaced, let bundled = Bundle.main.resourceURL?.appendingPathComponent(CrewFont.fileName) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            CrewSetup.refreshGhosttyLine(home: home, environment: ProcessInfo.processInfo.environment)
            CrewSetup.refreshFont(home: home, bundled: bundled)
        }
        // Open at login follows the app to a new folder, never to one that goes with the dmg.
        if !misplaced { LoginItem.follow(settings) }
        updates = Updates()
        // Only a release counts: a build to work on the app has no update feed and sends nothing.
        if updates.isAvailable {
            settings.$dailyCount
                .sink { [dailyCount] on in dailyCount.setEnabled(on) }
                .store(in: &watches)
        }
        wireSending()
        store.start()
        notch = NotchWindowController(store: store, settings: settings, limits: limits, answers: answers, sound: SoundPlayer(settings: settings), usage: usage, updates: updates,
                                      away: awayWatch, desk: desk)
    }
}

extension AppDelegate {
    /// Phone messages to sessions, Away mode and the button that shows it. Nothing sends yet:
    /// a later change links the phone, and until then the button stays hidden.
    private func wireSending() {
        awayWatch = AwayWatch(desk: desk, lastInput: {
            Date().addingTimeInterval(-CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!))
        })
        awayWatch.start()
        let logFile = AnswerServer.defaultDirectory.appendingPathComponent("send.log")
        desk.holds = { [store] in store.reach[$0]?.route == .stopHook }
        sender = SessionSender(
            reach: { [store] in store.reach[$0] },
            // A hidden request still counts: the terminal asks all the same. The record is read
            // fresh too: with the answers switch off, a prompt that opened this second shows only there.
            asking: { [store, answers] session in
                if answers.pending.contains(where: { $0.ask.session == session }) { return true }
                guard let reach = store.reach[session] else { return false }
                return reach.waitingOnPerson || AgentStore.recordWaitsOnPerson(pid: reach.process.pid, sessions: store.sessionsFolder)
            },
            holdsTab: { process, place in
                let facts = AgentStore.facts(ofProcess: process.pid)
                return place.map { TabGuard.claudeHoldsTab(facts, process: process, place: $0) } ?? TabGuard.claudeInFront(facts, process: process)
            },
            type: { text, place, check in
                TabTyping.send(text, to: place, check: check, run: TabTyping.osascript, wait: Thread.sleep(forTimeInterval:))
            },
            superset: { workspace, terminal, text, check in
                SupersetSend.send(workspace: workspace, terminal: terminal, text: text, check: check,
                                  run: SupersetSend.run(SupersetSend.binary(home: FileManager.default.homeDirectoryForCurrentUser)),
                                  wait: Thread.sleep(forTimeInterval:))
            },
            desk: desk,
            away: { [awayWatch] in awayWatch?.turnOn($0) },
            worker: DispatchQueue(label: "agent-valley.send"),
            onStatus: { [store] id, session, status in
                SendLog.write(id: id, route: store.reach[session]?.route.kind ?? "none", status: status, to: logFile)
            })
        answers.onIntro = { [store, settings] request, connection in
            guard settings.crewNames else { connection.reply(nil); return }
            store.introduce(request) { connection.reply($0) }
        }
        answers.onStop = { [desk] stop, connection in
            let hook = desk.arrived(stop) { connection.reply($0) }
            connection.onClose = { [weak desk] in desk?.hookGone(hook) }
        }
        // Published values arrive before they are stored: look again once they have landed.
        answers.$pending
            .receive(on: DispatchQueue.main)
            .sink { [sender] _ in sender?.askingChanged() }
            .store(in: &watches)
        store.$reach
            .receive(on: DispatchQueue.main)
            .sink { [sender] _ in sender?.askingChanged() }
            .store(in: &watches)
        store.$reach.combineLatest(awayWatch.$phoneLinked)
            .sink { [awayWatch] reach, linked in
                awayWatch?.buttonShown = linked && reach.values.contains { $0.route == .stopHook }
            }
            .store(in: &watches)
    }

    /// Quitting ends every request without a decision and takes the socket file away.
    func applicationWillTerminate(_ notification: Notification) {
        answers.setEnabled(false)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
