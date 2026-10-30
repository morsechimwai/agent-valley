import AppKit
import Combine
import SwiftUI

/// Where the panel sits. Screen rectangles use AppKit coordinates: origin bottom-left, y up.
enum NotchGeometry {
    static let expandedWidth: CGFloat = 520
    /// Room on each side of the notch: the mascot and its number on one, the limit's ring on the other. No wider: a
    /// menu bar's last title ends close to the notch, and a wider bar covered the end of it.
    static let wing: CGFloat = 44
    static let maxHeightRatio: CGFloat = 0.6

    static let statusRowHeight: CGFloat = 30

    /// How far the island flares out on each side where it meets the top of the screen, shut
    /// and open: it runs into that edge in a curve, as the notch itself does.
    static let shoulder: CGFloat = 6
    static let openShoulder: CGFloat = 12

    /// The open island: the bar, the status row, then the content.
    static func openFrame(screen: CGRect, barHeight: CGFloat, contentHeight: CGFloat) -> CGRect {
        expandedFrame(screen: screen, barHeight: barHeight + statusRowHeight, contentHeight: contentHeight)
    }

    /// Whether the content is taller than the open island may grow, so part of it sits below the edge.
    static func overflows(screen: CGRect, barHeight: CGFloat, contentHeight: CGFloat) -> Bool {
        barHeight + statusRowHeight + contentHeight > screen.height * maxHeightRatio
    }

    /// How much height the session list may take: what the open island allows, less the bar and the status row.
    static func listRoom(screen: CGRect, barHeight: CGFloat) -> CGFloat {
        screen.height * maxHeightRatio - barHeight - statusRowHeight
    }

    /// Whether something in the list is on screen from top to bottom: not cut by the list's top
    /// edge and not under the band of `fade` points that fades out its bottom.
    /// Of the requests the bottom edge or its fade still hides, the one nearest the top: where
    /// the way down has to lead first, since a request that is not all in view takes no click.
    static func firstCutBelow(_ spans: [UUID: ClosedRange<CGFloat>], viewport: CGFloat, fade: CGFloat) -> UUID? {
        spans.filter { $0.value.upperBound > viewport - fade }.min { $0.value.lowerBound < $1.value.lowerBound }?.key
    }

    static func isInFullView(minY: CGFloat, maxY: CGFloat, viewport: CGFloat, fade: CGFloat, top: CGFloat = 0) -> Bool {
        minY >= top && maxY <= viewport - fade
    }

    /// How tall the band at an edge of the list is, and how much of it, from the edge inward,
    /// lets nothing of the list show through. What starts inside that part is as good as past
    /// the edge.
    static let band: CGFloat = 44
    static let bandCover: CGFloat = 22
    /// The band at the top of a scrolled list.
    static let topBand: CGFloat = 30

    /// How far the window reaches past the open island, so a spring that overshoots is not cut off.
    static let overshoot: CGFloat = 24

    /// The window around an open island: wider and taller, still flush with the top of the screen.
    static func stageFrame(around island: CGRect) -> CGRect {
        CGRect(x: island.minX - overshoot, y: island.minY - overshoot,
               width: island.width + overshoot * 2, height: island.height + overshoot)
    }

    /// The display picked in the settings while it is connected. Else the notched display if
    /// there is one, else the primary display, which is always first.
    static func screenIndex(notchHeights: [CGFloat], ids: [String?] = [], chosen: String = DisplayChoice.automatic.id) -> Int? {
        if chosen != DisplayChoice.automatic.id, let index = ids.firstIndex(of: chosen) { return index }
        return notchHeights.firstIndex { $0 > 0 } ?? (notchHeights.isEmpty ? nil : 0)
    }

    /// Whether the cursor is over the panel. Grown by a point because a cursor pushed against the
    /// top of the screen sits exactly on maxY, which `contains` treats as outside.
    static func isOver(_ frame: CGRect, cursor: CGPoint) -> Bool {
        frame.insetBy(dx: -1, dy: -1).contains(cursor)
    }

    /// The welcome's island: a square as wide as the open panel, smaller on a screen too short for that.
    static func welcomeFrame(screen: CGRect) -> CGRect {
        let side = min(expandedWidth, screen.width, screen.height * maxHeightRatio)
        return CGRect(x: screen.midX - side / 2, y: screen.maxY - side, width: side, height: side)
    }

    static func collapsedFrame(screen: CGRect, notchWidth: CGFloat, barHeight: CGFloat) -> CGRect {
        let width = min(notchWidth + wing * 2, screen.width)
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - barHeight, width: width, height: barHeight)
    }

    static func expandedFrame(screen: CGRect, barHeight: CGFloat, contentHeight: CGFloat) -> CGRect {
        let width = min(expandedWidth, screen.width)
        let height = min(barHeight + contentHeight, screen.height * maxHeightRatio)
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    }
}

