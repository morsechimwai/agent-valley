import AppKit
import Combine
import SwiftUI

enum Format {
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        // Past ten minutes the seconds say nothing, and ticked on every row.
        if total < 600 { return "\(total / 60)m \(String(format: "%02d", total % 60))s" }
        if total < 3600 { return "\(total / 60)m" }
        return "\(total / 3600)h \(String(format: "%02d", total % 3600 / 60))m"
    }

    static func tokens(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 1_000_000 { return String(format: "%.1fk", Double(count) / 1000) }
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }

    /// "Opus 4.5" for claude-opus-4-5-20251101: the family and its version, without the release
    /// date, which is noise in a row. An id of another shape keeps its words, less "claude-" and the date.
    static func model(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        guard parts.count >= 2, parts[0] == "claude" else { return id }
        parts.removeFirst()
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard let family = parts.first, family.allSatisfy(\.isLetter) else { return parts.joined(separator: "-") }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }

    /// "> Read login.ts", or nil before the agent's first tool call.
    static func stepLine(_ lastStep: String) -> String? {
        lastStep.isEmpty ? nil : "> \(lastStep)"
    }

    /// A folded session's one step: that of the unfinished row, lead or sub-agent, that moved
    /// last. While the lead waits on its helpers its own step names no file.
    static func sessionStep(_ card: SessionCard) -> String? {
        card.rows.filter { $0.status != .done && !$0.step.isEmpty }
            .max { ($0.info.lastActivity ?? .distantPast) < ($1.info.lastActivity ?? .distantPast) }
            .flatMap { stepLine($0.step) }
    }

    static func steps(_ count: Int) -> String {
        count == 1 ? "1 step" : "\(count) steps"
    }

    static func working(_ count: Int) -> String {
        "\(count) working"
    }

    /// "1 needs you · 2 working · 1 quiet": each is named only when there are some. "0 working"
    /// is said only when it is all there is to say.
    static func summary(working: Int, quiet: Int, needsYou: Int = 0) -> String {
        let parts = (needsYou > 0 ? [Format.needsYou(needsYou)] : []) + (working > 0 ? [Format.working(working)] : []) + (quiet > 0 ? ["\(quiet) quiet"] : [])
        return parts.isEmpty ? Format.working(0) : parts.joined(separator: " · ")
    }

    /// Requests past the edge that Allow, Deny or an option row can answer from the panel.
    static func toAnswer(_ count: Int) -> String {
        "\(count) to answer here"
    }

    static func needsYou(_ count: Int) -> String {
        "\(count) \(count == 1 ? "needs" : "need") you"
    }

    /// Under a quiet row: the word alone says nothing to someone who has not read the code.
    /// What is known of it and no more. A session Claude Code calls busy is the least likely to
    /// have a prompt up, and a sub-agent has no terminal of its own.
    static func quietHint(main: Bool, calledBusy: Bool) -> String {
        if calledBusy { return "Claude Code says it is busy, but nothing has been written. It may be stuck." }
        return main ? "No activity. It may be waiting for you in its terminal." : "No activity. It may be waiting, or stuck."
    }

    static func idle(_ count: Int) -> String {
        "\(count) idle"
    }

    static func hidden(_ count: Int) -> String {
        "\(count) hidden"
    }

    /// The sessions a folded row stands for, each by the name its card would carry.
    static func names(_ sessions: [SessionCard]) -> String {
        sessions.map(\.name).joined(separator: " · ")
    }

    static func done(_ count: Int) -> String {
        "\(count) done"
    }

    /// What lies past the bottom edge of the list, or nil when nothing to name does: whole
    /// sessions, and rows that wait, which can be past the edge in a card that starts above it.
    /// `answerable` names those of the waiting rows whose request the panel itself can answer.
    static func below(sessions: Int, quiet: Int, needsYou: Int, answerable: Int = 0) -> String? {
        let parts = (sessions > 0 ? ["+\(sessions) \(sessions == 1 ? "session" : "sessions")"] : []) + (needsYou > 0 ? [Format.needsYou(needsYou)] : [])
            + (answerable > 0 ? [Format.toAnswer(answerable)] : []) + (quiet > 0 ? ["\(quiet) quiet"] : [])
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What a row leads with: the task, which is what tells agents apart, or the type when there is none.
    static func rowTitle(task: String, type: String) -> String {
        task.isEmpty ? type : task
    }

    /// The type on the row's second line, unless it already led as the title. The default type is
    /// left out, as its mascot says it, and a plugin's type goes without the plugin's name:
    /// both took room from the step, which is what differs from row to row.
    static func rowSubtitle(task: String, type: String) -> String? {
        task.isEmpty || type == "general-purpose" ? nil : type.split(separator: ":").last.map(String.init)
    }

    /// What a row can do without: its type, unless that led as the title. It stands at the end
    /// of the row's second line and is the first to go.
    static func rowExtras(task: String, type: String) -> String {
        rowSubtitle(task: task, type: type) ?? ""
    }


    /// Where a session runs: its folder, its branch when it has one, and whether that is a worktree.
    static func place(_ card: SessionCard) -> String {
        card.branch.isEmpty ? card.project : "\(card.project) \(card.branch)" + (card.worktree ? " (worktree)" : "")
    }

    /// The shortcut that opens the panel from any app, as the keys are drawn on a Mac. A space
    /// between the keys: set tight in the panel's type they ran into one mark.
    static func shortcut(_ key: ShortcutKey) -> String {
        "⌃ ⌥ ⌘ \(key.letter)"
    }
    /// What the keyboard does in the panel, shown while it is being worked that way. Return is
    /// named only where it leads somewhere: to the app the chosen session runs in.
    static func keysHint(app: String?) -> String {
        (["↑ ↓ move"] + (app.map { ["return goes to \($0)"] } ?? []) + ["? keys", "esc closes"]).joined(separator: " · ")
    }

    /// Read out as the ring arrives on a session: which one the keys now act on. The session's
    /// own name, then the app's word for how it is doing: listed, and not made into a sentence.
    static func chosen(_ card: SessionCard) -> String {
        let wait = card.main.flatMap { $0.status == .needsYou ? waitedAloud($0.quietFor) : nil }
        return [card.name, cardStatus(card), wait].compactMap { $0 }.joined(separator: ", ")
    }

    /// What the ring says of itself to a screen reader, ahead of the card's own words.
    static let chosenLabel = "The arrow keys are on this session"

    /// Every key, for the legend: the key, and what it does.
    static let keysCaption = "Keys that work after the shortcut has opened the panel:"
    static let keys: [(key: String, does: String)] = [
        ("↑ ↓", "move between sessions"), ("return", "go to its app"),
        ("⌘↩", "allow once"), ("⌘⌫", "deny (skip a question)"),
        ("⌘1–⌘4", "pick an answer"), ("h", "hide the session"),
        ("u", "show hidden ones"), ("d", "expand done agents"),
        ("i", "expand idle sessions"), ("p", "pin the panel"),
        (",", "settings"), ("?", "this list of keys"),
        ("t", "open History"), ("esc", "close"),
    ]
    /// Without the word "turn", which a reader for whom English is a second language took for
    /// something else. True of a session, which was last given a prompt, and of a sub-agent,
    /// which was given its task.
    static let timeCaption = "The time on a row is how long it has worked on its last task, or how long it has been quiet or waiting."
    static let timeHelp = "How long it has been working since it was last given something to do, or how long it has been quiet or waiting"

    /// The first-launch line. It names the mascot, which every Mac shows, not the notch.
    /// The shortcut is offered only while it works. What the panel is doing now comes first:
    /// it opened without the person, and stays until the pointer has been in it. "It closes
    /// when you move away" was read with the pointer nowhere near, over a panel that stayed.
    /// Before any of that, what the panel is for: the one sentence that said so stood on the
    /// last page of the settings, and people handed the app went looking for it.
    static func intro(shortcut: ShortcutKey?) -> String {
        "This panel shows what your Claude Code agents are doing, and when one needs you. It opened by itself this once: point at it, then move away, and it closes. To open it again, point at the mascot at the top of the screen\(shortcut.map { ", or press \(Format.shortcut($0))" } ?? ""). The ? above explains the symbols."
    }

    /// What an empty panel says, or nil when there is something to show or nothing has been read yet.
    static func emptyState(loaded: Bool, rootMissing: Bool, isEmpty: Bool) -> String? {
        guard loaded else { return nil }
        if rootMissing { return "Can't find ~/.claude/projects. Run Claude Code once and agents appear here." }
        return isEmpty ? "No agents running. Start Claude Code in a terminal and they appear here." : nil
    }

    /// What stands in for the limits when there are no numbers, or nil when there is nothing to say.
    static func limitsNotice(_ display: PlanLimitsClient.Display) -> String? {
        switch display {
        // Switched off is a choice, not news: it is not said again in every glance.
        case .off: return nil
        case .unavailable: return "Plan limits unavailable"
        case .loading, .limits: return nil
        }
    }

    static let limitsLoading = "Checking limits…"

    /// The sign the crew hangs up when a plan limit has run out: a few hours out fishing, or days away.
    static func fishingSign(weekly: Bool) -> String {
        weekly ? "On vacation" : "Gone fishin\u{2019}"
    }

    /// Beside the sign, in the crew's words: which limit it was, and where they went.
    static func fishingLine(weekly: Bool) -> String {
        weekly ? "The weekly limit ran out. Everyone piled into the van, and Felix brought the bongos."
            : "The 5-hour limit ran out, so we went to the lake. Walt swears they're biting."
    }

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// When the sign says the crew is back: the time today, or tomorrow, or the day's name. On a
    /// 24-hour clock in English, as the quiet hours are, whatever the Mac's language and calendar.
    static func backAt(_ date: Date?, now: Date, calendar: Calendar = HistoryReport.calendar()) -> String {
        guard let date else { return "Back soon" }
        // A reset a moment before the minute is that minute.
        let at = calendar.dateComponents([.weekday, .hour, .minute], from: date.addingTimeInterval(30))
        let time = String(format: "%02d:%02d", at.hour ?? 0, at.minute ?? 0)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date.addingTimeInterval(30))).day ?? 0
        switch days {
        case ...0: return "Back at \(time)"
        case 1: return "Back tomorrow at \(time)"
        default: return "Back \(weekdays[((at.weekday ?? 1) - 1) % 7]) at \(time)"
        }
    }

    /// What to tell the person under the Plan limits switch: the cause, and what they can do.
    static func limitsReason(_ failure: LimitsFailure) -> String {
        switch failure {
        case .noLogin: return "No Claude Code login in Keychain. Sign in with Claude Code first."
        case .loginExpired: return "The Claude Code login has expired. Use Claude Code once to renew it."
        case .offline: return "No connection to api.anthropic.com. \(limitsRetry)"
        case .refused(let status): return "api.anthropic.com answered with error \(status). \(limitsRetry)"
        case .unreadable: return "api.anthropic.com sent an answer this version does not understand. A newer version of the app may."
        case .noAnswer: return "No answer after a minute. It will try again."
        }
    }

    /// What happens next after a check that failed: the cause alone left the person to guess.
    private static let limitsRetry = "It tries again every \(Int(PlanLimitsClient.refreshEvery) / 60) minutes."

    /// To the pointer, on numbers that say how old they are: why, and what happens next.
    static let limitsAgeHelp = "The last check failed, so these are the numbers from before. \(limitsRetry)"

    /// A limit in words, for the pointer: the row itself has room for "5h" and "7d" only.
    static func limitHelp(spoken: String, percent: String, reset: String?) -> String {
        "\(spoken): \(percent) used" + (reset.map { ", resets in \($0)" } ?? "")
    }

    /// "12m old", for numbers kept from before a refresh that failed.
    static func limitsAge(asOf: Date, now: Date) -> String {
        "\(max(1, Int(now.timeIntervalSince(asOf)) / 60))m old"
    }

    static let terminalOnly = "Answer in the terminal."
    /// Puts a request away without answering it.
    static let hideRequest = "Hide"
    static let hideRequestHelp = "Removes this from the panel without answering it. It still waits in the terminal."
    /// Under a request that cannot be allowed from here. The app's own sentence: no text from
    /// the request goes into it, or the request could put words in the app's mouth.
    static let cannotShow = "Can't show all of this here. Deny it, or answer in the terminal."
    /// Stands where the value of a field would, for one that is left out.
    static let notShown = "not shown"

    /// What stands for a moment where a request was, once it has ended.
    static func settled(_ outcome: AnswerStore.Outcome) -> String {
        switch outcome {
        case .answered(.allow): return "Allowed once"
        case .answered(.deny): return "Denied"
        case .answered(.option): return "Answered"
        // Skip sends word to Claude Code, where Hide sends none: the two looked alike.
        case .answered(.skip): return "Skipped. Claude Code was told."
        case .inTerminal: return "Answered in the terminal"
        case .notTaken: return "Not delivered. Answer in the terminal."
        }
    }

    /// The request's own text that goes with that word: the option that was picked, or the
    /// tool that was allowed or denied. Drawn beside the app's word and never inside it.
    static func settledDetail(_ outcome: AnswerStore.Outcome, tool: String) -> String? {
        switch outcome {
        case .answered(.option(let label)): return label
        case .answered(.skip), .inTerminal: return nil
        case .answered, .notTaken: return tool.isEmpty ? nil : tool
        }
    }

    /// The link on a card that waits on the person, naming the app its terminal runs in.
    static func goTo(app: String) -> String {
        "Go to \(app)"
    }

    /// What an answer button says aloud, in the app's own words.
    static func answerLabel(_ answer: Answer) -> String {
        switch answer {
        case .allow: return "Allow once"
        case .deny: return "Deny"
        case .option: return "Answer"
        case .skip: return "Skip"
        }
    }

    /// What it answers and for whom, read out after that: the request's and the transcript's
    /// own words, listed and never put inside a sentence of the app's.
    static func answerValue(_ answer: Answer, tool: String, title: String, detail: String = "") -> String {
        // An option's own description goes with its label: both are drawn on its row.
        if case .option(let label) = answer { return [label, detail, title].filter { !$0.isEmpty }.joined(separator: ", ") }
        return "\(tool), \(title)"
    }

    /// What a press does, to the pointer and read out: what Claude Code is told, which the word
    /// on the button does not say. Only what the app sends: what Claude Code does next is its own
    /// affair. Nothing for an option, whose row already says it in the request's words.
    static func answerHelp(_ answer: Answer) -> String? {
        switch answer {
        case .allow: return "Lets Claude Code do this, this one time."
        case .deny: return "Refuses this. Claude Code is told it was denied from the notch."
        case .skip: return "Leaves the question unanswered. Claude Code is told you chose not to answer."
        case .option: return nil
        }
    }

    /// Read out with each answer button: what it does, then how it is pressed, so that pressing
    /// one from the keyboard is not a puzzle.
    static func answerHint(_ answer: Answer) -> String {
        [answerHelp(answer), "By a click, or by its key after the shortcut has opened the panel."].compactMap { $0 }.joined(separator: " ")
    }

    /// What installs the plugin, with the path of this very copy of the app. One line to copy:
    /// leaving the panel to paste closes it, and a second trip was easy to forget.
    /// `replacing`: the plugin points at an older copy of the app. Claude Code will not add a
    /// second list by the same name, so the old one goes first.
    static func installCommand(resources: URL, replacing: Bool = false) -> String {
        let path = URL(fileURLWithPath: stablePath(resources)).appendingPathComponent("claude-plugin").path
        return (replacing ? "claude plugin marketplace remove \(PluginPlace.marketplace) && " : "")
            + "claude plugin marketplace add \(quoted(path)) && claude plugin install notch-answers@agent-valley"
    }

    /// A path into this copy of the app that still works after `brew upgrade`. Homebrew keeps each
    /// version in a folder of its own and deletes the old one when it upgrades; its opt link names
    /// whichever is installed.
    static func stablePath(_ url: URL) -> String {
        var parts = url.pathComponents
        if let i = parts.indices.dropLast(2).first(where: { parts[$0] == "Cellar" && parts[$0 + 1] == "agent-valley" }) {
            parts.replaceSubrange(i...i + 2, with: ["opt", "agent-valley"])
        }
        return NSString.path(withComponents: parts)
    }

    /// The app's `crew` command as a shell runs it: Claude Code's settings hold it, and the
    /// install and uninstall lines are pasted into a terminal.
    static func crewCommand(executable: String, _ mode: String) -> String {
        "\(quoted(executable)) crew \(mode)"
    }

    /// Single quotes, so nothing in the path is read by the shell the command is pasted into.
    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func answersStatus(_ state: AnswerStore.State, now: Date) -> String? {
        switch state {
        case .off:
            return nil
        case .listening(nil):
            return "Listening for the plugin, on this Mac only. Nothing has arrived yet. Only sessions that you start after installing the plugin send their prompts here."
        case .listening(let last?):
            let minutes = Int(now.timeIntervalSince(last)) / 60
            return minutes < 1 ? "Listening. Last request just now." : "Listening. Last request \(minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h") ago."
        case .failed(let reason):
            return "Could not listen: \(reason). Switch it off and on to try again."
        }
    }

    /// What a click on the pin will do, whichever way it is set.
    static func pinHelp(pinned: Bool) -> String {
        pinned ? "Let the panel close again" : "Keep the panel open"
    }

    /// `update`: the version whose green dot is on the gear.
    static func gearHelp(showingSettings: Bool, update: String? = nil) -> String {
        if showingSettings { return "Back to agents" }
        return update.map { "Settings · " + updateWaiting(version: $0) } ?? "Settings"
    }

    static func historyHelp(showing: Bool) -> String {
        showing ? "Back to agents" : "History"
    }

    /// What a click on the speaker will do, or why nothing sounds for now.
    static func soundHelp(on: Bool, quietUntil: Int?) -> String {
        guard on else { return "Turn sounds on" }
        return quietUntil.map { "Quiet hours until \(hour($0))" } ?? "Turn sounds off"
    }

    /// The speaker as the bar draws it: struck out when off, asleep in the quiet hours.
    static func soundSymbol(on: Bool, quiet: Bool) -> String {
        on ? (quiet ? "speaker.zzz" : "speaker.wave.2") : "speaker.slash"
    }

    /// An hour of the day on a 24-hour clock, the same for everyone.
    static func hour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    static let soundsCaption = "A sound when an agent needs you and when a session finishes. Silent while the screen is locked."
    static let finishedCaption = "Only when the session had been working for \(Int(Sound.shortTurn)) seconds or more."
    static let remindCaption = "Repeats while an agent still waits and you have not opened the panel."
    static let scenesCaption = "Needs Plan limits."
    static let tabCaption = "Asks Terminal, iTerm2 or Ghostty to show the session's own tab. macOS asks you to allow this once for each. To change your answer: System Settings > Privacy & Security > Automation."

    /// The line over a project's sessions: its name and how many sessions, with the word, as on
    /// a status group's line. With them in more than one folder it counts the folders, and the
    /// sessions as well when some share one.
    static func projectHeader(_ header: ProjectHeader) -> String {
        let sessions = "\(header.sessions) \(header.sessions == 1 ? "session" : "sessions")"
        guard header.worktrees > 1 else { return "\(header.project) · \(sessions)" }
        return "\(header.project) · \(header.worktrees) worktrees" + (header.sessions > header.worktrees ? ", \(sessions)" : "")
    }

    /// Whether a card names its folder beside its branch. One without a title is called by its
    /// folder already, and under its project's line the project's own folder goes without saying.
    static func namesFolder(_ card: SessionCard, under project: String?) -> Bool {
        !card.title.isEmpty && card.project != project
    }

    /// The line over a group of sessions. With the word "sessions": the line under the notch
    /// counts agents, and a bare number here would be read as one of those. With the agents
    /// too, where a session holds more than one of them: "3 working" up there over
    /// "Working · 1 session" here read as two counts that disagree. There are then always
    /// two agents or more, so the word is never "agent".
    static func groupHeader(_ header: GroupHeader) -> String {
        let name: String
        switch header.group {
        case .needsYou: name = "Needs you"
        case .working: name = "Working"
        case .quiet: name = "Quiet"
        case .idle: name = "Idle"
        }
        return "\(name) · \(header.count) \(header.count == 1 ? "session" : "sessions")" + (header.agents > header.count ? ", \(header.agents) agents" : "")
    }

    /// To the pointer on the counts under the notch, and read out with them: what they count.
    /// Nothing on that line says, and it has no room to.
    static let countsHelp = "These count agents, sub-agents too. One session can run several."

    /// What a tab over the list does, for the pointer and for VoiceOver.
    static func groupingHelp(_ grouping: Grouping) -> String {
        switch grouping {
        case .projects: return "All sessions, grouped by project"
        case .status: return "Sessions grouped by status"
        }
    }

    /// How many tokens went in and came out: the last five hours, then today. Not `named`:
    /// without the word in front, where the line has no room for it. Both stretches of time
    /// are what the line is for, and they fit the list's width whatever the numbers.
    /// "last 5h", not "5h": that is what the row under the notch calls the plan's 5-hour
    /// limit, which runs from a fixed start and not back from now. A comma inside each
    /// stretch, where a dot stood, pays for the word.
    static func usageLine(_ summary: UsageSummary, named: Bool = true) -> String {
        let counts = "last 5h \(tokens(summary.fiveHours.incoming)) in, \(tokens(summary.fiveHours.output)) out · today \(tokens(summary.today.incoming)) in, \(tokens(summary.today.output)) out"
        return named ? "Tokens · \(counts)" : counts
    }

    /// The same in full, with what was read back from the cache: for the pointer and for VoiceOver.
    static func usageHelp(_ summary: UsageSummary) -> String {
        func part(_ name: String, _ totals: TokenTotals) -> String {
            "\(name): \(tokens(totals.incoming)) in, \(tokens(totals.output)) out, \(tokens(totals.cacheRead)) read from cache"
        }
        return "\(part("Last 5 hours", summary.fiveHours)). \(part("Today", summary.today)). Bars: tokens out in each of the last 12 hours."
    }

    static let usageCaption = "Tokens used in the last 5 hours and today, and the History page. Counted from Claude Code's files on this Mac, and kept in AgentValley's own folder so History goes back further than Claude Code keeps its files. Nothing is sent anywhere."

    /// Which app this is, for someone it was handed to.
    static func about(name: String?, version: String?) -> String {
        [name ?? "AgentValley", version].compactMap { $0 }.joined(separator: " ")
    }

    /// A new bug report on GitHub, its form (.github/ISSUE_TEMPLATE/bug_report.yml) already holding
    /// what we would ask first. The fields are named by their ids in that form.
    static func bugReport(version: String?, macOS: OperatingSystemVersion, mac: String) -> URL {
        var url = URLComponents(string: "https://github.com/morsechimwai/agent-valley/issues/new")!
        url.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            version.map { URLQueryItem(name: "version", value: $0) },
            URLQueryItem(name: "macos", value: "macOS \(macOS.majorVersion).\(macOS.minorVersion).\(macOS.patchVersion), \(mac)"),
        ].compactMap { $0 }
        return url.url!
    }

    /// The promise the app is built on, where a new owner will look for it. True with every
    /// switch on: it used to end "Changes nothing.", under a switch that answers Claude Code and
    /// another that reads the Keychain and goes online. What reaches further than reading is
    /// named, and each is off until its switch is turned on.
    /// `updates`: this copy checks for new versions, which a release does from the start.
    static func readOnly(updates: Bool) -> String {
        "Reads Claude Code's files, and which Superset workspace a session is in. Never writes to them: Install the plugin runs Claude Code's own command, only when you press it. Answering requests stays off until the plugin is in; checking plan limits online and showing a session's tab, until you turn on their switch. Each switch says what it does."
            + (updates ? " It asks GitHub once an hour if there's a new version; that switch starts on." : "")
    }
    static let updatesTitle = "Check for updates"
    static let updatesCaption = "Once an hour we look on GitHub. Nothing gets installed until you say so."
    static let checkNow = "Check now"
    static func updateWaiting(version: String) -> String { "Version \(version) came in." }
    static let updateLook = "Have a look"
    static let moveTitle = "Move AgentValley to Applications?"
    static let moveMessage = "Out here we can't update ourselves, and the plugin loses track of us when you quit."
    static let moveButton = "Move to Applications"
    static let notNow = "Not now"
    static let awayHelpOff = "Going away? Claude waits for your phone when it finishes."
    static let awayHelpOn = "Away. Click when you're back."
    static let awayBandTitle = "Away. Your phone has it."
    static let awayBandNote = "Touch the Mac when you're back."
    static let leftOverTitle = "From your phone, not sent:"
    static let pluginLostLine = "Allow and Deny can't find us anymore."
    static let pluginLostFix = "Fix it"
    static let pluginLostNote = "The plugin still points at a copy of us that's gone. Run this once more."
    static let oldCopyLine = "Our 0.1 from Homebrew is still installed."
    static let oldCopyNote = "Homebrew left our 0.1 on this Mac, and it opens at login beside us. Run this once in a terminal to take it out."
    static let moveFailed = "We couldn't make the move. Drag AgentValley into Applications yourself and open it from there."
    static let movedNotOpened = "We made it to Applications but didn't wake up. Open AgentValley from there."
    static let idleCaption = "Sessions whose agents have all stopped."
    /// Beside the buttons of a request, for a moment, when a click on one did not count: why.
    /// `cut`: the request was not all in view, and the click brought it there. Else it came
    /// within a moment of the panel opening, the request arriving or the list moving: one
    /// sentence that is true of all three.
    /// Short enough for the room there is: beside "Allow once ⌘↩" and "Deny ⌘⌫" on a card
    /// that is some thirty columns, and "Too soon to count. Press again." ended in "agai…".
    static func notCounted(cut: Bool, key: Bool = false) -> String {
        (cut ? "Not all in view. " : "Too soon. ") + (key ? "Press again." : "Click again.")
    }

    /// The chord that answers, as drawn on the button it fires.
    static func chord(_ key: KeyCommand) -> String? {
        switch key {
        case .allow: return "⌘↩"
        case .deny: return "⌘⌫"
        case .option(let number): return "⌘\(number)"
        default: return nil
        }
    }

    /// What stands in a row's time column: its state and for how long, or how long its turn has
    /// run. A busy row that has stopped writing says since when, here and not at the end of its
    /// step: in the same place on every row it can be seen without reading for it.
    static func rowTime(_ status: AgentStatus, elapsed: TimeInterval, quietFor: TimeInterval) -> String {
        statusLabel(status, isMain: false, quietFor: quietFor) ?? lastMoved(status, silentFor: quietFor) ?? Format.elapsed(elapsed)
    }
    /// Over the install command: what the person is about to put into Claude Code. The app
    /// asks them to run a command it does not run itself, so it owes them what the command
    /// does: nine of thirteen testers stopped at a bare command, and the one who came to check
    /// what the app touches found nothing said. Only what `plugin/` does.
    static let pluginWhat = "The plugin is inside this app, and installing it points Claude Code at it. It adds two hooks to Claude Code: each permission prompt and question is handed to this app, and while you're Away with your phone paired, a finished turn waits here for your next message. All on this Mac only. With the app closed or this switch off, Claude Code asks in the terminal and ends its turns as before."
    /// Under the button: what it runs, which can also be pasted by hand. Then the one step left.
    /// The button since 2026-10-26: nine of thirteen testers stopped at the command alone.
    static let installSteps = (
        run: "Install runs this command for you. Or copy it and run it in a terminal yourself: the Terminal app, or wherever you start Claude Code.",
        restart: "Then start Claude Code again. Sessions that were already open do not have the plugin."
    )
    static let installButton = "Install the plugin"
    static let installing = "Installing"
    /// What became of the last press of Install, on the line under the command.
    static func installResult(_ result: PluginInstall.Result) -> String {
        switch result {
        case .installed: return "Installed, and the switch is on."
        case .noClaude: return "Couldn't find Claude Code's claude command. Copy the command and run it in a terminal."
        case .failed(let reason): return "Couldn't install: \(reason). Copy the command and run it in a terminal."
        }
    }
    /// Beside the way to the terminal on a card that waits: this one is answered there, the next
    /// one need not be. To the settings, where the plugin goes in.
    static let answerHereNextTime = "Answer here next time"
    static let answerHereNextTimeHelp = "Set up answering from the notch"
    /// Under the command: the one word in it that reads as something else.
    static let marketplaceNote = "In the command, \u{201C}marketplace\u{201D} is Claude Code's word for a list of plugins. Nothing is bought."
    /// The line that unfolds the way out. Not "Remove the plugin": standing there before
    /// anything was installed, that read as if a plugin were already in.
    static let removePlugin = "How to remove the plugin"
    /// The crew's row on the Claude Code page: what it does, the two steps, and the way out. It is
    /// a command the person runs themselves, like the plugin: the app does not write into ~/.claude.
    static let crewTitle = "Crew in the terminal"
    static let crewWhat = "We show up in Claude Code's terminal too. The status line under the prompt gets this session's face, model, plan and limits, and each sub-agent row gets its face, model and current step. Works with this app closed."
    static let crewSetup = "How to set it up"
    static let crewSteps = (
        run: "1. Copy this and run it in a terminal. It installs our font and sets statusLine and subagentStatusLine in Claude Code's settings.json. Anything it replaces is kept, and comes back when you take it out.",
        restart: "2. Start Claude Code again. If you use Ghostty, quit and reopen it first."
    )
    static let removeCrew = "How to take it out"
    static let removeCrewNote = "Puts back the status line you had before, and removes our font and the line added to Ghostty's config."
    static let stepsHelp = "Tool calls so far"
    static let extrasHelp = "The agent's type"
    static let jumpHelp = "Show who needs you"
    /// On the band at the bottom of the settings: what is past the edge.
    /// Under a page of the settings that runs past the edge. Quit is named on the page it is on.
    static func settingsBelow(_ tab: SettingsTab) -> String {
        tab == .about ? "More and Quit below" : "More settings below"
    }
    static let moreBelow = "more below"
    /// "For a while" left a person to guess whether quiet meant ten seconds or ten minutes: "a
    /// few minutes" says which, without the two rules behind it (two minutes, or ten while
    /// Claude Code calls the session busy).
    static let quietCaption = "Quiet: nothing written for a few minutes. It may be waiting for you in its terminal, or stuck."
    /// In the list, when the system would not give the shortcut: leads to the settings.
    static let shortcutTakenList = "The shortcut could not be registered: another app may hold it. Pick another in settings."

    /// The legend's name, wherever it is named. "Symbols", where it said "marks": a word two
    /// readers took for scores or for something they could not place.
    static let legendTitle = "What the symbols mean"

    /// Under the Plan limits switch. What is read is named for what it is: "your login" left
    /// a reader to wonder whether that meant a password.
    static let limitsCaption = "Reads the access token of your Claude Code login from Keychain, and sends it to api.anthropic.com to ask for your usage. It is never stored and never sent anywhere else."

    /// The name of the setting for how long what has stopped stays in the list.
    static let keepTitle = "Keep idle and done listed for"

    static func legendHelp(showing: Bool) -> String {
        showing ? "Hide what the symbols mean" : legendTitle
    }

    /// Under the switch that turns answering on. Until the plugin is in, how to install is right below.
    static func answersCaption(installed: Bool) -> String {
        "Shows Claude Code's permission prompts and questions here, with buttons to answer. The terminal still asks too. You can allow a request here only when the panel can show all of it, such as a short command." + (installed ? "" : " Needs a plugin that comes with this app: install it below.")
    }
    static let barMascotCaption = "The mascot on the bar is the agent to look at first."
    /// Past this many sub-agents in the list, each takes one line: at two lines each, a dozen
    /// push every other session off the panel.
    static let compactPast = 8

    static func oneLineRows(liveAgents: Int) -> Bool { liveAgents > compactPast }
    static let shortcutCaption = "Opens the panel from any app. ↑ ↓ move between sessions, return goes to the session's app, ⌘return and ⌘delete answer a request, esc closes. The ? lists every key."
    static let barCaption = "The number on the bar: red is how many agents need you, white how many are working, grey how many are quiet."
    static let waitCaption = "Once an agent has waited a minute for you, the longest wait shows in red where the ring is."
    static let ringCaption = "The ring shows how much of your 5-hour limit is used. It turns yellow at 80%. It is shown only when Plan limits is on."

    /// The ring on the bar, read out: it has no room for a word of its own.
    static func ringLabel(_ ring: LimitRing) -> String {
        "5-hour limit \(ring.limit.percentLabel) used" + (ring.stale ? ", from before the last check failed" : "")
    }
    /// Under the shortcut's switch when the system would not give the chord.
    static let shortcutTaken = "This shortcut could not be registered: another app may hold it. Pick another below."
    /// Which display the bar is on. Nothing in the app said: someone who works on a second
    /// display all day could not tell whether the bar would be there. It is not: it stays with
    /// the notch while a display with one is on.
    static let displayCaption = "The bar is on the display with a notch, or on your main display when there is none, unless you pick one under Display in the settings."
    static let displayChoiceCaption = "Automatic is the display with a notch, or your main one."
    static let beatCaption = "While an agent waits for you, the bar glows red every few seconds, until you open the panel."
    static let keepCaption = "How long a session or an agent stays listed after it stops."
    static let legendCaption = "The person shows the kind of agent."

    /// What takes the plugin out again. The names are the plugin's and its marketplace's own.
    static let uninstallCommand = "claude plugin uninstall notch-answers@agent-valley && claude plugin marketplace remove agent-valley"

    static func quit(appName: String?) -> String {
        appName.map { "Quit \($0)" } ?? "Quit"
    }

    /// "14m" or "1h 05m".
    private static func span(minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    /// "14m ago" after a working row's step, once its transcript has been silent as long as would
    /// make it quiet. Claude Code calls the session busy through a long command and through a
    /// hung one alike; how long ago it last wrote is the one thing known.
    static func lastMoved(_ status: AgentStatus, silentFor: TimeInterval) -> String? {
        status == .working && silentFor >= TranscriptReader.quietAfter ? "\(span(minutes: Int(silentFor) / 60)) ago" : nil
    }

    /// Whether the word beside a session's name is the plain running clock of a turn at work.
    static func runningClock(_ card: SessionCard) -> Bool {
        guard let main = card.main, main.status == .working, card.workingAfterMain == 0 else { return false }
        return lastMoved(main.status, silentFor: main.quietFor) == nil
    }

    /// The word beside a session's name. A main agent that ended its turn is not idle while
    /// agents it started work on.
    static func cardStatus(_ card: SessionCard) -> String? {
        guard let main = card.main else { return nil }
        let behind = card.workingAfterMain
        if behind > 0 { return working(behind) }
        // At work: how long this turn has run, as a sub-agent's row says how long it has.
        // Gone silent, it says since when in that same place.
        if main.status == .working { return lastMoved(main.status, silentFor: main.quietFor) ?? (main.elapsed > 0 ? elapsed(main.elapsed) : nil) }
        // Idle with jobs still running: the jobs are the news, not the word "idle".
        if main.status == .done, !card.jobs.isEmpty { return jobsRunning(card.jobs) }
        return statusLabel(main.status, isMain: true, quietFor: main.quietFor)
    }

    /// "1 shell, 2 monitors running": how many of each kind, as Claude Code counts them.
    static func jobsRunning(_ jobs: [BackgroundJob]) -> String {
        func count(_ kind: BackgroundJob.Kind, _ word: String) -> String? {
            let n = jobs.filter { $0.kind == kind }.count
            return n == 0 ? nil : "\(n) \(word)\(n == 1 ? "" : "s")"
        }
        return [count(.shell, "shell"), count(.monitor, "monitor")].compactMap { $0 }.joined(separator: ", ") + " running"
    }

    /// The same count for VoiceOver, which has no row to say where they run.
    static func jobsInBackground(_ jobs: [BackgroundJob]) -> String { jobsRunning(jobs) + " in the background" }

    /// What a job does: a shell's own description, or what a monitor waits for.
    static func jobLine(_ job: BackgroundJob) -> String {
        switch job.kind {
        case .shell: return job.name.isEmpty ? "Background command" : job.name
        case .monitor: return job.name.isEmpty ? "Monitor" : "Watching for: \(job.name)"
        }
    }

    /// How long a job has run, or how long it has left when it has an end. Never negative: the
    /// clock can step back.
    static func jobTime(_ job: BackgroundJob, now: Date) -> String {
        if let end = job.endsBy { return "ends in " + elapsed(max(0, end.timeIntervalSince(now))) }
        return elapsed(max(0, now.timeIntervalSince(job.startedAt)))
    }

    /// The tail of a list of jobs that did not fit.
    static func moreJobs(_ count: Int) -> String { "+\(count) more" }

    /// The red badge beside "needs you": how long the row has waited, from the first second,
    /// on the clock a working row keeps. Nil for a row not waiting on the person.
    static func waited(_ row: AgentRow?) -> String? {
        guard let row, row.status == .needsYou else { return nil }
        return elapsed(row.quietFor)
    }

    /// A wait read out: "4m" is read as four metres.
    static func waitedAloud(_ seconds: TimeInterval) -> String {
        func count(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        let total = Int(seconds)
        if total < 60 { return "waiting \(count(total, "second"))" }
        let minutes = total / 60
        if minutes < 60 { return "waiting \(count(minutes, "minute"))" }
        let hours = "waiting \(count(minutes / 60, "hour"))"
        return minutes % 60 == 0 ? hours : "\(hours) \(count(minutes % 60, "minute"))"
    }

    /// The longest wait on the bar, where the ring stands: whole minutes from the first, so
    /// nothing at the top of the screen ticks every second, and short enough for the wing.
    static func barWait(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds >= 60 else { return nil }
        let minutes = Int(seconds) / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    /// The word shown in place of progress, or nil while the agent is working.
    static func statusLabel(_ status: AgentStatus, isMain: Bool, quietFor: TimeInterval = 0) -> String? {
        switch status {
        case .working:
            return nil
        case .quiet:
            // Two minutes and forty minutes of silence mean different things; say which.
            let minutes = Int(quietFor) / 60
            return minutes < 1 ? "quiet" : "quiet \(span(minutes: minutes))"
        case .needsYou:
            // For how long is on the red badge beside it: `waited`.
            return "needs you"
        case .done:
            return isMain ? "idle" : "done"
        }
    }
}

struct PanelView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var state: NotchState
    @ObservedObject var settings: Settings
    @ObservedObject var limits: PlanLimitsClient
    @ObservedObject var answers: AnswerStore
    /// Makes the app's sounds. Not observed: nothing is drawn from what it remembers.
    let sound: SoundPlayer
    @ObservedObject var usage: UsageLedger
    @ObservedObject var updates: Updates
    /// Away mode and the phone's messages left over. The defaults are an Away that is never shown.
    @ObservedObject var away = AwayWatch(desk: StopDesk(), lastInput: { .distantPast })
    @ObservedObject var desk = StopDesk()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the list has been scrolled to its end, where nothing more waits below.
    @State private var atEnd = false
    /// The cards that start below the bottom edge of the list as it is scrolled now.
    @State private var below: Set<String> = []
    /// The rows that wait on the person and start below the bottom edge, as scrolled now. A
    /// card can start above the edge and hold such a row past it.
    @State private var belowRows: Set<String> = []
    /// A card the list has been asked to scroll to.
    @State private var scrollTarget: ScrollTarget?
    /// A key that was pressed to answer and did not count, for the request it was meant for.
    @State private var keyNote: KeyNote?
    /// Where each request sits in the list, as last laid out. Outside the view's state on
    /// purpose: it changes on every scrolled frame, and nothing is drawn from it.
    @State private var spans = RequestSpans()
    /// How tall the band that fades out the bottom of the list is right now; 0 when there is none.
    @State private var fade: CGFloat = 0
    /// Whether the list is scrolled to its very top, and the cards wholly above its top edge.
    @State private var atTop = true
    @State private var above: Set<String> = []
    /// The white packets running along the cards' branches: a sub-agent started or finished.
    @State private var pulses: [CrewPulse] = []
    /// The cards' sub-agents as the packets last saw them; empty while the list is not drawn.
    @State private var seen: [String: [String: AgentStatus]] = [:]
    /// How tall the band at the top of a scrolled list is right now; 0 when there is none.
    /// Worked out from where the list is, not kept: kept, it lagged a pass behind the band.
    private var topFade: CGFloat { state.expanded && !atTop ? NotchGeometry.topBand : 0 }
    /// Counts the times one more agent started to wait on the person. Each one is marked on the bar.
    @State private var arrivals = 0
    /// Ticks when an answerable request lands below the fold of the open panel.
    @State private var bandBeats = 0
    /// Counts the beats the bar makes while someone goes on waiting.
    @State private var beats = 0
    /// When someone last started to wait. No beat lands on the mark of that moment.
    @State private var arrived = Date.distantPast
    /// Whether the person has opened the panel since then. Once they have, the beating stops.
    @State private var watch = WaitWatch()
    /// How wide the tabs at the bar's left end are: the crowd behind the mascot stops short of them.
    @State private var tabsWidth: CGFloat = 84
    /// How far each one of the crowd stands from the one in front: a little less than half a person.
    private static let crowdStep: CGFloat = 8
    /// Ticks at the pace of those beats. Kept here, made once: a timer made in `body` would
    /// start over on every redraw and never fire.
    private let beat = Timer.publish(every: Motion(reduced: false).waitingBeat ?? 3, on: .main, in: .common).autoconnect()

    var body: some View {
        let motion = Motion(reduced: reduceMotion)
        let open = NotchGeometry.openFrame(screen: state.screenFrame, barHeight: state.barHeight, contentHeight: state.contentHeight).size
        let closed = NotchGeometry.collapsedFrame(screen: state.screenFrame, notchWidth: state.notchWidth, barHeight: state.barHeight).size
        let island = state.expanded ? open : closed
        let radius: CGFloat = state.expanded ? 20 : 10
        let shoulder = state.expanded ? NotchGeometry.openShoulder : NotchGeometry.shoulder
        let waiting = AgentStore.barState(sessions).waiting > 0
        let chrome = state.barHeight + NotchGeometry.statusRowHeight

        ZStack(alignment: .top) {
            // Laid out at its final size from the start: the island's growing edge uncovers the
            // content, and its text never reflows on the way.
            content(motion, viewport: max(0, open.height - chrome))
                .frame(width: open.width, height: max(0, open.height - chrome))
                .overlay(alignment: .bottom) {
                    // The list runs past the panel's edge: fade the last lines and say what is below.
                    let overflowing = state.expanded && !atEnd && NotchGeometry.overflows(screen: state.screenFrame, barHeight: state.barHeight, contentHeight: state.contentHeight)
                    // Of the cards that are drawn: one folded away since leaves its id behind.
                    let drawn = AgentStore.arrange(sessions, idle: settings.idleSessions, keeping: answers.settledSessions).cards
                    let hidden = drawn.filter { below.contains($0.id) }
                    // Every row that waits past the edge, also inside a card that starts above it.
                    let waiting = AgentStore.waitingBelow(drawn, cards: below, rows: belowRows)
                    let quiet = AgentStore.count(.quiet, in: hidden)
                    let answerable = answerableBelow(drawn).count
                    let label = state.showingSettings ? Format.settingsBelow(state.settingsTab)
                        : state.showingHistory ? Format.historyBelow : Format.below(sessions: hidden.count, quiet: quiet, needsYou: waiting.count, answerable: answerable)
                    // One height whatever it says: it used to jump as its words came and went.
                    let height: CGFloat = overflowing ? NotchGeometry.band : 0
                    // First to a request the edge cuts: it takes no click where it is. Else to
                    // the first row that waits below, else to the first session below, else on
                    // to the end: never for nothing.
                    let down = {
                        if state.showingPage {
                            scrollTarget = .end
                        } else if let request = NotchGeometry.firstCutBelow(spans.byID, viewport: max(0, open.height - chrome), fade: fade) {
                            scrollTarget = .request(request)
                        } else if let row = waiting.first, let card = drawn.first(where: { $0.rows.contains { $0.id == row.id } }) {
                            scrollTarget = ScrollTarget.to(row, on: card)
                        } else {
                            scrollTarget = (hidden.first { $0.rows.contains(where: \.mayNeedPerson) } ?? hidden.first).map { .card($0.id) } ?? .end
                        }
                    }
                    Group {
                        if overflowing {
                            // Black from halfway down: under the words nothing of the list shows through.
                            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black, location: 0.5), .init(color: .black, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: height)
                                .overlay(alignment: .bottom) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chevron.compact.down").font(.system(size: 13, weight: .semibold))
                                        if state.showingPage, let label {
                                            Text(verbatim: label)
                                        } else if label != nil {
                                            // Who waits is red here as everywhere else.
                                            band(sessions: hidden.count, waiting: waiting.count, quiet: quiet, answerable: answerable, pulse: bandBeats)
                                        } else {
                                            Text(verbatim: Format.moreBelow)
                                        }
                                    }
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.bottom, 4)
                                }
                                // The band takes the click itself. What it fades out must not be
                                // clickable through it, least of all a button that answers a request.
                                .contentShape(Rectangle())
                                .onTapGesture(perform: down)
                                // One button to a screen reader, and one it can press. The fade
                                // and the words on it each took the label, so it was read twice,
                                // and a tap is not a press: neither of the two did anything.
                                .accessibilityElement(children: .ignore)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(Text(verbatim: label.map { "Scroll down. \($0)" } ?? "Scroll down"))
                                .accessibilityAction(.default, down)
                        }
                    }
                    .onChange(of: height, initial: true) { _, new in fade = new }
                }
                .overlay(alignment: .top) {
                    // Scrolled, the list has gone on above its top edge too, and says so the same way.
                    // Not the settings: their pages stay at the top, and the band would cover them.
                    let scrolled = state.expanded && !atTop && !state.showingSettings
                    let hidden = AgentStore.arrange(sessions, idle: settings.idleSessions, keeping: answers.settledSessions).cards.filter { above.contains($0.id) }
                    let waiting = AgentStore.count(.needsYou, in: hidden)
                    let label = state.showingPage ? nil : Format.below(sessions: hidden.count, quiet: AgentStore.count(.quiet, in: hidden), needsYou: waiting)
                    let height: CGFloat = scrolled ? NotchGeometry.topBand : 0
                    // To whoever waits above, else back to the top.
                    let up = { scrollTarget = hidden.first { $0.rows.contains { $0.status == .needsYou } }.map { .card($0.id) } ?? .top }
                    Group {
                        if scrolled {
                            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5), .init(color: .black.opacity(0), location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: height)
                                .overlay(alignment: .top) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chevron.compact.up").font(.system(size: 13, weight: .semibold))
                                        if state.keyboard, !state.showingPage {
                                            // Scrolled, the line about the keys is out of sight: it is said here.
                                            Text(verbatim: Format.keysHint(app: nil))
                                        } else if label != nil {
                                            band(sessions: hidden.count, waiting: waiting, quiet: AgentStore.count(.quiet, in: hidden), answerable: 0, pulse: 0)
                                        }
                                    }
                                    .foregroundStyle(.white.opacity(0.8))
                                    .padding(.top, 2)
                                }
                                // It takes the click itself, as the one at the bottom does, and
                                // is one button that can be pressed, as that one is.
                                .contentShape(Rectangle())
                                .onTapGesture(perform: up)
                                .accessibilityElement(children: .ignore)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(Text(verbatim: label.map { "Scroll up. \($0)" } ?? "Scroll up"))
                                .accessibilityAction(.default, up)
                        }
                    }
                }
                .padding(.top, chrome)
                .allowsHitTesting(state.expanded)
                // Shut, nothing under the bar is there for a screen reader either. The list
                // fades out and was gone already. The settings do not fade, and stay in the
                // list's place a while after the panel shuts: their switches could be pressed
                // by a screen reader with nothing on the screen.
                .accessibilityHidden(!state.expanded)
            VStack(spacing: 0) {
                bar(motion, width: open.width)
                // Redrawn twice a minute so the times until reset keep counting down while open.
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    StatusRow(working: AgentStore.count(.working, in: sessions), quiet: AgentStore.count(.quiet, in: sessions),
                              needsYou: AgentStore.count(.needsYou, in: sessions), display: limits.display, now: timeline.date,
                              // To the page that says why the limits are missing. A link to the
                              // page already open would go nowhere.
                              openSettings: state.showingSettings && state.settingsTab == .general ? nil : {
                                  state.settingsTab = .general
                                  state.showingSettings = true
                              },
                              jump: jumpToWaiting, arrivals: arrivals)
                }
                    .frame(width: open.width)
                    .allowsHitTesting(state.expanded)
                    .modifier(Reveal(shown: state.expanded, index: 0, motion: motion, travels: false))
            }
        }
        .frame(width: island.width, height: island.height, alignment: .top)
        // While someone waits and the panel is shut, the whole bar glows red on every beat.
        // Shut only: open, the list says it in words, and nothing should flash at someone reading.
        .background(alignment: .top) {
            MascotFlag.red
                .frame(width: closed.width + NotchGeometry.shoulder * 2, height: closed.height)
                .keyframeAnimator(initialValue: 0.0, trigger: arrivals + beats) { glow, strength in
                    glow.opacity(strength)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(motion.flash, duration: 0.18)
                        CubicKeyframe(0, duration: 0.7)
                    }
                }
                .opacity(waiting && !state.expanded ? 1 : 0)
                // Gone the moment the panel opens, not faded out along with the island's growing.
                .transaction { $0.animation = nil }
        }
        // Black out to the tips of the shoulders, which lie outside the island's own rectangle.
        .background(Color.black.padding(.horizontal, -shoulder))
        .clipShape(IslandShape(radius: radius, shoulder: shoulder))
        .animation(motion.resize(opening: state.expanded), value: island)
        // The window's size whatever the island's, with the island at its top. The list grows a
        // turn before the window does, and an island taller than its window was centred in it:
        // the bar went up past the top of the screen, away from the notch, and sprang back.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
        // Shut, the panel drops what it said about requests answered while it was open: the
        // lines leave unseen, and the next opening does not start with last time's. Here, and
        // not on the list: the list is not there to hear of it while the settings show.
        .onChange(of: state.expanded) { _, open in
            guard !open else { return }
            // Shut, no packet is left half way to play out on the next opening.
            pulses = []
            // Once it has stayed shut: a pointer that slipped out and came straight back finds
            // the lines where they were.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if !state.expanded { answers.clearSettled() }
            }
        }
        // The panel can hold the keyboard, and no key presses anything in it: a ring around a
        // button would say otherwise.
        .focusEffectDisabled()
        // Every name, badge and "Go to" button in the list leaves for a session's app through
        // here, by one rule: not within a moment of the list moving under the pointer.
        .environment(\.goTo) { [answers] owner in
            // By when the finger went down. Pressed for the person by VoiceOver there is no
            // such moment, and the last click could be an hour old: by now.
            let at = NotchPanel.handlingClick ? NotchPanel.when(NotchPanel.pressedAt) : Date()
            if answers.goes(clickAt: at) { owner.bringForward() }
        }
        // Until the plugin is in and the switch on, each card that waits points the way there.
        .environment(\.setUpAnswers, settings.answers && answers.pluginInstalled ? nil : {
            state.settingsTab = .claudeCode
            state.showingSettings = true
        })
    }

    /// What the band says is below, with those who wait in red. The red count swells once per `pulse`.
    private func band(sessions: Int, waiting: Int, quiet: Int, answerable: Int, pulse: Int) -> some View {
        let parts: [String] = (sessions > 0 ? [Format.below(sessions: sessions, quiet: 0, needsYou: 0) ?? ""] : [])
        let tail: [String] = (answerable > 0 ? [Format.toAnswer(answerable)] : []) + (quiet > 0 ? ["\(quiet) quiet"] : [])
        return HStack(spacing: 0) {
            if !parts.isEmpty { Text(verbatim: parts[0] + (waiting > 0 || !tail.isEmpty ? " · " : "")) }
            if waiting > 0 { NeedsYouCount(count: waiting, pulse: pulse) }
            if !tail.isEmpty { Text(verbatim: (waiting > 0 ? " · " : "") + tail.joined(separator: " · ")) }
        }
    }

    /// The requests past the bottom edge that the panel can answer: Allow and Deny, or option rows.
    private func answerableBelow(_ drawn: [SessionCard]) -> [AnswerStore.Pending] {
        AgentStore.waitingBelow(drawn, cards: below, rows: belowRows).flatMap { row in
            drawn.first { $0.rows.contains { $0.id == row.id } }.map { answers.requests(forRow: row.id, in: $0) } ?? []
        }.filter { !$0.hidden && $0.ask.kind.isAnswerable }
    }

    /// To whoever waits on the person: the header's red count is where the pointer finds it.
    private func jumpToWaiting() {
        guard let found = AgentStore.arrange(sessions, idle: settings.idleSessions, keeping: answers.settledSessions).firstWaiting else { return }
        let target = ScrollTarget.to(found.row, on: found.card)
        guard state.showingPage else { return scrollTarget = target }
        // From a page the list has to be drawn first: a turn later it has rows to scroll to.
        state.showingSettings = false
        state.showingHistory = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scrollTarget = target }
    }

    /// Tells the sounds what the list holds, and whether the person is at the panel to see it:
    /// by the same rule as the bar's own mark, with whoever waits in view.
    private func listen(_ cards: [SessionCard]) {
        let drawn = AgentStore.arrange(cards, idle: settings.idleSessions, keeping: answers.settledSessions)
        let past = AgentStore.waitingBelow(drawn.cards, cards: below, rows: belowRows)
        sound.listed(cards, loaded: store.loaded, looks: state.looks,
                     looking: state.expanded && WaitWatch.looking(openFor: state.openedAt.map { Date().timeIntervalSince($0) }, pinned: state.pinned,
                                                                  inView: WaitWatch.inView(showingList: !state.showingPage, pastEdge: !past.isEmpty, grouping: settings.grouping, atTop: atTop)))
    }

    /// The sessions as the panel counts and draws them: a row with a request waiting needs the person.
    /// In the order the list is in: everything that reads an order reads this one.
    private var sessions: [SessionCard] {
        AgentStore.ordered(AgentStore.showing(answers.overlay(store.sessions), hidden: state.hidden), by: settings.grouping)
    }

    /// Whether there is more than one session to put in order. One alone is in every order
    /// at once: it gets no tabs and no line over it.
    private var grouped: Bool {
        let list = AgentStore.arrange(sessions, idle: settings.idleSessions, keeping: answers.settledSessions)
        return list.cards.count + list.folded.count >= 2
    }

    private func bar(_ motion: Motion, width: CGFloat) -> some View {
        let bar = AgentStore.barState(sessions)
        let crowd = AgentStore.crowd(sessions)
        let lead = crowd.first
        let looks = AgentStore.looks(sessions)
        // Open, as many of the rest as stand between the tabs and the mascot, which keeps its place.
        let room = (width - state.notchWidth) / 2 - NotchGeometry.wing + 5 - (grouped ? 8 + tabsWidth + 4 : 8)
        let behind = Array(crowd.dropFirst().prefix(max(0, Int(room / Self.crowdStep))))
        let extra = max(0, crowd.count - 1 - behind.count)
        return ZStack {
            // Stays beside the notch the whole time: the island grows around it. The mascot and
            // the one number there is room for on one wing, the limit's ring on the other.
            HStack(spacing: 3) {
                // Flagged whenever any agent may need the person, whoever the mascot itself stands for.
                // Still when the only rows called busy have all gone silent: nothing is known to move.
                // Without its dot while the red count stands beside it: the two said one thing
                // in one colour, a point apart.
                // With nothing at work, quiet or waiting, a coffee in its place.
                Group {
                    if let lead {
                        MascotView(status: lead.status, kind: MascotKind(type: lead.info.type, look: looks[lead.id] ?? LeadLook()),
                                   size: 18, flag: AgentStore.flag(sessions), dot: bar.waiting == 0, still: lead.isStalled,
                                   activity: lead.activity)
                    } else {
                        // Once a plan limit has run out, a fish on the line: the crew went fishing.
                        // Looked at twice a minute, so the coffee is back once the limit resets.
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            let jobs = sessions.flatMap(\.jobs)
                            // Beside it, while a job left in the background still runs: the crew
                            // rests, its commands don't. Still and dim once every job has run half
                            // an hour. Only here, with nobody at work: it never stands in for one.
                            // Five from the end, 18 of coffee, a gap of three and a screen of 17:
                            // 43 of the wing's 44, and nothing may run under the notch.
                            HStack(spacing: 3) {
                                if let out = limits.display.runOut(now: context.date) {
                                    if out.weekly { Van(size: 18) } else { Fish(size: 18) }
                                } else {
                                    Mug(size: 18)
                                }
                                if !jobs.isEmpty {
                                    JobScreen(size: 17, still: BackgroundJobs.resting(jobs, now: context.date))
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(Text(verbatim: Format.jobsInBackground(jobs)))
                                }
                            }
                        }
                    }
                }
                    // One hop when the cursor arrives: the bar noticed. Keyframes drive the offset
                    // and nothing else; a phase animator left its spring attached, so the mascot
                    // slid sideways whenever the window changed size.
                    .keyframeAnimator(initialValue: CGFloat.zero, trigger: state.opens) { mascot, lift in
                        mascot.offset(y: lift)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(motion.hop, duration: 0.11)
                            SpringKeyframe(0, duration: 0.32, spring: .bouncy(duration: 0.26, extraBounce: 0.15))
                        }
                    }
                    // One hop on every beat for as long as someone waits.
                    .keyframeAnimator(initialValue: CGFloat.zero, trigger: beats) { mascot, lift in
                        mascot.offset(y: lift)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(motion.hop, duration: 0.12)
                            SpringKeyframe(0, duration: 0.36, spring: .bouncy(duration: 0.26, extraBounce: 0.15))
                        }
                    }
                    // Three hops when an agent starts to wait on the person: a working agent
                    // moves all the time, and the one that is stuck must not be the one that
                    // makes no sign.
                    .keyframeAnimator(initialValue: CGFloat.zero, trigger: arrivals) { mascot, lift in
                        mascot.offset(y: lift)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(motion.hop, duration: 0.12)
                            SpringKeyframe(0, duration: 0.36, spring: .bouncy(duration: 0.26, extraBounce: 0.15))
                            CubicKeyframe(motion.hop, duration: 0.12)
                            SpringKeyframe(0, duration: 0.36, spring: .bouncy(duration: 0.26, extraBounce: 0.15))
                            CubicKeyframe(motion.hop, duration: 0.12)
                            SpringKeyframe(0, duration: 0.36, spring: .bouncy(duration: 0.26, extraBounce: 0.15))
                        }
                    }
                    // Open, everyone else not done stands behind it to the left, stepping out
                    // from behind it as the panel opens. Shut, they are gone, and draw nothing.
                    .background(alignment: .trailing) {
                        ZStack(alignment: .trailing) {
                            if state.expanded {
                                ForEach(Array(behind.enumerated()).reversed(), id: \.element.id) { place, row in
                                    let x = -CGFloat(place + 1) * Self.crowdStep
                                    MascotView(status: row.status, kind: MascotKind(type: row.info.type, look: looks[row.id] ?? LeadLook()), size: 18,
                                               flag: MascotFlag(status: row.status), dot: false, still: row.isStalled)
                                        .offset(x: x)
                                        .transition(motion.reduced ? .opacity : .opacity.combined(with: .offset(x: -x)))
                                }
                            }
                        }
                        .animation(state.expanded ? motion.reveal(index: 0) : motion.conceal, value: state.expanded)
                        .animation(motion.list, value: behind.map(\.id))
                    }
                // Shut, the bar's number is all there is. Open, the line under the bar says the
                // same in words, thirty points below: one of the two is enough.
                Group {
                switch bar {
                case .needsYou(let count, let working):
                    // The one number on the bar that asks for something: how many agents wait on
                    // the person, as a red badge. Nothing else on the bar is red.
                    BarBadge(count: count)
                        // And once more on every beat while the wait goes on.
                        .keyframeAnimator(initialValue: CGFloat(1), trigger: beats) { badge, scale in
                            badge.scaleEffect(scale)
                        } keyframes: { _ in
                            KeyframeTrack {
                                CubicKeyframe(motion.pulse, duration: 0.12)
                                SpringKeyframe(1, duration: 0.36, spring: .bouncy(duration: 0.3, extraBounce: 0.2))
                            }
                        }
                        // It swells three times as someone starts to wait, or dips and returns
                        // under Reduce Motion: the moment itself is marked, not only the state.
                        .keyframeAnimator(initialValue: Arrival(), trigger: arrivals) { badge, mark in
                            badge.scaleEffect(mark.scale).opacity(mark.opacity)
                        } keyframes: { _ in
                            // Six steps, each read from the motion's own list and at rest past
                            // its end: three swells, or one dip under Reduce Motion.
                            let swells = motion.arrivalSwells, dips = motion.arrivalDips
                            KeyframeTrack(\.scale) {
                                CubicKeyframe(Arrival.step(swells, 0), duration: 0.12)
                                SpringKeyframe(Arrival.step(swells, 1), duration: 0.36, spring: .bouncy(duration: 0.3, extraBounce: 0.2))
                                CubicKeyframe(Arrival.step(swells, 2), duration: 0.12)
                                SpringKeyframe(Arrival.step(swells, 3), duration: 0.36, spring: .bouncy(duration: 0.3, extraBounce: 0.2))
                                CubicKeyframe(Arrival.step(swells, 4), duration: 0.12)
                                SpringKeyframe(Arrival.step(swells, 5), duration: 0.36, spring: .bouncy(duration: 0.3, extraBounce: 0.2))
                            }
                            KeyframeTrack(\.opacity) {
                                CubicKeyframe(Arrival.step(dips, 0), duration: 0.12)
                                CubicKeyframe(Arrival.step(dips, 1), duration: 0.36)
                            }
                        }
                        // Alone: beside the mascot the wing has room for one number, and who waits
                        // comes before who works. Read out, those still at work are counted too.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: Format.summary(working: working, quiet: 0, needsYou: count)))
                case .working(let count):
                    Text(verbatim: "\(count)").bold().fixedSize()
                        .contentTransition(.numericText(value: Double(count)))
                        .animation(motion.list, value: count)
                        // Clear of the dot at the mascot's corner, which reaches past its frame.
                        .padding(.leading, 2)
                        .accessibilityLabel(Text(verbatim: Format.working(count)))
                case .quiet(let count):
                    // Dimmer than a working count: these are not moving, and may be waiting.
                    Text(verbatim: "\(count)").foregroundStyle(.white.opacity(0.6)).fixedSize()
                        .padding(.leading, 2)
                        .accessibilityLabel(Text(verbatim: "\(count) quiet"))
                case .idle:
                    EmptyView()
                }
                }
                .opacity(state.expanded ? 0 : 1)
                .animation(motion.reveal(index: 0), value: state.expanded)
                // Open, in the number's place: how many more there are than stand behind the
                // mascot. The line under the bar counts them all in words.
                .overlay(alignment: .leading) {
                    Text(verbatim: "+\(extra)").foregroundStyle(.white.opacity(0.6)).fixedSize()
                        .padding(.leading, 2)
                        .opacity(state.expanded && extra > 0 ? 1 : 0)
                        .animation(motion.reveal(index: 0), value: state.expanded)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                // While someone has waited a minute or more, how long the longest wait has run, in
                // the ring's place: the other wing is full. A wait outranks the limit, which the line
                // under the bar has in full. Gone with the panel open, as the number is.
                if let wait = AgentStore.longestWait(sessions), let text = Format.barWait(wait) {
                    Text(verbatim: text).bold().foregroundStyle(MascotFlag.red).fixedSize()
                        .opacity(state.expanded ? 0 : 1)
                        .animation(motion.reveal(index: 0), value: state.expanded)
                        .accessibilityLabel(Text(verbatim: Format.waitedAloud(wait)))
                } else if let ring = limits.display.ring {
                    // How much of the 5-hour limit is used, when that is known. Gone with the panel
                    // open, as the number is: the line under the bar has both limits in full.
                    LimitRingView(ring: ring)
                        .opacity(state.expanded ? 0 : 1)
                        .animation(motion.reveal(index: 0), value: state.expanded)
                }
            }
            // Five points from the left end: with the mascot, a gap of three and a count of two
            // digits that comes to 43 of the wing's 44, and nothing may run under the notch.
            .padding(.leading, 5)
            .padding(.trailing, 7)
            .frame(width: state.notchWidth + NotchGeometry.wing * 2)

            HStack(spacing: 2) {
                Spacer()
                // Asleep in the quiet hours, so that a silent night is not taken for a switch
                // that does nothing.
                let quiet = settings.sounds && sound.quiet(at: Date())
                // Only where a phone could answer for a session: the buttons below it are always there.
                if away.buttonShown {
                    AwayPill(on: away.mode.on) { away.toggleFromPanel() }
                }
                Button { settings.sounds.toggle() } label: {
                    Image(systemName: Format.soundSymbol(on: settings.sounds, quiet: quiet)).font(.system(size: 11))
                        .frame(width: 26, height: 26).contentShape(Rectangle()).hoverFill()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(settings.sounds ? 1 : 0.6))
                .help(Format.soundHelp(on: settings.sounds, quietUntil: quiet ? settings.quietUntil : nil))
                .accessibilityLabel(Text(verbatim: "Sounds"))
                .accessibilityValue(Text(verbatim: settings.sounds ? "On" : "Off"))
                // The panel closes when the pointer leaves, which is wrong for reading a long
                // request or keeping watch. The pin holds it open until it is clicked again.
                Button { state.pinned.toggle() } label: {
                    Image(systemName: state.pinned ? "pin.fill" : "pin").font(.system(size: 11))
                        .frame(width: 26, height: 26).contentShape(Rectangle()).hoverFill()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(state.pinned ? 1 : 0.6))
                .help(Format.pinHelp(pinned: state.pinned))
                .accessibilityLabel(Text(verbatim: "Keep the panel open"))
                .accessibilityValue(Text(verbatim: state.pinned ? "On" : "Off"))
                // History, beside the other pages. The token line at the end of the list opens it
                // too, but it reads as numbers rather than a button, and a long list scrolls it away.
                if settings.tokenUse {
                    Button { state.toggleHistory() } label: {
                        Image(systemName: "chart.bar.xaxis").font(.system(size: 11))
                            .frame(width: 26, height: 26).contentShape(Rectangle()).hoverFill()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(state.showingHistory ? 1 : 0.6))
                    .help(Format.historyHelp(showing: state.showingHistory))
                    .accessibilityLabel(Text(verbatim: Format.historyHelp(showing: state.showingHistory)))
                }
                // What the marks mean, beside the list they are on: the settings page that also
                // holds it takes the list's place.
                Button { state.toggleLegend() } label: {
                    Image(systemName: "questionmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26).contentShape(Rectangle()).hoverFill()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(state.showingLegend && !state.showingSettings ? 1 : 0.6))
                .help(Format.legendHelp(showing: state.showingLegend && !state.showingSettings))
                .accessibilityLabel(Text(verbatim: Format.legendHelp(showing: state.showingLegend && !state.showingSettings)))
                Button { state.showingSettings.toggle() } label: {
                    Image(systemName: "gearshape").frame(width: 26, height: 26)
                        .overlay(alignment: .topTrailing) { if updates.waiting != nil { UpdateDot().padding(4) } }
                        .contentShape(Rectangle()).hoverFill()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(state.showingSettings ? 1 : 0.6))
                .help(Format.gearHelp(showingSettings: state.showingSettings, update: updates.waiting))
                .accessibilityLabel(Text(verbatim: Format.gearHelp(showingSettings: state.showingSettings, update: updates.waiting)))
            }
            .padding(.trailing, 8)
            .modifier(Reveal(shown: state.expanded, index: 0, motion: motion, travels: false))
            .allowsHitTesting(state.expanded)

            // How the list is ordered, in the room the open panel has to the left of the bar.
            // Not over a page, which is no list.
            if grouped, !state.showingPage {
                HStack(spacing: 0) {
                    GroupingTabs(selection: $settings.grouping)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tabsWidth = $0 }
                    Spacer()
                }
                .padding(.leading, 8)
                .modifier(Reveal(shown: state.expanded, index: 0, motion: motion, travels: false))
                .allowsHitTesting(state.expanded)
            }
        }
        .frame(width: width, height: state.barHeight)
        .onChange(of: answers.pending.map(\.id)) { old, new in
            let fresh = Set(new).subtracting(old)
            guard state.expanded, !fresh.isEmpty else { return }
            // A turn later: the card has to be laid out before it is known to lie below the edge.
            DispatchQueue.main.async {
                let drawn = AgentStore.arrange(sessions, idle: settings.idleSessions, keeping: answers.settledSessions).cards
                if answerableBelow(drawn).contains(where: { fresh.contains($0.id) }) { bandBeats += 1 }
            }
        }
        .onChange(of: AgentStore.waiting(sessions)) { old, new in
            guard WaitWatch.arrived(from: old, to: new) else { return }
            // A turn later: the red count has to be on the bar before its mark can begin. Counted
            // in the same pass as the count first appearing, the mark never ran.
            DispatchQueue.main.async {
                // The wait may be over already: then there is nothing to mark.
                let count = AgentStore.barState(sessions).waiting
                guard count > 0 else { return }
                arrivals += 1
                arrived = Date()
                // And said, for someone who cannot see the bar: the app's own words alone.
                NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                     userInfo: [.announcement: Format.needsYou(count), .priority: NSAccessibilityPriorityLevel.high.rawValue])
                // Open under the pointer right now, it is seen as it happens. Pinned open, the
                // person may be anywhere.
                let drawn = AgentStore.arrange(sessions, idle: settings.idleSessions, keeping: answers.settledSessions)
                let past = AgentStore.waitingBelow(drawn.cards, cards: below, rows: belowRows)
                watch.arrived(looks: state.looks, lookingNow: state.expanded
                    && WaitWatch.looking(openFor: state.openedAt.map { Date().timeIntervalSince($0) }, pinned: state.pinned,
                                         inView: WaitWatch.inView(showingList: !state.showingPage, pastEdge: !past.isEmpty, grouping: settings.grouping, atTop: atTop)))
                // Pinned open with nobody at it, the list goes to whoever has started to wait:
                // past its edge they would wait unseen. Under the pointer it stays where it is.
                if state.expanded, state.pinned, !state.showingPage, !state.keyboard,
                   let row = past.first, let card = drawn.cards.first(where: { $0.rows.contains { $0.id == row.id } }) {
                    scrollTarget = ScrollTarget.to(row, on: card)
                }
            }
        }
        // While someone waits the bar beats again every few seconds, until the person has
        // opened the panel: then they have seen it, and it must not go on flashing at them. The
        // timer always runs and mostly does nothing, and never counts on top of an arrival's mark.
        .onReceive(beat) { _ in
            if bar.waiting > 0, !watch.seen(looks: state.looks), motion.beats(sinceArrival: Date().timeIntervalSince(arrived)) { beats += 1 }
            // The same tick carries the reminder, and the sound a locked screen held back.
            sound.beat(sessions, looks: state.looks)
            sound.limits(limits.display.runOut(now: Date()), known: limits.display.hasNumbers)
        }
        // What the list holds now, for the sounds. Its first reading too, even an empty one:
        // that is where they start from, and it makes none. And once as the bar appears: a
        // list read before the bar was first drawn would otherwise never be told.
        .onChange(of: sessions) { _, cards in listen(cards) }
        .onChange(of: store.loaded, initial: true) { _, _ in listen(sessions) }
        // Turned on, by the speaker or in the settings: the person hears what that means.
        // Turned off: quiet now, not after the clip playing.
        .onChange(of: settings.sounds) { _, on in
            if on { sound.sample(sessions, turnedOn: true) } else { sound.silence() }
        }
        // A new way for the crew to sound: the person hears it at once.
        .onChange(of: settings.soundStyle) { _, _ in
            if settings.sounds { sound.sample(sessions) }
        }
    }

    /// Sessions, or the settings in their place. Either way its height sizes the island.
    private func content(_ motion: Motion, viewport: CGFloat) -> some View {
        ScrollViewReader { reader in
            scroll(motion, viewport: viewport)
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(motion.list) {
                        switch target {
                        // To the mark on the card's top edge, and that a band's height down
                        // from the top: its first line then stands clear of the band a
                        // scrolled list has there.
                        case .card(let id): reader.scrollTo(ScrollTarget.above(id), anchor: ScrollTarget.clearOfBand(viewport: viewport))
                        case .top: reader.scrollTo(ScrollTarget.topID, anchor: .top)
                        case .shortcut: reader.scrollTo(ScrollTarget.shortcutID, anchor: .center)
                        // Its first line at the top, clear of the band: a card taller than the
                        // list used to be shown from its middle, with its name out of sight,
                        // and then from its very edge, with its name under the band.
                        case .selection(let id): reader.scrollTo(ScrollTarget.above(id), anchor: ScrollTarget.clearOfBand(viewport: viewport))
                        case .row(let id): reader.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.3))
                        // A third of the way down: the request whole, with its row still above it.
                        case .request(let id): reader.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.3))
                        case .end: reader.scrollTo(ScrollTarget.endID, anchor: .bottom)
                        }
                    }
                    // The list has moved under the pointer by the app's own doing: what is there
                    // now is not what was aimed at.
                    answers.noteLayoutChange()
                    scrollTarget = nil
                }
                .onChange(of: state.selected) { _, id in
                    guard let id else { return }
                    // On the first session the list stays at its very top: the line about the
                    // keys stands above that card, and must not be scrolled out by it.
                    let walked = AgentStore.arrange(sessions, idle: settings.idleSessions, keeping: answers.settledSessions).walked(idleExpanded: state.idleExpanded)
                    scrollTarget = id == walked.first?.id ? .top : .selection(id)
                    // And said, for someone who cannot see the ring arrive.
                    if let card = walked.first(where: { $0.id == id }) {
                        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                             userInfo: [.announcement: Format.chosen(card), .priority: NSAccessibilityPriorityLevel.high.rawValue])
                    }
                }
                // The legend stands at the head of the list, and each page starts from its top:
                // the list and the settings share one scroll.
                .onChange(of: state.showingLegend) { _, shown in
                    if shown { scrollTarget = .top }
                }
                .onChange(of: state.showingSettings) { _, _ in
                    scrollTarget = .top
                }
                // History too, and a level of it: each starts from its top.
                .onChange(of: state.showingHistory) { _, _ in
                    scrollTarget = .top
                }
                .onChange(of: state.historyPick.project) { _, _ in
                    scrollTarget = .top
                }
                .onChange(of: state.settingsTab) { _, _ in
                    scrollTarget = .top
                }
                // Every opening follows one rule. The list starts from its top, and if whoever
                // needs the person is not in view it goes there, and no further than it must:
                // never past a request that is all in view. Once the panel has grown, and before
                // the buttons take clicks. Opened by the shortcut, the ring is on that same
                // session and brings it into view itself.
                .onChange(of: state.opens) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard state.expanded, !state.showingPage, !state.keyboard else { return }
                        let found = AgentStore.arrange(sessions, idle: settings.idleSessions, keeping: answers.settledSessions).firstWaiting
                        let waiting = found.flatMap { found in
                            AgentStore.waitingBelow([found.card], cards: below, rows: belowRows).contains { $0.id == found.row.id } ? ScrollTarget.to(found.row, on: found.card) : nil
                        }
                        if let target = ScrollTarget.onOpening(spans: spans.byID, viewport: viewport, fade: fade, top: topFade, waitingBelow: waiting) { scrollTarget = target }
                    }
                }
                // Shut, the list goes back to its top, so that every opening starts from the
                // same place. Not a page: a pointer that strayed finds it as it was.
                .onChange(of: state.expanded) { _, open in
                    guard !open, !state.showingPage else { return }
                    // Once it has stayed shut, as above.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if !state.expanded, !state.showingPage { scrollTarget = .top }
                    }
                }
        }
    }

    private func scroll(_ motion: Motion, viewport: CGFloat) -> some View {
        ScrollView {
            Group {
                if state.showingSettings {
                    SettingsView(settings: settings, answers: answers, limits: limits, updates: updates,
                                 shortcutNote: state.shortcutTaken ? Format.shortcutTaken : nil, displays: state.displays,
                                 tab: $state.settingsTab) { state.showingSettings = false }
                } else if state.showingHistory {
                    HistoryPage(ledger: usage, pick: $state.historyPick) { state.showingHistory = false }
                } else {
                    sessions(motion, viewport: viewport)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.contentHeight = $0 }
            .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY <= viewport + 4 } action: { atEnd = $0 }
            .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY >= -4 } action: { atTop = $0 }
            // Where the bands lead when they have nothing to name.
            .overlay(alignment: .bottom) { Color.clear.frame(height: 1).id(ScrollTarget.endID) }
            .overlay(alignment: .top) { Color.clear.frame(height: 1).id(ScrollTarget.topID) }
        }
        // With a mouse attached the system gives the scroll bar its own strip, which narrows every
        // card; `.hidden` still allows that, `.never` does not. The fade at the bottom edge says
        // the list goes on.
        .scrollIndicators(.never)
    }

    private func sessions(_ motion: Motion, viewport: CGFloat) -> some View {
        let list = AgentStore.arrange(sessions, idle: settings.idleSessions, keeping: answers.settledSessions)
        let looks = AgentStore.looks(sessions)
        let putAway = AgentStore.putAway(answers.overlay(store.sessions), hidden: state.hidden)
        // Past eight sub-agents each takes one line.
        let compact = Format.oneLineRows(liveAgents: list.cards.reduce(0) { $0 + $1.liveAgents().count })
        // The line over each group's first card, when the list is grouped and there is more
        // than one session to group.
        let byProject = grouped && settings.grouping == .projects
        let headers: [String: String] = !grouped ? [:] : byProject
            ? AgentStore.projectHeaders(of: list.cards).mapValues(Format.projectHeader)
            : AgentStore.headers(of: list.cards, by: settings.grouping).mapValues(Format.groupHeader)
        // The lines under the list, which take room from it.
        let under = ListFit.under(idle: !list.folded.isEmpty, hidden: putAway.count, plain: [
            settings.tokenUse && usage.summary.map { !$0.isEmpty } ?? false, answers.pluginLost, updates.oldCopyLeft, updates.waiting != nil,
            // The line about the keys sits over the list, not under it, but takes as much room.
            state.keyboard,
        ].filter { $0 }.count)
        // Sessions drawn as one line, so the list fits the panel without a scroll.
        let folded = foldedRows(list, headers: headers, oneLineAgents: compact, under: under)
        let crew = CrewTree.snapshot(list.cards)
        let leftOut = folded.union(below).union(above)
        // A change in this very frame is already a packet on its way, before `.onChange` below
        // keeps it: the new row is hidden from its first frame, and the finished one held.
        let fresh = CrewTree.pulses(old: seen, new: crew, open: state.expanded, reduced: motion.reduced, leftOut: leftOut)
        return VStack(alignment: .leading, spacing: 10) {
            if away.mode.on {
                AwayBand().modifier(Reveal(shown: state.expanded, index: 0, motion: motion))
            }
            // Phone messages that did not go, whether or not the button shows.
            ForEach(desk.leftOver) { item in
                LeftOverRow(item: item) { desk.dismiss(item.id) }
                    .modifier(Reveal(shown: state.expanded, index: 0, motion: motion))
            }
            if state.introducing {
                notice(Format.intro(shortcut: settings.shortcut && !state.shortcutTaken ? settings.shortcutKey : nil), motion, dim: false, lines: 6)
            }
            if settings.shortcut, state.shortcutTaken {
                // Where it will be seen, and a click away from where it is put right.
                Button {
                    // The page the row is on.
                    state.settingsTab = .shortcuts
                    state.showingSettings = true
                    // To the row itself, once the page is there to scroll.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scrollTarget = .shortcut }
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: Format.shortcutTakenList).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "gearshape").font(.system(size: 9))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                    .hoverFill()
                    .padding(.horizontal, -6)
                }
                .buttonStyle(.plain)
                .modifier(Reveal(shown: state.expanded, index: 0, motion: motion))
            }
            if state.showingLegend {
                // Beside the list it explains.
                Legend(tab: $state.legendTab) { state.showingLegend = false }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .modifier(Reveal(shown: state.expanded, index: 0, motion: motion))
            }
            if state.keyboard {
                // Said while the keys work, and only then: what they do, and so what they do not.
                // One line whatever it says, so the cards under it do not move as the ring does.
                // What a chord answers is drawn on the buttons it fires.
                notice(Format.keysHint(app: list.walked(idleExpanded: state.idleExpanded).first { $0.id == state.selected }?.owner?.name), motion).lineLimit(1)
            }
            // While a plan limit has run out, the crew's sign over the list. It goes when the
            // numbers do: opening the panel fetches them again once they are a minute old.
            if let out = limits.display.runOut(now: Date()) {
                GoneFishin(out: out, now: Date())
                    .modifier(Reveal(shown: state.expanded, index: 0, motion: motion))
            }
            if let empty = Format.emptyState(loaded: store.loaded, rootMissing: store.rootMissing, isEmpty: list.cards.isEmpty && list.folded.isEmpty && putAway.isEmpty) {
                // A folder that is not there is something wrong, and as bright as every other such line.
                notice(empty, motion, dim: !store.rootMissing)
            }
            // With a hide button on any card, every card keeps its place for one: the columns
            // beside it then stand in line down the list.
            let anyHide = list.cards.contains { card in card.canHide && !answers.pending.contains { $0.ask.session == AnswerStore.sessionID(of: card) } }
            ForEach(Array(list.cards.enumerated()), id: \.element.id) { index, card in
                if let header = headers[card.id] {
                    // What the cards under it have in common, in the app's own word for it.
                    Text(verbatim: header).foregroundStyle(.white.opacity(0.6))
                        // Where the list goes to for the card under it: the line comes into
                        // view with its card, and is not left under the band at the top.
                        .overlay(alignment: .top) { Self.mark(above: card.id) }
                        .padding(.top, index == 0 ? 0 : 4)
                        .accessibilityAddTraits(.isHeader)
                        .modifier(Reveal(shown: state.expanded, index: index, motion: motion))
                        .transition(.opacity)
                }
                let asked = answers.pending.contains { $0.ask.session == AnswerStore.sessionID(of: card) }
                let hide: (() -> Void)? = card.canHide && !asked ? { state.hidden[card.id] = card.movedAt ?? Date() } : nil
                Group {
                    if folded.contains(card.id) {
                        CompactSessionRow(card: card, motion: motion, look: looks[card.main?.id ?? ""] ?? LeadLook(), hide: hide, reserveHide: anyHide)
                    } else {
                        SessionCardView(card: card, motion: motion, look: looks[card.main?.id ?? ""] ?? LeadLook(), showsApp: list.showsApps,
                                        underProject: byProject ? card.belongsTo : nil, asking: AnswerContext(
                            requests: { [answers] in answers.requests(forRow: $0, in: card) },
                            settled: { [answers] in answers.settled(forRow: $0, in: card) },
                            armsAt: { [answers, state] in answers.armsAt($0, panelOpenedAt: state.openedAt) },
                            inFullView: { NotchGeometry.isInFullView(minY: $0, maxY: $1, viewport: viewport, fade: fade, top: topFade) },
                            answer: { [answers, state] id, answer, clickAt in answers.answer(id, answer, clickAt: clickAt, panelOpenedAt: state.openedAt) },
                            placed: { [spans] id, view, span in
                                if let span { spans.place(id, by: view, at: span) } else { spans.forget(id, by: view) }
                            },
                            reveal: { scrollTarget = .request($0) },
                            moved: { [answers] in answers.noteMoved($0) },
                            hide: { [answers, state] id, clickAt in answers.hide(id, clickAt: clickAt, panelOpenedAt: state.openedAt) },
                            keyTarget: state.keyboard && state.selected == card.id ? answers.keyTarget(in: card)?.id : nil,
                            keyNote: keyNote
                        ), hide: hide,
                            moved: { [answers] in answers.noteLayoutChange() }, compact: compact, hintRow: list.hintRow,
                            // Whether each sub-agent's row starts past the bottom edge, for the band.
                            viewport: viewport, rowBelow: { row, below in
                                if below { belowRows.insert(row) } else { belowRows.remove(row) }
                            }, reserveHide: anyHide, showingDone: state.doneExpanded.contains(card.id),
                            toggleDone: { state.doneExpanded.formSymmetricDifference([card.id]) },
                            pulses: (pulses + fresh).filter { $0.card == card.id })
                    }
                }
                    .overlay { ring(on: card) }
                    .id(card.id)
                    .overlay(alignment: .top) {
                        // Under a group's line the mark is on the line.
                        if headers[card.id] == nil { Self.mark(above: card.id) }
                    }
                    // A card that leaves the list is neither below it nor above it.
                    .onDisappear {
                        below.remove(card.id)
                        above.remove(card.id)
                    }
                    // Whether this card's own row starts past the bottom edge or under the part of
                    // the band that lets nothing through, for the line that says what is below.
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY + 10 >= viewport - NotchGeometry.bandCover } action: { hidden in
                        if hidden { below.insert(card.id) } else { below.remove(card.id) }
                    }
                    // And whether all of it is past the top edge.
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY <= NotchGeometry.bandCover } action: { hidden in
                        if hidden { above.insert(card.id) } else { above.remove(card.id) }
                    }
                    // One folded row under another stands closer than cards do: 4 points, not 10.
                    // Out here, so the ring and the marks above keep the row's own frame.
                    .padding(.top, index > 0 && headers[card.id] == nil && folded.contains(card.id) && folded.contains(list.cards[index - 1].id) ? -6 : 0)
                    .modifier(Reveal(shown: state.expanded, index: index, motion: motion))
                    .transition(.opacity)
            }
            if !list.folded.isEmpty {
                IdleRow(sessions: list.folded, expanded: state.idleExpanded) { state.idleExpanded.toggle() }
                    .modifier(Reveal(shown: state.expanded, index: list.cards.count, motion: motion))
                if state.idleExpanded {
                    ForEach(list.folded) { card in
                        // Unfolded, the arrow keys walk these too, after the cards above. One
                        // line each while the list above has folded any.
                        Group {
                            if folded.isEmpty {
                                SessionCardView(card: card, motion: motion, look: looks[card.main?.id ?? ""] ?? LeadLook(), showsApp: list.showsApps, compact: compact)
                            } else {
                                CompactSessionRow(card: card, motion: motion, look: looks[card.main?.id ?? ""] ?? LeadLook(), reserveHide: anyHide)
                            }
                        }
                            .overlay { ring(on: card) }
                            .id(card.id)
                            .overlay(alignment: .top) { Self.mark(above: card.id) }
                            .padding(.top, !folded.isEmpty && card.id != list.folded.first?.id ? -6 : 0)
                            .transition(.opacity)
                    }
                }
            }
            if !putAway.isEmpty {
                // What the person put away is out of the list, the counts and the bar. It stays
                // named here, the one way back for a session that will not move by itself.
                HiddenRow(sessions: putAway) { for card in $0 { state.hidden[card.id] = nil } }
                    .modifier(Reveal(shown: state.expanded, index: list.cards.count + 1, motion: motion))
            }
            if settings.tokenUse, let summary = usage.summary, !summary.isEmpty {
                UsageLine(summary: summary) { state.openHistory() }
                    .modifier(Reveal(shown: state.expanded, index: list.cards.count + 2, motion: motion))
            }
            if answers.pluginLost {
                NoticeLine(text: Format.pluginLostLine, button: Format.pluginLostFix) {
                    // The page with the command, which now takes the old list out first.
                    state.settingsTab = .claudeCode
                    state.showingSettings = true
                }
                    .modifier(Reveal(shown: state.expanded, index: list.cards.count + 3, motion: motion))
            }
            if updates.oldCopyLeft {
                // To About, where the command is first.
                NoticeLine(text: Format.oldCopyLine, button: Format.pluginLostFix) {
                    state.settingsTab = .about
                    state.showingSettings = true
                }
                    .modifier(Reveal(shown: state.expanded, index: list.cards.count + 3, motion: motion))
            }
            if let version = updates.waiting {
                NoticeLine(text: Format.updateWaiting(version: version), button: Format.updateLook) { updates.show() }
                    .modifier(Reveal(shown: state.expanded, index: list.cards.count + 3, motion: motion))
            }

        }
        .padding(12)
        // Also as a card grows or closes up with its agents: what is under it moves with it, in
        // step, rather than jumping to where it ends up.
        .animation(motion.list, value: list.cards.map(\.id) + ["|"] + list.folded.map(\.id) + [state.idleExpanded ? "open" : "shut"] + headers.keys.sorted()
            + list.cards.flatMap { card in card.agents.map { card.id + "/" + $0.id + ($0.status == .done ? " done" : "") } }
            + (pulses + fresh).filter { $0.up && !$0.arrived }.map { $0.card + "/" + $0.agent + " up" })
        // h and d, from the keys, on the session they are on.
        // A key for the list: acted on once, here, as it is pressed, on the session the arrow
        // keys were on at that moment. Nothing of it is handed on or kept: a key that found
        // nothing to answer must never answer the request the arrows reach next.
        .onChange(of: state.keyed) { _, keyed in
            guard let keyed, state.keyboard else { return }
            if keyed.command == .unhide {
                for card in putAway { state.hidden[card.id] = nil }
                return
            }
            guard keyed.acts(on: state.selected, keyboard: state.keyboard), let card = list.cards.first(where: { $0.id == keyed.card }) else { return }
            switch keyed.command {
            case .allow, .deny, .option:
                let outcome = answers.answer(byKey: keyed.command, at: keyed.at, in: card, whole: { id in
                    spans.byID[id].map { NotchGeometry.isInFullView(minY: $0.lowerBound, maxY: $0.upperBound, viewport: viewport, fade: fade, top: topFade) } ?? false
                }, panelOpenedAt: state.openedAt)
                if case .refused(let id, let cut) = outcome {
                    // Said beside that request's buttons, and it is brought into view if it was cut.
                    keyNote = KeyNote(request: id, cut: cut, serial: keyed.serial)
                    if cut { scrollTarget = .request(id) }
                } else {
                    keyNote = nil
                }
            case .hide:
                guard card.canHide, !answers.pending.contains(where: { $0.ask.session == AnswerStore.sessionID(of: card) }) else { return }
                // The ring goes on to the next session, or back to the one before the last.
                let ids = list.cards.map(\.id)
                let index = ids.firstIndex(of: card.id) ?? 0
                state.selected = index + 1 < ids.count ? ids[index + 1] : index > 0 ? ids[index - 1] : nil
                state.hidden[card.id] = card.movedAt ?? Date()
            case .done:
                // A folded row shows no sub-agents to unfold.
                guard !folded.contains(card.id), !card.doneAgents().isEmpty else { return }
                state.doneExpanded.formSymmetricDifference([card.id])
                answers.noteLayoutChange()
            default:
                break
            }
        }
        // The note about a key that did not count is said for a moment and taken back.
        .task(id: keyNote?.serial) {
            guard keyNote != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { keyNote = nil }
        }
        // A sub-agent that starts or finishes sends a packet along its branch: only while the
        // panel is open and the card is drawn whole and in view. Nothing plays back on opening:
        // shut, the list is still drawn and keeps up with what it has seen.
        .onChange(of: crew, initial: true) { _, new in
            for pulse in CrewTree.pulses(old: seen, new: new, open: state.expanded, reduced: motion.reduced, leftOut: leftOut) {
                let id = pulse.id
                pulses.append(pulse)
                DispatchQueue.main.asyncAfter(deadline: .now() + CrewTree.run) {
                    if let i = pulses.firstIndex(where: { $0.id == id }) { pulses[i].arrived = true }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + CrewTree.run + CrewTree.flash) {
                    pulses.removeAll { $0.id == id }
                }
            }
            seen = new
        }
        // Away behind a page, it sees nothing: back, it starts from what is there then.
        .onDisappear { seen = [:] }
        // A session folding or unfolding moves every card under it.
        .onChange(of: folded) { _, _ in
            answers.noteLayoutChange()
        }
        // A hide button coming or going makes its line a little taller or shorter.
        .onChange(of: list.cards.filter(\.canHide).map(\.id)) { _, _ in
            answers.noteLayoutChange()
        }
        // The line about the keys comes and goes above every card.
        .onChange(of: state.keyboard) { _, _ in
            answers.noteLayoutChange()
        }
        // So do the first-launch words, the legend and the line about a shortcut that will not work.
        .onChange(of: [state.introducing, state.showingLegend, settings.shortcut && state.shortcutTaken]) { _, _ in
            answers.noteLayoutChange()
        }
        // The pages of the legend are not one height: turning one moves every card under it.
        .onChange(of: state.legendTab) { _, _ in
            answers.noteLayoutChange()
        }

        // Back from the settings the whole list is drawn afresh, where the settings stood a moment ago.
        .onAppear { answers.noteLayoutChange() }
    }

    /// The sessions to draw as one line: as few as it takes for the list to fit the panel.
    private func foldedRows(_ list: SessionList, headers: [String: String], oneLineAgents: Bool, under: CGFloat) -> Set<String> {
        // Less the list's padding and the lines under it.
        let room = NotchGeometry.listRoom(screen: state.screenFrame, barHeight: state.barHeight) - ListFit.padding - under
        let entries = list.cards.map { card in
            let session = AnswerStore.sessionID(of: card)
            return ListFit.Entry(
                id: card.id,
                full: ListFit.fullHeight(card, header: headers[card.id] != nil,
                                         requests: { answers.requests(forRow: $0, in: card).map { ListFit.requestHeight($0.ask.kind, hidden: $0.hidden) } },
                                         settled: { answers.settled(forRow: $0, in: card).count }, hintRow: list.hintRow,
                                         showingDone: state.doneExpanded.contains(card.id), oneLineAgents: oneLineAgents),
                row: ListFit.rowHeight(header: headers[card.id] != nil),
                // Asks something of the person, or has just been answered and shows how, or the
                // person has just opened its done agents.
                keepsFull: card.group == .needsYou || answers.pending.contains { $0.ask.session == session } || answers.settledSessions.contains(session)
                    || state.doneExpanded.contains(card.id),
                quiet: card.group == .quiet || card.group == .idle,
                header: headers[card.id] != nil,
                crew: !card.liveAgents().isEmpty)
        }
        return ListFit.compact(entries, room: room)
    }

    /// Where the arrow keys are. A ring and no more: it moves nothing. To a screen reader it is
    /// an element of its own on the card, which says so: as a picture alone it told a person
    /// who cannot see it nothing, and the keys answer a request on the session it is on.
    @ViewBuilder
    private func ring(on card: SessionCard) -> some View {
        if state.selected == card.id {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)
                // Words, read just before the card's own first words, which are its name.
                .accessibilityElement()
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(Text(verbatim: Format.chosenLabel))
        }
    }

    /// Where the list goes to for a card: a mark on its top edge, or on the top edge of the
    /// group's line over it. Nothing tall and nothing moved out of place: the scroll goes by
    /// where a mark is laid out, and one shifted up above the card by an alignment guide was
    /// taken to start at the card's own edge. `ScrollTarget.clearOfBand` leaves the room.
    private static func mark(above card: String) -> some View {
        Color.clear.frame(height: 0).id(ScrollTarget.above(card))
    }

    private func notice(_ text: String, _ motion: Motion, dim: Bool = true, lines: Int = 2) -> some View {
        Text(verbatim: text)
            .foregroundStyle(.white.opacity(dim ? 0.6 : 1))
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(Reveal(shown: state.expanded, index: 0, motion: motion))
    }
}

