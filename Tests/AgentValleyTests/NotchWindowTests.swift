import AppKit
import SwiftUI
import XCTest
@testable import AgentValley

/// Stands in the panel for a button: it notes every key and every click that reaches it.
private final class Recorder: NSView {
    var keys = 0
    /// Whether the panel called each mouse-up a click while it was being handled.
    var clicks: [Bool] = []

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { keys += 1 }
    override func keyUp(with event: NSEvent) { keys += 1 }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { clicks.append(NotchPanel.handlingClick) }
}

final class NotchWindowTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testCollapsedBarIsTopCentered() {
        let frame = NotchGeometry.collapsedFrame(screen: screen, notchWidth: 185, barHeight: 32)
        // No wider than this: a menu bar's last title ends close to the notch, and at 56 pt on
        // each side the bar covered the end of "Help" in an app with a long menu.
        XCTAssertEqual(frame, CGRect(x: 619.5, y: 950, width: 273, height: 32))
    }

    func testExpandedPanelFitsItsContent() {
        let frame = NotchGeometry.expandedFrame(screen: screen, barHeight: 32, contentHeight: 200)
        XCTAssertEqual(frame, CGRect(x: 496, y: 750, width: 520, height: 232))
    }

    func testExpandedPanelIsCappedAt60PercentOfScreenHeight() {
        let frame = NotchGeometry.expandedFrame(screen: screen, barHeight: 32, contentHeight: 5000)
        XCTAssertEqual(frame.height, 589.2, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 982, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 756, accuracy: 0.001)
    }

    // A cursor pushed against the top of the screen sits exactly on the panel's maxY, which
    // CGRect.contains treats as outside.
    func testCursorOnTheTopScreenEdgeCountsAsOverThePanel() {
        let frame = CGRect(x: 496, y: 750, width: 520, height: 232)
        XCTAssertTrue(NotchGeometry.isOver(frame, cursor: CGPoint(x: 756, y: 982)))
        XCTAssertTrue(NotchGeometry.isOver(frame, cursor: CGPoint(x: 756, y: 800)))
        XCTAssertFalse(NotchGeometry.isOver(frame, cursor: CGPoint(x: 756, y: 700)))
        XCTAssertFalse(NotchGeometry.isOver(frame, cursor: CGPoint(x: 300, y: 900)))
    }

    // With no notched display the bar belongs on the primary display, not on whichever has focus.
    func testPicksTheNotchedScreenElseThePrimaryOne() {
        XCTAssertEqual(NotchGeometry.screenIndex(notchHeights: [0, 38]), 1)
        XCTAssertEqual(NotchGeometry.screenIndex(notchHeights: [0, 0]), 0)
        XCTAssertNil(NotchGeometry.screenIndex(notchHeights: []))
    }

    // Issue #1: the bar goes to the display picked in the settings, notch or not. While that
    // display is not connected, the bar is where it would be with Automatic.
    func testTheChosenDisplayWinsWhileItIsConnected() {
        let ids: [String?] = ["notch", "dell"]
        XCTAssertEqual(NotchGeometry.screenIndex(notchHeights: [38, 0], ids: ids, chosen: "dell"), 1)
        XCTAssertEqual(NotchGeometry.screenIndex(notchHeights: [38, 0], ids: ids, chosen: "unplugged"), 0)
        XCTAssertEqual(NotchGeometry.screenIndex(notchHeights: [38, 0], ids: ids, chosen: DisplayChoice.automatic.id), 0)
    }

    // Nothing in the app said which display the bar is on. A tester who works on a second
    // display went through every page for it and left without an answer. The legend's page
    // about the bar says what the rule above does, and where on that display the bar is.
    func testTheLegendSaysWhichDisplayTheBarIsOn() {
        // One sentence since 2026-10-15, with the same answer, and since issue #1 the way to change it.
        XCTAssertEqual(Format.displayCaption, "The bar is on the display with a notch, or your main one, unless you pick another under Display in the settings.")
        // A notched display beside a second one: the bar is on the notched one, whichever is the main display.
        XCTAssertEqual(NotchGeometry.screenIndex(notchHeights: [0, 38]), 1)
        XCTAssertEqual(NotchGeometry.screenIndex(notchHeights: [38, 0]), 0)
        // The top middle: as far from each side, flush with the top edge.
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let bar = NotchGeometry.collapsedFrame(screen: screen, notchWidth: 180, barHeight: 24)
        XCTAssertEqual(bar.midX, screen.midX)
        XCTAssertEqual(bar.maxY, screen.maxY)
    }

    // The window is larger than the island while it is open, so a spring that overshoots is not cut off.
    func testStageLeavesRoomAroundTheIslandButStaysAtTheTopOfTheScreen() {
        let island = CGRect(x: 496, y: 750, width: 520, height: 232)
        let stage = NotchGeometry.stageFrame(around: island)
        XCTAssertEqual(stage, CGRect(x: 472, y: 726, width: 568, height: 256))
        XCTAssertEqual(stage.maxY, island.maxY)
    }

    // The island flares out where it meets the top of the screen, in a curve, and nowhere below.
    func testIslandFlaresOutOnlyAtTheTopOfTheScreen() {
        let path = IslandShape(radius: 20, shoulder: 12).path(in: CGRect(x: 100, y: 0, width: 520, height: 200))
        XCTAssertTrue(path.contains(CGPoint(x: 95, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 625, y: 1)))
        XCTAssertFalse(path.contains(CGPoint(x: 95, y: 11)))
        XCTAssertFalse(path.contains(CGPoint(x: 625, y: 11)))
        XCTAssertFalse(path.contains(CGPoint(x: 87, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 360, y: 100)))
        // The corners at the bottom stay round.
        XCTAssertFalse(path.contains(CGPoint(x: 101, y: 199)))
    }

    // The list grows before the window does: the window is sized a turn later. For that turn the
    // island was taller than its window, which centred it: the bar went up past the top of the
    // screen, away from the notch, and sprang back. It stays flush with the top whatever its size.
    @MainActor
    func testTheIslandStaysAtTheTopOfAWindowItHasOutgrown() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = Settings(defaults: throwawayDefaults())
        let state = NotchState()
        state.screenFrame = screen
        state.barHeight = 38
        state.notchWidth = 200
        state.expanded = true
        let host = NSHostingView(rootView: PanelView(store: AgentStore(root: home), state: state, settings: settings, limits: PlanLimitsClient(),
                                                     answers: AnswerStore(directory: home), sound: SoundPlayer(settings: settings),
                                                     usage: UsageLedger(root: home, database: home.appendingPathComponent("history.sqlite")), updates: Updates(info: [:])))
        host.sizingOptions = []
        // The window around an island 300 points tall, off the screen.
        let island = NotchGeometry.expandedFrame(screen: screen, barHeight: 38, contentHeight: 262)
        let window = NSWindow(contentRect: NotchGeometry.stageFrame(around: island).offsetBy(dx: -4000, dy: 0), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        // The list has grown and the window not yet.
        state.contentHeight = 500
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        host.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        let scale = CGFloat(image.pixelsWide) / host.bounds.width
        // Two points in from the island's side, two down from the top of the window: inside the
        // shoulder only while the island's top is the window's.
        let shoulder = try XCTUnwrap(image.colorAt(x: Int((NotchGeometry.overshoot - 2) * scale), y: Int(2 * scale)))
        XCTAssertGreaterThan(shoulder.alphaComponent, 0.9)
    }

    // On first launch the panel opens by itself, with the cursor somewhere else. It must not
    // close again before the person has found it.
    func testAnOpeningThatIsHeldIgnoresTheCursorBeingAway() {
        XCTAssertEqual(ExitWatch.count(1, inside: false, held: false, pinned: false), 2)
        XCTAssertEqual(ExitWatch.count(1, inside: true, held: false, pinned: false), 0)
        XCTAssertEqual(ExitWatch.count(1, inside: false, held: true, pinned: false), 0)
    }

    // A click that brings a shorter page, like the token line at the foot of the list opening
    // History, shrinks the panel out from under a pointer that has not moved. That is not the
    // pointer leaving: the panel keeps the place it had until the pointer leaves that place, or
    // comes back onto the panel.
    func testAPanelThatShrinksFromUnderThePointerKeepsItsPlace() {
        let tall = CGRect(x: 496, y: 400, width: 520, height: 582)
        let short = CGRect(x: 496, y: 700, width: 520, height: 282)
        let foot = CGPoint(x: 756, y: 420)
        let kept = ExitWatch.kept(.null, was: tall, island: short, cursor: foot)
        XCTAssertEqual(kept, tall)
        // Moving about in that place, it still counts as over the panel.
        XCTAssertEqual(ExitWatch.kept(kept, was: short, island: short, cursor: CGPoint(x: 600, y: 500)), tall)
        // Out of it, the panel may close.
        XCTAssertEqual(ExitWatch.kept(kept, was: short, island: short, cursor: CGPoint(x: 756, y: 300)), .null)
        // Back onto the panel, the place is forgotten: leaving the panel then closes it.
        XCTAssertEqual(ExitWatch.kept(kept, was: short, island: short, cursor: CGPoint(x: 756, y: 900)), .null)
        // A pointer that leaves a panel of one size keeps nothing.
        XCTAssertEqual(ExitWatch.kept(.null, was: tall, island: tall, cursor: CGPoint(x: 756, y: 300)), .null)
    }

    // Reading a long request, or keeping watch on a second task, wants the panel to stay. Pinned
    // by the person, it stays however far the cursor goes; it is never pinned by itself.
    func testAPinnedPanelIgnoresTheCursorBeingAway() {
        XCTAssertEqual(ExitWatch.count(1, inside: false, held: false, pinned: true), 0)
        XCTAssertEqual(ExitWatch.count(1, inside: false, held: false, pinned: false), 2)
        XCTAssertFalse(NotchState().pinned)
    }

    // Reaching for a menu or a status item crosses the bar. Resting on it is what opens the
    // panel, and the rest must be too short to feel like waiting.
    func testThePanelOpensAfterAShortRestOnTheBar() {
        XCTAssertGreaterThanOrEqual(EntryWatch.dwell, 0.08)
        XCTAssertLessThanOrEqual(EntryWatch.dwell, 0.12)
    }

    // The panel closes at once, as its owner asked: on the first look that finds the cursor
    // gone. It waited three tenths of a second for a few hours on 2026-10-13, so that a slip
    // past the edge did not shut it on someone reading a request, and the wait read as the
    // panel hanging. What keeps it open is the pin.
    func testThePanelClosesAtOnceWhenTheCursorLeaves() {
        XCTAssertLessThanOrEqual(ExitWatch.longestWait, 0.05)
        XCTAssertGreaterThanOrEqual(ExitWatch.count(0, inside: false, held: false, pinned: false), ExitWatch.readings)
        // Inside, held open or pinned, it stays.
        XCTAssertLessThan(ExitWatch.count(0, inside: true, held: false, pinned: false), ExitWatch.readings)
        XCTAssertLessThan(ExitWatch.count(0, inside: false, held: true, pinned: false), ExitWatch.readings)
        XCTAssertLessThan(ExitWatch.count(0, inside: false, held: false, pinned: true), ExitWatch.readings)
    }

    // A request can be answered only while all of it is on screen: not cut by the top edge of the
    // list, and not under the band at the bottom that fades it out.
    func testARequestIsInFullViewOnlyWhenNoneOfItIsCutOrFaded() {
        XCTAssertTrue(NotchGeometry.isInFullView(minY: 10, maxY: 200, viewport: 400, fade: 44))
        XCTAssertTrue(NotchGeometry.isInFullView(minY: 0, maxY: 356, viewport: 400, fade: 44))
        XCTAssertFalse(NotchGeometry.isInFullView(minY: -1, maxY: 200, viewport: 400, fade: 44))
        XCTAssertFalse(NotchGeometry.isInFullView(minY: 10, maxY: 357, viewport: 400, fade: 44))
        // With nothing below the edge there is no band, and the whole viewport counts.
        XCTAssertTrue(NotchGeometry.isInFullView(minY: 10, maxY: 400, viewport: 400, fade: 0))
        // Scrolled, the list has a band at its top edge too, and what is under it is not in view.
        XCTAssertFalse(NotchGeometry.isInFullView(minY: 10, maxY: 200, viewport: 400, fade: 44, top: 30))
        XCTAssertTrue(NotchGeometry.isInFullView(minY: 30, maxY: 200, viewport: 400, fade: 44, top: 30))
    }

    // Every opening follows one rule, by pointer or by keys. A request the person can answer
    // where it is: nothing moves. Else to the first request the edge cuts. Else to the first
    // row that waits and starts below the edge. Never past a request that is all in view.
    func testAnOpeningLeadsToWhoeverWaitsAndMovesNoFurtherThanItMust() {
        let a = UUID(), b = UUID()
        let below = ScrollTarget.row("r")
        XCTAssertNil(ScrollTarget.onOpening(spans: [a: 40...160, b: 300...420], viewport: 400, fade: 44, waitingBelow: below))
        XCTAssertEqual(ScrollTarget.onOpening(spans: [b: 300...420], viewport: 400, fade: 44, waitingBelow: below), .request(b))
        XCTAssertEqual(ScrollTarget.onOpening(spans: [:], viewport: 400, fade: 44, waitingBelow: below), below)
        XCTAssertNil(ScrollTarget.onOpening(spans: [:], viewport: 400, fade: 44, waitingBelow: nil))
        // A request wholly past the edge is reached by its row.
        XCTAssertEqual(ScrollTarget.onOpening(spans: [b: 500...620], viewport: 400, fade: 44, waitingBelow: below), .request(b))
        // A list left scrolled has a band at its top: a request under that is not one to answer
        // where it is, and does not hold the list still.
        XCTAssertEqual(ScrollTarget.onOpening(spans: [a: 10...160], viewport: 400, fade: 44, top: 30, waitingBelow: below), below)
        XCTAssertNil(ScrollTarget.onOpening(spans: [a: 30...160], viewport: 400, fade: 44, top: 30, waitingBelow: below))
    }

    func testOpenIslandHasRoomForTheStatusRow() {
        let frame = NotchGeometry.openFrame(screen: screen, barHeight: 32, contentHeight: 200)
        XCTAssertEqual(frame, CGRect(x: 496, y: 720, width: 520, height: 262))
    }

    // A request cut by the bottom edge takes no click. The way down has to lead to it, not past
    // it: of the requests the edge or the fade still hides, the one nearest the top.
    func testTheWayDownLeadsToTheFirstRequestTheEdgeCuts() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(NotchGeometry.firstCutBelow([a: 20...180, b: 300...420, c: 500...640], viewport: 400, fade: 44), b)
        XCTAssertEqual(NotchGeometry.firstCutBelow([c: 500...640], viewport: 400, fade: 44), c)
        // In full view: nothing to lead to.
        XCTAssertNil(NotchGeometry.firstCutBelow([a: 20...180], viewport: 400, fade: 44))
        XCTAssertNil(NotchGeometry.firstCutBelow([:], viewport: 400, fade: 44))
        // Scrolled off the top is behind, not below.
        XCTAssertNil(NotchGeometry.firstCutBelow([a: -90...60], viewport: 400, fade: 44))
    }

    // A request can move from one row to another: the view that drew it goes and a new one
    // comes, in either order. The one leaving must not wipe out where the new one stands.
    func testARequestsPlaceIsForgottenOnlyByTheViewThatSetIt() {
        let spans = RequestSpans()
        let request = UUID(), leaving = UUID(), arriving = UUID()
        spans.place(request, by: leaving, at: 0...10)
        spans.place(request, by: arriving, at: 50...90)
        spans.forget(request, by: leaving)
        XCTAssertEqual(spans.byID[request], 50...90)
        spans.forget(request, by: arriving)
        XCTAssertNil(spans.byID[request])
    }

    // The panel can be worked from the keyboard once the shortcut has opened it. Four keys do
    // something; every other key does nothing, and none is ever handed on to a button.
    func testTheKeysThatMeanSomethingInThePanel() {
        func key(_ code: UInt16, _ characters: String = "", _ modifiers: NSEvent.ModifierFlags = []) -> KeyCommand? {
            KeyCommand(keyCode: code, characters: characters, modifiers: modifiers)
        }
        XCTAssertEqual(key(126), .up)
        XCTAssertEqual(key(125), .down)
        XCTAssertEqual(key(36), .go)
        XCTAssertEqual(key(76), .go)
        XCTAssertEqual(key(53), .close)
        // Space, which presses a focused button anywhere else in macOS, means nothing here.
        XCTAssertNil(key(49, " "))
        XCTAssertNil(key(0, "a"))
        // The owner lifted "answered by click only" on 2026-10-13. An answer is still a
        // deliberate act: it takes Command, and plain Return never answers.
        XCTAssertEqual(key(36, "\r", .command), .allow)
        XCTAssertEqual(key(51, "", .command), .deny)
        XCTAssertNil(key(51))
        // Command and nothing else. The shortcut that opens the panel is Control, Option and
        // Command with a letter: with those still held down, Return must not allow.
        XCTAssertNil(key(36, "\r", [.command, .control, .option]))
        XCTAssertNil(key(36, "\r", [.command, .shift]))
        XCTAssertNil(key(51, "", [.command, .option]))
        // An option is picked by the digit the key types, wherever that key is: on a French
        // keyboard the digits are typed with Shift.
        XCTAssertEqual(["1", "2", "3", "4"].map { key(0, $0, .command) }, [.option(1), .option(2), .option(3), .option(4)])
        XCTAssertEqual(key(0, "1", [.command, .shift]), .option(1))
        XCTAssertNil(key(18, "1"))
        XCTAssertNil(key(0, "5", .command))
        XCTAssertNil(key(0, "1", [.command, .control]))
        // What the pointer reaches, the keys reach: hide and show again, the folds, the pin,
        // the legend, the settings. By the letter the key types, not by where it sits.
        XCTAssertEqual(["h", "u", "d", "i", "p", "?", ",", "t"].map { key(0, $0) }, [.hide, .unhide, .done, .idle, .pin, .legend, .settings, .history])
        XCTAssertEqual(key(0, "H", .shift), .hide)
        XCTAssertEqual(key(0, "?", .shift), .legend)
        // A keyboard that types no Latin letters, as the Thai one does not, is read by the
        // letter its key stands for in a shortcut, which is how macOS reads its own there: the
        // key marked H types "้" by itself, and "h" with Command.
        func thai(_ typed: String, _ shortcut: String, _ modifiers: NSEvent.ModifierFlags = []) -> KeyCommand? {
            KeyCommand(keyCode: 0, characters: typed, shortcut: shortcut, modifiers: modifiers)
        }
        // The key marked T types "ะ" by itself, and "t" with Command.
        XCTAssertEqual([("้", "h"), ("ี", "u"), ("ก", "d"), ("ร", "i"), ("ย", "p"), ("ฝ", "/"), ("ม", ","), ("ะ", "t")].map { thai($0.0, $0.1) },
                       [.hide, .unhide, .done, .idle, .pin, .legend, .settings, .history])
        XCTAssertEqual(thai("ฦ", "?", .shift), .legend)
        // Its digit keys type "ๅ", "/", "_" and "ภ" by themselves, and the digits with Command.
        XCTAssertEqual([("ๅ", "1"), ("/", "2"), ("_", "3"), ("ภ", "4")].map { thai($0.0, $0.1, .command) }, [.option(1), .option(2), .option(3), .option(4)])
        XCTAssertNil(thai("ๅ", "1"))
        XCTAssertNil(thai("้", "h", .command))
        XCTAssertNil(thai("ถ", "5", .command))
        // A keyboard that does type Latin letters is taken at its word, whatever its keys stand
        // for in a shortcut: "Dvorak - QWERTY ⌘" types "d" on the key that is "h" with Command.
        XCTAssertEqual(thai("d", "h"), .done)
        XCTAssertNil(thai("x", "h"))
        // A key that types nothing by itself, as one that only begins an accent, means nothing.
        XCTAssertNil(thai("", "h"))
        // With Command, Control or Option held those letters are other apps' chords, not the panel's.
        XCTAssertNil(key(4, "h", .command))
        XCTAssertNil(key(4, "h", .control))
        XCTAssertNil(key(4, "h", .option))
        // An arrow held down goes on walking. Nothing else repeats, an answer least of all:
        // the next request must not be answered by a key still down from the last.
        XCTAssertEqual([KeyCommand.up, .down, .allow, .deny, .option(1), .go, .hide, .close].map(\.repeats), [true, true, false, false, false, false, false, false])
        XCTAssertEqual([KeyCommand.allow, .deny, .option(2), .go, .hide].map(\.answers), [true, true, true, false, false])
    }

    private func panel(with view: NSView) -> NotchPanel {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view
        panel.makeFirstResponder(view)
        return panel
    }

    private func key(_ code: UInt16, down: Bool = true, in panel: NSPanel) -> NSEvent {
        NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                         characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: code)!
    }

    // No key sent to the panel goes on to what is in it, whichever way AppKit brings the key:
    // Space and Return press a focused button anywhere else in macOS.
    func testNoKeyReachesWhatIsInThePanel() {
        let view = Recorder()
        let panel = panel(with: view)
        var commands: [KeyCommand] = []
        panel.onKey = { command, _ in commands.append(command) }
        for takesKeys in [true, false] {
            panel.takesKeys = takesKeys
            for code: UInt16 in [49, 36, 48, 125] {
                panel.sendEvent(key(code, in: panel))
                panel.sendEvent(key(code, down: false, in: panel))
            }
        }
        XCTAssertEqual(view.keys, 0)
        // While the panel has the keyboard each key is acted on once, by the panel itself. Any
        // key other than its own hands the keyboard back, so that a chord pressed by accident
        // costs one keystroke and not everything typed after it. Without the keyboard, nothing.
        // Tab does nothing at all: see below.
        XCTAssertEqual(commands, [.close, .go, .down])
        // A key held down is not pressed again and again.
        commands = []
        panel.takesKeys = true
        func held(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], isARepeat: Bool = true) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                             characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: isARepeat, keyCode: code)!
        }
        panel.sendEvent(held(49))
        XCTAssertEqual(commands, [])
        // Command-Return answers once, and held down it does not answer the request after.
        XCTAssertTrue(panel.performKeyEquivalent(with: held(36, .command, isARepeat: false)))
        XCTAssertTrue(panel.performKeyEquivalent(with: held(36, .command)))
        XCTAssertEqual(commands, [.allow])
        // An arrow held down goes on walking.
        commands = []
        panel.sendEvent(held(125))
        XCTAssertEqual(commands, [.down])

        // The app offers every key down as a key equivalent first. The panel takes it there
        // while it has the keyboard, and has no say while it does not.
        commands = []
        panel.takesKeys = true
        XCTAssertTrue(panel.performKeyEquivalent(with: key(126, in: panel)))
        XCTAssertTrue(panel.performKeyEquivalent(with: key(49, in: panel)))
        panel.takesKeys = false
        XCTAssertFalse(panel.performKeyEquivalent(with: key(126, in: panel)))
        XCTAssertEqual(view.keys, 0)
        XCTAssertEqual(commands, [.up, .close])
    }

    // Tab moves between controls everywhere else on a Mac. Pressed in the panel for that, it
    // shut the panel: three testers who work by keyboard lost it that way, one of them on a
    // screen reader. It does nothing now, alone or with Shift. It still moves nothing: the
    // settings cannot be worked by keyboard yet.
    func testTabDoesNotShutThePanel() {
        XCTAssertTrue(NotchPanel.isTab(keyCode: 48, modifiers: []))
        XCTAssertTrue(NotchPanel.isTab(keyCode: 48, modifiers: .shift))
        // With Control it is another app's chord, and like any key the panel does not know.
        XCTAssertFalse(NotchPanel.isTab(keyCode: 48, modifiers: .control))
        XCTAssertFalse(NotchPanel.isTab(keyCode: 48, modifiers: [.command, .shift]))
        XCTAssertFalse(NotchPanel.isTab(keyCode: 49, modifiers: []))

        let view = Recorder()
        let panel = panel(with: view)
        var commands: [KeyCommand] = []
        panel.onKey = { command, _ in commands.append(command) }
        panel.takesKeys = true
        func tab(_ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                             characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
        }
        panel.sendEvent(tab([]))
        XCTAssertTrue(panel.performKeyEquivalent(with: tab(.shift)))
        XCTAssertEqual(commands, [])
        // And it is not handed on to anything in the panel.
        XCTAssertEqual(view.keys, 0)
        panel.sendEvent(tab(.control))
        XCTAssertEqual(commands, [.close])
        // The arrows to either side still hand the keyboard back, as before.
        panel.sendEvent(key(123, in: panel))
        XCTAssertEqual(commands, [.close, .close])
    }

    // A key is judged by when it was pressed, as a click is by when the button went down. If
    // the app is slow to get to it, a second Command-Return pressed at the first request must
    // not be judged later, when the next request has had time to arm.
    func testAKeyIsTimedByWhenItWasPressed() {
        let panel = panel(with: Recorder())
        panel.takesKeys = true
        var times: [Date] = []
        panel.onKey = { _, at in times.append(at) }
        let uptime = ProcessInfo.processInfo.systemUptime
        func press(at timestamp: TimeInterval) {
            _ = panel.performKeyEquivalent(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: timestamp, windowNumber: panel.windowNumber,
                                                                 context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        }
        press(at: uptime - 2)
        XCTAssertEqual(times[0].timeIntervalSinceNow, -2, accuracy: 0.5)
        // A time ahead of the clock is not believed.
        press(at: uptime + 60)
        XCTAssertEqual(times[1].timeIntervalSinceNow, 0, accuracy: 0.5)
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(NotchPanel.when(40, now: now, uptime: 42), now.addingTimeInterval(-2))
        XCTAssertEqual(NotchPanel.when(50, now: now, uptime: 42), now)
    }

    // A key acts on the session the arrows were on when it was pressed, once, and nowhere
    // else. A key that found nothing to answer there once answered the request the arrows
    // reached next: what is kept of a key names its session, and is turned down on any other.
    func testAKeyActsOnTheSessionItWasPressedOnAndNoOther() {
        let state = NotchState()
        state.keyboard = true
        state.selected = "a"
        let at = Date(timeIntervalSince1970: 1000)
        state.press(.allow, at: at)
        XCTAssertEqual(state.keyed, Keyed(serial: 1, command: .allow, at: at, card: "a"))
        XCTAssertEqual(state.keyed?.acts(on: "a", keyboard: true), true)
        // The arrows move on: nothing happens there.
        state.selected = "b"
        XCTAssertEqual(state.keyed?.card, "a")
        XCTAssertEqual(state.keyed?.acts(on: "b", keyboard: true), false)
        // Nor where it was pressed, once the keyboard has been handed back.
        XCTAssertEqual(state.keyed?.acts(on: "a", keyboard: false), false)
        // The same key again is another press, on the session the arrows are on now.
        state.press(.allow, at: at)
        XCTAssertEqual(state.keyed, Keyed(serial: 2, command: .allow, at: at, card: "b"))
        // With no session chosen a key is for none.
        state.selected = nil
        state.press(.deny, at: at)
        XCTAssertEqual(state.keyed?.acts(on: nil, keyboard: true), false)
    }

    // A request is answered by the pointer and by nothing else. "This is a click" holds only
    // while the panel is handing a mouse-up to what was clicked: a button's action that runs at
    // any other time, for a key or for anything else, finds it false.
    func testAClickIsAClickOnlyWhileItIsBeingHandled() {
        let view = Recorder()
        let panel = panel(with: view)
        func mouse(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: 50, y: 50), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        // A window hands clicks on only while it is on a screen. Far off every one, and clear.
        panel.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        XCTAssertFalse(NotchPanel.handlingClick)
        panel.sendEvent(mouse(.leftMouseDown))
        XCTAssertFalse(NotchPanel.handlingClick)
        panel.sendEvent(mouse(.leftMouseUp))
        XCTAssertEqual(view.clicks, [true])
        XCTAssertFalse(NotchPanel.handlingClick)
        // A right click is not one.
        panel.sendEvent(mouse(.rightMouseUp))
        XCTAssertFalse(NotchPanel.handlingClick)
    }

    // A pinned panel is never opened again, so an opening cannot be what says "seen" there.
    // The pointer resting in it is: one look for each second it stays.
    func testAPointerRestingInAPinnedPanelIsALook() {
        var rested: TimeInterval = 0
        var looks = 0
        func tick(inside: Bool = true, pinned: Bool = true) {
            let next = EntryWatch.rest(rested, inside: inside, pinned: pinned)
            rested = next.rested
            looks += next.looked ? 1 : 0
        }
        for _ in 0..<19 { tick() }
        XCTAssertEqual(looks, 0)
        tick()
        XCTAssertEqual(looks, 1)
        // And again for the next second.
        for _ in 0..<20 { tick() }
        XCTAssertEqual(looks, 2)
        // Leaving starts the count over.
        for _ in 0..<15 { tick() }
        tick(inside: false)
        for _ in 0..<15 { tick() }
        XCTAssertEqual(looks, 2)
        // Unpinned, an opening that lasts is the look; resting adds none.
        for _ in 0..<40 { tick(pinned: false) }
        XCTAssertEqual(looks, 2)
    }

    // On a page no session is in sight, the settings or History: the keys that walk the sessions
    // and go to one do nothing there. Esc still closes.
    func testTheSessionKeysDoNothingOnAPage() {
        XCTAssertTrue(KeyCommand.down.acts(onPage: false))
        XCTAssertFalse(KeyCommand.down.acts(onPage: true))
        XCTAssertFalse(KeyCommand.up.acts(onPage: true))
        // History's key works from a page too: it is about the app, not a session.
        XCTAssertTrue(KeyCommand.history.acts(onPage: true))
        XCTAssertFalse(KeyCommand.go.acts(onPage: true))
        XCTAssertTrue(KeyCommand.close.acts(onPage: true))
        // Nor do the keys that act on a session or answer one. The ones that are about the
        // panel itself work on either page.
        XCTAssertEqual([KeyCommand.allow, .deny, .option(1), .hide, .unhide, .done, .idle].map { $0.acts(onPage: true) }, [false, false, false, false, false, false, false])
        XCTAssertEqual([KeyCommand.pin, .legend, .settings].map { $0.acts(onPage: true) }, [true, true, true])
    }

    // History stands where the list was, as the settings do: one page at a time, and the legend
    // goes as either opens. Opened from the list it starts afresh; what was picked stays while the
    // page does, so a pointer that strayed finds it again.
    func testHistoryIsAPageOfThePanel() {
        let state = NotchState()
        state.showingLegend = true
        state.historyPick.project = "shop-web"
        state.openHistory()
        XCTAssertTrue(state.showingHistory)
        XCTAssertTrue(state.showingPage)
        XCTAssertFalse(state.showingLegend)
        XCTAssertNil(state.historyPick.project)
        state.historyPick.project = "api"
        state.showingSettings = true
        XCTAssertFalse(state.showingHistory)
        XCTAssertTrue(state.showingPage)
        state.toggleHistory()
        XCTAssertTrue(state.showingHistory)
        XCTAssertFalse(state.showingSettings)
        // Opened again from the settings: afresh.
        XCTAssertNil(state.historyPick.project)
        state.historyPick.project = "api"
        state.toggleLegend()
        XCTAssertTrue(state.showingLegend)
        XCTAssertFalse(state.showingHistory)
        XCTAssertFalse(state.showingPage)
        state.openHistory()
        state.toggleHistory()
        XCTAssertFalse(state.showingHistory)
    }

    func testTokenUseOffPutsHistoryAway() {
        let state = NotchState()
        state.openHistory()
        state.tokenUse(true)
        XCTAssertTrue(state.showingHistory)
        state.tokenUse(false)
        XCTAssertFalse(state.showingHistory)
    }

    func testArrowKeysWalkTheCardsAndStopAtTheEnds() {
        let cards = ["a", "b", "c"]
        XCTAssertEqual(KeyCommand.move(nil, by: 1, in: cards), "a")
        XCTAssertEqual(KeyCommand.move(nil, by: -1, in: cards), "c")
        XCTAssertEqual(KeyCommand.move("a", by: 1, in: cards), "b")
        XCTAssertEqual(KeyCommand.move("c", by: 1, in: cards), "c")
        XCTAssertEqual(KeyCommand.move("a", by: -1, in: cards), "a")
        // The card that was chosen has gone: start again from the nearer end.
        XCTAssertEqual(KeyCommand.move("gone", by: 1, in: cards), "a")
        XCTAssertNil(KeyCommand.move("a", by: 1, in: []))
    }

    // The shortcut and then Return is the whole trip to an agent that waits: the keyboard starts
    // on the first session that may need the person, or on the first one when none does.
    func testTheKeyboardStartsOnTheFirstSessionThatMayNeedThePerson() {
        func card(_ id: String, _ status: AgentStatus) -> SessionCard {
            SessionCard(id: id, project: id, branch: "", main: AgentRow(id: id, info: AgentInfo(), status: status, elapsed: 0), agents: [], startedAt: Date(timeIntervalSince1970: 0))
        }
        XCTAssertEqual(KeyCommand.start(in: [card("a", .working), card("b", .needsYou), card("c", .quiet)]), "b")
        // One that waits comes before one that is only quiet, wherever it stands: the same
        // session a pointer's opening leads to.
        XCTAssertEqual(KeyCommand.start(in: [card("a", .quiet), card("b", .needsYou)]), "b")
        XCTAssertEqual(KeyCommand.start(in: [card("a", .working), card("b", .quiet)]), "b")
        XCTAssertEqual(KeyCommand.start(in: [card("a", .working), card("b", .done)]), "a")
        XCTAssertNil(KeyCommand.start(in: []))
    }

    func testContentTallerThanThePanelAllowsIsReportedAsOverflowing() {
        XCTAssertFalse(NotchGeometry.overflows(screen: screen, barHeight: 32, contentHeight: 400))
        XCTAssertTrue(NotchGeometry.overflows(screen: screen, barHeight: 32, contentHeight: 600))
    }

    func testExpandedPanelNeverExceedsANarrowOffsetScreen() {
        let narrow = CGRect(x: 100, y: 50, width: 400, height: 800)
        let frame = NotchGeometry.expandedFrame(screen: narrow, barHeight: 24, contentHeight: 100)
        XCTAssertEqual(frame, CGRect(x: 100, y: 726, width: 400, height: 124))
    }

    // Five pages since 2026-10-21, the way a Mac app's settings are split: two had grown long,
    // a page of fifteen rows. The first is the general one, and the page last read is the one
    // found again, until the app quits.
    func testTheSettingsOpenOnGeneralAndAreFivePages() {
        XCTAssertEqual(NotchState().settingsTab, .general)
        XCTAssertEqual(SettingsTab.allCases.map(\.label), ["General", "Sounds", "Shortcuts", "Claude Code", "About"])
    }

    // The legend is three short pages. The pointer finds the page it last read. The key that is
    // said to list every key opens on the keys: no key turns the pages.
    func testTheLegendOpensOnItsLastPageAndByItsKeyOnTheKeys() {
        XCTAssertEqual(LegendTab.allCases.map(\.label), ["Mascots", "Bar", "Keys"])
        let state = NotchState()
        state.toggleLegend()
        XCTAssertTrue(state.showingLegend)
        XCTAssertEqual(state.legendTab, .mascots)
        state.legendTab = .bar
        state.toggleLegend()
        XCTAssertFalse(state.showingLegend)
        state.toggleLegend()
        XCTAssertEqual(state.legendTab, .bar)
        state.toggleLegend()
        state.toggleLegend(byKey: true)
        XCTAssertTrue(state.showingLegend)
        XCTAssertEqual(state.legendTab, .keys)
        // Put away by its key, it is left on the page it was on.
        state.legendTab = .bar
        state.toggleLegend(byKey: true)
        XCTAssertFalse(state.showingLegend)
        XCTAssertEqual(state.legendTab, .bar)
    }

    // The card the arrow keys land on is brought to stand clear of the band at the top of a
    // scrolled list. It used to come to the list's very edge, its name under the band: the
    // testers who answered by the keys could not read which session they were answering.
    func testAChosenCardIsBroughtToStandClearOfTheTopBand() {
        let anchor = ScrollTarget.clearOfBand(viewport: 400)
        XCTAssertEqual(anchor.y * 400, NotchGeometry.topBand + 4, accuracy: 0.001)
        XCTAssertGreaterThan(anchor.y * 400, NotchGeometry.topBand)
        // A list with no height yet, and one shorter than the band: nowhere past its own edges.
        XCTAssertEqual(ScrollTarget.clearOfBand(viewport: 0).y, 0)
        XCTAssertEqual(ScrollTarget.clearOfBand(viewport: 20).y, 1)
    }

    // With the legend up, the gear opened the settings over it and left it standing. Back
    // from the settings there was the legend, with a second "← Agents" of its own to press:
    // five of thirteen testers pressed twice to get back to the agents.
    func testOpeningTheSettingsPutsTheLegendAway() {
        let state = NotchState()
        state.toggleLegend()
        state.showingSettings.toggle()
        XCTAssertTrue(state.showingSettings)
        XCTAssertFalse(state.showingLegend)
        state.showingSettings = false
        XCTAssertFalse(state.showingLegend, "one press back is the agents")
        // The legend's own way out is untouched, and so is its page.
        state.legendTab = .bar
        state.toggleLegend()
        XCTAssertTrue(state.showingLegend)
        state.showingSettings = false
        XCTAssertTrue(state.showingLegend)
        XCTAssertEqual(state.legendTab, .bar)
    }

    // From the settings the legend is shown, whatever it was left at, and the settings go.
    func testFromTheSettingsTheLegendIsShown() {
        let state = NotchState()
        state.showingLegend = true
        state.showingSettings = true
        state.toggleLegend()
        XCTAssertTrue(state.showingLegend)
        XCTAssertFalse(state.showingSettings)
    }
}
