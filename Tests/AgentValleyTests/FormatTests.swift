import AppKit
import SwiftUI
import XCTest
@testable import AgentValley

final class FormatTests: XCTestCase {
    func testElapsed() {
        XCTAssertEqual(Format.elapsed(0), "0s")
        XCTAssertEqual(Format.elapsed(45.9), "45s")
        XCTAssertEqual(Format.elapsed(130), "2m 10s")
        XCTAssertEqual(Format.elapsed(599), "9m 59s")
        // Past ten minutes the seconds say nothing, and ticked on every row.
        XCTAssertEqual(Format.elapsed(600), "10m")
        XCTAssertEqual(Format.elapsed(1899), "31m")
        XCTAssertEqual(Format.elapsed(3900), "1h 05m")
    }

    func testTokens() {
        XCTAssertEqual(Format.tokens(0), "0")
        XCTAssertEqual(Format.tokens(950), "950")
        XCTAssertEqual(Format.tokens(12_300), "12.3k")
        XCTAssertEqual(Format.tokens(236_600), "236.6k")
        XCTAssertEqual(Format.tokens(1_200_000), "1.2M")
    }

    func testStepLineIsOmittedBeforeTheFirstToolCall() {
        XCTAssertNil(Format.stepLine(""))
        XCTAssertEqual(Format.stepLine("Read login.ts"), "> Read login.ts")
    }