/// A key that was pressed to answer a request and did not count: which request, and why.
struct KeyNote: Equatable {
    let request: UUID
    /// Not all in view. Else it had just moved or arrived.
    let cut: Bool
    let serial: Int
}

/// Where the list has been asked to scroll.
enum ScrollTarget: Equatable {
    case card(String)
    /// The card the arrow keys have landed on.
    case selection(String)
    /// A sub-agent's row.
    case row(String)
    case request(UUID)
    case top
    case end
    /// The shortcut's row in the settings.
    case shortcut

    static let shortcutID = "agent-valley.shortcut"

    /// The id of the mark at the very top of the list's content.
    static let topID = "agent-valley.top"

    /// The id of the mark on the top edge of a card, or of the group's line over it.
    static func above(_ card: String) -> String {
        "agent-valley.above." + card
    }

    /// Where in a list `viewport` tall such a mark is brought to: as far down from the top as
    /// the band there is tall, and a little more. A scroll's anchor is a share of the list's
    /// height, and the mark has none of its own, so the share is all that places it.
    static func clearOfBand(viewport: CGFloat) -> UnitPoint {
        UnitPoint(x: 0.5, y: viewport > 0 ? min(1, (NotchGeometry.topBand + 4) / viewport) : 0)
    }

    /// Where a row is: its card when it is the session's own row, the row itself when a
    /// sub-agent's, which can sit far down a tall card.
    static func to(_ row: AgentRow, on card: SessionCard) -> ScrollTarget {
        card.main?.id == row.id ? .card(card.id) : .row(row.id)
    }

