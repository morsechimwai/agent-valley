import Foundation

/// What to do with sessions where every agent has finished.
enum IdleSessions: String, CaseIterable, Identifiable {
    case fold, hide, show

    var id: String { rawValue }
    /// Read after the setting's name, each says what it does. Words of the setting's own:
    /// "Hide" and "Show" are what a card's own button and the hidden row do. What is stored
    /// keeps its old names.
    var label: String {
        switch self {
        case .fold: return "In one line"
        // Not "Left out": read by one for whom English is a second language as "left" and "out".
        case .hide: return "Not listed"
        case .show: return "As cards"
        }
    }
}

/// The letter that goes with Control, Option and Command to open the panel. More than one to
/// pick from: another app can hold a chord already, and that app cannot be named.
enum ShortcutKey: String, CaseIterable {
    case a, n, k

    var letter: String { rawValue.uppercased() }

    /// The key's code on an ANSI keyboard, as the hot-key API takes it.
    var keyCode: UInt32 {
        switch self {
        case .a: return 0
        case .n: return 45
        case .k: return 40
        }
    }
}

/// How the sessions are listed.
enum Grouping: String, CaseIterable {
    /// By project, each project's sessions together and newest first: the order holds still
    /// while agents work. Saved as "all", the one list it grew out of.
    case projects = "all"
    /// By what they are doing, with those that wait on the person first.
    case status

    /// The word on its tab. "ALL", not "PROJECTS": every session is in it, each under its
    /// project's line, and the longer word leaves the tabs no room beside a 14-inch notch.
    var label: String { self == .projects ? "ALL" : "STATUS" }
}

/// How the crew sounds: talking, its stings alone for a meeting or a shared screen, or the
/// Glass and Pop macOS has always had.
enum SoundStyle: String, CaseIterable {
    case crew, stings, chimes

    var title: String {
        switch self {
        case .crew: return "Crew talks"
        case .stings: return "Crew, no talking"
        case .chimes: return "Chimes"
        }
    }
}

/// A display the bar can be put on, by the id macOS keeps for it across restarts and plugging
/// in, and the name System Settings shows for it.
struct DisplayChoice: Hashable {
    let id: String
    let name: String

    /// The display with a notch, or the main one when none has it.
    static let automatic = DisplayChoice(id: "", name: "Automatic")
}

/// The app's own preferences. The only place that reads and writes UserDefaults.
final class Settings: ObservableObject {
    static let keepFinishedChoices = [1, 5, 10, 30]
    /// Minutes between reminders that an agent still waits; 0 for none.
    static let remindChoices = [0, 1, 2, 3, 5]

    @Published var planLimits: Bool {
        didSet { defaults.set(planLimits, forKey: Key.planLimits) }
    }

    /// Whether the app listens for the plugin's hook so prompts can be answered from the panel.
    @Published var answers: Bool {
        didSet { defaults.set(answers, forKey: Key.answers) }
    }

    @Published var idleSessions: IdleSessions {
        didSet { defaults.set(idleSessions.rawValue, forKey: Key.idleSessions) }
    }

    @Published var keepFinishedMinutes: Int {
        didSet { defaults.set(keepFinishedMinutes, forKey: Key.keepFinishedMinutes) }
    }

    /// Whether the shortcut that opens the panel from any app is registered.
    @Published var shortcut: Bool {
        didSet { defaults.set(shortcut, forKey: Key.shortcut) }
    }

    /// Which chord the shortcut is.
    @Published var shortcutKey: ShortcutKey {
        didSet { defaults.set(shortcutKey.rawValue, forKey: Key.shortcutKey) }
    }


    /// Whether the app makes any sound at all. On from the start: the crew talking is half of
    /// what the app is, and one switch turns it off. Stored only once the person flips it, so
    /// whoever never did hears the crew after an update too.
    @Published var sounds: Bool {
        didSet { defaults.set(sounds, forKey: Key.sounds) }
    }

    /// A sound when an agent starts to wait on the person.
    @Published var soundNeedsYou: Bool {
        didSet { defaults.set(soundNeedsYou, forKey: Key.soundNeedsYou) }
    }

    /// A sound when a session ends a turn.
    @Published var soundFinished: Bool {
        didSet { defaults.set(soundFinished, forKey: Key.soundFinished) }
    }

    /// How the crew sounds.
    @Published var soundStyle: SoundStyle {
        didSet { defaults.set(soundStyle.rawValue, forKey: Key.soundStyle) }
    }

    /// The crew's scene when a plan limit runs out and when it is back.
    @Published var soundScenes: Bool {
        didSet { defaults.set(soundScenes, forKey: Key.soundScenes) }
    }

    /// Minutes between reminders while an agent still waits unseen; 0 for none.
    @Published var remindMinutes: Int {
        didSet { defaults.set(remindMinutes, forKey: Key.remindMinutes) }
    }

    /// Whether the hours from `quietFrom` up to `quietUntil` are silent.
    @Published var quietHours: Bool {
        didSet { defaults.set(quietHours, forKey: Key.quietHours) }
    }

    /// The hour of the day the silence begins, 0 to 23.
    @Published var quietFrom: Int {
        didSet { defaults.set(quietFrom, forKey: Key.quietFrom) }
    }

    /// The hour of the day it ends, 0 to 23.
    @Published var quietUntil: Int {
        didSet { defaults.set(quietUntil, forKey: Key.quietUntil) }
    }

