import AppKit
import AVFoundation
import XCTest
@testable import AgentValley

final class SoundTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let crew = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("sounds/crew")
    private var defaults: UserDefaults!
    private var settings: Settings!
    private var center: NotificationCenter!
    private var player: SoundPlayer!
    private var played: [String] = []
    /// While true, a clip plays on until the test ends it: `pending` holds how to.
    private var holding = false
    private var pending: [() -> Void] = []

    /// Sounds on, the middle of the day, and a list of names in place of the speaker.
    override func setUp() {
        defaults = throwawayDefaults()
        settings = Settings(defaults: defaults)
        settings.sounds = true
        center = NotificationCenter()
        played = []
        holding = false
        pending = []
        player = makePlayer(memory: defaults)
    }

    override func tearDown() {
        player = nil
    }

    /// The repo's own clips, the first line of every group, and a clock in UTC.
    private func makePlayer(memory: UserDefaults) -> SoundPlayer {
        let player = SoundPlayer(settings: settings, center: center, memory: memory)
        player.sounds = CrewSounds(folder: Self.crew)
        player.random = { _ in 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        player.calendar = calendar
        player.hour = { _ in 12 }
        player.sink = { [unowned self] name, done in
            self.played.append(name)
            if self.holding { self.pending.append(done) } else { done() }
        }
        return player
    }

    /// What each clip was for: a finish, or a wait.
    private func events(_ names: [String]) -> [String] {
        names.map { $0.contains("-done-") || $0.contains("sting-done") || $0.contains("chime-done") ? "done" : "need" }
    }

    /// A folder of this test's own holding empty files by these names.
    private func folder(holding names: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-valley-crew-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        for name in names { XCTAssertTrue(FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data())) }
        return folder
    }

    private func after(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    private func list(_ cards: [SessionCard], at seconds: TimeInterval = 0, looking: Bool = false) {
        player.listed(cards, loaded: true, looks: 0, looking: looking, now: after(seconds))
    }

    /// The bar's tick, with one session that waits, or none, unless `cards` says otherwise.
    private func beat(at seconds: TimeInterval, waiting: Bool = true, looks: Int = 0, cards: [SessionCard]? = nil) {
        player.beat(cards ?? (waiting ? [card(.needsYou)] : [card(.working)]), looks: looks, now: after(seconds))
    }

    /// What macOS says when the screen locks, unlocks, or the screen saver starts and stops.
    private func post(_ name: String) {
        center.post(name: Notification.Name(name), object: nil)
    }

    private func job(age: TimeInterval, at seconds: TimeInterval) -> BackgroundJob {
        BackgroundJob(id: "j", kind: .shell, name: "", startedAt: after(seconds - age), endsBy: nil)
    }

    func testAYoungJobHoldsTheDoneSoundUntilItEnds() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        var held = card(.done, moved: after(40)); held.jobs = [job(age: 60, at: 50)]
        let waiting = Sound.finished([held], since: began, now: after(50))
        XCTAssertTrue(waiting.finished.isEmpty)
        XCTAssertEqual(waiting.since, ["s": now])
        XCTAssertEqual(Sound.finished([card(.done, moved: after(200))], since: waiting.since, now: after(210)).finished.map(\.id), ["s"])
    }

    // The job turned half an hour old with nothing more written: the turn ended long ago.
    func testAFinishHeldUntilTheJobAgesIsDroppedNotSounded() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        var held = card(.done, moved: after(40)); held.jobs = [job(age: 60, at: 50)]
        let waiting = Sound.finished([held], since: began, now: after(50))
        XCTAssertTrue(waiting.finished.isEmpty)
        var aged = card(.done, moved: after(40)); aged.jobs = [job(age: 1800, at: 1790)]
        let late = Sound.finished([aged], since: waiting.since, now: after(1790))
        XCTAssertTrue(late.finished.isEmpty)
        XCTAssertEqual(late.since, [:])
    }

    // The job's end is written before the line that wakes Claude, and the two may be read apart:
    // the card is idle, jobless, and its last line is old. The held sound still rings.
    func testAJobEndingWhileIdleStillRingsTheHeldSound() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        var held = card(.done, moved: after(40)); held.jobs = [job(age: 60, at: 50)]
        let waiting = Sound.finished([held], since: began, now: after(50))
        XCTAssertTrue(waiting.finished.isEmpty)
        let ended = Sound.finished([card(.done, moved: after(40))], since: waiting.since, now: after(300))
        XCTAssertEqual(ended.finished.map(\.id), ["s"])
    }

    // An old dev server is no reason to call a finish stale: only a job that aged out is.
    func testAnOldJobBesideAYoungOneEndingDoesNotMakeTheFinishStale() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        var held = card(.done, moved: after(40)); held.jobs = [job(age: 2000, at: 50), job(age: 60, at: 50)]
        let waiting = Sound.finished([held], since: began, now: after(50))
        XCTAssertTrue(waiting.finished.isEmpty)
        var ended = card(.done, moved: after(40)); ended.jobs = [job(age: 2250, at: 300)]
        XCTAssertEqual(Sound.finished([ended], since: waiting.since, now: after(300)).finished.map(\.id), ["s"])
    }

    func testAJobPastHalfAnHourHoldsNothing() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        var long = card(.done, moved: after(40)); long.jobs = [job(age: 1800, at: 50)]
        XCTAssertEqual(Sound.finished([long], since: began, now: after(50)).finished.map(\.id), ["s"])
    }

    func testAClosedSessionFinishesNothing() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        var closed = card(.done, moved: after(40)); closed.closed = true
        let gone = Sound.finished([closed], since: began, now: after(50))
        XCTAssertTrue(gone.finished.isEmpty)
        XCTAssertEqual(gone.since, [:])
    }

    /// The one session of a test that has only one.
    private func card(_ status: AgentStatus, ran: TimeInterval = 0, agents: [AgentStatus] = [], moved: Date? = nil,
                      look: LeadLook? = LeadLook(face: 1), tool: String? = nil, agentType: String = "agent",
                      turn: Date? = nil) -> SessionCard {
        card("s", status, ran: ran, agents: agents, moved: moved, look: look, tool: tool, agentType: agentType, turn: turn)
    }

    /// A session whose rows have all run for `ran` seconds, and wrote their last line at `moved`.
    /// Walt sits in it unless `look` says otherwise. `tool`: the call its own row has open.
    /// `agentType`: what its sub-agents are. `started`: seconds after `now` it began.
    private func card(_ id: String, _ status: AgentStatus, ran: TimeInterval = 0, agents: [AgentStatus] = [], moved: Date? = nil,
                      look: LeadLook? = LeadLook(face: 1), tool: String? = nil, agentType: String = "agent",
                      started: TimeInterval = 0, turn: Date? = nil) -> SessionCard {
        func row(_ name: String, _ status: AgentStatus, type: String, tool: String?) -> AgentRow {
            var info = AgentInfo()
            info.type = type
            info.lastActivity = moved
            if name == "/main" { info.turnStartedAt = turn }
            info.openTools = tool.map { [OpenTool(id: "t", tool: $0, input: [:])] } ?? []
            return AgentRow(id: id + name, info: info, status: status, elapsed: ran)
        }
        var card = SessionCard(id: id, project: id, branch: "", main: row("/main", status, type: "main", tool: tool),
                               agents: agents.enumerated().map { row("/agent\($0.offset)", $0.element, type: agentType, tool: nil) },
                               startedAt: after(started))
        card.look = look
        return card
    }

    // MARK: - What decides

    // Near a quarter the knob lands on it; elsewhere on the whole percent under it.
    func testTheVolumeSnapsToQuartersNearThem() {
        XCTAssertEqual(Sound.volume(dragged: 0.53), 0.5)
        XCTAssertEqual(Sound.volume(dragged: 0.47), 0.5)
        XCTAssertEqual(Sound.volume(dragged: 0.97), 1)
        XCTAssertEqual(Sound.volume(dragged: 0.04), 0)
        XCTAssertEqual(Sound.volume(dragged: 0.63), 0.63, accuracy: 0.0001)
        XCTAssertEqual(Sound.volume(dragged: 0.384), 0.38, accuracy: 0.0001)
        XCTAssertEqual(Sound.volume(dragged: 1.08), 1.08, accuracy: 0.0001)
        XCTAssertEqual(Sound.volume(dragged: 1.22), 1.25)
        XCTAssertEqual(Sound.volume(dragged: -0.2), 0)
        XCTAssertEqual(Sound.volume(dragged: 1.4), 1.25)
    }

    // Past 100% a clip is made louder, up to 10 dB at the top, but never past what its loudest
    // point allows: it would break up. Never quieter than its file.
    func testAboveFullTheClipIsBoostedAsFarAsItsPeakAllows() {
        XCTAssertEqual(Sound.boost(volume: 1, peak: 0.1), 1)
        XCTAssertEqual(Sound.boost(volume: 0.5, peak: 0.1), 1)
        XCTAssertEqual(Sound.boost(volume: 1.25, peak: 0.1), 3.162, accuracy: 0.001)
        XCTAssertEqual(Sound.boost(volume: 1.125, peak: 0.1), 1.778, accuracy: 0.001)
        XCTAssertEqual(Sound.boost(volume: 1.25, peak: 0.5), 1.78, accuracy: 0.01)
        XCTAssertEqual(Sound.boost(volume: 1.25, peak: 0.95), 1)
        XCTAssertEqual(Sound.boost(volume: 1.25, peak: 0), 1)
    }

    // The louder copy is the same clip, as long, with its loudest point turned up by the boost
    // for it. Fast enough to make on the main thread as a bark comes in.
    func testALouderCopyOfARealClipIsTurnedUpByItsBoost() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../sounds/crew/sunny-done-long-2.m4a").standardized
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("louder-test-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: copy) }
        let started = Date()
        XCTAssertTrue(SoundPlayer.boost(url, volume: 1.25, into: copy))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.3)
        func read(_ url: URL) throws -> (peak: Float, frames: AVAudioFramePosition) {
            let file = try AVAudioFile(forReading: url)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channels = try XCTUnwrap(buffer.floatChannelData)
            var peak: Float = 0
            for c in 0..<Int(buffer.format.channelCount) { for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channels[c][i])) } }
            return (peak, file.length)
        }
        let plain = try read(url), louder = try read(copy)
        XCTAssertEqual(louder.frames, plain.frames)
        XCTAssertGreaterThan(Sound.boost(volume: 1.25, peak: plain.peak), 1.5)
        XCTAssertEqual(louder.peak / plain.peak, Sound.boost(volume: 1.25, peak: plain.peak), accuracy: 0.01)
        XCTAssertNotNil(SoundPlayer.louder(URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"), volume: 1.25))
    }

    func testQuietHoursInsideOneDay() {
        XCTAssertFalse(Sound.isQuiet(hour: 11, from: 12, until: 14))
        XCTAssertTrue(Sound.isQuiet(hour: 12, from: 12, until: 14))
        XCTAssertTrue(Sound.isQuiet(hour: 13, from: 12, until: 14))
        XCTAssertFalse(Sound.isQuiet(hour: 14, from: 12, until: 14))
    }

    func testQuietHoursThroughMidnight() {
        for hour in [22, 23, 0, 7] { XCTAssertTrue(Sound.isQuiet(hour: hour, from: 22, until: 8), "\(hour)") }
        for hour in [8, 12, 21] { XCTAssertFalse(Sound.isQuiet(hour: hour, from: 22, until: 8), "\(hour)") }
    }

    func testTheSameHourForBothIsNoQuietAtAll() {
        for hour in 0..<24 { XCTAssertFalse(Sound.isQuiet(hour: hour, from: 8, until: 8), "\(hour)") }
    }

    func testAnHourStepsRoundTheClock() {
        XCTAssertEqual(Sound.hour(22, movedBy: 1), 23)
        XCTAssertEqual(Sound.hour(23, movedBy: 1), 0)
        XCTAssertEqual(Sound.hour(0, movedBy: -1), 23)
    }

    func testEveryReasonAgainstSilencesASound() {
        XCTAssertTrue(Sound.plays(sounds: true, enabled: true, locked: false, quiet: false))
        XCTAssertFalse(Sound.plays(sounds: false, enabled: true, locked: false, quiet: false))
        XCTAssertFalse(Sound.plays(sounds: true, enabled: false, locked: false, quiet: false))
        XCTAssertFalse(Sound.plays(sounds: true, enabled: true, locked: true, quiet: false))
        XCTAssertFalse(Sound.plays(sounds: true, enabled: true, locked: false, quiet: true))
    }

    func testAReminderIsDueOnceItsMinutesHavePassed() {
        XCTAssertFalse(Sound.remindDue(every: 0, since: now, now: after(3600)))
        XCTAssertFalse(Sound.remindDue(every: 1, since: nil, now: now))
        XCTAssertFalse(Sound.remindDue(every: 1, since: now, now: after(59)))
        XCTAssertTrue(Sound.remindDue(every: 1, since: now, now: after(60)))
    }

    func testASessionThatStopsAfterALongTurnHasFinished() {
        let began = Sound.finished([card(.working)], since: [:], now: now)
        XCTAssertTrue(began.finished.isEmpty)
        XCTAssertEqual(began.since, ["s": now])
        XCTAssertTrue(Sound.finished([card(.done)], since: began.since, now: after(29)).finished.isEmpty)
        let ended = Sound.finished([card(.done)], since: began.since, now: after(30))
        XCTAssertEqual(ended.finished.map(\.id), ["s"])
        XCTAssertEqual(ended.since, [:])
    }

    // A row is called done some seconds after its last line: the turn ended when that line
    // was written, and that is where its length is measured to.
    func testATurnIsMeasuredToItsLastLineNotToWhenItWasSeenDone() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        XCTAssertTrue(Sound.finished([card(.done, moved: after(22))], since: began, now: after(32)).finished.isEmpty)
        XCTAssertFalse(Sound.finished([card(.done, moved: after(30))], since: began, now: after(40)).finished.isEmpty)
    }

    func testASessionFirstSeenIdleHasFinishedNothing() {
        XCTAssertTrue(Sound.finished([card(.done)], since: [:], now: now).finished.isEmpty)
    }

    // The app opened in the middle of a turn: it began when the transcript says, not just now.
    func testASessionFirstSeenAtWorkBeganWhenItsLongestAgentDid() {
        let seen = Sound.finished([card(.working, ran: 120)], since: [:], now: now)
        XCTAssertEqual(seen.since, ["s": after(-120)])
        XCTAssertFalse(Sound.finished([card(.done)], since: seen.since, now: after(1)).finished.isEmpty)
    }

    // The main agent has ended its turn and a sub-agent works on: the session has not finished.
    func testASessionIsNotFinishedWhileASubAgentWorks() {
        let began = Sound.finished([card(.working)], since: [:], now: now).since
        let behind = Sound.finished([card(.done, agents: [.working])], since: began, now: after(60))
        XCTAssertTrue(behind.finished.isEmpty)
        XCTAssertEqual(behind.since, ["s": now])
        XCTAssertFalse(Sound.finished([card(.done, agents: [.done])], since: behind.since, now: after(90)).finished.isEmpty)
    }

    func testAWaitThatEndsInAFinishedTurnHasFinished() {
        let began = Sound.finished([card(.needsYou)], since: [:], now: now).since
        XCTAssertFalse(Sound.finished([card(.done)], since: began, now: after(45)).finished.isEmpty)
    }

    // MARK: - What is said when work is done

    func testALongTurnSaysSo() {
        list([card(.working)])
        list([card(.done, moved: after(700))], at: 710)
        XCTAssertEqual(played, ["walt-done-long-1.m4a"])
    }

    // An hour of the person's own thinking is not an hour of work.
    func testTimeWaitingIsNotWork() {
        list([card(.working)])
        list([card(.needsYou)], at: 60)
        list([card(.working)], at: 660)
        list([card(.done, moved: after(700))], at: 705)
        XCTAssertEqual(played.last, "walt-done-short-1.m4a")
    }

    func testLateAtNightTheCrewSaysGoToBed() {
        player.hour = { _ in 23 }
        list([card(.working)])
        list([card(.done)], at: 100)
        XCTAssertEqual(played, ["walt-done-night-1.m4a"])
    }

    func testTheMorningsFirstFinishGreets() {
        player.hour = { _ in 9 }
        list([card(.working)])
        list([card(.done)], at: 40)
        list([card(.working)], at: 50)
        list([card(.done)], at: 100)
        XCTAssertEqual(played, ["walt-done-first-1.m4a", "walt-done-short-1.m4a"])
    }

    func testEveryoneDoneTogether() {
        list([card("a", .working, look: LeadLook(face: 1)), card("b", .working, look: LeadLook(face: 2))])
        list([card("a", .done, look: LeadLook(face: 1)), card("b", .done, look: LeadLook(face: 2))], at: 40)
        XCTAssertEqual(played, ["walt-done-group-1.m4a"])
    }

    func testNotEveryoneWhileSomeoneStillWorks() {
        list([card("a", .working), card("b", .working), card("c", .working)])
        list([card("a", .done), card("b", .done), card("c", .working)], at: 40)
        XCTAssertEqual(played, ["walt-done-short-1.m4a"])
    }

    // MARK: - The player

    // What was already there when the app opened is not news.
    func testTheFirstListMakesNoSound() {
        player.listed([card(.needsYou)], loaded: false, looks: 0, looking: false, now: now)
        list([card(.needsYou)])
        XCTAssertEqual(played, [])
    }

    func testAnAgentThatStartsToWaitSounds() {
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(events(played), ["need"])
    }

    // The app opened with nothing running: the first session to wait is news.
    func testAWaitAfterAnEmptyFirstListSounds() {
        list([])
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(events(played), ["need"])
    }

    func testSeveralStartingToWaitAtOnceSoundOnce() {
        list([card("a", .working), card("b", .working)])
        list([card("a", .needsYou), card("b", .needsYou)], at: 5)
        XCTAssertEqual(events(played), ["need"])
    }

    func testAWaitSeenAsItHappensMakesNoSound() {
        list([card(.working)])
        list([card(.needsYou)], at: 5, looking: true)
        XCTAssertEqual(played, [])
    }

    func testAFinishedSessionSounds() {
        list([card(.working)])
        list([card(.done)], at: 40)
        XCTAssertEqual(events(played), ["done"])
    }

    func testAShortTurnEndsWithoutASound() {
        list([card(.working)])
        list([card(.done)], at: 10)
        XCTAssertEqual(played, [])
    }

    // One sound for one list: the wait is the one that asks for something.
    func testAWaitComesBeforeAFinishInTheSameList() {
        list([card("a", .working), card("b", .working)])
        list([card("a", .done), card("b", .needsYou)], at: 40)
        XCTAssertEqual(events(played), ["need"])
    }

    func testSwitchedOffNothingSounds() {
        settings.sounds = false
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        list([card(.done)], at: 40)
        XCTAssertEqual(played, [])
    }

    func testEachMomentHasItsOwnSwitch() {
        settings.soundNeedsYou = false
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(played, [])
        list([card(.done)], at: 40)
        XCTAssertEqual(events(played), ["done"])

        settings.soundNeedsYou = true
        settings.soundFinished = false
        list([card(.working)], at: 50)
        list([card(.done)], at: 100)
        XCTAssertEqual(events(played), ["done"])
        list([card(.needsYou)], at: 110)
        XCTAssertEqual(events(played), ["done", "need"])
    }

    func testQuietHoursAreSilentAndNothingFollowsThem() {
        settings.quietHours = true
        player.hour = { _ in 23 }
        XCTAssertTrue(player.quiet(at: now))
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(played, [])
        // Morning: nothing is owed for the night.
        player.hour = { _ in 9 }
        XCTAssertFalse(player.quiet(at: now))
        beat(at: 36_000)
        XCTAssertEqual(played, [])
    }

    func testALockedScreenHoldsAWaitsSoundUntilItIsUnlocked() {
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.needsYou)], at: 5)
        beat(at: 8)
        XCTAssertEqual(played, [])
        post("com.apple.screenIsUnlocked")
        beat(at: 11)
        XCTAssertEqual(events(played), ["need"])
        beat(at: 14)
        XCTAssertEqual(events(played), ["need"])
    }

    func testNothingIsOwedOnceThePersonHasLooked() {
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.needsYou)], at: 5)
        post("com.apple.screenIsUnlocked")
        beat(at: 8, looks: 1)
        XCTAssertEqual(played, [])
    }

    func testNothingIsOwedOnceNobodyWaits() {
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.needsYou)], at: 5)
        post("com.apple.screenIsUnlocked")
        beat(at: 8, waiting: false)
        beat(at: 11)
        XCTAssertEqual(played, [])
    }

    func testAFinishedTurnUnderALockIsDropped() {
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.done)], at: 40)
        post("com.apple.screenIsUnlocked")
        beat(at: 43, waiting: false)
        XCTAssertEqual(played, [])
    }

    // The screen saver stops when the person touches a key, and the lock screen is still up.
    func testAScreenSaverThatStopsUnderALockLeavesTheScreenLocked() {
        XCTAssertFalse(player.locked)
        post("com.apple.screensaver.didstart")
        post("com.apple.screenIsLocked")
        post("com.apple.screensaver.didstop")
        XCTAssertTrue(player.locked)
        post("com.apple.screenIsUnlocked")
        XCTAssertFalse(player.locked)
    }

    func testAScreenSaverAloneSilences() {
        list([card(.working)])
        post("com.apple.screensaver.didstart")
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(played, [])
        post("com.apple.screensaver.didstop")
        beat(at: 8)
        XCTAssertEqual(events(played), ["need"])
    }

    // Unlocked in the quiet hours: the sound is owed no more, and none follows in the morning.
    func testAHeldSoundIsDroppedWhenTheUnlockFallsInQuietHours() {
        settings.quietHours = true
        list([card(.working)])
        post("com.apple.screenIsLocked")
        list([card(.needsYou)], at: 5)
        post("com.apple.screenIsUnlocked")
        player.hour = { _ in 23 }
        beat(at: 8)
        player.hour = { _ in 9 }
        beat(at: 36_000)
        XCTAssertEqual(played, [])
    }

    func testRemindersRepeatUntilThePersonLooks() {
        settings.remindMinutes = 1
        list([card(.working)])
        list([card(.needsYou)])
        beat(at: 59)
        XCTAssertEqual(played.count, 1)
        beat(at: 60)
        XCTAssertEqual(events(played), ["need", "need"])
        beat(at: 119)
        XCTAssertEqual(played.count, 2)
        beat(at: 120)
        XCTAssertEqual(played.count, 3)
        // Looked: the reminders stop, as the bar's glow does.
        beat(at: 180, looks: 1)
        XCTAssertEqual(played.count, 3)
    }

    func testAnotherAgentStartingToWaitStartsTheCountAgain() {
        settings.remindMinutes = 1
        list([card("a", .working), card("b", .working)])
        list([card("a", .needsYou), card("b", .working)])
        list([card("a", .needsYou), card("b", .needsYou)], at: 50)
        XCTAssertEqual(played.count, 2)
        beat(at: 60)
        XCTAssertEqual(played.count, 2)
        beat(at: 110)
        XCTAssertEqual(played.count, 3)
    }

    func testNoRemindersWhenTheyAreOff() {
        list([card(.working)])
        list([card(.needsYou)])
        beat(at: 3600)
        XCTAssertEqual(events(played), ["need"])
    }

    // Waiting since before the app opened: never sounded, so never sounded again.
    func testNoRemindersForAWaitFromBeforeTheAppOpened() {
        settings.remindMinutes = 1
        list([card(.needsYou)])
        beat(at: 600)
        XCTAssertEqual(played, [])
    }

    func testAReminderUnderALockIsOwed() {
        settings.remindMinutes = 1
        list([card(.working)])
        list([card(.needsYou)])
        post("com.apple.screenIsLocked")
        beat(at: 60)
        XCTAssertEqual(events(played), ["need"])
        post("com.apple.screenIsUnlocked")
        beat(at: 63)
        XCTAssertEqual(events(played), ["need", "need"])
    }

    // The person's own click: they hear what turning sounds on means, whatever the hour.
    func testTheSamplePlaysWhateverTheHour() {
        settings.quietHours = true
        player.hour = { _ in 23 }
        player.sample([])
        XCTAssertEqual(events(played), ["need"])
    }

    // MARK: - Who speaks, and what

    func testTheLeadOfTheWaitingSessionSpeaks() {
        list([card(.working)])
        list([card(.needsYou, tool: "Bash")], at: 5)
        XCTAssertEqual(played, ["walt-need-run-1.m4a"])
    }

    // Judy made the plan, so she brings it. Without her on the team the lead says it.
    func testAPlanWithJudyOnTheTeamIsJudys() {
        list([card(.working, agents: [.done], agentType: "plan")])
        list([card(.needsYou, agents: [.done], moved: after(3), tool: "ExitPlanMode", agentType: "plan")], at: 5)
        XCTAssertTrue(played.first?.hasPrefix("judy-plan-") ?? false, "\(played)")

        played = []
        list([card("t", .working)], at: 10)
        list([card("t", .needsYou, tool: "ExitPlanMode")], at: 15)
        XCTAssertEqual(played, ["walt-need-plan-1.m4a"])
    }

    // The session began to work by our poll before the prompt that made this plan: the turn's own start counts.
    func testAPlanAgentFromBeforeTheTurnStartIsNotJudys() {
        list([card(.working, agents: [.done], agentType: "plan")])
        list([card(.needsYou, agents: [.done], moved: after(3), tool: "ExitPlanMode", agentType: "plan", turn: after(4))], at: 5)
        XCTAssertEqual(played, ["walt-need-plan-1.m4a"])
    }

    func testAPlanAgentFromThisTurnIsJudys() {
        list([card(.working, agents: [.done], agentType: "plan")])
        list([card(.needsYou, agents: [.done], moved: after(3), tool: "ExitPlanMode", agentType: "plan", turn: after(3))], at: 5)
        XCTAssertTrue(played.first?.hasPrefix("judy-plan-") ?? false, "\(played)")
    }

    // A plan agent last heard from before this turn began made some other plan: the lead says this one.
    func testAPlanAgentFromAnEarlierTurnIsNotJudys() {
        list([card(.working, agents: [.done], agentType: "plan")])
        list([card(.needsYou, agents: [.done], moved: after(-60), tool: "ExitPlanMode", agentType: "plan")], at: 5)
        list([card("t", .working, agents: [.done], agentType: "plan")], at: 10)
        list([card("t", .needsYou, agents: [.done], moved: after(10), tool: "ExitPlanMode", agentType: "plan")], at: 15)
        XCTAssertEqual(played.count, 2)
        XCTAssertEqual(played.first, "walt-need-plan-1.m4a")
        XCTAssertTrue(played.last?.hasPrefix("judy-plan-") ?? false, "\(played)")
    }

    // Nobody seated: the app cannot say who calls, and does not guess.
    func testWithoutASeatTheWaitChimes() {
        list([card(.working, look: nil)])
        list([card(.needsYou, look: nil)], at: 5)
        XCTAssertEqual(played, ["chime-need.m4a"])
    }

    func testTheFirstNewWaitInListOrderSpeaks() {
        let pearl = LeadLook(face: 3)
        list([card("a", .working, look: pearl), card("b", .working)])
        list([card("a", .needsYou, look: pearl), card("b", .needsYou)], at: 5)
        XCTAssertEqual(played, ["pearl-need-generic-1.m4a"])

        // The first one has no seat: it chimes, and Walt behind it does not speak for it.
        list([card("c", .working, look: nil), card("d", .working)], at: 10)
        list([card("c", .needsYou, look: nil), card("d", .needsYou)], at: 15)
        XCTAssertEqual(played, ["pearl-need-generic-1.m4a", "chime-need.m4a"])
    }

    func testTheMorningsFirstWaitGreetsUnlessItSaysWhat() {
        player.hour = { _ in 9 }
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        list([card(.working)], at: 10)
        list([card(.needsYou)], at: 15)
        XCTAssertEqual(played, ["walt-need-first-1.m4a", "walt-need-generic-1.m4a"])

        // The first of a day that knows what it is about says what.
        played = []
        player = makePlayer(memory: throwawayDefaults())
        player.hour = { _ in 9 }
        list([card(.working)])
        list([card(.needsYou, tool: "ExitPlanMode")], at: 5)
        XCTAssertEqual(played, ["walt-need-plan-1.m4a"])
    }

    func testRemindersGrowMoreUrgent() {
        settings.remindMinutes = 1
        list([card(.working)])
        list([card(.needsYou)])
        for seconds in [60.0, 120, 180, 240] { beat(at: seconds) }
        XCTAssertEqual(played, ["walt-need-generic-1.m4a", "walt-remind-1-1.m4a", "walt-remind-2-1.m4a",
                                "walt-remind-3-1.m4a", "walt-remind-3-1.m4a"])
    }

    // Pearl's is the newest wait, so she reminds; once she is answered, Walt, who still waits, does.
    func testAReminderComesFromWhoeverStillWaits() {
        settings.remindMinutes = 1
        let pearl = LeadLook(face: 3)
        list([card("a", .working, look: pearl), card("b", .working)])
        list([card("a", .working, look: pearl), card("b", .needsYou)])
        list([card("a", .needsYou, look: pearl), card("b", .needsYou)], at: 10)
        beat(at: 70, cards: [card("a", .needsYou, look: pearl), card("b", .needsYou)])
        list([card("a", .working, look: pearl), card("b", .needsYou)], at: 100)
        beat(at: 130, cards: [card("a", .working, look: pearl), card("b", .needsYou)])
        XCTAssertEqual(played, ["walt-need-generic-1.m4a", "pearl-need-generic-1.m4a", "pearl-remind-1-1.m4a", "walt-remind-2-1.m4a"])
    }

    func testNoLineTwiceInARow() {
        for start in [0.0, 100, 200] {
            list([card(.working)], at: start)
            list([card(.needsYou)], at: start + 5)
        }
        XCTAssertEqual(played, ["walt-need-generic-1.m4a", "walt-need-generic-2.m4a", "walt-need-generic-3.m4a"])
    }

    func testASoundIsNeverCutOffAndAWaitBumpsAQueuedFinish() {
        holding = true
        let all = ["a", "b", "c", "d"]
        func cards(done: Set<String>, waiting: String? = nil) -> [SessionCard] {
            all.map { card($0, $0 == waiting ? .needsYou : done.contains($0) ? .done : .working) }
        }
        list(cards(done: []))
        list(cards(done: ["a"]), at: 40)
        XCTAssertEqual(played, ["walt-done-short-1.m4a"])
        // Another finish waits its turn; a wait takes its place; a finish after that does not.
        list(cards(done: ["a", "b"]), at: 50)
        list(cards(done: ["a", "b"], waiting: "c"), at: 55)
        list(cards(done: ["a", "b", "d"], waiting: "c"), at: 60)
        XCTAssertEqual(played.count, 1)
        pending.removeFirst()()
        XCTAssertEqual(events(played), ["done", "need"])
        pending.removeFirst()()
        XCTAssertEqual(events(played), ["done", "need"])
        XCTAssertNil(player.queued)
    }

    func testStylesPickTheirOwnFiles() {
        settings.soundStyle = .stings
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        settings.soundStyle = .chimes
        list([card(.working)], at: 10)
        list([card(.needsYou)], at: 15)
        list([card(.done)], at: 60)
        XCTAssertEqual(played, ["walt-sting-need.m4a", "chime-need.m4a", "chime-done.m4a"])
    }

    // The chimes are macOS's own, as before the crew spoke: Glass for a wait, Pop for a finish.
    func testChimesAreTheSystemSounds() {
        XCTAssertEqual(SoundPlayer.systemChimes, ["chime-need.m4a": "Glass", "chime-done.m4a": "Pop"])
        for name in SoundPlayer.systemChimes.values { XCTAssertNotNil(NSSound(named: name), name) }
    }

    // A renamed line or an old build: the group's generic line, then the chime.
    func testAMissingFileFallsBackToTheGenericLineThenTheChime() throws {
        player.sounds = CrewSounds(folder: try folder(holding: ["walt-need-generic-1.m4a"]))
        list([card(.working)])
        list([card(.needsYou, tool: "Bash")], at: 5)
        player.sounds = CrewSounds(folder: try folder(holding: []))
        list([card(.working)], at: 10)
        list([card(.needsYou, tool: "Bash")], at: 15)
        XCTAssertEqual(played, ["walt-need-generic-1.m4a", "chime-need.m4a"])
    }

    // No speaker in the way: a clip that cannot be opened is over at once, and the next is not
    // left queued behind it. Walt's line is an empty file, so nothing is heard.
    func testAClipThatCannotBeOpenedNeverHoldsUpTheQueue() throws {
        player.sink = nil
        player.sounds = CrewSounds(folder: try folder(holding: ["walt-need-generic-1.m4a"]))
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        list([card(.working)], at: 10)
        list([card(.needsYou)], at: 15)
        XCTAssertNil(player.queued)
    }

    func testSampleUsesTheNewestSeatedSession() {
        player.sample([card("old", .done), card("new", .done, look: LeadLook(face: 3), started: 60),
                       card("newest", .done, look: nil, started: 120)])
        player.sample([])
        XCTAssertEqual(played, ["pearl-need-generic-1.m4a", "walt-need-generic-1.m4a"])
    }

    // The speaker button says sounds are on, not that someone waits; the Voice picker still
    // plays a wait, which is what the person will hear.
    func testTurningSoundsOnSaysSoAndTheVoicePickerPlaysAWait() {
        player.sample([], turnedOn: true)
        player.sample([])
        XCTAssertEqual(played, ["walt-on-1.m4a", "walt-need-generic-1.m4a"])
    }

    // An old bundle with no such line: the wait line, not silence.
    func testTurningSoundsOnWithoutItsLineFallsBackToAWait() throws {
        player.sounds = CrewSounds(folder: try folder(holding: ["walt-need-generic-1.m4a"]))
        player.sample([], turnedOn: true)
        XCTAssertEqual(played, ["walt-need-generic-1.m4a"])
    }

    // The speaker never said the clip ended, and it is not playing: the next bark still plays.
    // Its file is empty, so nothing is heard; that it was tried shows in the crew's memory.
    func testAClipThatStoppedWithoutSayingSoDoesNotSilenceTheRest() throws {
        player.sink = nil
        player.sounds = CrewSounds(folder: try folder(holding: ["walt-need-generic-1.m4a"]))
        player.speaking = true
        player.playing = try XCTUnwrap(NSSound(named: "Glass"))
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        XCTAssertEqual(defaults.object(forKey: "crewSpokeAt") as? Date, after(5))
        XCTAssertNil(player.queued)
        XCTAssertFalse(player.speaking)
    }

    // A queued bark waits behind a clip that went quiet unsaid: the beat starts it, with nothing new said.
    func testTheBeatHealsAClipThatStoppedWithoutSayingSo() throws {
        player.sounds = CrewSounds(folder: try folder(holding: ["walt-need-generic-1.m4a"]))
        holding = true
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        XCTAssertNotNil(defaults.object(forKey: "crewSpokeAt"))
        defaults.removeObject(forKey: "crewSpokeAt")
        list([card(.working)], at: 10)
        list([card(.needsYou)], at: 15)
        XCTAssertNotNil(player.queued)
        player.sink = nil
        player.playing = try XCTUnwrap(NSSound(named: "Glass"))
        beat(at: 16, waiting: false)
        XCTAssertNil(player.queued)
        XCTAssertEqual(defaults.object(forKey: "crewSpokeAt") as? Date, after(15))
    }

    // The lock cuts a clip that is playing, and the player is not left speaking.
    func testALockStopsTheClipAndFreesThePlayer() throws {
        player.sink = nil
        player.speaking = true
        player.playing = try XCTUnwrap(NSSound(named: "Glass"))
        post("com.apple.screenIsLocked")
        XCTAssertFalse(player.speaking)
        XCTAssertNil(player.playing)
    }

    /// A system sound playing at no volume: a clip the speaker is in the middle of, heard by nobody.
    private func playingClip() throws -> NSSound {
        let clip = try XCTUnwrap(NSSound(named: "Glass")?.copy() as? NSSound)
        clip.volume = 0
        XCTAssertTrue(clip.play())
        addTeardownBlock { clip.stop() }
        player.speaking = true
        player.playing = clip
        return clip
    }

    // Sounds off: the clip playing stops at once, and nothing waiting behind it plays after.
    func testTurningSoundsOffStopsTheClipAndDropsTheQueue() throws {
        player.sink = nil
        player.sounds = CrewSounds(folder: try folder(holding: ["walt-need-generic-1.m4a"]))
        let clip = try playingClip()
        player.sample([])
        list([card(.working)])
        list([card(.needsYou)], at: 5)
        settings.sounds = false
        player.silence()
        XCTAssertFalse(clip.isPlaying)
        XCTAssertNil(player.playing)
        XCTAssertNil(player.queued)
        XCTAssertFalse(player.speaking)
    }

    // Clicked on again and again: each click is heard now, never in a line behind the last.
    func testTheSampleCutsOffTheClipPlaying() throws {
        player.sink = nil
        player.sounds = CrewSounds(folder: try folder(holding: ["walt-need-generic-1.m4a"]))
        let clip = try playingClip()
        player.sample([])
        XCTAssertFalse(clip.isPlaying)
        XCTAssertNil(player.queued)
        XCTAssertFalse(player.speaking)
    }

    // A clip waiting its turn meets the rules as they are when it would start.
    func testAQueuedFinishIsDroppedOnceSoundsAreOff() {
        holding = true
        list([card("a", .working), card("b", .working)])
        list([card("a", .done), card("b", .working)], at: 40)
        list([card("a", .done), card("b", .done)], at: 50)
        settings.sounds = false
        pending.removeFirst()()
        XCTAssertEqual(played.count, 1)
        XCTAssertNil(player.queued)
    }

    func testAQueuedFinishUnderALockIsDroppedAndNotOwed() {
        holding = true
        list([card("a", .working), card("b", .working)])
        list([card("a", .done), card("b", .working)], at: 40)
        list([card("a", .done), card("b", .done)], at: 50)
        post("com.apple.screenIsLocked")
        pending.removeFirst()()
        post("com.apple.screenIsUnlocked")
        beat(at: 53, waiting: false)
        XCTAssertEqual(played.count, 1)
    }

    func testAQueuedWaitUnderALockIsOwedUntilItLifts() {
        holding = true
        list([card("a", .working), card("b", .working)])
        list([card("a", .done), card("b", .working)], at: 40)
        list([card("a", .done), card("b", .needsYou)], at: 45)
        post("com.apple.screenIsLocked")
        pending.removeFirst()()
        XCTAssertEqual(played.count, 1)
        post("com.apple.screenIsUnlocked")
        beat(at: 48, cards: [card("a", .done), card("b", .needsYou)])
        XCTAssertEqual(events(played), ["done", "need"])
    }

    // MARK: - Plan limits

    private func out(_ weekly: Bool = false, resets: TimeInterval = 3600) -> RunOut { RunOut(weekly: weekly, resetsAt: after(resets)) }

    func testTheFirstReadingIsNotNews() {
        player.limits(out(), known: true, now: after(0))
        XCTAssertEqual(played, [])
    }

    func testRunningOutSendsTheCrewFishing() {
        player.limits(nil, known: true, now: after(0))
        player.limits(out(), known: true, now: after(10))
        XCTAssertEqual(played, ["sunny-fishout-1.m4a"])
        player.limits(nil, known: true, now: after(3700))
        player.limits(out(), known: true, now: after(3800))
        XCTAssertEqual(played.count, 3)
        XCTAssertTrue(played[2].hasPrefix("walt-fishout-"))
    }

    func testTheyComeBackAfterTheReset() {
        player.limits(out(), known: true, now: after(0))
        player.limits(nil, known: true, now: after(3601))
        XCTAssertEqual(played, ["sunny-fishback-1.m4a"])
    }

    func testTheyComeBackAfterTheResetWhoLeft() {
        player.limits(nil, known: true, now: after(0))
        player.limits(out(), known: true, now: after(10))
        player.limits(nil, known: true, now: after(3601))
        XCTAssertEqual(played, ["sunny-fishout-1.m4a", "sunny-fishback-1.m4a"])
    }

    func testRunOutGoneBeforeItsResetIsSilent() {
        player.limits(out(), known: true, now: after(0))
        player.limits(nil, known: true, now: after(3000))
        XCTAssertEqual(played, [])
        player.limits(nil, known: false, now: after(3050))
        player.limits(out(), known: true, now: after(3100))
        player.limits(nil, known: false, now: after(3200))
        player.limits(nil, known: true, now: after(3601))
        XCTAssertEqual(played, [])
    }

    func testTheWeekCanFollowTheFiveHours() {
        player.limits(out(), known: true, now: after(0))
        player.limits(out(true, resets: 99999), known: true, now: after(10))
        XCTAssertEqual(played, ["sunny-vanout-1.m4a"])
        player.limits(out(), known: true, now: after(20))
        XCTAssertEqual(played, ["sunny-vanout-1.m4a"])
    }

    func testTheOneWhoLeftComesBackAfterARestart() {
        player.limits(nil, known: true, now: after(0))
        player.limits(out(true), known: true, now: after(10))
        XCTAssertEqual(played, ["sunny-vanout-1.m4a"])
        let b = makePlayer(memory: defaults)
        b.random = { $0 - 1 }
        b.limits(out(true), known: true, now: after(20))
        b.limits(nil, known: true, now: after(3601))
        XCTAssertEqual(played, ["sunny-vanout-1.m4a", "sunny-vanback-1.m4a"])
    }

    func testScenesHaveTheirOwnSwitchAndStyles() {
        func leave() {
            player.limits(nil, known: true, now: after(0))
            player.limits(out(), known: true, now: after(10))
            player.limits(nil, known: false, now: after(20))
        }
        settings.soundScenes = false
        leave()
        XCTAssertEqual(played, [])
        settings.soundScenes = true
        settings.soundStyle = .stings
        leave()
        XCTAssertEqual(played, ["bed-fishout.m4a"])
        settings.soundStyle = .chimes
        leave()
        XCTAssertEqual(played, ["bed-fishout.m4a"])
        settings.soundStyle = .crew
        settings.quietHours = true
        settings.quietFrom = 10
        settings.quietUntil = 14
        leave()
        XCTAssertEqual(played, ["bed-fishout.m4a"])
    }
}