    /// Where an opening leads, or nil when nothing has to move. With a request all in view
    /// there is something to answer where it is. Else to the first request the edge cuts, and
    /// else to `waitingBelow`: the first row that waits, when it starts below the edge.
    static func onOpening(spans: [UUID: ClosedRange<CGFloat>], viewport: CGFloat, fade: CGFloat, top: CGFloat = 0, waitingBelow: ScrollTarget?) -> ScrollTarget? {
        if spans.values.contains(where: { NotchGeometry.isInFullView(minY: $0.lowerBound, maxY: $0.upperBound, viewport: viewport, fade: fade, top: top) }) { return nil }
        return NotchGeometry.firstCutBelow(spans, viewport: viewport, fade: fade).map { .request($0) } ?? waitingBelow
    }

    /// The id of the mark at the very end of the list's content.
    static let endID = "agent-valley.end"
}

/// Where each request sits in the list. A class, so writing to it redraws nothing.
final class RequestSpans {
    private(set) var byID: [UUID: ClosedRange<CGFloat>] = [:]
    /// The view that last said where each request is.
    private var owners: [UUID: UUID] = [:]

    func place(_ request: UUID, by view: UUID, at span: ClosedRange<CGFloat>) {
        byID[request] = span
        owners[request] = view
    }

    /// A request can pass from one row to another: the view leaving must not wipe out where the
    /// one arriving has just put it.
    func forget(_ request: UUID, by view: UUID) {
        guard owners[request] == view else { return }
        byID[request] = nil
        owners[request] = nil
    }
}