    // The interface is English only. Reading the sources keeps a stray Thai label from slipping in.
    func testAppSourcesContainNoThaiText() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AgentValley")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let thai = text.unicodeScalars.first { (0x0E00...0x0E7F).contains($0.value) }
            XCTAssertNil(thai, "\(file.lastPathComponent) contains Thai text")
        }
    }

    func testStepCountIsSingularForOneStep() {
        XCTAssertEqual(Format.steps(1), "1 step")
        XCTAssertEqual(Format.steps(22), "22 steps")
    }

    func testHeaderCounts() {
        XCTAssertEqual(Format.working(0), "0 working")
        XCTAssertEqual(Format.working(4), "4 working")
        XCTAssertEqual(Format.idle(3), "3 idle")
    }

    // The task is what tells agents apart, so it leads. The type leads only when there is no task.
    func testRowTitleAndSubtitle() {
        XCTAssertEqual(Format.rowTitle(task: "Find auth files", type: "Explore"), "Find auth files")
        XCTAssertEqual(Format.rowTitle(task: "", type: "Explore"), "Explore")
        XCTAssertEqual(Format.rowSubtitle(task: "Find auth files", type: "Explore"), "Explore")
        XCTAssertNil(Format.rowSubtitle(task: "", type: "Explore"))
    }

    // "general-purpose" is the default, and the round mascot already says so. A plugin's prefix says
    // whose agent it is, not what it does. Both took room from the step.
    func testRowSubtitleLeavesOutWhatSaysNothing() {
        XCTAssertNil(Format.rowSubtitle(task: "Fix the pay button", type: "general-purpose"))
        XCTAssertEqual(Format.rowSubtitle(task: "Review the diff", type: "acme:code-reviewer"), "code-reviewer")
        XCTAssertNil(Format.rowSubtitle(task: "Review the diff", type: ""))
        // With no task the type is the row's only name, so it stays whole.
        XCTAssertEqual(Format.rowTitle(task: "", type: "acme:code-reviewer"), "acme:code-reviewer")
    }

    // A row Claude Code calls busy stays "working" through any silence. Past two minutes the step
    // says how long ago the transcript last moved, so a hung command does not pass for progress.
    func testAWorkingRowSaysWhenItLastMoved() {
        XCTAssertNil(Format.lastMoved(.working, silentFor: 119))
        XCTAssertEqual(Format.lastMoved(.working, silentFor: 14 * 60 + 20), "14m ago")
        // It stands where the row's time stands, in the same place on every row: at the end of
        // the step it sat somewhere else on each, and had to be read for.
        XCTAssertEqual(Format.rowTime(.working, elapsed: 400, quietFor: 14 * 60 + 20), "14m ago")
        XCTAssertEqual(Format.rowTime(.working, elapsed: 400, quietFor: 20), "6m 40s")
        XCTAssertEqual(Format.rowTime(.quiet, elapsed: 400, quietFor: 300), "quiet 5m")
        XCTAssertEqual(Format.rowTime(.needsYou, elapsed: 400, quietFor: 70), "needs you")
        XCTAssertEqual(Format.rowTime(.done, elapsed: 400, quietFor: 0), "done")
        XCTAssertEqual(Format.lastMoved(.working, silentFor: 3700), "1h 01m ago")
        // Quiet and asking rows already say for how long, beside their name.
        XCTAssertNil(Format.lastMoved(.quiet, silentFor: 900))
        XCTAssertNil(Format.lastMoved(.needsYou, silentFor: 900))
        XCTAssertNil(Format.lastMoved(.done, silentFor: 900))
    }

    // The main agent can end its turn while agents it started run on. "idle" over working rows
    // read as a finished session.
    func testACardWhoseMainAgentEndedSaysHowManyStillWork() {
        func card(main: AgentStatus, agents: [AgentStatus]) -> SessionCard {
            func row(_ id: String, _ status: AgentStatus) -> AgentRow { AgentRow(id: id, info: AgentInfo(), status: status, elapsed: 0, quietFor: 200) }
            return SessionCard(id: "s", project: "p", branch: "", main: row("m", main),
                               agents: agents.enumerated().map { row("a\($0.offset)", $0.element) }, startedAt: Date(timeIntervalSince1970: 0))
        }
        XCTAssertEqual(Format.cardStatus(card(main: .done, agents: [.working, .done, .working])), "2 working")
        XCTAssertEqual(Format.cardStatus(card(main: .done, agents: [.done])), "idle")
        // A quiet agent is not known to be at work: its own row says what it is.
        XCTAssertEqual(Format.cardStatus(card(main: .done, agents: [.quiet])), "idle")
        // At work and silent for three minutes: since when, where its time would stand.
        XCTAssertEqual(Format.cardStatus(card(main: .working, agents: [.working])), "3m ago")
        XCTAssertEqual(Format.cardStatus(card(main: .needsYou, agents: [.working])), "needs you")
    }

    func testQuitLabelNamesTheApp() {
        XCTAssertEqual(Format.quit(appName: "AgentValley"), "Quit AgentValley")
        XCTAssertEqual(Format.quit(appName: nil), "Quit")
    }

    // An empty panel says what to do next, not only that it is empty.
    func testEmptyStatesSayWhatToDo() {
        XCTAssertEqual(Format.emptyState(loaded: true, rootMissing: false, isEmpty: true), "No agents running. Start Claude Code in a terminal and they appear here.")
        XCTAssertEqual(Format.emptyState(loaded: true, rootMissing: true, isEmpty: true), "Can't find ~/.claude/projects. Run Claude Code once and agents appear here.")
        XCTAssertNil(Format.emptyState(loaded: true, rootMissing: false, isEmpty: false))
    }

    // At launch the list is empty because nothing has been read yet. Saying "No agents running"
    // for that moment tells a person with ten agents to go and start one.
    func testNothingIsClaimedBeforeTheFirstScan() {
        XCTAssertNil(Format.emptyState(loaded: false, rootMissing: false, isEmpty: true))
        XCTAssertNil(Format.emptyState(loaded: false, rootMissing: true, isEmpty: true))
    }

    // A Mac without a notch still gets the bar, so the first-launch line must not send people to a notch.
    func testTheIntroPointsAtSomethingEveryMacShows() {
        XCTAssertFalse(Format.intro(shortcut: .a).lowercased().contains("notch"))
        XCTAssertTrue(Format.intro(shortcut: .a).contains("mascot"))
        // And the way in that needs no pointer, while there is one: not when the shortcut is
        // switched off or another app holds it.
        XCTAssertTrue(Format.intro(shortcut: .n).contains("⌃ ⌥ ⌘ N"))
        XCTAssertFalse(Format.intro(shortcut: nil).contains("⌘"))
        // And where the marks are explained, in place of a page of them.
        XCTAssertTrue(Format.intro(shortcut: nil).contains("The ? above explains the symbols."))
        XCTAssertTrue(Format.intro(shortcut: nil).contains("mascot"))
    }

    // At first launch the panel opens by itself and stays until the pointer has been in it.
    // "It closes when you move away" stood on it meanwhile: four of thirteen testers watched
    // it not close. The line says what the panel does this once, then how to open it again.
    func testTheIntroSaysWhyThePanelIsStillOpen() {
        XCTAssertEqual(Format.intro(shortcut: nil), "This panel shows what your Claude Code agents are doing, and when one needs you. It opened by itself this once: point at it, then move away, and it closes. To open it again, point at the mascot at the top of the screen. The ? above explains the symbols.")
        // What the app is for comes first. It used to be said only on the last page of the
        // settings: five of thirteen testers went through the pages to find out.
        XCTAssertTrue(Format.intro(shortcut: .a).hasPrefix("This panel shows what your Claude Code agents are doing, and when one needs you."))
        XCTAssertTrue(Format.intro(shortcut: .a).contains("point at the mascot at the top of the screen, or press ⌃ ⌥ ⌘ A."))
        XCTAssertFalse(Format.intro(shortcut: .a).contains("It closes when you move away."))
    }

    func testLimitsNoticeNamesTheSettingWhenThereAreNoNumbers() {
        let some = PlanLimits(fiveHour: PlanLimit(usedPercent: 40, resetsAt: nil), week: nil)
        // Switched off is a choice, not news: nothing is said of it in every glance.
        XCTAssertNil(Format.limitsNotice(.off))
        XCTAssertEqual(Format.limitsNotice(.unavailable(.offline)), "Plan limits unavailable")
        XCTAssertNil(Format.limitsNotice(.loading))
        XCTAssertNil(Format.limitsNotice(.limits(some, asOf: Date())))
    }

    // Each reason says what the person can do, and none carries anything from the login or the reply.
    func testLimitsReasonsSayWhatToDo() {
        XCTAssertEqual(Format.limitsReason(.noLogin), "No Claude Code login in Keychain. Sign in with Claude Code first.")
        XCTAssertEqual(Format.limitsReason(.loginExpired), "The Claude Code login has expired. Use Claude Code once to renew it.")
        XCTAssertEqual(Format.limitsReason(.offline), "No connection to api.anthropic.com. It tries again every 5 minutes.")
        XCTAssertEqual(Format.limitsReason(.refused(529)), "api.anthropic.com answered with error 529. It tries again every 5 minutes.")
        XCTAssertEqual(Format.limitsReason(.unreadable), "api.anthropic.com sent an answer this version does not understand. A newer version of the app may.")
        XCTAssertEqual(Format.limitsReason(.noAnswer), "No answer after a minute. It will try again.")
        XCTAssertEqual(Format.limitsLoading, "Checking limits…")
    }

    // Old numbers say how old they are; dimming them only made them hard to read.
    func testOldLimitsSayTheirAge() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Format.limitsAge(asOf: now.addingTimeInterval(-720), now: now), "12m old")
        XCTAssertEqual(Format.limitsAge(asOf: now.addingTimeInterval(-20), now: now), "1m old")
        // And, to the pointer, why they are old and what happens next.
        XCTAssertEqual(Format.limitsAgeHelp, "The last check failed, so these are the numbers from before. It tries again every 5 minutes.")
    }

    // The ring on the bar has no room for a word: read out, it says which limit and how much,
    // and that the number is an old one when it is.
    func testTheRingOnTheBarSaysItsLimitInWords() {
        let limit = PlanLimit(usedPercent: 61.6, resetsAt: nil)
        XCTAssertEqual(Format.ringLabel(LimitRing(limit: limit, stale: false)), "5-hour limit 62% used")
        XCTAssertEqual(Format.ringLabel(LimitRing(limit: limit, stale: true)), "5-hour limit 62% used, from before the last check failed")
    }

    // "5h" and "7d" are short for the row's sake. Resting the pointer on one says it in words.
    func testALimitSaysItselfInWords() {
        XCTAssertEqual(Format.limitHelp(spoken: "5-hour limit", percent: "42%", reset: "2h 09m"), "5-hour limit: 42% used, resets in 2h 09m")
        XCTAssertEqual(Format.limitHelp(spoken: "Weekly limit", percent: "8%", reset: nil), "Weekly limit: 8% used")
    }

    // Finished agents fold into one line per card, so live work is not pushed off the panel.
    func testFinishedAgentsFoldIntoOneLine() {
        XCTAssertEqual(Format.done(1), "1 done")
        XCTAssertEqual(Format.done(3), "3 done")
    }

    // "More below" is not enough: say how much, and whether any of it may need the person.
    func testTheEdgeOfTheListSaysWhatIsBelowIt() {
        XCTAssertNil(Format.below(sessions: 0, quiet: 0, needsYou: 0))
        XCTAssertEqual(Format.below(sessions: 1, quiet: 0, needsYou: 0), "+1 session")
        XCTAssertEqual(Format.below(sessions: 3, quiet: 0, needsYou: 0), "+3 sessions")
        XCTAssertEqual(Format.below(sessions: 3, quiet: 1, needsYou: 0), "+3 sessions · 1 quiet")
        XCTAssertEqual(Format.below(sessions: 2, quiet: 1, needsYou: 2), "+2 sessions · 2 need you · 1 quiet")
        // A row that waits can be past the edge inside a card that starts above it.
        XCTAssertEqual(Format.below(sessions: 0, quiet: 0, needsYou: 1), "1 needs you")
    }

    // A request the panel can answer is named apart from the rows that merely wait.
    func testTheEdgeNamesRequestsAnswerableHere() {
        XCTAssertEqual(Format.below(sessions: 2, quiet: 0, needsYou: 2, answerable: 1), "+2 sessions · 2 need you · 1 to answer here")
        XCTAssertEqual(Format.below(sessions: 0, quiet: 0, needsYou: 1, answerable: 1), "1 needs you · 1 to answer here")
        XCTAssertEqual(Format.below(sessions: 2, quiet: 1, needsYou: 2, answerable: 2), "+2 sessions · 2 need you · 2 to answer here · 1 quiet")
        // None, and the phrase is absent, as it was.
        XCTAssertEqual(Format.below(sessions: 2, quiet: 0, needsYou: 2, answerable: 0), "+2 sessions · 2 need you")
        XCTAssertFalse(Format.below(sessions: 1, quiet: 1, needsYou: 1)!.contains("answer"))
    }

    func testOnlyShownRequestsCountAsAnswerable() {
        XCTAssertTrue(Ask.Kind.question(text: "?", header: "", options: []).isAnswerable)
        XCTAssertTrue(Ask.Kind.permission(Ask.Shown(command: "ls", fields: [])).isAnswerable)
        XCTAssertFalse(Ask.Kind.permissionHidden(Ask.Partial(fields: [], missing: [])).isAnswerable)
        XCTAssertFalse(Ask.Kind.terminalOnly(text: "plan").isAnswerable)
    }

    func testSummaryNamesQuietAgentsOnlyWhenThereAreSome() {
        XCTAssertEqual(Format.summary(working: 2, quiet: 1), "2 working · 1 quiet")
        XCTAssertEqual(Format.summary(working: 2, quiet: 0), "2 working")
        // "0 working" is said only when it is all there is to say.
        XCTAssertEqual(Format.summary(working: 0, quiet: 3), "3 quiet")
        XCTAssertEqual(Format.summary(working: 0, quiet: 0, needsYou: 5), "5 need you")
        XCTAssertEqual(Format.summary(working: 0, quiet: 0), "0 working")
        // Whoever needs the person leads: it is the one thing on the row to act on.
        XCTAssertEqual(Format.summary(working: 5, quiet: 1, needsYou: 1), "1 needs you · 5 working · 1 quiet")
        XCTAssertEqual(Format.summary(working: 2, quiet: 0, needsYou: 3), "3 need you · 2 working")
    }

    // A button read aloud must say what it answers and for whom, not just "Allow". The app's
    // words and the request's are read apart: a tool's name or a title inside the app's own
    // sentence could put words in its mouth.
    func testAnswerButtonsSayWhatTheyAnswer() {
        XCTAssertEqual(Format.answerLabel(.allow), "Allow once")
        XCTAssertEqual(Format.answerLabel(.deny), "Deny")
        XCTAssertEqual(Format.answerLabel(.option("Red")), "Answer")
        XCTAssertEqual(Format.answerLabel(.skip), "Skip")
        XCTAssertEqual(Format.answerValue(.allow, tool: "Bash", title: "Add a receipt email"), "Bash, Add a receipt email")
        XCTAssertEqual(Format.answerValue(.deny, tool: "Bash", title: "Add a receipt email"), "Bash, Add a receipt email")
        XCTAssertEqual(Format.answerValue(.option("Red"), tool: "AskUserQuestion", title: "Add a receipt email"), "Red, Add a receipt email")
        // An option's description is drawn on its row, so it is read with its label.
        XCTAssertEqual(Format.answerValue(.option("Red"), tool: "AskUserQuestion", title: "Add a receipt email", detail: "The brand color"), "Red, The brand color, Add a receipt email")
        XCTAssertEqual(Format.terminalOnly, "Answer in the terminal.")
        // The app's own sentence carries no text from the request.
        XCTAssertEqual(Format.cannotShow, "Can't show all of this here. Deny it, or answer in the terminal.")
        XCTAssertEqual(Format.notShown, "not shown")
        // "quiet" on its own explains nothing to someone who has not read the code.
    }

    func testInstallCommandsUseTheAppsOwnPath() {
        // One command to copy: leaving the panel to paste closes it, and a second trip was easy to forget.
        XCTAssertEqual(Format.installCommand(resources: URL(fileURLWithPath: "/Applications/My App.app/Contents/Resources")),
                       "claude plugin marketplace add '/Applications/My App.app/Contents/Resources/claude-plugin' && claude plugin install notch-answers@agent-valley")
        // Pasted into a shell: nothing in the app's own path may be read as shell syntax.
        XCTAssertTrue(Format.installCommand(resources: URL(fileURLWithPath: "/Apps/It's $(x) `y`/R"))
            .hasPrefix("claude plugin marketplace add '/Apps/It'\\''s $(x) `y`/R/claude-plugin' && "))
    }

    // When the plugin points at an older copy of the app, the old list goes first: Claude Code
    // will not add a second one by the same name.
    func testInstallCommandReplacing() {
        let resources = URL(fileURLWithPath: "/Applications/AgentValley.app/Contents/Resources")
        XCTAssertEqual(Format.installCommand(resources: resources), "claude plugin marketplace add '/Applications/AgentValley.app/Contents/Resources/claude-plugin' && claude plugin install notch-answers@agent-valley")
        XCTAssertEqual(Format.installCommand(resources: resources, replacing: true), "claude plugin marketplace remove agent-valley && " + Format.installCommand(resources: resources))
        XCTAssertEqual(Format.pluginLostLine, "Allow and Deny can't find us anymore.")
        XCTAssertEqual(Format.pluginLostFix, "Fix it")
        XCTAssertEqual(Format.pluginLostNote, "The plugin still points at a copy of us that's gone. Run this once more.")
    }

    func testStablePathAndCrewCommand() {
        XCTAssertEqual(Format.stablePath(URL(fileURLWithPath: "/opt/homebrew/Cellar/agent-valley/0.1.2/AgentValley.app/Contents/MacOS/AgentValley")),
                       "/opt/homebrew/opt/agent-valley/AgentValley.app/Contents/MacOS/AgentValley")
        XCTAssertEqual(Format.crewCommand(executable: "/Apps/It's/AgentValley", "install"), #"'/Apps/It'\''s/AgentValley' crew install"#)
    }

    func testAnswersStatusLine() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(Format.answersStatus(.off, now: now))
        // Where it listens: for the plugin, and on this Mac. "Listening." alone left that open.
        XCTAssertEqual(Format.answersStatus(.listening(lastRequest: nil), now: now), "Listening for the plugin, on this Mac only. Nothing has arrived yet. Only sessions that you start after installing the plugin send their prompts here.")
        XCTAssertEqual(Format.answersStatus(.listening(lastRequest: now.addingTimeInterval(-130)), now: now), "Listening. Last request 2m ago.")
        XCTAssertEqual(Format.answersStatus(.listening(lastRequest: now.addingTimeInterval(-20)), now: now), "Listening. Last request just now.")
        XCTAssertEqual(Format.answersStatus(.failed("its folder is open to other accounts"), now: now), "Could not listen: its folder is open to other accounts. Switch it off and on to try again.")
    }

    // How long it has waited is on the red badge beside the words, not in them.
    func testNeedsYouLabelLeavesTheTimeToItsBadge() {
        XCTAssertEqual(Format.statusLabel(.needsYou, isMain: false, quietFor: 20), "needs you")
        XCTAssertEqual(Format.statusLabel(.needsYou, isMain: true, quietFor: 200), "needs you")
    }

    // A tester asked how long each agent had waited, to answer the oldest first. The badge
    // counts from the first second, as a working row's clock does.
    func testTheWaitBadgeCountsFromTheFirstSecond() {
        func row(_ status: AgentStatus, waited: TimeInterval) -> AgentRow {
            AgentRow(id: "r", info: AgentInfo(), status: status, elapsed: 0, quietFor: waited)
        }
        XCTAssertEqual(Format.waited(row(.needsYou, waited: 0)), "0s")
        XCTAssertEqual(Format.waited(row(.needsYou, waited: 41)), "41s")
        XCTAssertEqual(Format.waited(row(.needsYou, waited: 255)), "4m 15s")
        XCTAssertEqual(Format.waited(row(.needsYou, waited: 3900)), "1h 05m")
        XCTAssertNil(Format.waited(row(.quiet, waited: 255)))
        XCTAssertNil(Format.waited(row(.working, waited: 255)))
        XCTAssertNil(Format.waited(nil))
    }

    // The island's alert says whose work waits and on what, in one line.
    func testTheAlertNamesTheWorkAndItsStep() {
        XCTAssertEqual(Format.alertLine(name: "Deploy preview build", step: "Bash git push origin preview"),
                       "Deploy preview build · Bash git push origin preview")
        XCTAssertEqual(Format.alertLine(name: "Fix login", step: ""), "Fix login")
    }

    // Read out in words: "4m" is read as four metres.
    func testTheWaitIsReadOutInWords() {
        XCTAssertEqual(Format.waitedAloud(1), "waiting 1 second")
        XCTAssertEqual(Format.waitedAloud(41), "waiting 41 seconds")
        XCTAssertEqual(Format.waitedAloud(60), "waiting 1 minute")
        XCTAssertEqual(Format.waitedAloud(255), "waiting 4 minutes")
        XCTAssertEqual(Format.waitedAloud(3600), "waiting 1 hour")
        XCTAssertEqual(Format.waitedAloud(3900), "waiting 1 hour 5 minutes")
        XCTAssertEqual(Format.waitedAloud(7260), "waiting 2 hours 1 minute")
    }

    // The bar: whole minutes only, from the first, so nothing at the top of the screen ticks
    // every second.
    func testTheBarSaysTheLongestWaitInWholeMinutes() {
        XCTAssertNil(Format.barWait(nil))
        XCTAssertNil(Format.barWait(59))
        XCTAssertEqual(Format.barWait(60), "1m")
        XCTAssertEqual(Format.barWait(12 * 60 + 59), "12m")
        XCTAssertEqual(Format.barWait(59 * 60 + 59), "59m")
        XCTAssertEqual(Format.barWait(3600 + 1800), "1h")
        XCTAssertEqual(Format.barWait(10 * 3600), "10h")
    }

    // "quiet" alone does not say whether it has been two minutes or forty.
    func testQuietLabelSaysForHowLong() {
        XCTAssertEqual(Format.statusLabel(.quiet, isMain: false, quietFor: 130), "quiet 2m")
        XCTAssertEqual(Format.statusLabel(.quiet, isMain: true, quietFor: 12 * 60 + 40), "quiet 12m")
        XCTAssertEqual(Format.statusLabel(.quiet, isMain: false, quietFor: 3700), "quiet 1h 01m")
        XCTAssertEqual(Format.statusLabel(.done, isMain: false, quietFor: 3700), "done")
    }

    // A request used to vanish on a click, the same as when the terminal won.
    func testASettledRequestSaysHowItEnded() {
        XCTAssertEqual(Format.settled(.answered(.allow)), "Allowed once")
        XCTAssertEqual(Format.settled(.answered(.deny)), "Denied")
        // The option's label is the request's text: beside the app's word, never inside it.
        XCTAssertEqual(Format.settled(.answered(.option("Red"))), "Answered")
        XCTAssertEqual(Format.settledDetail(.answered(.option("Red")), tool: "AskUserQuestion"), "Red")
        // A skipped question says so in the app's word alone: the tool's name adds nothing.
        // And that Claude Code heard of it: Hide, beside it, tells Claude Code nothing.
        XCTAssertEqual(Format.settled(.answered(.skip)), "Skipped. Claude Code was told.")
        XCTAssertNil(Format.settledDetail(.answered(.skip), tool: "AskUserQuestion"))
        // What was allowed or denied: the tool's name, the request's own word, beside the app's.
        XCTAssertEqual(Format.settledDetail(.answered(.allow), tool: "Bash"), "Bash")
        XCTAssertEqual(Format.settledDetail(.answered(.deny), tool: "Edit"), "Edit")
        XCTAssertEqual(Format.settledDetail(.notTaken, tool: "Bash"), "Bash")
        XCTAssertNil(Format.settledDetail(.inTerminal, tool: ""))
        // A click that did not count says why.
        XCTAssertEqual(Format.notCounted(cut: false), "Too soon. Click again.")
        XCTAssertEqual(Format.notCounted(cut: true), "Not all in view. Click again.")
        // After a key, in a key's words.
        XCTAssertEqual(Format.notCounted(cut: false, key: true), "Too soon. Press again.")
        XCTAssertEqual(Format.notCounted(cut: true, key: true), "Not all in view. Press again.")
        // Each fits the room beside the two buttons with their chords on them, some thirty
        // columns: the longer words they had ended in "agai…" on the one card that showed them.
        for cut in [false, true] {
            for key in [false, true] { XCTAssertLessThanOrEqual(Format.notCounted(cut: cut, key: key).count, 29) }
        }
        // The chord that answers, drawn on the button it fires.
        XCTAssertEqual(Format.chord(.allow), "⌘↩")
        XCTAssertEqual(Format.chord(.deny), "⌘⌫")
        XCTAssertEqual(Format.chord(.option(2)), "⌘2")
        XCTAssertNil(Format.chord(.go))
        XCTAssertEqual(Format.settled(.inTerminal), "Answered in the terminal")
        XCTAssertEqual(Format.settled(.notTaken), "Not delivered. Answer in the terminal.")
        XCTAssertEqual(Format.goTo(app: "Superset"), "Go to Superset")
    }

    func testHiddenRowAndIdleRowNameSessionsByTitle() {
        XCTAssertEqual(Format.hidden(1), "1 hidden")
        XCTAssertEqual(Format.hidden(3), "3 hidden")
        func card(_ project: String, title: String = "") -> SessionCard {
            SessionCard(id: project, project: project, branch: "", main: nil, agents: [], startedAt: Date(timeIntervalSince1970: 0), title: title)
        }
        // Two sessions in one folder are told apart by title, in the fold as on the cards.
        XCTAssertEqual(Format.names([card("web-app", title: "Fix rounding"), card("web-app", title: "Add receipts"), card("api")]), "Fix rounding · Add receipts · api")
    }

    // A working session says how long this turn has run, where a sub-agent says how long it has.
    func testAWorkingCardSaysHowLongTheTurnHasRun() {
        func card(_ status: AgentStatus, elapsed: TimeInterval) -> SessionCard {
            SessionCard(id: "s", project: "p", branch: "", main: AgentRow(id: "m", info: AgentInfo(), status: status, elapsed: elapsed), agents: [], startedAt: Date(timeIntervalSince1970: 0))
        }
        XCTAssertEqual(Format.cardStatus(card(.working, elapsed: 192)), "3m 12s")
        XCTAssertNil(Format.cardStatus(card(.working, elapsed: 0)))
        XCTAssertEqual(Format.cardStatus(card(.done, elapsed: 192)), "idle")
    }

    // What a row can do without: its type. It stands at the end of the second line and is the
    // first to go, so the step is the last thing cut. The tokens a sub-agent held stood there too
    // until 2026-10-15: they decided nothing, and the History page says what was used.
    func testARowsExtraIsItsType() {
        XCTAssertEqual(Format.rowExtras(task: "Find auth files", type: "Explore"), "Explore")
        XCTAssertEqual(Format.rowExtras(task: "Fix the pay button", type: "general-purpose"), "")
        XCTAssertEqual(Format.rowExtras(task: "Review the diff", type: "acme:code-reviewer"), "code-reviewer")
        // The type already led as the title.
        XCTAssertEqual(Format.rowExtras(task: "", type: "Explore"), "")
        XCTAssertEqual(Format.extrasHelp, "The agent's type")
    }

    // A button with a picture on it says what a click will do, whichever way it is set.
    func testPinAndGearSayWhatAClickWillDo() {
        XCTAssertEqual(Format.pinHelp(pinned: false), "Keep the panel open")
        XCTAssertEqual(Format.pinHelp(pinned: true), "Let the panel close again")
        XCTAssertEqual(Format.gearHelp(showingSettings: false), "Settings")
        XCTAssertEqual(Format.gearHelp(showingSettings: true), "Back to agents")
        // The green dot on the gear, in words: under the pointer and to a screen reader.
        XCTAssertEqual(Format.gearHelp(showingSettings: false, update: "0.3.4"), "Settings · Version 0.3.4 came in.")
        XCTAssertEqual(Format.gearHelp(showingSettings: true, update: "0.3.4"), "Back to agents")
        XCTAssertEqual(Format.historyHelp(showing: false), "History")
        XCTAssertEqual(Format.historyHelp(showing: true), "Back to agents")
    }

    func testTheSpeakerSaysWhatAClickWillDo() {
        XCTAssertEqual(Format.soundHelp(on: false, quietUntil: nil), "Turn sounds on")
        XCTAssertEqual(Format.soundHelp(on: true, quietUntil: nil), "Turn sounds off")
        XCTAssertEqual(Format.soundHelp(on: true, quietUntil: 8), "Quiet hours until 08:00")
        // Off is off, whatever the hour.
        XCTAssertEqual(Format.soundHelp(on: false, quietUntil: 8), "Turn sounds on")
        XCTAssertEqual(Format.soundSymbol(on: false, quiet: true), "speaker.slash")
        XCTAssertEqual(Format.soundSymbol(on: true, quiet: false), "speaker.wave.2")
        XCTAssertEqual(Format.soundSymbol(on: true, quiet: true), "speaker.zzz")
    }

    func testHoursReadOnATwentyFourHourClock() {
        XCTAssertEqual(Format.hour(0), "00:00")
        XCTAssertEqual(Format.hour(8), "08:00")
        XCTAssertEqual(Format.hour(22), "22:00")
        XCTAssertEqual(Format.finishedCaption, "Only when the session had been working for 30 seconds or more.")
    }

    // A symbol's name the system does not know draws nothing, and says nothing.
    func testTheSpeakerAndStepperSymbolsExist() {
        for name in ["speaker.slash", "speaker.wave.2", "speaker.zzz", "minus", "plus"] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    // The switch says which apps are told what to do, that macOS will ask, and where to undo it.
    func testTheTabSwitchSaysWhatItAsksOfWhom() {
        XCTAssertEqual(Format.tabCaption, "Asks Terminal, iTerm2 or Ghostty to show the session's own tab. macOS asks you to allow this once for each. To change your answer: System Settings > Privacy & Security > Automation.")
    }

    // Without this line in the bundle macOS refuses the request and asks the person nothing.
    func testTheAppBundleSaysWhyItTellsATerminalWhatToDo() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(text.contains("<key>NSAppleEventsUsageDescription</key>\n\t<string>Shows the tab of the session you clicked, in your terminal.</string>"))
    }

    // The app can be given leave to tell a terminal what to do. Signed with the hardened
    // runtime, no other code can be loaded into its process to borrow that leave.
    func testTheAppIsSignedSoThatItsLeaveCannotBeBorrowed() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(text.contains("SIGN=(codesign --force --options runtime --sign \"$SIGN_IDENTITY\")"))
        XCTAssertTrue(text.contains("\"${SIGN[@]}\" --entitlements \"$ENTITLEMENTS\" \"$APP\""))
        XCTAssertTrue(text.contains("<key>com.apple.security.automation.apple-events</key>\n\t<true/>"))
        XCTAssertFalse(text.contains("codesign --force --sign -"))
    }

    // A card is drawn again every second: its app's icon is asked of the system once.
    func testAnAppsIconIsAskedForOnce() {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        XCTAssertTrue(AppIcons.icon(of: finder) === AppIcons.icon(of: finder))
    }

    // The line under the notch counts agents. A group's line counts sessions, and says so.
    func testAGroupsLineCountsSessionsInWords() {
        XCTAssertEqual(Format.groupHeader(GroupHeader(group: .needsYou, count: 2)), "Needs you · 2 sessions")
        XCTAssertEqual(Format.groupHeader(GroupHeader(group: .working, count: 1)), "Working · 1 session")
        XCTAssertEqual(Format.groupHeader(GroupHeader(group: .quiet, count: 3)), "Quiet · 3 sessions")
        XCTAssertEqual(Format.groupHeader(GroupHeader(group: .idle, count: 1)), "Idle · 1 session")
    }

    // "3 working" under the notch over "Working · 1 session" in the list: nine of thirteen
    // testers read the two as disagreeing. Where a session holds more than one such agent the
    // line gives both numbers, each with its word.
    func testAGroupsLineAlsoCountsAgentsWhereTheyOutnumberSessions() {
        XCTAssertEqual(Format.groupHeader(GroupHeader(group: .working, count: 1, agents: 3)), "Working · 1 session, 3 agents")
        XCTAssertEqual(Format.groupHeader(GroupHeader(group: .needsYou, count: 2, agents: 3)), "Needs you · 2 sessions, 3 agents")
        // One agent to a session: the one number says it.
        XCTAssertEqual(Format.groupHeader(GroupHeader(group: .quiet, count: 2, agents: 2)), "Quiet · 2 sessions")
        XCTAssertEqual(Format.groupHeader(GroupHeader(group: .idle, count: 2, agents: 0)), "Idle · 2 sessions")
        XCTAssertEqual(Format.countsHelp, "These count agents, sub-agents too. One session can run several.")
    }

    // A project's line names it and counts its sessions. With them in more than one folder it
    // counts the folders, and the sessions as well when some share one.
    func testAProjectsLineNamesItAndCountsItsFolders() {
        XCTAssertEqual(Format.projectHeader(ProjectHeader(project: "api", worktrees: 1, sessions: 1)), "api · 1 session")
        XCTAssertEqual(Format.projectHeader(ProjectHeader(project: "docs", worktrees: 1, sessions: 2)), "docs · 2 sessions")
        XCTAssertEqual(Format.projectHeader(ProjectHeader(project: "shop-web", worktrees: 2, sessions: 2)), "shop-web · 2 worktrees")
        XCTAssertEqual(Format.projectHeader(ProjectHeader(project: "web", worktrees: 2, sessions: 3)), "web · 2 worktrees, 3 sessions")
    }

    // Under its project's line a card does not name the folder again when it is the project's
    // own; a worktree's folder still says which one it is.
    func testUnderItsProjectACardNamesOnlyAFolderOfItsOwn() {
        func card(_ folder: String) -> SessionCard {
            SessionCard(id: folder, project: folder, branch: "", main: nil, agents: [], startedAt: Date(), title: "Fix the coupon field")
        }
        XCTAssertTrue(Format.namesFolder(card("fix-coupons"), under: "shop-web"))
        XCTAssertFalse(Format.namesFolder(card("shop-web"), under: "shop-web"))
        XCTAssertTrue(Format.namesFolder(card("shop-web"), under: nil))
        // A card without a title is called by its folder already.
        XCTAssertFalse(Format.namesFolder(SessionCard(id: "x", project: "fix-coupons", branch: "", main: nil, agents: [], startedAt: Date()), under: "shop-web"))
    }

    func testTheTabsSayWhatTheyDo() {
        XCTAssertEqual(Format.groupingHelp(.projects), "All sessions, grouped by project")
        XCTAssertEqual(Format.groupingHelp(.status), "Sessions grouped by status")
    }

    // The tabs stand in the room the open panel has to the left of the bar. Past it they
    // would run under the mascot, and then under the notch. Measured for a notch of 220
    // points: about what a 14-inch MacBook's is at its smallest text, "More Space".
    @MainActor func testTheTabsFitBesideTheNotch() {
        let room = (NotchGeometry.expandedWidth - 220 - NotchGeometry.wing * 2) / 2 - 8
        let tabs = NSHostingView(rootView: GroupingTabs(selection: .constant(.status)))
        XCTAssertGreaterThan(tabs.fittingSize.width, 40)
        XCTAssertLessThanOrEqual(tabs.fittingSize.width, room)
        XCTAssertLessThanOrEqual(tabs.fittingSize.height, 26)
    }

    // The red count stands beside the mascot on one wing of the bar, and what runs past the wing
    // is under the notch, where nothing shows. Five points of margin, the mascot's eighteen and
    // a gap of three leave it eighteen, also for a count of two digits.
    @MainActor func testTheRedCountFitsBesideTheMascot() {
        let room = NotchGeometry.wing - 5 - 18 - 3
        for count in [1, 9, 10, 99] {
            let badge = NSHostingView(rootView: BarBadge(count: count).font(.system(size: 12, design: .monospaced)))
            XCTAssertGreaterThanOrEqual(badge.fittingSize.width, 16, "\(count)")
            XCTAssertLessThanOrEqual(badge.fittingSize.width, room - 1, "\(count)")
            XCTAssertEqual(badge.fittingSize.height, 16, "\(count)")
        }
    }

    func testSettingsSayWhichAppThisIsAndHowToTakeThePluginOut() {
        XCTAssertEqual(Format.about(name: "AgentValley", version: "0.1.0"), "AgentValley 0.1.0")
        XCTAssertEqual(Format.about(name: "AgentValley", version: nil), "AgentValley")
        XCTAssertEqual(Format.about(name: nil, version: "0.1.0"), "AgentValley 0.1.0")
        XCTAssertEqual(Format.uninstallCommand, "claude plugin uninstall notch-answers@agent-valley && claude plugin marketplace remove agent-valley")
    }

    // Report a bug fills in the form's fields by their ids; a build without a version leaves that one to the person.
    func testReportABugOpensTheFormFilledIn() {
        let os = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)
        XCTAssertEqual(Format.bugReport(version: "0.1.3", macOS: os, mac: "Mac15,6").absoluteString,
                       "https://github.com/morsechimwai/agent-valley/issues/new?template=bug_report.yml&version=0.1.3&macos=macOS%2026.0.1,%20Mac15,6")
        XCTAssertEqual(Format.bugReport(version: nil, macOS: os, mac: "Mac15,6").absoluteString,
                       "https://github.com/morsechimwai/agent-valley/issues/new?template=bug_report.yml&macos=macOS%2026.0.1,%20Mac15,6")
    }

    // The report also says how the built-in display's top edge is cut, so a Mac with an island
    // instead of a notch tells us its numbers. What AppKit does not give is left out.
    func testReportABugDescribesTheTopOfTheScreen() {
        XCTAssertEqual(Format.screenReport(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), inset: 32, gap: 185,
                                           cutout: CGRect(x: 663.5, y: 950, width: 185, height: 32), safeAperture: false),
                       "screen 1512x982 at 0,0 inset 32 gap 185 cutout 663.5,950 185x32 aperture no")
        XCTAssertEqual(Format.screenReport(frame: CGRect(x: -1728, y: 120, width: 1728, height: 1117), inset: 0, gap: nil, cutout: nil, safeAperture: nil),
                       "screen 1728x1117 at -1728,120 inset 0")
    }

    // A session can wait on a question it wrote down, or on a prompt in its terminal that leaves
    // no trace. Only the first has words to show; the second says where to look, and its last
    // step is not dressed up as the question.
    func testAWaitingRowSaysWhatItWaitsFor() {
        func row(_ status: AgentStatus, asking: Bool) -> AgentRow {
            var info = AgentInfo()
            info.asking = asking
            info.lastStep = "Read flow.ts"
            return AgentRow(id: "r", info: info, status: status, elapsed: 0)
        }
        XCTAssertTrue(row(.needsYou, asking: true).asksInWords)
        XCTAssertFalse(row(.needsYou, asking: false).asksInWords)
        XCTAssertFalse(row(.working, asking: true).asksInWords)
    }

    // A card that waits on the person says where to answer once: the button to its app when the
    // app is known, words when it is not. "Waiting for you in its terminal." stood above the
    // button until 2026-10-15, beside "needs you" in red: three ways of saying one thing.
    // Past eight sub-agents in the list each takes one line, so that the other sessions stay in
    // sight. There was a switch to have that sooner until 2026-10-15; the panel does it alone now.
    func testRowsTakeOneLinePastEightSubAgents() {
        XCTAssertFalse(Format.oneLineRows(liveAgents: 0))
        XCTAssertFalse(Format.oneLineRows(liveAgents: 8))
        XCTAssertTrue(Format.oneLineRows(liveAgents: 9))
    }

    func testAWaitSaysWhereToAnswerOnce() {
        XCTAssertNil(WayToAnswer.words(appKnown: true))
        XCTAssertEqual(WayToAnswer.words(appKnown: false), "Answer in the terminal.")
        // Until the plugin is in, the card also points to where it goes in.
        XCTAssertEqual(Format.answerHereNextTime, "Answer here next time")
    }

    // What the line under a card's name says when the pointer rests on it: where the session runs.
    func testACardsPlaceIsItsFolderItsBranchAndWhetherThatIsAWorktree() {
        func card(branch: String) -> SessionCard {
            SessionCard(id: "s", project: "web-app", branch: branch, main: nil, agents: [], startedAt: Date(timeIntervalSince1970: 0), title: "Fix checkout rounding")
        }
        XCTAssertEqual(Format.place(card(branch: "main")), "web-app main")
        XCTAssertEqual(Format.place(card(branch: "")), "web-app")
        // The mark for a worktree is a picture: resting the pointer on the line says it in a word.
        var apart = card(branch: "feat/dashboard")
        apart.worktree = true
        XCTAssertEqual(Format.place(apart), "web-app feat/dashboard (worktree)")
    }

    // Nine of thirteen testers stopped at the bare command. Before it now stands what the plugin
    // does, a button that runs it when pressed, and the one step left after.
    func testTheInstallCommandComesWithWhatItDoesAndWhatToDo() {
        XCTAssertEqual(Format.pluginWhat, "The plugin is inside this app, and installing it points Claude Code at it. It adds hooks to Claude Code: each permission prompt and question is handed to this app, each new session and sub-agent learns which of us it is, and while you're Away with your phone paired, a finished turn waits here for your next message. All on this Mac only. With the app closed or this switch off, Claude Code asks in the terminal and ends its turns as before.")
        // Crew names ride on the same socket, and only a new session hears them.
        XCTAssertEqual(Format.crewNamesCaption, "Your sessions hand work to Judy, Faye and Felix by name and get it back the same way. Needs Answer from the notch. Starts with the next session you open.")
        // The tags say what copying does to them, and that a terminal opened before the font shows none.
        XCTAssertEqual(Format.nameTagsCaption, "Claude writes our names as small tags with our faces. Copied out of the terminal, each tag turns into three boxes. Needs Crew in the terminal. Starts with the next terminal you open.")
        XCTAssertEqual(Format.installButton, "Install the plugin")
        XCTAssertEqual(Format.installSteps.run, "Install runs this command for you. Or copy it and run it in a terminal yourself: the Terminal app, or wherever you start Claude Code.")
        XCTAssertEqual(Format.installSteps.restart, "Then start Claude Code again. Sessions that were already open do not have the plugin.")
        XCTAssertEqual(Format.installResult(.installed), "Installed, and the switch is on.")
        XCTAssertEqual(Format.installResult(.noClaude), "Couldn't find Claude Code's claude command. Copy the command and run it in a terminal.")
        XCTAssertEqual(Format.installResult(.failed("it took over a minute")), "Couldn't install: it took over a minute. Copy the command and run it in a terminal.")
        XCTAssertEqual(Format.marketplaceNote, "In the command, \u{201C}marketplace\u{201D} is Claude Code's word for a list of plugins. Nothing is bought.")
        // Until the plugin is in, the caption says it is needed, and where it goes in.
        XCTAssertTrue(Format.answersCaption(installed: false).hasSuffix(" Needs a plugin that comes with this app: install it below."))
        XCTAssertFalse(Format.answersCaption(installed: true).contains("Needs a plugin"))
        // The way out reads as a way out, not as word that a plugin is already in.
        XCTAssertEqual(Format.removePlugin, "How to remove the plugin")
    }

    // The row for the crew in the terminal says what it does, the two steps, and the way out.
    func testTheCrewInTheTerminalSaysWhatItDoesAndHowToTakeItOut() {
        XCTAssertEqual(Format.crewTitle, "Crew in the terminal")
        XCTAssertEqual(Format.crewWhat, "We show up in Claude Code's terminal too. The status line under the prompt gets this session's face, model, plan and limits, and each sub-agent row gets its face, model and current step. Works with this app closed.")
        XCTAssertEqual(Format.crewSetup, "How to set it up")
        XCTAssertEqual(Format.crewSteps.run, "1. Copy this and run it in a terminal. It installs our font and sets statusLine and subagentStatusLine in Claude Code's settings.json. Anything it replaces is kept, and comes back when you take it out.")
        XCTAssertEqual(Format.crewSteps.restart, "2. Start Claude Code again. If you use Ghostty, quit and reopen it first.")
        XCTAssertEqual(Format.removeCrew, "How to take it out")
        XCTAssertEqual(Format.removeCrewNote, "Puts back the status line you had before, and removes our font and the line added to Ghostty's config.")
    }

    // What that sentence says of the plugin is what the plugin's own files do.
    func testWhatIsSaidOfThePluginIsWhatItDoes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("plugin/notch-answers")
        let hooks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("hooks/hooks.json"))) as? [String: Any])
        // Permission requests, Stop, and the two starts that ask for names, each with its one script.
        let events = try XCTUnwrap(hooks["hooks"] as? [String: Any])
        XCTAssertEqual(Set(events.keys), ["PermissionRequest", "Stop", "SessionStart", "SubagentStart"])
        for name in ["ask.sh", "stop.sh", "intro.sh"] {
            let script = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            // To this app's own socket on this Mac, and to no address on a network.
            if name == "stop.sh" {
                XCTAssertTrue(script.contains(#"DIR="$HOME/Library/Application Support/AgentValley""#), name)
                XCTAssertTrue(script.contains(#"SOCK="$DIR/answers.sock""#), name)
                // "while you're Away": with no flag from the app, the turn ends as before.
                XCTAssertTrue(script.contains(#"[ -e "$DIR/away" ] || exit 0"#), name)
            } else {
                XCTAssertTrue(script.contains(#"SOCK="$HOME/Library/Application Support/AgentValley/answers.sock""#), name)
            }
            XCTAssertTrue(script.contains(#"--unix-socket "$SOCK""#), name)
            XCTAssertEqual(script.components(separatedBy: "http").count - 1, 1, "\(name): one address, the one spoken over the socket")
            // With no socket there, as when the app is closed or the switch is off, it says nothing.
            XCTAssertTrue(script.contains(#"[ -S "$SOCK" ] || exit 0"#), name)
        }
    }

    // Six of thirteen testers had to guess at the app's own words, and one for whom English is
    // a second language listed which: an idiom, a phrasal verb, a "once" that could mean one
    // time, an "It" with nothing to point at. Each is said plainly here. What the words mean
    // has not changed, and the terms that are Claude Code's own are left as they are.
    func testTheAppsOwnWordsArePlainOnes() {
        // "marks" was taken for scores.
        XCTAssertEqual(Format.legendTitle, "What the symbols mean")
        XCTAssertEqual(Format.legendHelp(showing: false), "What the symbols mean")
        XCTAssertEqual(Format.legendHelp(showing: true), "Hide what the symbols mean")
        // "turn": how long it has worked, since when. Cut to what a reader needs on 2026-10-15.
        XCTAssertEqual(Format.timeCaption, "The time on a row is how long it has worked on its last task, or how long it has been quiet or waiting.")
        XCTAssertEqual(Format.timeHelp, "How long it has been working since it was last given something to do, or how long it has been quiet or waiting")
        // "Used anyway once more than eight are listed."
        // "It allows only what it can show in full": who allows, and how much is in full.
        XCTAssertEqual(Format.answersCaption(installed: true), "Shows Claude Code's permission prompts and questions here, with buttons to answer. The terminal still asks too. You can allow a request here only when the panel can show all of it, such as a short command.")
        // "Put this away": a phrasal verb.
        XCTAssertEqual(Format.hideRequestHelp, "Removes this from the panel without answering it. It still waits in the terminal.")
        // "once the shortcut has opened the panel" read as "one time".
        XCTAssertEqual(Format.keysCaption, "Keys that work after the shortcut has opened the panel:")
        // "unfold", "this", and "deny, or skip" with no word on which of the two.
        let keys = Dictionary(uniqueKeysWithValues: Format.keys.map { ($0.key, $0.does) })
        XCTAssertEqual(keys["d"], "open or close the book")
        XCTAssertEqual(keys["i"], "expand idle sessions")
        XCTAssertEqual(keys["?"], "this list of keys")
        XCTAssertEqual(keys["⌘⌫"], "deny (skip a question)")
        XCTAssertEqual(keys["t"], "open History")
        // "most worth a look", "else", "at work", "with none waiting", "yellow from", "waits on you".
        // One sentence each since 2026-10-15: the order of the mascot's choice and when each
        // colour takes over were more than a reader needs.
        XCTAssertEqual(Format.barMascotCaption, "The mascot on the bar is the agent to look at first.")
        XCTAssertEqual(Format.legendCaption, "The person shows the kind of agent, its pose how it is doing, and what it holds the tool it is using.")
        XCTAssertEqual(Format.waitCaption, "After a minute of waiting, the longest wait shows in red in the ring's place.")
        XCTAssertEqual(Format.ringCaption, "The ring is how much of your 5-hour limit is used, yellow from 80%. Only with Plan limits on.")
        XCTAssertEqual(Format.beatCaption, "While one waits for you, the bar glows red every few seconds until you open the panel.")
        // A label that was half a sentence, and "your login", which could have been a password.
        XCTAssertEqual(Format.keepTitle, "Keep idle and done listed for")
        XCTAssertEqual(Format.limitsCaption, "Reads the access token of your Claude Code login from Keychain, and sends it to api.anthropic.com to ask for your usage. It is never stored and never sent anywhere else.")
    }

    // The ring the arrow keys move was a picture and nothing else. A tester on a screen reader
    // allowed a command by its key without knowing which session it was for. The ring's arrival
    // is read out, and the ring says what it is: the session's name, then how it is doing.
    func testTheSessionTheKeysAreOnIsSaid() {
        var card = SessionCard(id: "/r/p/s1", project: "api", branch: "main",
                               main: AgentRow(id: "/r/p/s1.jsonl", info: AgentInfo(), status: .needsYou, elapsed: 0, quietFor: 250),
                               agents: [], startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(Format.chosen(card), "api, needs you, waiting 4 minutes")
        card.title = "Fix flaky login test"
        XCTAssertEqual(Format.chosen(card), "Fix flaky login test, needs you, waiting 4 minutes")
        XCTAssertEqual(Format.chosenLabel, "The arrow keys are on this session")
    }

    // "Nothing written for a while" did not say how long: seconds or minutes. The legend gave
    // both numbers the panel goes by until 2026-10-15; "a few minutes" answers the question
    // without the rule behind it. The numbers themselves are the rules', tested here.
    func testTheLegendSaysHowLongQuietIs() {
        XCTAssertEqual(Format.quietCaption, "Quiet: nothing written for a few minutes. It may be waiting for you in its terminal, or stuck.")
        let info = AgentInfo()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // No word from Claude Code: quiet at two minutes.
        XCTAssertEqual(TranscriptReader.status(of: info, lastActivity: now.addingTimeInterval(-119), now: now), .working)
        XCTAssertEqual(TranscriptReader.status(of: info, lastActivity: now.addingTimeInterval(-120), now: now), .quiet)
        // Called busy: at work until ten minutes of silence, then shown as quiet.
        func shown(silentFor: TimeInterval) -> AgentStatus? {
            let row = AgentRow(id: "/r/p/s1.jsonl", info: info, status: TranscriptReader.status(of: info, lastActivity: now.addingTimeInterval(-silentFor), now: now, session: .busy),
                               elapsed: 0, quietFor: silentFor)
            return SessionCard(id: "/r/p/s1", project: "p", branch: "", main: row, agents: [], startedAt: now).asShown.main?.status
        }
        XCTAssertEqual(shown(silentFor: 599), .working)
        XCTAssertEqual(shown(silentFor: 600), .quiet)
    }

    // A release checks for updates from the start, with no switch turned on first: the promise
    // says so there, and only there.
    func testReadOnlyMentionsUpdatesOnlyWhenOn() {
        let old = "Reads Claude Code's files, and which Superset workspace a session is in. Never writes to them: Install the plugin runs Claude Code's own command, only when you press it. Answering requests stays off until the plugin is in; checking plan limits online and showing a session's tab, until you turn on their switch. Each switch says what it does."
        XCTAssertEqual(Format.readOnly(updates: false), old)
        XCTAssertEqual(Format.readOnly(updates: true), old + " It asks GitHub once an hour if there's a new version, and sends us one anonymous count a day; both switches start on.")
    }

    func testUpdateLines() {
        XCTAssertEqual(Format.updatesTitle, "Check for updates")
        XCTAssertEqual(Format.updatesCaption, "Once an hour we look on GitHub. Nothing gets installed until you say so.")
        XCTAssertEqual(Format.checkNow, "Check now")
        XCTAssertEqual(Format.updateWaiting(version: "0.2.1"), "Version 0.2.1 came in.")
        XCTAssertEqual(Format.updateLook, "Have a look")
    }

    // "Changes nothing." stood under a switch that answers Claude Code's prompts and another
    // that reads the Keychain and goes online: six of thirteen testers caught it, one nearly
    // left over it. The promise now holds with every switch on, and names what is behind one.
    func testThePromiseHoldsWithEverySwitchOn() {
        XCTAssertEqual(Format.readOnly(updates: false), "Reads Claude Code's files, and which Superset workspace a session is in. Never writes to them: Install the plugin runs Claude Code's own command, only when you press it. Answering requests stays off until the plugin is in; checking plan limits online and showing a session's tab, until you turn on their switch. Each switch says what it does.")
        XCTAssertFalse(Format.readOnly(updates: false).contains("Changes nothing"))
        // Each of those switches does say what it adds.
        XCTAssertTrue(Format.answersCaption(installed: false).contains("buttons to answer"))
        XCTAssertTrue(Format.tabCaption.hasPrefix("Asks Terminal, iTerm2 or Ghostty to show the session's own tab."))
    }

    func testAnAnswerButtonSaysItTakesAClick() {
        XCTAssertEqual(Format.answerHint(.option("Red")), "By a click, or by its key after the shortcut has opened the panel.")
    }

    // Seven of thirteen testers could not tell what a press would send: Skip tells Claude Code
    // the question was refused, and the button said one word. Said to the pointer and read out.
    func testAnAnswerButtonSaysWhatClaudeCodeIsTold() {
        XCTAssertEqual(Format.answerHelp(.allow), "Lets Claude Code do this, this one time.")
        XCTAssertEqual(Format.answerHelp(.deny), "Refuses this. Claude Code is told it was denied from the notch.")
        XCTAssertEqual(Format.answerHelp(.skip), "Leaves the question unanswered. Claude Code is told you chose not to answer.")
        // An option's row says what it answers in the request's own words.
        XCTAssertNil(Format.answerHelp(.option("Red")))
        XCTAssertEqual(Format.answerHint(.skip), "Leaves the question unanswered. Claude Code is told you chose not to answer. By a click, or by its key after the shortcut has opened the panel.")
    }

    func testTheShortcutAndItsKeysAreSpelledOut() {
        // A space between the keys: set tight in the panel's type they ran into one mark.
        XCTAssertEqual(Format.shortcut(.a), "⌃ ⌥ ⌘ A")
        // Another app can hold a chord already, so there is more than one to pick from.
        XCTAssertEqual(ShortcutKey.allCases.map(Format.shortcut), ["⌃ ⌥ ⌘ A", "⌃ ⌥ ⌘ N", "⌃ ⌥ ⌘ K"])
        XCTAssertEqual(ShortcutKey.allCases.map(\.keyCode), [0, 45, 40])
        // Return is promised only where it leads somewhere: to the app of the chosen session.
        XCTAssertEqual(Format.keysHint(app: "Superset"), "↑ ↓ move · return goes to Superset · ? keys · esc closes")
        XCTAssertEqual(Format.keysHint(app: nil), "↑ ↓ move · ? keys · esc closes")
        // Under a quiet row: what is known of it, and no more.
        XCTAssertEqual(Format.quietHint(main: true, calledBusy: false), "No activity. It may be waiting for you in its terminal.")
        XCTAssertEqual(Format.quietHint(main: true, calledBusy: true), "Claude Code says it is busy, but nothing has been written. It may be stuck.")
        XCTAssertEqual(Format.quietHint(main: false, calledBusy: false), "No activity. It may be waiting, or stuck.")
    }

    func testStatusLabel() {
        XCTAssertNil(Format.statusLabel(.working, isMain: false))
        XCTAssertEqual(Format.statusLabel(.quiet, isMain: false), "quiet")
        XCTAssertEqual(Format.statusLabel(.done, isMain: false), "done")
        XCTAssertEqual(Format.statusLabel(.done, isMain: true), "idle")
    }

    // The band under a page that runs past the edge names Quit only on the page that has it.
    func testTheBandUnderTheSettingsNamesQuitOnlyWhereItIs() {
        XCTAssertEqual(Format.settingsBelow(.about), "More and Quit below")
        XCTAssertEqual(Format.settingsBelow(.general), "More settings below")
        XCTAssertEqual(Format.settingsBelow(.claudeCode), "More settings below")
    }

    func testExportWords() {
        XCTAssertEqual(Format.exportPDF, "Export PDF")
        XCTAssertEqual(Format.exportPDFHint, "Makes a PDF report of this period and opens it")
        XCTAssertEqual(Format.couldNotMakePDF("The disk is full."), "Couldn't make the PDF. The disk is full.")
    }

    // The sign on the bar says when the crew is back, in English on a 24-hour clock.
    func testTheFishingSignSaysWhenTheCrewIsBack() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let now = ISO8601DateFormatter().date(from: "2026-10-21T03:00:00Z")!  // Wednesday 10:00 in Bangkok
        func back(_ hours: Double) -> String { Format.backAt(now.addingTimeInterval(hours * 3600), now: now, calendar: calendar) }
        XCTAssertEqual(back(5), "Back at 15:00")
        // A reset a moment before the minute reads as that minute.
        XCTAssertEqual(back(5 - 0.3 / 3600), "Back at 15:00")
        XCTAssertEqual(back(23), "Back tomorrow at 09:00")
        XCTAssertEqual(back(71), "Back Saturday at 09:00")
        XCTAssertEqual(Format.backAt(nil, now: now, calendar: calendar), "Back soon")
        // The Mac's own calendar may count years otherwise: the default is the common era's.
        XCTAssertEqual(Format.backAt(now.addingTimeInterval(71 * 3600), now: now).hasPrefix("Back "), true)
        XCTAssertNotEqual(Format.fishingLine(weekly: false), Format.fishingLine(weekly: true))
    }

    // Everything a sign can say is in its pixel font: a letter it lacks would simply be missing.
    func testTheSignsFontHasEveryLetterTheySay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let now = ISO8601DateFormatter().date(from: "2026-10-21T03:00:00Z")!
        var said = [Format.fishingSign(weekly: false), Format.fishingSign(weekly: true), Format.backAt(nil, now: now, calendar: calendar)]
        for hours in stride(from: 0.0, through: 24 * 7, by: 1.25) {
            said.append(Format.backAt(now.addingTimeInterval(hours * 3600), now: now, calendar: calendar))
        }
        for words in said { XCTAssertTrue(PixelFont.covers(words), words) }
        XCTAssertNotEqual(Format.fishingSign(weekly: false), Format.fishingSign(weekly: true))
        // A pixel apart, letters line up: "AT" is a 5-wide A, a gap and a 5-wide T.
        XCTAssertEqual(PixelFont.cells("AT", bold: false).width, 11)
        XCTAssertEqual(PixelFont.cells("AT", bold: true).width, 13)
    }

    // The boards' pictures are where build-app.sh copies them from, twice the size they are drawn.
    func testTheSignsPicturesAreTwiceTheirSize() throws {
        let signs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("signs")
        for art in [SignArt.fishing, SignArt.vacation] {
            let picture = try XCTUnwrap(NSImage(contentsOf: signs.appendingPathComponent(art.file))?.representations.first, art.file)
            XCTAssertEqual(picture.pixelsWide, Int(art.size.width * 2), art.file)
            XCTAssertEqual(picture.pixelsHigh, Int(art.size.height * 2), art.file)
            XCTAssertLessThan(art.boardMiddle, art.size.height)
        }
    }

    // MARK: Background jobs

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func job(_ kind: BackgroundJob.Kind, _ name: String = "x", age: TimeInterval = 60, endsIn: TimeInterval? = nil) -> BackgroundJob {
        BackgroundJob(id: name, kind: kind, name: name, startedAt: now.addingTimeInterval(-age), endsBy: endsIn.map { now.addingTimeInterval($0) })
    }

    private func card(main: AgentStatus, agents: [AgentStatus] = []) -> SessionCard {
        func row(_ id: String, _ status: AgentStatus) -> AgentRow { AgentRow(id: id, info: AgentInfo(), status: status, elapsed: 0) }
        return SessionCard(id: "s", project: "p", branch: "", main: row("m", main),
                           agents: agents.enumerated().map { row("a\($0.offset)", $0.element) }, startedAt: Date(timeIntervalSince1970: 0))
    }

    func testJobCountsReadLikeClaudeCode() {
        XCTAssertEqual(Format.jobsRunning([job(.shell)]), "1 shell running")
        XCTAssertEqual(Format.jobsRunning([job(.shell), job(.shell)]), "2 shells running")
        XCTAssertEqual(Format.jobsRunning([job(.monitor)]), "1 monitor running")
        XCTAssertEqual(Format.jobsRunning([job(.monitor), job(.shell)]), "1 shell, 1 monitor running")
        XCTAssertEqual(Format.jobsRunning([job(.shell), job(.shell), job(.monitor), job(.monitor), job(.monitor)]), "2 shells, 3 monitors running")
        XCTAssertEqual(Format.jobsInBackground([job(.shell), job(.monitor)]), "1 shell, 1 monitor running in the background")
    }

    func testAJobLineSaysWhatItRuns() {
        XCTAssertEqual(Format.jobLine(job(.shell, "Run CadQuery benchmark")), "Run CadQuery benchmark")
        XCTAssertEqual(Format.jobLine(job(.monitor, "CadQuery benchmark completion")), "Watching for: CadQuery benchmark completion")
        XCTAssertEqual(Format.jobLine(job(.shell, "")), "Background command")
        XCTAssertEqual(Format.jobLine(job(.monitor, "")), "Monitor")
    }

    func testAJobTimeIsItsAgeOrWhenItEnds() {
        XCTAssertEqual(Format.jobTime(job(.shell, age: 720), now: now), "12m")
        XCTAssertEqual(Format.jobTime(job(.monitor, endsIn: 185), now: now), "ends in 3m 05s")
        XCTAssertEqual(Format.jobTime(job(.monitor, age: 90), now: now), "1m 30s")
        // A clock that stepped back never shows a negative time.
        XCTAssertEqual(Format.jobTime(job(.shell, age: -30), now: now), "0s")
        XCTAssertEqual(Format.jobTime(job(.monitor, endsIn: -5), now: now), "ends in 0s")
        XCTAssertEqual(Format.moreJobs(2), "+2 more")
    }

    func testOnlyIdleGivesWayToTheJobCount() {
        var idle = card(main: .done); idle.jobs = [job(.shell), job(.monitor)]
        XCTAssertEqual(Format.cardStatus(idle), "1 shell, 1 monitor running")
        var behind = card(main: .done, agents: [.working]); behind.jobs = [job(.shell)]
        XCTAssertEqual(Format.cardStatus(behind), "1 working")
        var waiting = card(main: .needsYou); waiting.jobs = [job(.shell)]
        XCTAssertEqual(Format.cardStatus(waiting), "needs you")
    }

    // A folded session shows the step of whichever row moved last and is not finished: while the
    // lead waits on its helpers its own step is only "> Agent ...", which names no file.
    func testASessionShowsTheStepOfItsLatestUnfinishedRow() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        func row(_ id: String, _ status: AgentStatus, _ step: String, _ at: Date?) -> AgentRow {
            var info = AgentInfo()
            info.lastStep = step
            info.openTools = [OpenTool(id: "t", tool: "Edit", input: [:])]
            info.lastActivity = at
            return AgentRow(id: id, info: info, status: status, elapsed: 0)
        }
        let card = SessionCard(id: "s", project: "shop", branch: "", main: row("m", .working, "Agent Write cart tests", t.addingTimeInterval(-30)),
                               agents: [row("a", .working, "Edit Cart.tsx", t.addingTimeInterval(-5)), row("b", .done, "Read x", t.addingTimeInterval(-1))],
                               startedAt: t)
        XCTAssertEqual(Format.sessionStep(card), "> Edit Cart.tsx")
    }

    func testASessionWithNoStepShowsNone() {
        let cardWithEmptySteps = SessionCard(id: "s", project: "shop", branch: "", main: AgentRow(id: "m", info: AgentInfo(), status: .working, elapsed: 0),
                                             agents: [], startedAt: Date())
        XCTAssertNil(Format.sessionStep(cardWithEmptySteps))
    }

    func testAHandBackIsSaidByWhoBroughtIt() {
        XCTAssertEqual(Format.handedBack(type: "Explore"), "Faye handed back")
        XCTAssertEqual(Format.handedBack(type: "general-purpose"), "Felix handed back")
        XCTAssertEqual(Format.handedBack(type: ""), "Felix handed back")
        XCTAssertEqual(Format.handedBack(type: "plan"), "Judy handed back")
        XCTAssertEqual(Format.handedBack(type: "review-kit:code-reviewer"), "code-reviewer handed back")
    }

    func testADoneLineIsTheTaskAndWhatCameBack() {
        var info = AgentInfo()
        info.task = "Map payment call sites"
        info.type = "Explore"
        info.handedBack = "## 14 call sites in 6 files.\n3 skip the retry wrapper."
        info.handedBackAt = Date()
        XCTAssertEqual(Format.doneLine(AgentRow(id: "a", info: info, status: .done, elapsed: 0)), "Map payment call sites → 14 call sites in 6 files.")
        XCTAssertEqual(Format.handBackAloud(AgentRow(id: "a", info: info, status: .done, elapsed: 0)), "Faye handed back: 14 call sites in 6 files.")
        // Handed in with no words.
        info.handedBack = ""
        XCTAssertEqual(Format.handBackText(info), "Handed back a result.")
        // Stopped with nothing back: the task alone.
        info.handedBackAt = nil
        XCTAssertEqual(Format.doneLine(AgentRow(id: "a", info: info, status: .done, elapsed: 0)), "Map payment call sites")
    }

    func testTheFirstLineSkipsBlanksAndMarks() {
        XCTAssertEqual(Format.firstLine("\n\n# Title\nrest"), "Title")
        XCTAssertEqual(Format.firstLine("- **a** b"), "**a** b")
        var info = AgentInfo()
        info.handedBack = "## 14 call sites in 6 files.\n\n- 3 skip the retry wrapper.\nmore"
        XCTAssertEqual(Format.handBackText(info), "14 call sites in 6 files.\n3 skip the retry wrapper.")
        XCTAssertEqual(Format.handBackLine(info), "14 call sites in 6 files.")
        info.handedBack = "Only one line."
        XCTAssertEqual(Format.handBackText(info), "Only one line.")
        XCTAssertEqual(Format.firstLine(String(repeating: "x", count: 50_000)).count, TranscriptReader.stepDetailLimit + 1)
    }

    func testHowLongAgoItCameBack() {
        XCTAssertEqual(Format.handedBackAge(30), "just now")
        XCTAssertEqual(Format.handedBackAge(240), "4m ago")
        XCTAssertEqual(Format.handedBackAge(7300), "2h ago")
    }

    // A document in the book is named like a Markdown file, after its task.
    func testADocumentIsNamedAfterItsTask() {
        XCTAssertEqual(Format.docName(task: "Review Task 4", type: "general-purpose"), "review-task-4.md")
        XCTAssertEqual(Format.docName(task: "Audit Mark.tsx", type: "general-purpose"), "audit-mark-tsx.md")
        XCTAssertEqual(Format.docName(task: "  Fix: the *bold* bug!! ", type: "general-purpose"), "fix-the-bold-bug.md")
        XCTAssertEqual(Format.docName(task: "", type: "Explore"), "explore.md")
        XCTAssertEqual(Format.docName(task: "", type: ""), "handed-back.md")
        XCTAssertEqual(Format.docName(task: "แก้บั๊ก Read all", type: "general-purpose"), "แก้บั๊ก-read-all.md")
        // Long tasks are cut on a word, never mid-word or on a dash.
        XCTAssertEqual(Format.docName(task: "Implement the frame that draws the whole look of the reel", type: "general-purpose"),
                       "implement-the-frame-that-draws.md")
        XCTAssertEqual(Format.docName(task: "https://example.com/averyveryverylongpathname/withmore", type: "general-purpose"),
                       "https-example-com.md")
        XCTAssertEqual(Format.docName(task: "Supercalifragilisticexpialidociousandthensome", type: "general-purpose"),
                       "supercalifragilisticexpialidoc.md")
        XCTAssertEqual(Format.newDocs(1), "1 new")
    }

    // What came back reads as the Markdown it mostly is, but never as a link.
    // Every character stays, so what was written reads and copies whole: the marks go faint,
    // they never go. A glob, a dunder name or a regex is not mistaken for emphasis.
    func testMarkdownKeepsEveryCharacterAndFadesItsMarks() {
        func plain(_ s: AttributedString) -> String { String(s.characters) }
        func runs(_ s: AttributedString, _ text: String) -> [AttributedString.Runs.Run] {
            s.runs.filter { String(s[$0.range].characters) == text }
        }
        func strong(_ s: AttributedString, _ text: String) -> Bool {
            runs(s, text).contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        }
        func faint(_ s: AttributedString, _ text: String) -> Bool { runs(s, text).contains { $0.foregroundColor != nil } }
        let samples = ["**Overall verdict:** ship it, with *one* fix.", "## Findings\n- one\n* two\n3. three",
                       "See [the site](https://example.com) and <https://evil.example>.", "Run:\n```sh\nmake **all**\n```\nDone `now`.",
                       "Search src/**/*.ts, read __init__ and a*b*c.", "a\n\nb"]
        // Odd ones: a combining accent or a Thai vowel right after a mark, an emoji, Windows line
        // ends, stacked or empty marks, double backticks, and a long line of openers that never close.
        let odd = ["`a`\u{301}b", "**ตัวหนา**ที่ `ก`ี่ ข้อ", "`x`\u{2764}\u{FE0F} **ok** \u{1F469}\u{200D}\u{1F4BB}",
                   "## Head\r\n- item\r\n```\r\ncode\r\n```", "***x***", "** and *", "``code``",
                   String(repeating: " **a [b `c", count: 800)]
        for sample in samples + odd {
            XCTAssertEqual(Array(plain(Format.markdown(sample)).unicodeScalars), Array(sample.unicodeScalars), sample)
        }
        XCTAssertTrue(strong(Format.markdown("a\r\n## Next"), "Next"))

        let verdict = Format.markdown(samples[0])
        XCTAssertTrue(strong(verdict, "Overall verdict:"))
        XCTAssertTrue(faint(verdict, "**"))
        XCTAssertTrue(runs(verdict, "one").contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        let heading = Format.markdown(samples[1])
        XCTAssertTrue(strong(heading, "Findings"))
        XCTAssertTrue(faint(heading, "## "))
        XCTAssertTrue(faint(heading, "- "))
        XCTAssertTrue(faint(heading, "* "))
        let link = Format.markdown(samples[2])
        XCTAssertFalse(link.runs.contains { $0.link != nil })
        XCTAssertTrue(faint(link, "](https://example.com)"))
        XCTAssertFalse(faint(link, "the site"))
        let code = Format.markdown(samples[3])
        XCTAssertTrue(faint(code, "```sh"))
        XCTAssertTrue(runs(code, "make **all**").contains { $0.inlinePresentationIntent?.contains(.code) == true })
        XCTAssertTrue(runs(code, "now").contains { $0.backgroundColor != nil })
        let names = Format.markdown(samples[4])
        XCTAssertFalse(names.runs.contains { $0.inlinePresentationIntent != nil || $0.foregroundColor != nil })
    }

    // The foot of the Library says since when its books are kept. The owner's Mac counts years
    // the Buddhist way; the panel speaks English, so the year is the common era's.
    func testLibraryFootSaysSinceWhen() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let since = ISO8601DateFormatter().date(from: "2026-09-29T03:00:00Z")!
        XCTAssertEqual(Format.libraryFoot(since: since, calendar: HistoryReport.calendar(from: buddhist)),
                       "Kept since Sep 29, 2026 · until the project folder is gone")
    }

    // A book's line says how many chapters it has and the day of the last, near days in words and
    // this year's without the year. Chapters nobody has read yet say so instead, in its place.
    func testBookMetaSaysCountAndDay() {
        var calendar = HistoryReport.calendar(from: Calendar(identifier: .buddhist))
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let now = ISO8601DateFormatter().date(from: "2026-10-30T05:00:00Z")!  // noon in Bangkok
        func meta(_ chapters: Int, _ new: Int, _ last: String) -> String {
            Format.bookMeta(chapters: chapters, newCount: new, last: ISO8601DateFormatter().date(from: last)!, now: now, calendar: calendar)
        }
        XCTAssertEqual(meta(2, 0, "2026-10-29T17:30:00Z"), "2 · today")  // just past midnight in Bangkok
        XCTAssertEqual(meta(1, 0, "2026-10-29T16:30:00Z"), "1 · yesterday")
        XCTAssertEqual(meta(3, 0, "2026-10-27T05:00:00Z"), "3 · Oct 27")
        XCTAssertEqual(meta(4, 0, "2025-12-30T05:00:00Z"), "4 · Dec 30, 2025")
        XCTAssertEqual(meta(5, 2, "2026-10-30T04:00:00Z"), "2 new")
        XCTAssertEqual(Format.openPDF, "Open PDF")
    }

    // A shelf counts its books; the page names itself on the button that opens it, and says what
    // will come when it has nothing yet.
    func testShelfMetaSaysBooks() {
        XCTAssertEqual(Format.shelfMeta(books: 1), "1 book")
        XCTAssertEqual(Format.shelfMeta(books: 12), "12 books")
        XCTAssertEqual(Format.libraryHelp(showing: false), "Library")
        XCTAssertEqual(Format.libraryHelp(showing: true), "Back to agents")
        XCTAssertEqual(Format.noBooks, "No books yet. When a sub-agent hands work back, it lands here.")
    }
}