/// What a key means in the panel once the shortcut has opened it. No key is ever handed on to
/// a button: the panel acts on the few it knows itself. What the pointer reaches, the keys
/// reach. An answer to a request takes Command with it, so that it is a decision and not a slip
/// of Return or Space: the owner lifted "answered by click only" on 2026-10-13.
enum KeyCommand: Equatable {
    case up, down, go, close
    /// Command-Return, Command-Delete, Command-1 to Command-4: on the chosen session's first request.
    case allow, deny, option(Int)
    /// h, u, d, i: hide the chosen session, show the hidden ones again, unfold its done
    /// agents, unfold the idle sessions.
    case hide, unhide, done, idle
    /// p, ?, comma, t: the pin, the legend, the settings, the History page.
    case pin, legend, settings, history

    /// Arrows, Return, Delete and Esc are told by the key itself, which sits in the same place
    /// on every keyboard. A letter or a digit is told by what the key types: where it sits
    /// differs from one keyboard to another. `shortcut` is what it types with Command held,
    /// the letter macOS takes its own shortcuts by on a keyboard that types no Latin ones.
    init?(keyCode: UInt16, characters: String = "", shortcut: String = "", modifiers: NSEvent.ModifierFlags = []) {
        let held = modifiers.intersection([.command, .control, .option, .shift])
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 53: self = .close
        // An answer takes Command and nothing else. The shortcut that opens the panel is
        // Control, Option and Command with a letter: with those still down, Return allows nothing.
        case 36, 76:
            guard held.isEmpty || held == .command else { return nil }
            self = held.isEmpty ? .go : .allow
        case 51:
            guard held == .command else { return nil }
            self = .deny
        default:
            let typed = characters.lowercased()
            // A digit with Command, and with Shift where the keyboard types its digits that way.
            // The Thai keyboard types its digits with Command and not without.
            if held.contains(.command) {
                guard held.subtracting([.command, .shift]).isEmpty, let number = Int(typed) ?? Int(shortcut), (1...4).contains(number) else { return nil }
                self = .option(number)
                return
            }
            // A letter of the panel's own, with nothing held but the Shift some are typed with:
            // with Control or Option it is another app's chord.
            guard held.subtracting(.shift).isEmpty else { return nil }
            // A keyboard that types Latin letters is taken at its word. One that types none, as
            // the Thai one, is read by the letter its key stands for in a shortcut.
            switch typed.allSatisfy(\.isASCII) ? typed : shortcut.lowercased() {
            case "h": self = .hide
            case "u": self = .unhide
            case "d": self = .done
            case "i": self = .idle
            case "p": self = .pin
            case "?", "/": self = .legend
            case ",": self = .settings
            case "t": self = .history
            default: return nil
            }
        }
    }

    /// Whether the key goes on acting while it is held down. An arrow goes on walking. Nothing
    /// else does, an answer least of all: the next request must not be answered by a key still
    /// down from the last.
    var repeats: Bool { self == .up || self == .down }

    /// Whether the key answers a request.
    var answers: Bool {
        switch self {
        case .allow, .deny, .option: return true
        default: return false
        }
    }

    /// Whether the key does anything right now. On a page, the settings or History, no session
    /// is in sight, so the keys that walk the sessions, act on one or answer one do nothing
    /// there. Those about the panel itself work on every page.
    func acts(onPage: Bool) -> Bool {
        switch self {
        case .close, .pin, .legend, .settings, .history: return true
        default: return !onPage
        }
    }

    /// Where the keyboard starts: the first session that may need the person, so the shortcut
    /// and then Return is the whole trip there. With none, the first session.
    static func start(in cards: [SessionCard]) -> String? {
        // One that waits before one that is only quiet, wherever it stands: the same session an
        // opening by pointer leads to.
        (cards.first { $0.rows.contains { $0.status == .needsYou } } ?? cards.first { $0.rows.contains(where: \.mayNeedPerson) } ?? cards.first)?.id
    }

    /// The card an arrow key lands on: the next one that way, staying at the ends. With none
    /// chosen yet, or the chosen one gone, it starts from the end the arrow comes from.
    static func move(_ selected: String?, by step: Int, in cards: [String]) -> String? {
        guard !cards.isEmpty else { return nil }
        guard let selected, let index = cards.firstIndex(of: selected) else { return step > 0 ? cards.first : cards.last }
        return cards[min(max(index + step, 0), cards.count - 1)]
    }
}

/// How the bar tells a cursor that came for the panel from one passing on its way to a menu.
enum EntryWatch {
    /// How long the cursor has to stay on the bar before the panel opens.
    static let dwell: TimeInterval = 0.1
    /// How long the panel has to stay open to count as looked at.
    static let look: TimeInterval = 1
    /// How long the settings stay as they were after the panel shuts: a pointer that strayed
    /// comes back to the same page, scrolled where it was. After that the next opening shows
    /// the agents again.
    static let settingsLinger: TimeInterval = 10