/// How the red count looks at one instant of the mark it makes when someone starts to wait.
private struct Arrival {
    var scale: CGFloat = 1
    var opacity: Double = 1

    /// The value at one step of a list of them, and rest once the list has run out.
    static func step<Value: ExpressibleByIntegerLiteral>(_ values: [Value], _ index: Int) -> Value {
        index < values.count ? values[index] : 1
    }
}

/// Fades its content in after its turn in the queue, settling from just above its place.
/// Leaving is a quick fade with no travel.
/// The island's outline: round at the bottom, and at the top flaring out by `shoulder` on each
/// side in a curve that runs into the edge of the screen. The flare lies outside the rectangle.
struct IslandShape: Shape {
    var radius: CGFloat
    var shoulder: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, shoulder) }
        set { (radius, shoulder) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + shoulder, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: shoulder)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX - shoulder, y: rect.minY), radius: shoulder)
        path.closeSubpath()
        return path
    }
}

private struct Reveal: ViewModifier {
    let shown: Bool
    let index: Int
    let motion: Motion
    var travels = true

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || !travels ? 0 : motion.travel)
            .animation(shown ? motion.reveal(index: index) : motion.conceal, value: shown)
    }
}

/// Sessions where every agent has finished, folded into one line. Click to list them.
struct IdleRow: View {
    let sessions: [SessionCard]
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                FoldMark(open: expanded)
                Text(verbatim: Format.idle(sessions.count)).bold().foregroundStyle(.white)
                // verbatim: project names come from transcripts and must never be read as Markdown.
                Text(verbatim: Format.names(sessions)).help(Text(verbatim: Format.names(sessions)))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.14)))
            .contentShape(Rectangle())
            .hoverFill(radius: 10)
        }
        .buttonStyle(.plain)
        .help(expanded ? "Hide idle sessions" : "Show idle sessions")
        .accessibilityValue(Text(verbatim: expanded ? "Shown" : "Hidden"))
    }
}

