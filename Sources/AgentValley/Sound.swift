import AppKit
import AVFoundation

/// What decides whether a sound plays. No clock and no speaker here: everything is handed in.
enum Sound {
    /// A session that was at it for less than this ends without a sound: the person was most
    /// likely still at the terminal.
    // ponytail: one length for everyone; make it a setting if people ask.
    static let shortTurn: TimeInterval = 30

    /// A finish is dropped, not sounded, when a job still listed turned half an hour old more than
    /// this after the session's last line: the sound was let go by a job aging, long after the turn
    /// ended. A job that ended is not that, however late it is seen (it is gone from the list), and
    /// neither is one already half an hour old by then.
    static let staleFinish: TimeInterval = 120

    /// Whether `hour` falls in the quiet hours: from `start` up to, not including, `end`. A
    /// start after the end runs through midnight. The same hour for both is no quiet at all.
    static func isQuiet(hour: Int, from start: Int, until end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (start..<end).contains(hour) : hour >= start || hour < end
    }

    /// An hour of the day moved by `step` hours, round the clock.
    static func hour(_ hour: Int, movedBy step: Int) -> Int {
        ((hour + step) % 24 + 24) % 24
    }

    /// The top of the volume slider. Past 1 the crew is louder than its clips: for someone who
    /// must hear them over everything else.
    static let loudest = 1.25

    /// The marks on the volume slider. A drag that ends near one lands on it.
    static let volumeMarks: [Double] = [0, 0.25, 0.5, 0.75, 1, 1.25]

    /// The volume a drag across the slider lands on, from the volume under the pointer (past
    /// either end too): a mark within 5 points of it, else the whole percent.
    static func volume(dragged at: Double) -> Double {
        let at = min(max(at, 0), loudest)
        if let mark = volumeMarks.first(where: { abs($0 - at) <= 0.05 }) { return mark }
        return (at * 100).rounded() / 100
    }

    /// How many times louder than its file a clip plays at a volume past 1: up to 10 dB at the
    /// top, and only as far as `peak`, its loudest sample, stays under -1 dB: past that it
    /// breaks up. Never quieter than the file.
    static func boost(volume: Double, peak: Float) -> Float {
        guard volume > 1, peak > 0 else { return 1 }
        let wanted = Float(pow(10, (volume - 1) / (loudest - 1) * 10 / 20))
        return max(1, min(wanted, 0.89 / peak))
    }

    /// Whether a sound may play. In the order the reasons against are checked.
    static func plays(sounds: Bool, enabled: Bool, locked: Bool, quiet: Bool) -> Bool {
        sounds && enabled && !locked && !quiet
    }

    /// Whether it is time to say again that someone waits.
    static func remindDue(every minutes: Int, since last: Date?, now: Date) -> Bool {
        guard minutes > 0, let last else { return false }
        return now.timeIntervalSince(last) >= TimeInterval(minutes * 60)
    }

    /// A session that has just finished, and how long it worked: time spent waiting on the
    /// person is not work.
    struct Finish: Equatable {
        let id: String
        let worked: TimeInterval
    }

    /// Follows how long each session has been at it. `since` says when each session that is not
    /// idle began; what comes back says the same for this list. Finished: a session in `since`
    /// is idle now, and wrote its last line at least `shortTurn` after it began: a row is only
    /// called done some seconds after that line. Not when a job aged into letting it go, more
    /// than `staleFinish` after its last line: that finish is dropped with its start. A session first seen idle has finished
    /// nothing, and one first seen at work began when its longest-running agent did.
    /// `resumed`: when each session last stopped waiting on the person. Work is counted from the
    /// later of that and its start; the 30 s rule still counts from its start.
    static func finished(_ cards: [SessionCard], since: [String: Date], resumed: [String: Date] = [:],
                         now: Date) -> (finished: [Finish], since: [String: Date]) {
        var going: [String: Date] = [:]
        var finished: [Finish] = []
        for card in cards {
            // A young job still running keeps the session going: it is not done yet. A closed
            // session has nothing live left to be done.
            if card.isIdle && BackgroundJobs.resting(card.jobs, now: now) {
                guard !card.closed, let began = since[card.id] else { continue }
                let end = card.movedAt ?? now
                guard !card.jobs.contains(where: { $0.startedAt.addingTimeInterval(BackgroundJobs.longAfter) > end.addingTimeInterval(staleFinish) }) else { continue }
                if end.timeIntervalSince(began) >= shortTurn {
                    finished.append(Finish(id: card.id, worked: max(0, end.timeIntervalSince(max(began, resumed[card.id] ?? began)))))
                }
            } else {
                let longest = card.rows.filter { $0.status != .done }.map(\.elapsed).max() ?? 0
                going[card.id] = since[card.id] ?? now.addingTimeInterval(-longest)
            }
        }
        return (finished, going)
    }
}