    /// How long the pointer has rested in the open panel after one more reading, and whether
    /// that rest has just become a look. Only a pinned panel is looked at this way: it is never
    /// opened again, so an opening cannot be what says "seen" there. Each second of rest is one look.
    static func rest(_ rested: TimeInterval, inside: Bool, pinned: Bool) -> (rested: TimeInterval, looked: Bool) {
        guard inside, pinned else { return (0, false) }
        let now = rested + ExitWatch.interval
        // Less a hair: twenty readings of a twentieth of a second do not add up to exactly one.
        return now >= look - 0.001 ? (0, true) : (now, false)
    }
}

/// How the open island decides the cursor has really left.
enum ExitWatch {
    static let interval: TimeInterval = 0.05
    /// Outside readings in a row before closing. One: the panel shuts on the first look that
    /// finds the cursor gone, as its owner asked on 2026-10-13. For a few hours that day it was
    /// six, three tenths of a second, so that a slip past the edge did not shut it on someone
    /// reading a request: the wait read as the panel hanging. The pin is what keeps it open.
    static let readings = 1
    static var longestWait: TimeInterval { interval * Double(readings) }

    /// The count of outside readings after one more. While `held` nothing counts: the panel
    /// opened by itself and waits for the cursor to visit before it may close. Nor while
    /// `pinned`: the person asked it to stay.
    static func count(_ readings: Int, inside: Bool, held: Bool, pinned: Bool) -> Int {
        inside || held || pinned ? 0 : readings + 1
    }

    /// Where the pointer still counts as over the panel besides the island itself. A click that
    /// brings a shorter page shrinks the island out from under a pointer that has not moved:
    /// the island keeps the place it had, `was`, until the pointer leaves it or comes back on.
    static func kept(_ kept: CGRect, was: CGRect, island: CGRect, cursor: CGPoint) -> CGRect {
        if NotchGeometry.isOver(island, cursor: cursor) { return .null }
        if NotchGeometry.isOver(kept, cursor: cursor) { return kept }
        return NotchGeometry.isOver(was, cursor: cursor) ? was : .null
    }
}