/// What marks a line that unfolds. A triangle: a chevron beside it read the same as the ">" that
/// begins every step.
struct FoldMark: View {
    let open: Bool

    var body: some View {
        Image(systemName: "arrowtriangle.right.fill")
            .font(.system(size: 7))
            .rotationEffect(.degrees(open ? 90 : 0))
    }
}

/// The sessions the person has put away, a line each. A click brings that one back; with
/// several, one more line brings back all of them.
struct HiddenRow: View {
    let sessions: [SessionCard]
    let restore: ([SessionCard]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sessions.count > 1 {
                line(sessions, word: "Show all", spoken: "Show all hidden sessions") {
                    Text(verbatim: Format.hidden(sessions.count)).bold().foregroundStyle(.white)
                }
            }
            ForEach(sessions) { card in
                line([card], word: "Show", spoken: "Show hidden session", value: card.name, status: card) {
                    if sessions.count == 1 { Text(verbatim: Format.hidden(1)).bold().foregroundStyle(.white) }
                    // verbatim: titles come from transcripts and must never be read as Markdown.
                    Text(verbatim: card.name).help(Text(verbatim: card.name))
                }
            }
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.14)))
    }

    /// One line that brings sessions back: what they are, then the word for the click.
    private func line<Label: View>(_ cards: [SessionCard], word: String, spoken: String, value: String? = nil, status: SessionCard? = nil,
                                   @ViewBuilder label: () -> Label) -> some View {
        Button { restore(cards) } label: {
            HStack(spacing: 8) {
                // The eye marks the row once, on its first line; the lines under it stand in line with the words.
                Image(systemName: "eye.slash").font(.system(size: 9, weight: .bold))
                    .opacity(cards.count == sessions.count ? 1 : 0)
                label()
                Spacer(minLength: 8)
                // What was put away may be waiting: its state stays in sight, where a card's
                // own would be, and red as anywhere.
                if let status, let text = Format.cardStatus(status) {
                    Text(verbatim: text).fixedSize()
                        .foregroundStyle(status.main?.status == .needsYou ? MascotFlag.red : Color.white.opacity(0.6))
                    WaitBadge(row: status.main)
                }
                Text(verbatim: word).foregroundStyle(.white).fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .contentShape(Rectangle())
            .hoverFill(radius: 8)
        }
        .buttonStyle(.plain)
        // No label of the app's own with a name inside it: the titles are text from
        // transcripts, and read out as they are.
        .accessibilityLabel(Text(verbatim: spoken))
        .accessibilityValue(Text(verbatim: value ?? ""))
    }
}