/// What a sound is for, least to most pressing: a playing clip is cut off only by the person
/// (a sample, sounds off, the lock), and the one waiting behind it gives way only to something
/// as pressing or more.
enum BarkKind: Int, Comparable {
    case finished, scene, needsYou

    static func < (a: BarkKind, b: BarkKind) -> Bool { a.rawValue < b.rawValue }
}

/// Makes the app's sounds: the crew of each session speaking for it. Told what the list holds
/// and when the bar's timer ticks; decides with `Sound` and `Barks`, and remembers only what it
/// was last told. Plays one clip at a time. Used on the main thread alone.
final class SoundPlayer: NSObject, NSSoundDelegate {
    private let settings: Settings
    private let center: NotificationCenter
    /// Where the moment the crew last spoke is kept, across launches: it says whether the
    /// morning has heard them yet.
    private let memory: UserDefaults
    private static let spokeKey = "crewSpokeAt"
    /// Who last left, and for what: "fish:<who>" or "van:<who>". The one who left comes back.
    private static let sceneKey = "crewSceneBy"
    /// Takes each clip's file name in place of the speaker, and is called back once it has
    /// played. For tests, which say when a clip ends.
    var sink: ((String, @escaping () -> Void) -> Void)?
    /// The hour of the day at a moment. For tests, which cannot wait for the evening.
    var hour: (Date) -> Int = { Calendar.current.component(.hour, from: $0) }
    /// Picks one of n lines. For tests, which want the same line every time.
    var random: (Int) -> Int = { Int.random(in: 0..<$0) }
    /// Where a day begins and ends, for the morning's first word.
    var calendar = Calendar.current
    var sounds = CrewSounds()

    /// Two marks, not one: the screen saver stops at a key press while the lock is still up.
    private var screenLocked = false
    private var saverRunning = false
    /// Nobody is at the screen to hear anything.
    var locked: Bool { screenLocked || saverRunning }

    /// How many rows waited on the person in each session, as last listed. nil until the first
    /// list has been read: what was already there when the app opened is not news.
    private var waiting: [String: Int]?
    /// When each session that is not idle began.
    private var since: [String: Date] = [:]
    /// When each session last stopped waiting on the person: that time is not work.
    private var resumed: [String: Date] = [:]
    /// Whether the person has looked since someone last started to wait.
    private var watch = WaitWatch()
    /// When the wait was last sounded, or would have been: reminders count from here. nil until
    /// someone starts to wait while the app runs.
    private var soundedAt: Date?
    /// The session that last started to wait, and how many reminders of it have come due.
    private var arrival: String?
    private var reminders = 0
    /// Who said the wait or its last reminder, or was to: a held one is said again from the same group.
    private var lastCall: Call?
    /// A wait's sound came due under a locked screen, and is owed once it is not.
    private var held = false
    private var picker = LinePicker()
    /// The run-out at the last reading that had numbers. nil: no such reading yet (a reading
    /// with nothing run out is `.some(nil)`).
    private var lastLimits: RunOut??

    /// A clip is playing, and nothing cuts it off. Set by tests too, with `playing`, to stand
    /// for a clip that went quiet without saying so.
    var speaking = false
    var playing: NSSound?
    /// The one bark waiting for the playing clip to end.
    private(set) var queued: Bark?
    private var observers: [NSObjectProtocol] = []

    /// One clip to play, and what it is for. `spokeAt`: the crew has spoken for a wait or a
    /// finish at this moment, once it plays; nil for a chime, a sample or a scene. `asked`: the
    /// person's own click, which the switches and the quiet hours do not hold back.
    struct Bark {
        let kind: BarkKind
        let name: String
        let spokeAt: Date?
        let asked: Bool
    }

    /// Who speaks for a wait, and the group of lines it is said from. `lead`: the session's
    /// own, whose sting it is without words. Judy speaks for a plan she made, in her own group.
    private struct Call {
        let who: Crew?
        let lead: Crew?
        let group: String
    }