final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var contentHeight: CGFloat = 0
    /// Where Apple's Dynamic Island is on the screen the panel sits on. Nil on a notch or a plain screen.
    @Published var appleIsland: CGRect?
    /// The island is showing its alert pill for a moment.
    @Published var alerting = false
    /// Counts the times someone starts waiting. The island answers each with an alert.
    @Published var alerts = 0
    @Published var barHeight: CGFloat = 32
    @Published var notchWidth: CGFloat = 180
    @Published var screenFrame = CGRect.zero
    /// The displays connected now, for the Display setting.
    @Published var displays: [DisplayChoice] = []
    /// Counts openings. Each one makes the mascot hop.
    @Published var opens = 0
    /// Counts the openings that lasted long enough to have been read. The bar stops beating for
    /// a wait once the person has looked, and a pointer brushing the bar is not a look.
    @Published var looks = 0
    /// The settings stand where the list was. The legend at the head of the list goes as they
    /// open, by whichever of the four ways in: left up, it was still there on the way back,
    /// and "← Agents" had to be pressed a second time to reach the agents. History goes too:
    /// one page at a time, and the Library with it.
    @Published var showingSettings = false {
        didSet { if showingSettings { showingHistory = false; showingLibrary = false } }
    }
    /// History stands where the list was, as the settings do.
    @Published var showingHistory = false {
        didSet { if showingHistory { showingSettings = false; showingLibrary = false } }
    }
    /// The Library too: the books the sub-agents handed back, by project.
    @Published var showingLibrary = false {
        didSet { if showingLibrary { showingSettings = false; showingHistory = false } }
    }
    /// The shelf open on the Library page, or nil for every shelf. Kept while the page is, as
    /// History's pick is; the page opened anew starts on its shelves.
    @Published var libraryShelf: String?
    /// What is picked on the History page. Kept while the page is, so that a pointer that
    /// strayed finds it again; a page opened anew starts afresh.
    @Published var historyPick = HistoryPick()
    /// A page stands where the list was: the keys and the bands about sessions are put away.
    var showingPage: Bool { showingSettings || showingHistory || showingLibrary }
    /// The page of the settings last read. Remembered while the app runs.
    @Published var settingsTab = SettingsTab.general
    /// Whether the folded idle sessions are listed. Remembered while the app runs.
    @Published var idleExpanded = false
    /// The projects whose line the person has clicked shut, by `projectKey`. Remembered while the app runs.
    @Published var shutProjects: Set<String> = []
    /// The first opening ever, which the app does by itself to show where it lives.
    @Published var introducing = false
    /// When the panel last opened, or nil while it is shut. Answer buttons arm a moment after.
    @Published var openedAt: Date?
    /// Sessions the person has put away, with the time each had last moved. Kept while the app runs.
    @Published var hidden: [String: Date] = [:]
    /// The person has asked the panel to stay open, to read a long request or keep watch.
    /// Never set by the app itself, and forgotten when it quits.
    @Published var pinned = false
    /// The shortcut opened the panel and it has the keyboard: arrows, Return and Esc work in it.
    @Published var keyboard = false
    /// The card the arrow keys have landed on.
    @Published var selected: String?
    /// The shortcut is switched on and the system would not give it, as when another app has it.
    @Published var shortcutTaken = false
    /// The legend is the Symbols page of the settings.
    var showingLegend: Bool { showingSettings && settingsTab == .symbols }
    /// The page of the legend last read. Remembered while the app runs.
    @Published var legendTab = LegendTab.mascots
    /// The last key the list has to act on itself, because only it knows what is on screen:
    /// an answer, hiding the chosen session, unfolding its finished agents.
    @Published var keyed: Keyed?
    /// Whether each session's done lines are listed under its book, as the person last set
    /// it. None: listed, unless the list folds them to fit. Remembered while the app runs.
    @Published var doneShown: [String: Bool] = [:]
    /// The finished sub-agents whose hand-back box shows all of it, by row id. For this opening
    /// only: a box read here is a line at the next.
    @Published var readingAll: Set<String> = []
    /// The working sub-agents whose Asked box is open, by row id. Only a live row's id counts.
    @Published var askedOpen: Set<String> = []

    /// Once the panel has finished closing, what was for that opening only is put away: the
    /// first-launch words and the hand-backs left read whole.
    func finishedClosing() {
        introducing = false
        readingAll = []
    }

    /// A key for the list, pressed at `at` on the session the arrow keys are on now.
    func press(_ command: KeyCommand, at: Date) {
        keyed = Keyed(serial: (keyed?.serial ?? 0) + 1, command: command, at: at, card: selected)
    }

    /// The Symbols page of the settings, or back to the agents from it. By its key it opens on
    /// the keys: that is what the key is said to list, and no key turns the pages.
    func toggleLegend(byKey: Bool = false) {
        if showingLegend { return showingSettings = false }
        settingsTab = .symbols
        showingSettings = true
        if byKey { legendTab = .keys }
    }

    /// History, opened afresh: this month, every project, nothing picked.
    func openHistory() {
        historyPick = HistoryPick()
        showingHistory = true
    }

    /// Its key: History opens, or from History back to the list.
    func toggleHistory() {
        if showingHistory { showingHistory = false } else { openHistory() }
    }

    /// Its button: the Library opens on its shelves, or from the Library back to the list.
    func toggleLibrary() {
        if showingLibrary {
            showingLibrary = false
        } else {
            libraryShelf = nil
            showingLibrary = true
        }
    }

    /// Every page goes and the list is back: once the panel has stayed shut, or the keys walk
    /// the sessions.
    func putPagesAway() {
        showingSettings = false
        showingHistory = false
        showingLibrary = false
    }

    /// The "Token use" switch. Off, History has nothing to show and goes. The Library stays: it
    /// keeps its own books.
    func tokenUse(_ on: Bool) {
        if !on { showingHistory = false }
    }
}

/// A key pressed in the panel, with when: an answer is judged by that moment, as a click is.
struct Keyed: Equatable {
    let serial: Int
    let command: KeyCommand
    let at: Date
    /// The session the arrow keys were on when it was pressed. It acts there and nowhere else.
    let card: String?

    /// Whether it may act on the session the arrow keys are on now: only the one it was pressed
    /// on, and only while the panel has the keyboard.
    func acts(on selected: String?, keyboard: Bool) -> Bool {
        keyboard && card != nil && card == selected
    }
}

/// The panel's window. It takes the keyboard only while the shortcut has opened it, and every
/// key it is sent stops here: none may reach a button, least of all one that answers a request.
final class NotchPanel: NSPanel {
    var takesKeys = false
    /// Told of a key and of when it was pressed.
    var onKey: ((KeyCommand, Date) -> Void)?
    /// Told when the keyboard goes elsewhere, as it does on a click in another app.
    var onResign: (() -> Void)?
    /// True only while a panel hands a release of the mouse button to what was clicked. A
    /// request is answered by a click and nothing else, and this is how a button's action
    /// knows it is running for one: the last event the app saw could be a click from earlier.
    private(set) static var handlingClick = false
    /// When the mouse button last went down in a panel, as the system counts time.
    private(set) static var pressedAt: TimeInterval = 0

    /// The moment an event happened, from the time the system stamped it with. A click and a
    /// key are judged by when the finger went down, not by when the app got round to them. A
    /// time ahead of the clock is not believed.
    static func when(_ timestamp: TimeInterval, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Date {
        now.addingTimeInterval(min(0, timestamp - uptime))
    }

    override var canBecomeKey: Bool { takesKeys }

    override func resignKey() {
        super.resignKey()
        onResign?()
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            take(event)
        case .keyUp:
            break
        case .leftMouseDown:
            // A click is judged by when the finger went down.
            Self.pressedAt = event.timestamp
            super.sendEvent(event)
        case .leftMouseUp:
            Self.handlingClick = true
            defer { Self.handlingClick = false }
            super.sendEvent(event)
        default:
            super.sendEvent(event)
        }
    }