/// The panel is worked with the pointer alone, so what can be clicked answers the pointer.
private struct GoesTo: ViewModifier {
    let owner: OwnerApp?
    @Environment(\.goTo) private var goTo

    func body(content: Content) -> some View {
        if let owner {
            // Room around the row for the fill, taken back so the row stays in line.
            content
                .padding(4)
                .contentShape(Rectangle())
                .onTapGesture { goTo(owner) }
                .hoverFill()
                .padding(-4)
        } else {
            content
        }
    }
}

private struct HoverFill: ViewModifier {
    let radius: CGFloat
    /// For something already filled white: a lighter fill behind it would not show, so it darkens.
    let darkens: Bool
    @State private var over = false
    /// A button that can't be pressed shows nothing under the pointer.
    @Environment(\.isEnabled) private var enabled
    private var hovering: Bool { over && enabled }

    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(hovering && !darkens ? 0.1 : 0), in: RoundedRectangle(cornerRadius: radius))
            .overlay(Color.black.opacity(hovering && darkens ? 0.18 : 0).clipShape(RoundedRectangle(cornerRadius: radius)).allowsHitTesting(false))
            .onHover { over = $0 }
    }
}

extension View {
    func hoverFill(radius: CGFloat = 6, darkens: Bool = false) -> some View {
        modifier(HoverFill(radius: radius, darkens: darkens))
    }

