import ServiceManagement
import XCTest
@testable import AgentValley

extension XCTestCase {
    /// Settings of this test's own, gone when it ends. Kept at a path in a temporary folder, not
    /// in ~/Library/Preferences: there `removePersistentDomain` left an empty file for every test,
    /// and a file deleted after it came back, written late by the preferences daemon.
    func throwawayDefaults() -> UserDefaults {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-valley-tests-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = folder.appendingPathComponent("defaults").path
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        return defaults
    }
}

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = throwawayDefaults()
    }

    // Plan limits reads the Keychain and uses the network, so a new install starts with it off.
    func testDefaults() {
        let settings = Settings(defaults: defaults)
        XCTAssertFalse(settings.planLimits)
        XCTAssertEqual(settings.idleSessions, .fold)
        XCTAssertEqual(settings.keepFinishedMinutes, 10)
    }

    func testChangesSurviveARestart() {
        let settings = Settings(defaults: defaults)
        settings.planLimits = false
        settings.idleSessions = .hide
        settings.keepFinishedMinutes = 30

        let reopened = Settings(defaults: defaults)
        XCTAssertFalse(reopened.planLimits)
        XCTAssertEqual(reopened.idleSessions, .hide)
        XCTAssertEqual(reopened.keepFinishedMinutes, 30)
    }

    // Values written by another version of the app, or by hand.
    func testUnknownStoredValuesFallBackToDefaults() {
        defaults.set("sideways", forKey: "idleSessions")
        defaults.set(7, forKey: "keepFinishedMinutes")
        defaults.set("yes", forKey: "planLimits")

        let settings = Settings(defaults: defaults)
        XCTAssertFalse(settings.planLimits)
        XCTAssertEqual(settings.idleSessions, .fold)
        XCTAssertEqual(settings.keepFinishedMinutes, 10)
    }

    // Someone who already had the limits on keeps them after the default changed.
    func testAStoredChoiceToShowPlanLimitsIsKept() {
        defaults.set(true, forKey: "planLimits")
        XCTAssertTrue(Settings(defaults: defaults).planLimits)
    }

    // Answering from the notch opens a socket, so it is opted into like the plan limits.
    func testAnswersStartOffAndRememberTheChoice() {
        XCTAssertFalse(Settings(defaults: defaults).answers)
        Settings(defaults: defaults).answers = true
        XCTAssertTrue(Settings(defaults: defaults).answers)
        defaults.set("yes", forKey: "answers")
        XCTAssertFalse(Settings(defaults: defaults).answers)
    }

    // Crew names are on from the start, like the sounds; the choice to turn them off is kept.
    func testCrewNamesStartOnAndRememberTheChoice() {
        XCTAssertTrue(Settings(defaults: defaults).crewNames)
        Settings(defaults: defaults).crewNames = false
        XCTAssertFalse(Settings(defaults: defaults).crewNames)
    }

    // The crew talks from the start; one switch turns it off.
    func testSoundsStartOnWithBothMomentsReady() {
        let settings = Settings(defaults: defaults)
        XCTAssertTrue(settings.sounds)
        XCTAssertTrue(settings.soundNeedsYou)
        XCTAssertTrue(settings.soundFinished)
        XCTAssertEqual(settings.remindMinutes, 0)
        XCTAssertFalse(settings.quietHours)
        XCTAssertEqual(settings.quietFrom, 22)
        XCTAssertEqual(settings.quietUntil, 8)
        XCTAssertEqual(Settings.remindChoices, [0, 1, 2, 3, 5])
    }

    // Midnight is hour 0: a stored 0 is a choice, not a missing value.
    func testSoundChoicesSurviveARestart() {
        let settings = Settings(defaults: defaults)
        settings.sounds = true
        settings.soundNeedsYou = false
        settings.soundFinished = false
        settings.remindMinutes = 3
        settings.quietHours = true
        settings.quietFrom = 0
        settings.quietUntil = 23

        let reopened = Settings(defaults: defaults)
        XCTAssertTrue(reopened.sounds)
        XCTAssertFalse(reopened.soundNeedsYou)
        XCTAssertFalse(reopened.soundFinished)
        XCTAssertEqual(reopened.remindMinutes, 3)
        XCTAssertTrue(reopened.quietHours)
        XCTAssertEqual(reopened.quietFrom, 0)
        XCTAssertEqual(reopened.quietUntil, 23)
    }

    // Written by another version of the app, or by hand.
    func testSoundValuesOutOfRangeFallBackToDefaults() {
        defaults.set("loud", forKey: "sounds")
        defaults.set(4, forKey: "remindMinutes")
        defaults.set(24, forKey: "quietFrom")
        defaults.set(-1, forKey: "quietUntil")

        let settings = Settings(defaults: defaults)
        XCTAssertTrue(settings.sounds)
        XCTAssertEqual(settings.remindMinutes, 0)
        XCTAssertEqual(settings.quietFrom, 22)
        XCTAssertEqual(settings.quietUntil, 8)

        defaults.set("late", forKey: "quietFrom")
        XCTAssertEqual(Settings(defaults: defaults).quietFrom, 22)
    }

    func testSoundScenesDefaultsToOnAndPersists() {
        XCTAssertTrue(Settings(defaults: defaults).soundScenes)
        Settings(defaults: defaults).soundScenes = false
        XCTAssertFalse(Settings(defaults: defaults).soundScenes)
    }

    // The crew talks unless the person picks otherwise; anything else stored reads as talking.
    func testSoundStyleDefaultsToCrewAndPersists() {
        XCTAssertEqual(Settings(defaults: defaults).soundStyle, .crew)
        Settings(defaults: defaults).soundStyle = .chimes
        XCTAssertEqual(Settings(defaults: defaults).soundStyle, .chimes)
        defaults.set("bogus", forKey: "soundStyle")
        XCTAssertEqual(Settings(defaults: defaults).soundStyle, .crew)
        XCTAssertEqual(SoundStyle.allCases.map(\.title), ["Crew talks", "Crew, no talking", "Chimes"])
    }

    // Telling another app what to do is asked for, like everything else that reaches outside.
    func testGoingToASessionsTabStartsOffAndRemembersTheChoice() {
        XCTAssertFalse(Settings(defaults: defaults).goToTab)
        Settings(defaults: defaults).goToTab = true
        XCTAssertTrue(Settings(defaults: defaults).goToTab)
        defaults.set("yes", forKey: "goToTab")
        XCTAssertFalse(Settings(defaults: defaults).goToTab)
    }

    // By project is the order that holds still while agents work: grouping by status is asked for.
    // What was saved as the one list before projects came reads as by project.
    func testTheListStartsByProjectAndRemembersTheChoice() {
        XCTAssertEqual(Settings(defaults: defaults).grouping, .projects)
        Settings(defaults: defaults).grouping = .status
        XCTAssertEqual(Settings(defaults: defaults).grouping, .status)
        defaults.set("agent", forKey: "grouping")
        XCTAssertEqual(Settings(defaults: defaults).grouping, .projects)
        defaults.set("all", forKey: "grouping")
        XCTAssertEqual(Settings(defaults: defaults).grouping, .projects)
        XCTAssertEqual(Grouping.allCases.map(\.label), ["ALL", "STATUS"])
    }

    // Counted from Claude Code's transcripts, as the list is: no network and no Keychain, so it starts on.
    func testTokenUseStartsOnAndRemembersTheChoice() {
        XCTAssertTrue(Settings(defaults: defaults).tokenUse)
        Settings(defaults: defaults).tokenUse = false
        XCTAssertFalse(Settings(defaults: defaults).tokenUse)
        defaults.set("no", forKey: "tokenUse")
        XCTAssertTrue(Settings(defaults: defaults).tokenUse)
    }

    func testTheFirstLaunchIsReportedOnce() {
        let settings = Settings(defaults: defaults)
        XCTAssertTrue(settings.isFirstLaunch)
        settings.markLaunched()
        XCTAssertFalse(Settings(defaults: defaults).isFirstLaunch)
    }

    func testLoginItemMessages() {
        let failure = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        XCTAssertEqual(LoginItem.message(wanted: true, status: .notRegistered, error: failure), "Could not enable: Operation not permitted")
        XCTAssertEqual(LoginItem.message(wanted: false, status: .enabled, error: failure), "Could not disable: Operation not permitted")
        // Switched off by hand in System Settings: registering succeeds but macOS will not run it.
        // By the name the app goes by, which is not settled: not one written into the sentence.
        XCTAssertEqual(LoginItem.message(wanted: true, status: .requiresApproval, error: nil, appName: "Notchwatch"), "Allow Notchwatch in System Settings > General > Login Items")
        XCTAssertEqual(LoginItem.message(wanted: true, status: .requiresApproval, error: nil, appName: nil), "Allow this app in System Settings > General > Login Items")
        XCTAssertNil(LoginItem.message(wanted: true, status: .enabled, error: nil))
        XCTAssertNil(LoginItem.message(wanted: false, status: .notRegistered, error: nil))
    }

    // The shortcut is on from the start: a way in that nobody knows of helps nobody.
    func testTheShortcutStartsOn() {
        let defaults = throwawayDefaults()
        let settings = Settings(defaults: defaults)
        XCTAssertTrue(settings.shortcut)
        settings.shortcut = false
        let reopened = Settings(defaults: defaults)
        XCTAssertFalse(reopened.shortcut)
        // Which chord it is: A until chosen otherwise, and what is stored is read back.
        XCTAssertEqual(reopened.shortcutKey, .a)
        reopened.shortcutKey = .k
        XCTAssertEqual(Settings(defaults: defaults).shortcutKey, .k)
    }

    // Issue #1: a MacBook used as the second screen beside a bigger one. Automatic until a
    // display is picked, and the pick is kept by the display's own id.
    func testTheChosenDisplayIsAutomaticUntilPickedAndKept() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.display, DisplayChoice.automatic.id)
        settings.display = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
        XCTAssertEqual(Settings(defaults: defaults).display, "37D8832A-2D66-02CA-B9F7-8F30A301B230")
    }

    func testIdleSessionLabels() {
        // "Hide" and "Show" are what the x on a card and the hidden row do. The setting has words of its own.
        // Read after the setting's name, each says what it does: "Idle sessions: In one line".
        XCTAssertEqual(IdleSessions.allCases.map(\.label), ["In one line", "Not listed", "As cards"])
        XCTAssertEqual(IdleSessions.allCases.map(\.rawValue), ["fold", "hide", "show"], "what is stored must not change")
    }
}