    /// The app offers every key down here first, chord or not, and only what is turned down
    /// goes on to `sendEvent`. Nothing is turned down while the panel has the keyboard.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard takesKeys else { return false }
        take(event)
        return true
    }

    /// The keys it knows do what they say, and an arrow held down goes on walking. Any other
    /// key hands the keyboard back, as Esc does: a chord pressed by accident then costs one
    /// keystroke, not everything typed after it. Tab is the one that does nothing. It is what
    /// moves between controls everywhere else on a Mac, and it is pressed here for that, by
    /// someone who then watched the panel shut: it is not the start of something typed.
    private func take(_ event: NSEvent) {
        guard takesKeys else { return }
        let at = Self.when(event.timestamp)
        let shortcut = event.characters(byApplyingModifiers: event.modifierFlags.intersection(.shift).union(.command)) ?? ""
        if let command = KeyCommand(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "", shortcut: shortcut, modifiers: event.modifierFlags) {
            if !event.isARepeat || command.repeats { onKey?(command, at) }
        } else if Self.isTab(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            return
        } else if !event.isARepeat {
            onKey?(.close, at)
        }
    }

    /// Tab alone, or with Shift for the way back. With Control, Option or Command it is some
    /// other app's chord, and hands the keyboard back like any key the panel does not know.
    static func isTab(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        keyCode == 48 && modifiers.intersection([.command, .control, .option]).isEmpty
    }
}

/// Reports the cursor arriving or moving over the panel's window. It owns its tracking area so
/// SwiftUI's own hover handling is untouched.
final class HoverView: NSView {
    var onHover: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?()
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?()
    }
}

final class NotchWindowController: NSObject {
    /// How long the window keeps its larger size after the island starts shrinking inside it.
    private static let settleDelay: TimeInterval = 0.6

    private let state = NotchState()
    private let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var hotkey: Hotkey?
    private var shortcutWatch: AnyCancellable?
    /// The cards as the panel lists them, for the arrow keys to walk.
    private let cards: () -> [SessionCard]
    /// Starts with the panel open and pinned. For screenshots.
    private let pinnedAtLaunch = ProcessInfo.processInfo.environment["AGENT_VALLEY_PINNED"] != nil
    private var heightWatch: AnyCancellable?
    /// What the window is sized for. `state.expanded` follows one run-loop turn later and drives the animation.
    private var isExpanded = false
    /// Like `isExpanded`: what the window is sized for while the island's alert shows.
    private var isAlerting = false
    private var alertWatch: AnyCancellable?
    private var waitWatch: AnyCancellable?
    private var alertEnd: DispatchWorkItem?
    /// The bar beside the notch, and the island as it will be once it settles, in screen coordinates.
    private var barFrame = CGRect.zero
    private var islandFrame = CGRect.zero
    private var settle: DispatchWorkItem?
    private let limits: PlanLimitsClient
    private let answers: AnswerStore
    private let store: AgentStore
    /// For the "Token use" switch, which History hangs on.
    private let settings: Settings
    private let updates: Updates
    private var tokenWatch: AnyCancellable?
    private var displayWatch: AnyCancellable?
    private var leadLooksWatch: AnyCancellable?
    /// The bytes last written for `crew status`, so a refresh that changes nothing writes nothing.
    private var lastLeadLooks: Data?
    /// The panel opened by itself and stays until the cursor has been over it once.
    private var held = false
    /// The island at the last look for the cursor, and the place it shrank from under it.
    private var lastIsland = CGRect.null
    private var keptPlace = CGRect.null
    /// Set while the cursor's rest on the bar is being timed.
    private var entering: DispatchWorkItem?
    /// Counts openings, to tell one from the next.
    private var openings = 0
    /// How long the pointer has rested in the pinned panel since its last look.
    private var rested: TimeInterval = 0
    /// Takes the panel back from the settings to the agents some time after it has shut.
    private var leaveSettings: DispatchWorkItem?