    /// The whole of a session's row, or a sub-agent's, leaves for the app the session runs in on
    /// a click, as the session's name does. The buttons in it keep their own clicks. Nothing
    /// when the app is not known.
    func goesTo(_ owner: OwnerApp?) -> some View {
        modifier(GoesTo(owner: owner))
    }

    /// How a button with words on it looks in the panel: outlined, or filled for the one way
    /// on from here, to the session's app. An answer is never filled: neither is the one to pick.
    func panelButton(filled: Bool = false) -> some View {
        foregroundStyle(filled ? Color.black : Color.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(filled ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(filled ? 0 : 0.35)))
            .contentShape(Rectangle())
            .hoverFill(darkens: filled)
    }
}

/// One bar an hour, as tall as that hour's tokens out beside the busiest hour's.
struct UsageBars: View {
    let hourly: [Int]
    static let full: CGFloat = 10

    /// How tall each bar stands. An hour with none keeps a mark, so every place shows; one
    /// with any stands clear of that mark.
    static func heights(_ hourly: [Int], full: CGFloat = full) -> [CGFloat] {
        let most = hourly.max() ?? 0
        return hourly.map { $0 > 0 && most > 0 ? max(2, full * CGFloat($0) / CGFloat(most)) : 1 }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(Array(Self.heights(hourly).enumerated()), id: \.offset) { _, height in
                Rectangle().frame(width: 3, height: height)
            }
        }
        .frame(height: Self.full, alignment: .bottom)
    }
}

/// Away in the top bar: a grey outline when off, Away's yellow when on.
struct AwayPill: View {
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Text(verbatim: "Away").font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .foregroundStyle(on ? Color.black : .white.opacity(0.6))
                .background(Capsule().fill(on ? Color(red: 1, green: 0.839, blue: 0.039) : .clear))
                .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.35), lineWidth: 1))
                .frame(height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? Format.awayHelpOn : Format.awayHelpOff)
        .accessibilityLabel(Text(verbatim: "Away"))
        .accessibilityValue(Text(verbatim: on ? "On" : "Off"))
    }
}

/// Said under the summary line while Away is on.
struct AwayBand: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: Format.awayBandTitle).bold()
            Text(verbatim: Format.awayBandNote)
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(red: 1, green: 0.839, blue: 0.039), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// A phone message that did not reach its session: kept to copy, then dismissed. Plain text, never Markdown.
struct LeftOverRow: View {
    let item: LeftOver
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: Format.leftOverTitle).foregroundStyle(.white.opacity(0.6))
            Text(verbatim: item.text).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                }
                Button("Dismiss", action: dismiss)
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

/// One line at the foot of the list about the app itself, and the one thing to do about it. The
/// whole line is the button: it is the only thing on it to press.
struct NoticeLine: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(verbatim: text).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: button).fixedSize()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
            .contentShape(Rectangle())
            .hoverFill(radius: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(text) \(button)"))
    }
}

/// How many tokens went in and came out, and a bar for each of the last twelve hours. The
/// last line of the list, and dim: what the agents used, under who they are.
struct UsageLine: View {
    let summary: UsageSummary
    /// Opens the History page.
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                // With the word in front where there is room for it, and the mark that says the
                // line leads somewhere. Numbers in the millions leave room for neither.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { Text(verbatim: Format.usageLine(summary)).fixedSize(); mark }
                    HStack(spacing: 8) { Text(verbatim: Format.usageLine(summary, named: false)).fixedSize(); mark }
                    Text(verbatim: Format.usageLine(summary, named: false))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                UsageBars(hourly: summary.hourly)
            }
            .foregroundStyle(.white.opacity(0.6))
            .contentShape(Rectangle())
            .hoverFill(radius: 5)
        }
        .buttonStyle(.plain)
        .help(Format.usageHelp(summary))
        .accessibilityLabel(Text(verbatim: Format.usageHelp(summary)))
        .accessibilityHint(Text(verbatim: Format.opensHistory))
    }

    private var mark: some View {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
    }
}

/// The two ways to order the list, side by side: the one in use is filled.
struct GroupingTabs: View {
    @Binding var selection: Grouping

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Grouping.allCases, id: \.self) { grouping in
                Button { selection = grouping } label: {
                    Text(verbatim: grouping.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(grouping == selection ? Color.black : Color.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(grouping == selection ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                        .hoverFill(radius: 5, darkens: grouping == selection)
                }
                .buttonStyle(.plain)
                .help(Format.groupingHelp(grouping))
                .accessibilityLabel(Text(verbatim: Format.groupingHelp(grouping)))
                .accessibilityAddTraits(grouping == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
    }
}

/// How many agents wait on the person, as the bar shows it beside the mascot.
/// Sixteen points and little more: with the mascot it has to end before the notch begins. Two
/// digits get less padding for the same reason. The number is never shortened: a count cut to
/// "…" says nothing. Black on the red: about 6 to 1, where white managed 3.4.
struct BarBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: "\(count)").bold().foregroundStyle(.black).fixedSize()
            .padding(.horizontal, count > 9 ? 1 : 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(MascotFlag.red, in: Capsule())
    }
}

/// How long a row has waited on the person, beside its "needs you": black on red, as the bar's
/// count is. One column on every card, so the longest wait can be found at a glance. Nothing
/// for a row that is not waiting.
struct WaitBadge: View {
    let row: AgentRow?

    var body: some View {
        if let row, let text = Format.waited(row) {
            Text(verbatim: text).bold().foregroundStyle(.black).fixedSize()
                .padding(.horizontal, 5)
                .background(MascotFlag.red, in: Capsule())
                .accessibilityLabel(Text(verbatim: Format.waitedAloud(row.quietFor)))
        }
    }
}

/// App icons by where the app is on disk, each asked of the system once. Main thread only.
enum AppIcons {
    private static var known: [String: NSImage] = [:]

    static func icon(of bundle: URL) -> NSImage {
        if let icon = known[bundle.path] { return icon }
        var icon = NSWorkspace.shared.icon(forFile: bundle.path)
        // The system keeps many drawings of one icon, and those made for a screen that is not
        // Retina have a white rim as wide as the mark inside. A 12 point icon on a Retina screen
        // is 24 pixels, which is one of them. So only the 128 pixel drawing is kept, whose rim
        // is a hairline, and it is scaled to whatever size is asked for.
        var box = NSRect(x: 0, y: 0, width: 128, height: 128)
        if let fine = icon.cgImage(forProposedRect: &box, context: nil, hints: nil) {
            icon = NSImage(cgImage: fine, size: box.size)
        }
        known[bundle.path] = icon
        return icon
    }
}

/// A click that leaves for a session's app. The panel puts its rule about when such a click
/// counts in here; anywhere else it simply goes. The keys do not come this way: Return goes
/// to the session the ring is on, wherever that card stands.
private struct GoToKey: EnvironmentKey {
    static let defaultValue: (OwnerApp) -> Void = { $0.bringForward() }
}

extension EnvironmentValues {
    var goTo: (OwnerApp) -> Void {
        get { self[GoToKey.self] }
        set { self[GoToKey.self] = newValue }
    }
    /// To the page where the plugin goes in, while requests cannot be answered here. Nil once they can.
    var setUpAnswers: (() -> Void)? {
        get { self[SetUpAnswersKey.self] }
        set { self[SetUpAnswersKey.self] = newValue }
    }
}

private struct SetUpAnswersKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

/// The app a session runs in, by its icon and its name. A click goes there, as a click on the
/// session's name does.
struct AppBadge: View {
    let owner: OwnerApp
    /// What the session is called: every badge of one app says the same words otherwise.
    let session: String
    @Environment(\.goTo) private var goTo

    var body: some View {
        Button { goTo(owner) } label: {
            // The app's name is the first thing on the line to give way: the icon alone
            // still says where the session runs.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    icon
                    Text(verbatim: owner.name).foregroundStyle(.white.opacity(0.6)).lineLimit(1).fixedSize()
                }
                icon
            }
            // Takes clicks over 24 points, and stands in the line as the icon alone does: the
            // room is taken back, so the line is no wider or taller for it.
            .padding(.horizontal, 4)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
            .hoverFill()
            .padding(.horizontal, -4)
            .padding(.vertical, -5)
        }
        .buttonStyle(.plain)
        .help(Format.goTo(app: owner.name))
        .accessibilityLabel(Text(verbatim: Format.goTo(app: owner.name)))
        // The session's name is a transcript's text: read out as it is, not inside the app's words.
        .accessibilityValue(Text(verbatim: session))
    }

    /// An app icon is a plate with a clear margin round it. Drawn at 20 points the plate fills
    /// 16, which is the room it takes in the line: the margin hangs outside.
    private var icon: some View {
        Image(nsImage: AppIcons.icon(of: owner.bundle)).resizable()
            .frame(width: 20, height: 20)
            .frame(width: 16, height: 16)
    }
}

/// A card's type and spacing, in one place. Three sizes: a session's name leads, what is beside
/// the point of a row stands a size under the rest. Three gaps: lines that belong together sit
/// close, what a row is doing stands apart from what it is, and rows stand apart from each other.
enum CardStyle {
    static let name = Font.system(size: 13, weight: .bold, design: .monospaced)
    /// Where it runs, and which model: looked up, not read on every glance.
    static let aside = Font.system(size: 11, design: .monospaced)
    static let line: CGFloat = 3
    static let block: CGFloat = 6
    static let row: CGFloat = 10
    /// Around the rows, between them and the card's edge.
    static let inset: CGFloat = 12
    /// What stands under a row's lines, in from the card's edge by the mascot and its gap.
    static let underMascot: CGFloat = 20 + 8
}

/// A session's branch behind the mark branches go by, and a second mark where the session runs
/// in a worktree of its own. A short branch is never cut. A long one keeps room for both its
/// ends: squeezed to a single letter it said nothing, and showed no sign of being cut.
struct BranchLabel: View {
    let card: SessionCard

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            if card.branch.count <= 10 {
                Text(card.branch).fixedSize()
            } else {
                Text(card.branch).truncationMode(.middle).frame(minWidth: 70, alignment: .leading)
            }
            if card.worktree {
                Image(systemName: "square.on.square").font(.system(size: 9, weight: .semibold))
                    .accessibilityLabel(Text(verbatim: "worktree"))
            }
        }
        .foregroundStyle(.white.opacity(0.6))
    }
}

struct SessionCardView: View {
    let card: SessionCard
    let motion: Motion
    /// How the session's own agent looks: whoever `Roster` seated in it.
    var look = LeadLook()
    /// The list holds more than one app, so the card names its own.
    var showsApp = true
    /// The project whose line the card stands under, when the list is grouped by project.
    var underProject: String?
    /// Requests waiting on this card's rows, when answering from the panel is on.
    var asking: AnswerContext?
    /// Puts the session away until it moves again. nil when there is nothing to put away.
    var hide: (() -> Void)?
    /// Told when the card changes height by the person's own click, which the list cannot see.
    var moved: (() -> Void)?
    /// One line for each sub-agent in place of two.
    var compact = false
    /// The row that carries the list's one line explaining "quiet".
    var hintRow: String?
    /// How tall the list's window is, and who to tell whether a sub-agent's row starts below it.
    var viewport: CGFloat = .infinity
    var rowBelow: ((String, Bool) -> Void)?
    /// Keeps the hide button's place on a card that has none, so the columns stand in line.
    var reserveHide = false
    /// Whether the finished subagents are listed, and what a click on their line does.
    var showingDone = false
    var toggleDone: () -> Void = {}
    /// The packets running along this card's branches.
    var pulses: [CrewPulse] = []
    @Environment(\.goTo) private var goTo

    /// The requests under one row, each with its buttons.
    @ViewBuilder
    static func requests(_ asking: AnswerContext?, row: String?, title: String, owner: OwnerApp? = nil) -> some View {
        if let asking, let row {
            ForEach(asking.requests(row)) { item in
                AnswerView(item: item, title: title, armsAt: asking.armsAt(item), inFullView: asking.inFullView,
                           answer: { asking.answer(item.id, $0, $1) }, placed: { asking.placed(item.id, $0, $1) }, reveal: { asking.reveal(item.id) }, owner: owner,
                           isKeyTarget: asking.keyTarget == item.id, keyRefused: asking.keyNote?.request == item.id ? asking.keyNote?.cut : nil,
                           moved: { asking.moved(item.id) }, hide: { asking.hide(item.id, $0) })
                    // The app's own id for the request, so the list can scroll to it.
                    .id(item.id)
            }
            ForEach(asking.settled(row)) { item in
                // What became of a request, for a moment where it stood: on a click it used to
                // vanish, the same as when the terminal won.
                HStack(spacing: 6) {
                    // An answer that never arrived is the one outcome that asks for something: bright.
                    Text(verbatim: Format.settled(item.outcome)).foregroundStyle(.white.opacity(item.outcome == .notTaken ? 1 : 0.8))
                    // The request's own text, as bright as its values were: not the app's words.
                    if let detail = Format.settledDetail(item.outcome, tool: item.tool) { Text(verbatim: detail) }
                }
                .padding(.top, 4)
            }
        }
    }

    /// What the session is called: its own title, or its folder until Claude Code has named it.
    /// The one thing on a card set a size up, and alone at its end of the line: it is cut
    /// last. The status and the model are never cut.
    private var name: some View {
        // verbatim: the title is written by a model from the conversation and is untrusted.
        // A cut name can be read whole by resting the pointer on it.
        Text(verbatim: card.name).font(CardStyle.name).help(Text(verbatim: card.name))
    }

    /// Where the session runs, under its name and a size down: the folder when the name is
    /// not the folder already, the branch, and at the far end the app. What gives way when the
    /// line is full, in order: the app's name, then the branch, then the folder.
    @ViewBuilder
    private var place: some View {
        let namesFolder = Format.namesFolder(card, under: underProject)
        if namesFolder || !card.branch.isEmpty || (showsApp && card.owner != nil) {
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    if namesFolder {
                        // Two sessions in one folder differ by title; the folder and branch say where they run.
                        HStack(spacing: 4) {
                            Image(systemName: "folder").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
                            Text(card.project)
                        }
                        .layoutPriority(1)
                    }
                    if !card.branch.isEmpty { BranchLabel(card: card) }
                }
                .help(Text(verbatim: Format.place(card)))
                .layoutPriority(2)
                Spacer(minLength: 0)
                // In sight without resting the pointer on anything. Given room before the gap
                // is: with room to spare it shows the app's name.
                if showsApp, let owner = card.owner {
                    AppBadge(owner: owner, session: card.name).layoutPriority(1)
                }
                // Under the model's name, which stands clear of the hide button's place.
                if hide != nil || reserveHide { Color.clear.frame(width: 18, height: 1) }
            }
            .font(CardStyle.aside)
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    /// The card's first line: what the session is called at one end, how it is doing and
    /// which model at the other.
    private var heading: some View {
        HStack(spacing: 8) {
            if let owner = card.owner {
                // A click on the name goes to the app the session runs in, as one anywhere on
                // its row does. Kept a button for the keys and for VoiceOver.
                Button { goTo(owner) } label: {
                    HStack(spacing: 8) {
                        name
                        // The name leaves for another app: an arrow out, which says
                        // where to. What folds and unfolds has a triangle.
                        Image(systemName: "arrow.up.forward").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                            .help(Format.goTo(app: owner.name))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(verbatim: Format.goTo(app: owner.name)))
            } else {
                name
            }
            Spacer(minLength: 12)
            // How it is doing, then which model: two sizes, set on one baseline.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CardStatusText(card: card)
                WaitBadge(row: card.main)
                if let main = card.main {
                    Text(main.info.model).font(CardStyle.aside).foregroundStyle(.white.opacity(0.6))
                }
            }
            .fixedSize()
            if let hide {
                HideButton(name: card.name, action: hide)
            } else if reserveHide {
                // Its width only: the line is no taller for it.
                Color.clear.frame(width: 18, height: 1)
            }
        }
    }