    /// `center`: where macOS says the screen has locked. Another one in tests. `memory`: where
    /// the crew's last word is kept.
    init(settings: Settings, center: NotificationCenter = DistributedNotificationCenter.default(),
         memory: UserDefaults = .standard) {
        self.settings = settings
        self.center = center
        self.memory = memory
        super.init()
        observe("com.apple.screenIsLocked", \.screenLocked, true)
        observe("com.apple.screenIsUnlocked", \.screenLocked, false)
        observe("com.apple.screensaver.didstart", \.saverRunning, true)
        observe("com.apple.screensaver.didstop", \.saverRunning, false)
    }

    deinit {
        for observer in observers { center.removeObserver(observer) }
    }

    /// No queue: the distributed center posts on the main thread, and the mark is set as it does.
    private func observe(_ name: String, _ mark: ReferenceWritableKeyPath<SoundPlayer, Bool>, _ value: Bool) {
        observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { [weak self] _ in
            self?[keyPath: mark] = value
            if value { self?.hush() }
        })
    }

    /// The screen locked or the saver started: the clip playing stops mid-word. It is dropped
    /// before it is stopped, so the speaker's own end call finds nothing to end twice.
    private func hush() {
        guard sink == nil, let clip = playing else { return }
        playing = nil
        clip.stop()
        ended()
    }

    /// Sounds turned off: the clip playing stops mid-word, and nothing waiting behind it plays after.
    func silence() {
        queued = nil
        hush()
    }

    /// Whether this moment is in the person's quiet hours.
    func quiet(at now: Date) -> Bool {
        settings.quietHours && Sound.isQuiet(hour: hour(now), from: settings.quietFrom, until: settings.quietUntil)
    }

    /// The list as it is now. `looks`: how many times the panel has been looked at. `looking`:
    /// the person is at the open panel right now, and sees what happens as it does.
    func listed(_ cards: [SessionCard], loaded: Bool, looks: Int, looking: Bool, now: Date = Date()) {
        guard loaded else { return }
        let before = waiting
        let after = AgentStore.waiting(cards)
        waiting = after
        if let before {
            for (id, count) in before where count > 0 && (after[id] ?? 0) == 0 { resumed[id] = now }
        }
        let turn = Sound.finished(cards, since: since, resumed: resumed, now: now)
        since = turn.since
        resumed = resumed.filter { since[$0.key] != nil }
        guard let before else { return }
        if let card = WaitWatch.risen(from: before, to: after, in: cards) {
            watch.arrived(looks: looks, lookingNow: looking)
            soundedAt = now
            held = false
            arrival = card.id
            reminders = 0
            lastCall = call(for: card, now: now)
            // Seen as it happens: a sound would only say what the person is looking at.
            if !looking { ring(now: now) }
        } else if !turn.finished.isEmpty, allowed(.finished, now: now) {
            // Never on top of a wait's sound: the wait is the one that asks for something.
            let done = Set(turn.finished.map(\.id))
            let speaker = cards.first { done.contains($0.id) }
            let worked = turn.finished.first { $0.id == speaker?.id }?.worked ?? 0
            let last = memory.object(forKey: Self.spokeKey) as? Date
            let topic = Barks.doneTopic(group: done.count >= 2 && cards.allSatisfy { $0.isIdle }, worked: worked, hour: hour(now),
                                        first: Barks.firstOfDay(last: last, now: now, calendar: calendar))
            let lead = speaker?.look.map(Crew.lead)
            say(.finished, file(lead, lead: lead, groups: [CrewSounds.group(topic), CrewSounds.group(DoneTopic.short)], moment: "done"), at: now)
        }
    }

    /// Every few seconds, from the bar's own timer: the reminder, and the sound a locked
    /// screen held back.
    func beat(_ cards: [SessionCard], looks: Int, now: Date = Date()) {
        let waits = cards.filter { $0.rows.contains { $0.status == .needsYou } }
        // Nobody waits, or the person has looked: nothing is owed and nothing is said again.
        healIfStopped()
        guard let first = waits.first, lastCall != nil, !watch.seen(looks: looks) else { return held = false }
        if Sound.remindDue(every: settings.remindMinutes, since: soundedAt, now: now) {
            reminders += 1
            // The one who started the wait while it lasts, then whoever waits first.
            let lead = (waits.first { $0.id == arrival } ?? first).look.map(Crew.lead)
            lastCall = Call(who: lead, lead: lead, group: CrewSounds.group(remind: reminders))
        } else if !held {
            return
        }
        soundedAt = now
        ring(now: now)
    }

    /// From the bar's timer. `known`: the panel has numbers. Not known, nothing is said, and the
    /// next known reading is where things start from again: the first one is not news. The
    /// crew comes back only once the old run-out's reset time has passed.
    func limits(_ out: RunOut?, known: Bool, now: Date = Date()) {
        guard known else { return lastLimits = nil }
        let before = lastLimits
        lastLimits = .some(out)
        guard let before, let scene = Barks.scene(from: LimitState(before), to: LimitState(out), resetsAt: before?.resetsAt, now: now) else { return }
        let saved = (memory.string(forKey: Self.sceneKey) ?? "").split(separator: ":").map(String.init)
        let kind = scene == .fishout || scene == .fishback ? "fish" : "van"
        let leaving = scene == .fishout || scene == .vanout
        let who: Crew
        if !leaving, saved.count == 2, saved[0] == kind, let back = Crew(rawValue: saved[1]) {
            who = back
        } else {
            // Anyone but the one who left last time.
            let rest = Crew.allCases.filter { !leaving || saved.last != $0.rawValue }
            who = rest[min(max(random(rest.count), 0), rest.count - 1)]
        }
        if leaving { memory.set("\(kind):\(who.rawValue)", forKey: Self.sceneKey) }
        guard allowed(.scene, now: now) else { return }
        let name: String?
        switch settings.soundStyle {
        case .crew: name = picker.pick(sounds.lines(who, scene.rawValue), group: "\(who.rawValue)-\(scene.rawValue)", random: random)
        case .stings: name = sounds.files.contains("bed-\(scene.rawValue).m4a") ? "bed-\(scene.rawValue).m4a" : nil
        case .chimes: name = nil
        }
        if let name { say(.scene, name, at: nil) }
    }

    /// A sound on the person's own click: they have just turned sounds on or picked how the
    /// crew sounds, and hear what that means. `turnedOn`: the lead says sounds are on; else a
    /// wait, which is what the person will hear. Said by the lead of the newest session that
    /// has one, or by Walt. Not held back by the quiet hours. Heard at once: it cuts off the
    /// clip playing, so clicks in a row never line up behind each other.
    func sample(_ cards: [SessionCard], turnedOn: Bool = false) {
        let lead = cards.filter { $0.look != nil }.max { $0.startedAt < $1.startedAt }?.look.map(Crew.lead) ?? .walt
        let groups = (turnedOn ? [CrewSounds.turnedOn] : []) + [CrewSounds.group(WaitTopic.generic)]
        silence()
        say(.needsYou, file(lead, lead: lead, groups: groups, moment: "need"), at: nil, asked: true)
    }

    /// Who speaks for a wait that has just begun in `card`, and about what: its own row if that
    /// waits, else the first that does. Judy brings a plan when a plan agent worked in this
    /// turn: one from an earlier turn may still be listed, finished.
    private func call(for card: SessionCard, now: Date) -> Call {
        let last = memory.object(forKey: Self.spokeKey) as? Date
        let greet = Barks.morning(hour: hour(now)) && Barks.firstOfDay(last: last, now: now, calendar: calendar)
        let topic = card.rows.first { $0.status == .needsYou }.map { Barks.waitTopic($0, greet: greet) } ?? .generic
        let lead = card.look.map(Crew.lead)
        let start = card.main?.info.turnStartedAt ?? since[card.id]
        let planned = card.agents.contains { row in
            MascotKind(type: row.info.type) == .plan && start.map { (row.info.lastActivity ?? .distantPast) >= $0 } ?? true
        }
        if topic == .plan, planned {
            return Call(who: .judy, lead: lead, group: "plan")
        }
        return Call(who: lead, lead: lead, group: CrewSounds.group(topic))
    }

    /// The wait last called. Owed while the lock is up, and no longer: unlocked into the quiet
    /// hours, it is dropped.
    private func ring(now: Date) {
        held = locked
        guard let call = lastCall, allowed(.needsYou, now: now) else { return }
        say(.needsYou, file(call.who, lead: call.lead, groups: [call.group, CrewSounds.group(WaitTopic.generic)], moment: "need"), at: now)
    }

    /// Whether a bark of this kind may play now: sounds on, its own switch on, someone at the
    /// screen, and not the quiet hours.
    private func allowed(_ kind: BarkKind, now: Date) -> Bool {
        let enabled: Bool
        switch kind {
        case .needsYou: enabled = settings.soundNeedsYou
        case .finished: enabled = settings.soundFinished
        case .scene: enabled = settings.soundScenes
        }
        return Sound.plays(sounds: settings.sounds, enabled: enabled, locked: locked, quiet: quiet(at: now))
    }

    /// The clip for a bark, by how the crew sounds. Talking: `who`'s line from the first group
    /// that has one. Without words: the lead's sting. The chime when there is no speaker, or no
    /// file: who calls is never guessed. `moment`: "need" or "done".
    private func file(_ who: Crew?, lead: Crew?, groups: [String], moment: String) -> String {
        let chime = "chime-\(moment).m4a"
        switch settings.soundStyle {
        case .chimes:
            return chime
        case .stings:
            guard let lead, case let sting = "\(lead.rawValue)-sting-\(moment).m4a", sounds.files.contains(sting) else { return chime }
            return sting
        case .crew:
            guard let who else { return chime }
            for group in groups {
                if let line = picker.pick(sounds.lines(who, group), group: "\(who.rawValue)-\(group)", random: random) { return line }
            }
            return chime
        }
    }

    /// Plays now, or waits behind the playing clip: one slot, taken by anything as pressing as
    /// what holds it, or more.
    private func say(_ kind: BarkKind, _ name: String, at: Date?, asked: Bool = false) {
        let bark = Bark(kind: kind, name: name, spokeAt: name.hasPrefix("chime-") ? nil : at, asked: asked)
        healIfStopped()
        guard speaking else { return speak(bark) }
        if queued.map({ $0.kind <= kind }) ?? true { queued = bark }
    }

    /// A clip that stopped without saying so is over: the player never goes quiet behind it.
    private func healIfStopped() {
        if speaking, sink == nil, playing?.isPlaying != true {
            playing = nil
            ended()
        }
    }

    /// The chimes are macOS's own sounds, as before the crew spoke: Glass for a wait, Pop for a
    /// finish. A copy of each, so a delegate of ours is never set on the shared one.
    static let systemChimes = ["chime-need.m4a": "Glass", "chime-done.m4a": "Pop"]

    private func speak(_ bark: Bark) {
        speaking = true
        if let at = bark.spokeAt { memory.set(at, forKey: Self.spokeKey) }
        if let sink { return sink(bark.name) { [weak self] in self?.ended() } }
        // A clip that cannot be opened or played is no sound, and over at once: the next one
        // must not wait on it.
        let system = Self.systemChimes[bark.name]
        let url = system.map { URL(fileURLWithPath: "/System/Library/Sounds/\($0).aiff") } ?? sounds.url(bark.name)
        let volume = settings.soundVolume
        let plain = { system.flatMap { NSSound(named: $0)?.copy() as? NSSound } ?? NSSound(contentsOf: url, byReference: true) }
        guard let sound = (volume > 1 ? Self.louder(url, volume: volume) : nil) ?? plain() else { return ended() }
        sound.delegate = self
        sound.volume = Float(min(volume, 1))
        playing = sound
        if !sound.play() {
            playing = nil
            ended()
        }
    }

    /// The clip at `url` made louder for a volume past 1, by `Sound.boost`. Through a file of
    /// its own, read in whole and gone at once: NSSound plays no louder than its file. nil
    /// when the clip cannot be read or written: it then plays as it is.
    static func louder(_ url: URL, volume: Double) -> NSSound? {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("agent-valley-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: copy) }
        guard boost(url, volume: volume, into: copy) else { return nil }
        return NSSound(contentsOf: copy, byReference: false)
    }

    /// Writes the clip at `url` to `copy`, turned up by `Sound.boost` for its loudest sample.
    static func boost(_ url: URL, volume: Double, into copy: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let channels = buffer.floatChannelData else { return false }
        let frames = Int(buffer.frameLength), count = Int(buffer.format.channelCount)
        var peak: Float = 0
        for c in 0..<count { for i in 0..<frames { peak = max(peak, abs(channels[c][i])) } }
        let gain = Sound.boost(volume: volume, peak: peak)
        for c in 0..<count { for i in 0..<frames { channels[c][i] *= gain } }
        do {
            let out = try AVAudioFile(forWriting: copy, settings: file.processingFormat.settings)
            try out.write(from: buffer)
            out.close()
        } catch { return false }
        return true
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        guard sound === playing else { return }
        playing = nil
        ended()
    }

    /// The clip is over: the queued bark goes next if it may play now, by the same rules as
    /// had it come just now. The person's own click only waits for someone at the screen. A
    /// wait the lock keeps back is owed until it is down; anything else is dropped.
    private func ended() {
        speaking = false
        guard let next = queued else { return }
        queued = nil
        if next.asked ? !locked : allowed(next.kind, now: Date()) { return speak(next) }
        if next.kind == .needsYou, !next.asked, locked { held = true }
    }
}