    init(store: AgentStore, settings: Settings, limits: PlanLimitsClient, answers: AnswerStore, sound: SoundPlayer, usage: UsageLedger, updates: Updates,
         away: AwayWatch = AwayWatch(desk: StopDesk(), lastInput: { .distantPast }), desk: StopDesk = StopDesk()) {
        self.limits = limits
        self.answers = answers
        self.store = store
        self.settings = settings
        self.updates = updates
        let state = self.state
        cards = {
            let shown = AgentStore.ordered(AgentStore.showing(answers.overlay(store.sessions), hidden: state.hidden), by: settings.grouping)
            return AgentStore.arrange(shown, idle: settings.idleSessions, keeping: answers.settledSessions.union(HandBack.holding(shown, openedAt: state.openedAt)),
                                      shut: settings.grouping == .projects ? state.shutProjects : [])
                .walked(idleExpanded: state.idleExpanded)
        }
        super.init()
        // Have a look and Check now: the panel closes, unless pinned, and hands the keyboard back.
        updates.willShowWindow = { [weak self] in self?.closeFromKeyboard() }
        tokenWatch = settings.$tokenUse.sink { [weak self] on in self?.state.tokenUse(on) }
        // `crew status` runs without the app's data, so who sits where goes to it in a small file:
        // the terminal shows the notch's faces.
        leadLooksWatch = store.$looks.sink { [weak self] looks in
            guard let self else { return }
            let data = CrewSetup.leadLooksData(looks)
            // Remembered only once it is on disk, so a failed write is tried again.
            if data != self.lastLeadLooks, (try? CrewSetup.writeLeadLooks(data, home: FileManager.default.homeDirectoryForCurrentUser)) != nil {
                self.lastLeadLooks = data
            }
        }
        panel.isOpaque = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        // This app is never the active one, and its buttons' only explanations are their tooltips.
        panel.allowsToolTipsWhenApplicationIsInactive = true

        let host = NSHostingView(rootView: PanelView(store: store, state: state, settings: settings, limits: limits, answers: answers, sound: sound, usage: usage, updates: updates, away: away, desk: desk))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = HoverView()
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.onHover = { [weak self] in self?.hover() }
        panel.contentView = container

        heightWatch = state.$contentHeight.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.layout()
        }
        alertWatch = state.$alerts.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.alert() }
        NotificationCenter.default.addObserver(self, selector: #selector(layout), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // On the next turn of the loop: a @Published value is sent before it is stored.
        displayWatch = settings.$display.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.layout() }
        isExpanded = pinnedAtLaunch
        state.pinned = pinnedAtLaunch
        state.expanded = pinnedAtLaunch
        state.openedAt = pinnedAtLaunch ? Date() : nil
        layout()
        panel.orderFrontRegardless()
        // Open from the start: watched like any open panel, so it can close once it is unpinned.
        if pinnedAtLaunch { watchForExit(outside: 0) }

        // No Dock icon and no window: without this a first launch shows nothing at all.
        let firstLaunch = settings.isFirstLaunch
        settings.markLaunched()
        panel.onKey = { [weak self] in self?.key($0, at: $1) }
        panel.onResign = { [weak self] in self?.keyboardLeft() }
        hotkey = Hotkey { [weak self] in self?.toggleFromKeyboard() }
        // Fires now with the stored choice, then on every change of the switch.
        shortcutWatch = settings.$shortcut.combineLatest(settings.$shortcutKey).sink { [weak self] on, key in
            guard let self, let hotkey = self.hotkey else { return }
            let had = hotkey.setEnabled(on, key: key)
            self.state.shortcutTaken = on && !had
        }
        // Nobody waits any more: an island's alert has nobody left to name, and goes at once.
        waitWatch = store.$sessions.combineLatest(answers.$pending).receive(on: DispatchQueue.main).sink { [weak self] _ in
            if self?.anyoneWaiting == false { self?.endAlert() }
        }
        if firstLaunch, !pinnedAtLaunch {
            held = true
            state.introducing = true
            setExpanded(true)
            watchForExit(outside: 0)
        }
    }

    /// The window is larger than the bar while the island settles, so the cursor has to be over
    /// the bar itself to open it.
    private func hover() {
        guard !isExpanded, entering == nil, NotchGeometry.isOver(barFrame, cursor: NSEvent.mouseLocation) else { return }
        // Open only if the cursor is still here in a moment: one crossing the bar on its way to
        // a menu or a status item is gone by then.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.entering = nil
            guard !self.isExpanded, NotchGeometry.isOver(self.barFrame, cursor: NSEvent.mouseLocation) else { return }
            self.setExpanded(true)
            self.limits.refreshIfStale()
            self.watchForExit(outside: 0)
        }
        entering = work
        DispatchQueue.main.asyncAfter(deadline: .now() + EntryWatch.dwell, execute: work)
    }

    /// Someone waits on the person, held requests of the answer plugin included.
    private var anyoneWaiting: Bool { AgentStore.barState(answers.overlay(store.sessions)).waiting > 0 }

    /// Shows the alert pill for `IslandGeometry.alertShown`; a newer alert starts the time over.
    private func alert() {
        guard IslandGeometry.shouldAlert(island: state.appleIsland != nil, expanded: isExpanded, welcoming: false) else { return }
        alertEnd?.cancel()
        isAlerting = true
        layout()
        // Unless something ended the alert in this same turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isAlerting else { return }
            self.state.alerting = true
        }
        let end = DispatchWorkItem { [weak self] in self?.endAlert() }
        alertEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandGeometry.alertShown, execute: end)
    }

    private func clearAlert() {
        alertEnd?.cancel()
        alertEnd = nil
        isAlerting = false
        state.alerting = false
    }

    private func endAlert() {
        guard isAlerting || state.alerting else { return }
        clearAlert()
        layout()
    }

    private func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        // Opening answers the alert: it ends now, before the window takes the open size.
        if expanded { clearAlert() }
        // The plugin list and the old 0.1 may have changed since: the person may just have run the command.
        if expanded { answers.checkPlugin(); updates.lookForOldCopy() }
        openings += expanded ? 1 : 0
        layout()
        // One turn later the window already has its new size, so the island is the only thing that animates.
        DispatchQueue.main.async { [state] in
            // Opened again before the close settled, `finishedClosing` never ran: what was read whole was for the last opening.
            if expanded { state.opens += 1; state.readingAll = [] }
            state.expanded = expanded
            state.openedAt = expanded ? Date() : nil
        }
        leaveSettings?.cancel()
        lastIsland = .null
        keptPlace = .null
        guard !expanded else {
            // Still this same opening in a moment: then it has been looked at.
            let opening = openings
            DispatchQueue.main.asyncAfter(deadline: .now() + EntryWatch.look) { [weak self] in
                guard let self, self.isExpanded, self.openings == opening else { return }
                self.state.looks += 1
            }
            return
        }
        if state.keyboard || panel.takesKeys { releaseKeys() }
        // The first-launch words go once the panel has finished closing. Switching while it is
        // still closing would show through the fade.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.state.finishedClosing()
        }
        // The pages stay a little longer, for a pointer that only strayed.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.state.putPagesAway()
        }
        leaveSettings = work
        DispatchQueue.main.asyncAfter(deadline: .now() + EntryWatch.settingsLinger, execute: work)
    }

    /// The shortcut. It opens the panel and gives it the keyboard, and the panel stays open for
    /// as long as it has it. Pressed again it closes the panel and hands the keyboard back. The
    /// pin is the person's and is left as it is.
    private func toggleFromKeyboard() {
        if state.keyboard { return closeFromKeyboard() }
        entering?.cancel()
        entering = nil
        state.keyboard = true
        // The sessions are what the keys walk.
        state.putPagesAway()
        state.selected = KeyCommand.start(in: cards())
        if !isExpanded {
            setExpanded(true)
            limits.refreshIfStale()
            watchForExit(outside: 0)
        }
        panel.takesKeys = true
        panel.makeKey()
    }

    /// The panel closes with it, unless the person has pinned it open: then only the keyboard goes.
    private func closeFromKeyboard() {
        releaseKeys()
        if isExpanded, !state.pinned { setExpanded(false) }
    }

    /// The keyboard has gone to another window by the person's own doing. The panel stops saying
    /// that its keys work, and stops holding itself open.
    private func keyboardLeft() {
        guard state.keyboard else { return }
        state.keyboard = false
        state.selected = nil
        panel.takesKeys = false
    }

    /// Ends the keyboard's time in the panel and gives it back to whatever had it.
    private func releaseKeys() {
        state.keyboard = false
        state.selected = nil
        panel.takesKeys = false
        // Out and straight back in: taking the key window off the screen is what makes the
        // system hand the keyboard back to the app in front.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    private func key(_ command: KeyCommand, at: Date) {
        guard command.acts(onPage: state.showingPage) else { return }
        switch command {
        case .up, .down:
            state.selected = KeyCommand.move(state.selected, by: command == .down ? 1 : -1, in: cards().map(\.id))
        case .go:
            // To the app the chosen session runs in, when that is known. Nothing else: plain
            // Return never answers a request.
            guard let owner = cards().first(where: { $0.id == state.selected })?.owner else { return }
            closeFromKeyboard()
            owner.bringForward()
        case .allow, .deny, .option, .hide, .unhide, .done:
            // The list acts on these, once, as it hears of them: it knows which request is on
            // screen in full, and whether the chosen session can be hidden or has agents to unfold.
            state.press(command, at: at)
        case .idle:
            state.idleExpanded.toggle()
        case .pin:
            state.pinned.toggle()
        case .legend:
            state.toggleLegend(byKey: true)
        case .settings:
            state.showingSettings.toggle()
        case .history:
            // A page of the panel: the keyboard stays where it is.
            guard settings.tokenUse else { return }
            state.toggleHistory()
        case .close:
            closeFromKeyboard()
        }
    }

    // ponytail: polls the cursor rather than trusting mouseExited, which misfires while the panel
    // resizes under it. It goes on polling while the panel is pinned; stop and start it with the
    // pin if that ever shows in a profile.
    private func watchForExit(outside readings: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + ExitWatch.interval) { [weak self] in
            guard let self, self.isExpanded else { return }
            let cursor = NSEvent.mouseLocation
            self.keptPlace = ExitWatch.kept(self.keptPlace, was: self.lastIsland, island: self.islandFrame, cursor: cursor)
            self.lastIsland = self.islandFrame
            let inside = NotchGeometry.isOver(self.islandFrame, cursor: cursor) || NotchGeometry.isOver(self.keptPlace, cursor: cursor)
            if inside { self.held = false }
            let rest = EntryWatch.rest(self.rested, inside: inside, pinned: self.state.pinned)
            self.rested = rest.rested
            if rest.looked { self.state.looks += 1 }
            // The keyboard can leave without the panel being told. It must not go on saying its keys work.
            if self.state.keyboard, !self.panel.isKeyWindow { self.keyboardLeft() }
            // With the keyboard in it the panel is in use, wherever the pointer is.
            let readings = ExitWatch.count(readings, inside: inside, held: self.held || self.state.keyboard, pinned: self.state.pinned)
            if readings >= ExitWatch.readings {
                self.setExpanded(false)
            } else {
                self.watchForExit(outside: readings)
            }
        }
    }

    @objc private func layout() {
        let screens = NSScreen.screens
        let ids = screens.map(\.displayID)
        let displays = zip(screens, ids).compactMap { screen, id in id.map { DisplayChoice(id: $0, name: screen.localizedName) } }
        if state.displays != displays { state.displays = displays }
        guard let index = NotchGeometry.screenIndex(notchHeights: screens.map(\.safeAreaInsets.top), ids: ids, chosen: settings.display) else { return }
        let screen = screens[index]
        let apple = IslandGeometry.appleIsland(safeAperture: screen.safeAperture, cutout: screen.cutout, screen: screen.frame)
        if state.appleIsland != apple { state.appleIsland = apple }
        // No island on this screen (say, an external display was picked): an alert showing has nothing to sit on.
        if apple == nil, isAlerting || state.alerting { clearAlert() }
        let hasNotch = screen.safeAreaInsets.top > 0
        let barHeight = apple?.height ?? (hasNotch ? screen.safeAreaInsets.top : max(24, screen.frame.maxY - screen.visibleFrame.maxY))
        var notchWidth: CGFloat = apple?.width ?? 180
        if apple == nil, hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
        }
        if state.barHeight != barHeight { state.barHeight = barHeight }
        if state.notchWidth != notchWidth { state.notchWidth = notchWidth }
        if state.screenFrame != screen.frame { state.screenFrame = screen.frame }

        let target: CGRect
        if let apple {
            let frames = IslandGeometry.frames(screen: screen.frame, apple: apple, expanded: isExpanded, alerting: isAlerting,
                                               welcoming: false, contentHeight: state.contentHeight)
            barFrame = frames.bar
            islandFrame = frames.island
            target = frames.window
        } else {
            barFrame = NotchGeometry.collapsedFrame(screen: screen.frame, notchWidth: notchWidth, barHeight: barHeight)
            islandFrame = isExpanded
                ? NotchGeometry.openFrame(screen: screen.frame, barHeight: barHeight, contentHeight: state.contentHeight)
                : barFrame
            // Shut, the window is the bar and the shoulders it flares out into on either side.
            target = isExpanded ? NotchGeometry.stageFrame(around: islandFrame) : barFrame.insetBy(dx: -NotchGeometry.shoulder, dy: 0)
        }

        // Grow at once so the island never draws outside its window; shrink only after it has settled.
        settle?.cancel()
        // Moved to another display, it goes there at once: grown over both, the window would
        // span the gap between them until it settled.
        let moved = !screen.frame.contains(CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        let grown = panel.frame.isEmpty || moved ? target : panel.frame.union(target)
        panel.setFrame(grown, display: true)
        guard grown != target else { return }
        let work = DispatchWorkItem { [weak self] in self?.panel.setFrame(target, display: true) }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }
}

extension NSScreen {
    /// The id macOS keeps for this display across restarts and plugging in. Its place in
    /// `screens` changes as displays come and go.
    var displayID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// How the top edge is cut, from AppKit's private `_notchFrame` and `_isSafeAperture`. Asked only
    /// where the screen answers to them; a missing one reads as nil, never as a crash. Asked by
    /// their own names, so that KVC calls the very methods checked for.
    var cutout: CGRect? {
        responds(to: NSSelectorFromString("_notchFrame")) ? NSScreen.rect(from: value(forKey: "_notchFrame")) : nil
    }

    var safeAperture: Bool? {
        responds(to: NSSelectorFromString("_isSafeAperture")) ? value(forKey: "_isSafeAperture") as? Bool : nil
    }

    /// `rectValue` throws on a value that holds anything but a rectangle: checked first.
    static func rect(from value: Any?) -> CGRect? {
        guard let value = value as? NSValue, String(cString: value.objCType).hasPrefix("{CGRect") else { return nil }
        return value.rectValue
    }
}