    var body: some View {
        // A finished agent with the outcome of a request under it keeps its row until the
        // line has gone: folded away, the line would go with it.
        // So does one that just finished while its packet runs up its branch to the lead.
        let running = Set(pulses.filter { $0.up && !$0.arrived }.map(\.agent))
        let holding = Set(card.agents.filter { !(asking?.settled($0.id).isEmpty ?? true) }.map(\.id)).union(running)
        let flash = pulses.contains { $0.up && $0.arrived }
        let live = card.liveAgents(holding: holding)
        let finished = card.doneAgents(holding: holding)
        // The rows a line runs to from the lead, top to bottom, and the ones that wait on the person.
        // The finished ones hang off the envelope, not the lead: they are what it holds.
        let branches = live.map(\.id) + (finished.isEmpty ? [] : ["done"])
        let hot = Set(live.filter { CrewTree.hot($0, requests: asking?.requests($0.id).count ?? 0) }.map(\.id))
        // A new one shows once the packet running down reaches it; the lead lights up as one gets back.
        // One that waits on the person shows at once: its request must not be answered unseen.
        let coming = Set(pulses.filter { !$0.up && !$0.arrived }.map(\.agent)).subtracting(hot)
        VStack(alignment: .leading, spacing: compact ? CardStyle.block : CardStyle.row) {
            VStack(alignment: .leading, spacing: CardStyle.block) {
                // The main agent's row is built like a subagent's: mascot, then its lines under one another.
                HStack(alignment: .top, spacing: 8) {
                    Self.leadMascot(card, look: look, size: 20)
                        .brightness(flash ? 0.35 : 0)
                        .animation(.easeOut(duration: 0.15), value: flash)
                        .anchorPreference(key: CrewAnchors.self, value: .bounds) { ["lead": $0] }
                    VStack(alignment: .leading, spacing: CardStyle.block) {
                        // What it is and where it runs read as one: the place hugs the name, and
                        // what the session is doing stands apart below.
                        VStack(alignment: .leading, spacing: CardStyle.line) {
                            heading
                            place
                        }
                        // What it left running, whether or not its turn is over: a dev server
                        // runs on while Claude edits.
                        if !card.jobs.isEmpty { JobList(jobs: card.jobs, reserveHide: hide != nil || reserveHide) }
                        // No step line above a request: the request says what is asked, in full, and
                        // the step would repeat it or name something older.
                        if let main = card.main, main.status != .done, asking?.requests(main.id).isEmpty ?? true,
                           let line = Format.stepLine(main.step) {
                            HStack(spacing: 6) {
                                // What a waiting agent asks is why the person is here: all of it,
                                // on up to three lines, and as bright as the name. Only a question
                                // it wrote down: a wait Claude Code merely reports leaves the last
                                // step as it was, a step. It is given the same three lines, and
                                // shown by what it runs: a command cut at the card's edge was no
                                // answer to "what does it want to run".
                                // A question is not a step: without the mark that begins one.
                                Text(verbatim: main.asksInWords ? main.step : line)
                                    .lineLimit(main.status == .needsYou ? 3 : 1)
                                    .fixedSize(horizontal: false, vertical: true)
                                    // A cut step can be read whole by resting the pointer on it.
                                    .help(Text(verbatim: main.step))
                            }
                            .foregroundStyle(main.asksInWords ? Color.white : Color.white.opacity(0.8))
                        }
                        if let main = card.main, hintRow == main.id {
                            Text(verbatim: Format.quietHint(main: true, calledBusy: main.calledBusy)).foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .goesTo(card.owner)
                // Under the row's lines, out of the part a click leaves by: a click that misses Allow
                // must not take the person to another app.
                Group {
                    Self.requests(asking, row: card.main?.id, title: card.name, owner: card.owner)
                    // Not beside requests: one that cannot be allowed here leads there itself,
                    // and one that can is answered here.
                    if let main = card.main, main.status == .needsYou, asking?.requests(main.id).isEmpty ?? true {
                        // To answer in its terminal is the one thing the panel asks of the person.
                        WayToAnswer(owner: card.owner)
                    }
                }
                .padding(.leading, CardStyle.underMascot)
            }
            ForEach(live) { row in
                AgentRowView(row: row, asking: asking, hint: hintRow == row.id, compact: compact, reserveHide: hide != nil || reserveHide, owner: card.owner)
                    // Kept in place while hidden: its branch is drawn to where it stands.
                    .opacity(coming.contains(row.id) ? 0 : 1)
                    .animation(.easeOut(duration: 0.15), value: coming.contains(row.id))
                    .padding(.leading, CrewTree.indent)
                    // So the list can scroll to the row itself.
                    .id(row.id)
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY >= viewport - NotchGeometry.bandCover } action: { rowBelow?(row.id, $0) }
                    .onDisappear { rowBelow?(row.id, false) }
                    // Gone quickly as it finishes: a slow fade showed under the row moving up into its place.
                    .transition(.asymmetric(insertion: motion.rowEntrance, removal: .opacity.animation(.easeOut(duration: 0.1))))
            }
            if !finished.isEmpty {
                DoneRow(agents: finished, expanded: showingDone) {
                    toggleDone()
                    // The rows that unfold push down the cards below, and their answer buttons with them.
                    moved?()
                }
                .padding(.leading, CrewTree.indent)
                // In once the rows over it have moved up: in at once, it showed through the last of them.
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.15).delay(0.2)), removal: .opacity))
                if showingDone {
                    ForEach(finished) { row in
                        AgentRowView(row: row, compact: compact, reserveHide: hide != nil || reserveHide, owner: card.owner)
                            .padding(.leading, CrewTree.indent * 2).transition(.opacity)
                    }
                }
            }
        }
        .padding(CardStyle.inset)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlayPreferenceValue(CrewAnchors.self) { anchors in
            CrewTreeView(anchors: anchors, order: branches, hot: hot, pulses: pulses)
            if showingDone { CrewTreeView(anchors: anchors, root: "done", order: finished.map(\.id), hot: []) }
        }
        // Rows settle in as agents start, and the card closes up as they finish: also once a
        // packet has run up from one.
        .animation(motion.list, value: card.agents.map { $0.id + ($0.status == .done ? " done" : "") } + running.sorted())
    }
}

/// What a full card and a folded row both draw of the session.
extension SessionCardView {
    /// The session's own agent. Awake while agents it started work on: asleep over working rows
    /// read as a finished session. Still once every row called busy has gone silent: nothing
    /// here is known to move.
    static func leadMascot(_ card: SessionCard, look: LeadLook, size: CGFloat) -> MascotView {
        MascotView(status: card.workingAfterMain > 0 ? .working : card.main?.status ?? .done, kind: .lead(look), size: size,
                   flag: card.main.flatMap { MascotFlag(status: $0.status) },
                   still: card.rows.filter { $0.status == .working }.allSatisfy(\.isStalled),
                   // Its own turn over while its helpers work: on the phone to them.
                   activity: card.main?.activity ?? (card.workingAfterMain > 0 ? .calling : nil))
    }

    /// How the session is doing. Red where the person is waited on, as on the bar and the mascot.
    struct CardStatusText: View {
        let card: SessionCard

        var body: some View {
            if let label = Format.cardStatus(card) {
                // The jobs' count is no length of time: no tip, rather than one that says it is.
                let jobs = !card.jobs.isEmpty && label == Format.jobsRunning(card.jobs)
                // Red where the person is waited on, as on the bar and the mascot.
                Text(verbatim: label).fontWeight(card.main?.status == .needsYou ? .bold : .regular)
                    .foregroundStyle(card.main?.status == .needsYou ? MascotFlag.red : Format.runningClock(card) ? .white.opacity(0.6) : .white)
                    .help(Text(verbatim: jobs ? "" : Format.timeHelp))
            }
        }
    }

    /// For a session that was closed with a question up, or has stalled: it would otherwise
    /// keep the bar flagged for up to an hour.
    struct HideButton: View {
        let name: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                // Takes clicks over 24 points and stands in the line as 18. The
                // struck eye of the hidden row: an x read as closing the session.
                Image(systemName: "eye.slash").font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .hoverFill()
                    .padding(-3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .help("Hide until it does something again")
            // The title is a transcript's text: read out as it is, not inside the app's sentence.
            .accessibilityLabel(Text(verbatim: "Hide until it does something again"))
            .accessibilityValue(Text(verbatim: name))
        }
    }
}

/// Under a row that waits on the person with no request to answer here: where to answer it. A
/// button to the app its terminal runs in when that is known, and words when it is not: a
/// question with nothing under it was a dead end.
struct WayToAnswer: View {
    let owner: OwnerApp?
    @Environment(\.goTo) private var goTo
    @Environment(\.setUpAnswers) private var setUp

    /// Words only where there is no button: the row already says "needs you", and the button names the app.
    static func words(appKnown: Bool) -> String? {
        appKnown ? nil : Format.terminalOnly
    }

    var body: some View {
        if let words = Self.words(appKnown: owner != nil) {
            Text(verbatim: words).foregroundStyle(.white.opacity(0.6))
        }
        if owner != nil || setUp != nil {
            HStack(spacing: 8) {
                if let owner {
                    // Filled, as the one thing to do now.
                    Button { goTo(owner) } label: {
                        Text(verbatim: Format.goTo(app: owner.name)).panelButton(filled: true)
                    }
                    .buttonStyle(.plain)
                }
                if let setUp {
                    // Outlined: it is for the next request, not this one.
                    Button(action: setUp) {
                        Text(verbatim: Format.answerHereNextTime).panelButton()
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: Format.answerHereNextTimeHelp))
                    .accessibilityHint(Text(verbatim: Format.answerHereNextTimeHelp))
                }
            }
            .padding(.top, 4)
        }
    }
}

/// The jobs a session left running, a line each, oldest on top: the newest three, then how many
/// more. Looked at once a second, for the clocks.
struct JobList: View {
    let jobs: [BackgroundJob]
    var reserveHide = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: CardStyle.line) {
                ForEach(jobs.suffix(3)) { job in
                    let long = job.isLong(now: context.date)
                    // Half an hour in, likely left running on purpose: dimmed, as a quiet agent is.
                    // Once: the screen stops and dims itself, as on the bar.
                    let dim = long ? 0.5 : 1
                    // verbatim: what a job does is the model's own words, never Markdown.
                    let line = Format.jobLine(job)
                    HStack(spacing: 6) {
                        Group {
                            switch job.kind {
                            case .shell: JobScreen(size: 14, still: long)
                            case .monitor: JobEye(size: 14).opacity(dim)
                            }
                        }
                        .frame(width: 14, height: 14)
                        Text(verbatim: line).lineLimit(1).help(Text(verbatim: line)).opacity(dim)
                        Spacer(minLength: 8)
                        // Whole, as an agent row's time is: a long name gives way first.
                        Text(verbatim: Format.jobTime(job, now: context.date)).monospacedDigit().opacity(dim).fixedSize()
                    }
                    // One thing for VoiceOver: the time alone said nothing of which job.
                    .accessibilityElement(children: .combine)
                }
                if jobs.count > 3 { Text(verbatim: Format.moreJobs(jobs.count - 3)) }
            }
            .font(CardStyle.aside)
            .foregroundStyle(.white.opacity(0.8))
            // The clocks in line with the model's name, which keeps a place for the hide button.
            .padding(.trailing, reserveHide ? 8 + 18 : 0)
        }
    }
}

/// A card's finished subagents in one line. Click to list them.
struct DoneRow: View {
    let agents: [AgentRow]
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                // The anchor on the envelope itself, so the line ends just short of it.
                DoneEnvelope()
                    .anchorPreference(key: CrewAnchors.self, value: .bounds) { ["done": $0] }
                    .frame(width: 20)
                Text(verbatim: Format.done(agents.count)).foregroundStyle(.white.opacity(0.8))
                // verbatim: task names come from transcripts and must never be read as Markdown.
                let names = agents.map { Format.rowTitle(task: $0.info.task, type: $0.info.type) }.joined(separator: " · ")
                Text(verbatim: names).help(Text(verbatim: names))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.6))
            // "1 done" turns into "2 done" at once: faded one into the other, the two showed on top of each other.
            .contentTransition(.identity)
            // As tall as the other lines that take a click.
            .frame(minHeight: 22)
            .contentShape(Rectangle())
            .hoverFill()
        }
        .buttonStyle(.plain)
        .help(expanded ? "Hide done agents" : "Show done agents")
        .accessibilityValue(Text(verbatim: expanded ? "Shown" : "Hidden"))
    }
}

struct AgentRowView: View {
    let row: AgentRow
    var asking: AnswerContext?
    /// Whether this row carries the card's one line explaining "quiet".
    var hint = false
    /// One line in place of two. A row that asks something keeps both: its question is not cut.
    var compact = false
    /// The session's own row keeps a place for a hide button: this row's columns stand under its.
    var reserveHide = false
    /// The app the session runs in, for a request that has to be answered there.
    var owner: OwnerApp?

    var body: some View {
        let done = row.status == .done
        let extras = Format.rowExtras(task: row.info.task, type: row.info.type)
        let title = Format.rowTitle(task: row.info.task, type: row.info.type)
        // A request under the row says what is asked, in full: the step would repeat it or name something older.
        let asked = !(asking?.requests(row.id).isEmpty ?? true)
        let oneLine = compact && !asked && !row.asksInWords
        VStack(alignment: .leading, spacing: CardStyle.block) {
            HStack(alignment: .top, spacing: 8) {
                MascotView(status: row.status, kind: MascotKind(type: row.info.type), size: oneLine ? 14 : 20,
                           flag: MascotFlag(status: row.status), still: row.isStalled, activity: row.activity)
                    // The anchor on the mascot itself, so the line ends just short of a small one too.
                    .anchorPreference(key: CrewAnchors.self, value: .bounds) { [row.id: $0] }
                    .frame(width: 20)
                    // The person stands for the type; resting the pointer on it says which.
                    // verbatim: the type is a transcript's text.
                    .help(Text(verbatim: row.info.type))
                VStack(alignment: .leading, spacing: CardStyle.block) {
                    VStack(alignment: .leading, spacing: CardStyle.line) {
                        // The same two columns as the session's own row: how long or which state, then which model.
                        HStack(spacing: 8) {
                            // verbatim: transcript text is untrusted and must never be read as Markdown or a link.
                            if oneLine {
                                // The name first and whole while there is room: it is what tells
                                // the rows apart. The step keeps a little, and takes what is left.
                                Text(verbatim: title).help(Text(verbatim: title)).layoutPriority(1)
                                if !done, row.info.steps > 0 {
                                    step(extras: "", counted: false).foregroundStyle(.white.opacity(0.6)).frame(minWidth: 96, alignment: .leading)
                                }
                            } else {
                                Text(verbatim: title).help(Text(verbatim: title))
                            }
                            Spacer(minLength: 12)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(verbatim: Format.rowTime(row.status, elapsed: row.elapsed, quietFor: row.quietFor))
                                    .fontWeight(row.status == .needsYou ? .bold : .regular)
                                    .foregroundStyle(row.status == .needsYou ? MascotFlag.red : row.status == .working && Format.lastMoved(row.status, silentFor: row.quietFor) == nil ? .white.opacity(0.6) : .white)
                                    .help(Format.timeHelp)
                                WaitBadge(row: row)
                                // Dim on every row, as on the session's own. Coloured only where it
                                // differed from the session's, the rule could not be read off the screen.
                                Text(verbatim: row.info.model).font(CardStyle.aside).foregroundStyle(.white.opacity(0.6))
                            }
                            .fixedSize()
                            // In line with the session's own row, which keeps a place for its hide button.
                            if reserveHide { Color.clear.frame(width: 18, height: 1) }
                        }
                        // What it is doing and how far along. The step is the one thing here that differs
                        // from row to row, so it is the last thing cut: the type and the tokens go first, whole.
                        if !oneLine {
                            Group {
                                if done || row.info.steps == 0 || asked {
                                    // Always a second line, so a row keeps its height as its first step arrives.
                                    Text(verbatim: extras.isEmpty ? " " : extras)
                                } else if row.asksInWords {
                                    // What it asks is why the person is here: all of it, on up to three
                                    // lines, and as bright as the name.
                                    // A question is not a step: without the mark that begins one.
                                    Text(verbatim: row.step).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                        .foregroundStyle(.white)
                                        .help(Text(verbatim: row.step))
                                } else {
                                    ViewThatFits(in: .horizontal) {
                                        step(extras: extras)
                                        step(extras: "")
                                    }
                                }
                            }
                            .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    // Read out as one thing: what it is, how it is doing, which model, the step. The
                    // buttons under it stay their own.
                    .accessibilityElement(children: .combine)
                    if hint {
                        Text(verbatim: Format.quietHint(main: false, calledBusy: row.calledBusy)).foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // A sub-agent runs in its session's terminal: a click on its row goes there too.
            .goesTo(owner)
            Group {
                SessionCardView.requests(asking, row: row.id, title: title, owner: owner)
                if row.status == .needsYou, !asked {
                    // Under the row that asks, not under the session's own far above it.
                    WayToAnswer(owner: owner)
                }
            }
            .padding(.leading, CardStyle.underMascot)
        }
        // One level of dimming only: stacked on the 0.6 above, anything lower fails to read.
        .opacity(done ? 0.8 : 1)
    }

    /// The step, how many there have been and, for a row gone silent, since when. With room to
    /// spare, the extras stand at the far end.
    private func step(extras: String, counted: Bool = true) -> some View {
        HStack(spacing: 6) {
            // A cut step can be read whole by resting the pointer on it. A tier above what
            // stands beside it: what the agent is doing is what the row is for.
            Text(verbatim: "> \(row.step)").foregroundStyle(.white.opacity(0.8)).help(Text(verbatim: row.step))
            if counted { Text(verbatim: "· \(Format.steps(row.info.steps))").fixedSize().help(Format.stepsHelp) }
            if !extras.isEmpty {
                Spacer(minLength: 12)
                Text(verbatim: extras).fixedSize().help(Format.extrasHelp)
                // Under the model's name, which stands clear of the hide button's place.
                if reserveHide { Color.clear.frame(width: 18, height: 1) }
            }
        }
    }
}