    /// Whether a click that goes to a session's app also asks its terminal for the session's
    /// own tab. Off from the start: it tells another app what to do, and macOS asks the
    /// person before it lets that happen.
    @Published var goToTab: Bool {
        didSet { defaults.set(goToTab, forKey: Key.goToTab) }
    }

    /// Which of the two ways the list is in.
    @Published var grouping: Grouping {
        didSet { defaults.set(grouping.rawValue, forKey: Key.grouping) }
    }

    /// Whether the panel says how many tokens were used. On from the start: it is counted
    /// from Claude Code's transcripts, as the list is, with no network and no Keychain. It
    /// does read more of them than the list does: every one written in the last day.
    @Published var tokenUse: Bool {
        didSet { defaults.set(tokenUse, forKey: Key.tokenUse) }
    }

    /// The id of the display the bar is on, or Automatic's empty one. Asked for in issue #1, by
    /// someone whose MacBook is the second screen beside a bigger one.
    @Published var display: String {
        didSet { defaults.set(display, forKey: Key.display) }
    }

    /// Whether a release sends its one anonymous count a day (DailyCount). On from the start,
    /// the owner's pick: a count that waits to be turned on counts almost nobody.
    @Published var dailyCount: Bool {
        didSet { defaults.set(dailyCount, forKey: Key.dailyCount) }
    }

    /// When this Mac's count last went out; nil before the first one.
    var countedAt: Date? {
        get { defaults.object(forKey: Key.countedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.countedAt) }
    }

    private let defaults: UserDefaults

    /// True until `markLaunched`: the app has never run on this Mac.
    var isFirstLaunch: Bool { !defaults.bool(forKey: Key.launched) }

    func markLaunched() {
        defaults.set(true, forKey: Key.launched)
    }

    /// Where the app stood when it last asked macOS to open it at login: macOS keeps the item
    /// by that path.
    var loginItemPath: String? {
        get { defaults.string(forKey: Key.loginItemPath) }
        set { defaults.set(newValue, forKey: Key.loginItemPath) }
    }

    /// Anything the store holds that this version does not understand reads as the default.
    /// Plan limits starts off: it reads the Keychain and uses the network, so it is opted into.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        planLimits = defaults.object(forKey: Key.planLimits) as? Bool ?? false
        answers = defaults.object(forKey: Key.answers) as? Bool ?? false
        // On from the start: a way in that nobody knows of helps nobody.
        shortcut = defaults.object(forKey: Key.shortcut) as? Bool ?? true
        shortcutKey = ShortcutKey(rawValue: defaults.string(forKey: Key.shortcutKey) ?? "") ?? .a
        idleSessions = IdleSessions(rawValue: defaults.string(forKey: Key.idleSessions) ?? "") ?? .fold
        let minutes = defaults.integer(forKey: Key.keepFinishedMinutes)
        keepFinishedMinutes = Self.keepFinishedChoices.contains(minutes) ? minutes : 10
        sounds = defaults.object(forKey: Key.sounds) as? Bool ?? true
        soundNeedsYou = defaults.object(forKey: Key.soundNeedsYou) as? Bool ?? true
        soundFinished = defaults.object(forKey: Key.soundFinished) as? Bool ?? true
        soundScenes = defaults.object(forKey: Key.soundScenes) as? Bool ?? true
        soundStyle = SoundStyle(rawValue: defaults.string(forKey: Key.soundStyle) ?? "") ?? .crew
        let remind = defaults.object(forKey: Key.remindMinutes) as? Int ?? 0
        remindMinutes = Self.remindChoices.contains(remind) ? remind : 0
        quietHours = defaults.object(forKey: Key.quietHours) as? Bool ?? false
        quietFrom = Self.hour(defaults.object(forKey: Key.quietFrom), or: 22)
        quietUntil = Self.hour(defaults.object(forKey: Key.quietUntil), or: 8)
        goToTab = defaults.object(forKey: Key.goToTab) as? Bool ?? false
        grouping = Grouping(rawValue: defaults.string(forKey: Key.grouping) ?? "") ?? .projects
        tokenUse = defaults.object(forKey: Key.tokenUse) as? Bool ?? true
        display = defaults.string(forKey: Key.display) ?? DisplayChoice.automatic.id
        dailyCount = defaults.object(forKey: Key.dailyCount) as? Bool ?? true
    }

    /// A stored hour of the day, or the default when it is missing or is not one. Read as an
    /// object: read as an integer, a missing value and midnight are both 0.
    private static func hour(_ stored: Any?, or fallback: Int) -> Int {
        guard let hour = stored as? Int, (0...23).contains(hour) else { return fallback }
        return hour
    }

    private enum Key {
        static let planLimits = "planLimits"
        static let answers = "answers"
        static let idleSessions = "idleSessions"
        static let keepFinishedMinutes = "keepFinishedMinutes"
        static let launched = "launched"
        static let shortcut = "shortcut"
        static let shortcutKey = "shortcutKey"
        static let sounds = "sounds"
        static let soundNeedsYou = "soundNeedsYou"
        static let soundFinished = "soundFinished"
        static let soundStyle = "soundStyle"
        static let soundScenes = "soundScenes"
        static let remindMinutes = "remindMinutes"
        static let quietHours = "quietHours"
        static let quietFrom = "quietFrom"
        static let quietUntil = "quietUntil"
        static let goToTab = "goToTab"
        static let grouping = "grouping"
        static let tokenUse = "tokenUse"
        static let display = "display"
        static let loginItemPath = "loginItemPath"
        static let dailyCount = "dailyCount"
        static let countedAt = "countedAt"
    }
}
