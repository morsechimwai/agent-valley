import Foundation

/// What the app sends us: once a day, that a release ran. Its version, the macOS version, and
/// whether this is the Mac's first count. No name and no id: each count carries a new random
/// one, so two days can't be tied together. It goes through agentvalley.app to PostHog, which
/// reads the country from the IP address and then drops the address. A build to work on the app
/// never starts it; the switch is Send a daily count in About. The same switch carries the one
/// outcome of where the person heard about us (HeardFrom): an answer, or a final skip, sent once.
final class DailyCount {
    static let endpoint = URL(string: "https://agentvalley.app/ingest/i/v0/e/")!
    /// The site's public PostHog key: it can only send events, never read them.
    static let token = "phc_BW9fdvDdnyfQmKArTiTCJnQdBwXEFqi7LALhqcYQpAqb" // gitleaks:allow
    static let event = "app daily"
    static let heardEvent = "app heard from"
    static let ratingEvent = "app rating"

    private let settings: Settings
    private let session = URLSession(configuration: .ephemeral)
    private var timer: Timer?
    private var sending = false
    private var sendingHeard = false
    private var sendingRating = false

    init(settings: Settings) { self.settings = settings }

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        // Hourly, as the app stays open for days; a send that failed tries again an hour on.
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    static func isDue(last: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let last else { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }

    static func request(version: String, macOS: OperatingSystemVersion, first: Bool) -> URLRequest {
        post(event: event, properties: [
            "version": version,
            "macos": "\(macOS.majorVersion).\(macOS.minorVersion)",
            "first": first,
        ])
    }

    /// `again`: it came on the second ask, after a first skip.
    static func heardRequest(answer: String, version: String, again: Bool) -> URLRequest {
        post(event: heardEvent, properties: ["answer": answer, "version": version, "again": again])
    }

    /// `stars`: 1 to 5, or `AppRating.skipped` for a final skip. `again`: it came after a first skip.
    static func ratingRequest(stars: Int, version: String, again: Bool) -> URLRequest {
        let what: [String: Any] = stars == AppRating.skipped ? ["skipped": true] : ["stars": stars]
        return post(event: ratingEvent, properties: what.merging(["version": version, "again": again]) { a, _ in a })
    }

    private static func post(event: String, properties: [String: Any]) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AgentValley", forHTTPHeaderField: "User-Agent")
        // No person in PostHog for it, only the event.
        let body: [String: Any] = [
            "api_key": token,
            "event": event,
            "distinct_id": UUID().uuidString,
            "properties": properties.merging(["$process_person_profile": false]) { a, _ in a },
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// The person picked where they heard about us, or skipped for good: it goes now, while the
    /// count is on. One that
    /// fails goes again with the next hourly tick, or at the next launch.
    // ponytail: a reply lost after PostHog took the answer sends it again; rare, and there is no
    // id to tell the two apart. Dedupe in PostHog by time if it ever shows in the numbers.
    func sendHeard() {
        guard timer != nil, !sendingHeard, HeardFrom.due(answer: settings.heardFrom, sent: settings.heardSent, skippedAt: settings.heardSkippedAt),
              let answer = settings.heardFrom else { return }
        sendingHeard = true
        send(Self.heardRequest(answer: answer, version: Self.version,
                                          again: settings.heardSkippedAt != nil)) { [weak self] sent in
            self?.sendingHeard = false
            if sent { self?.settings.heardSent = true }
        }
    }

    /// The star rating goes out once, like the heard answer. It also starts the rating's week the
    /// first time the heard box is seen done.
    func sendRating() {
        settings.startRatingClock()
        guard timer != nil, !sendingRating, AppRating.due(rating: settings.rating, sent: settings.ratingSent),
              let stars = settings.rating else { return }
        sendingRating = true
        send(Self.ratingRequest(stars: stars, version: Self.version, again: settings.ratingSkippedAt != nil)) { [weak self] sent in
            self?.sendingRating = false
            if sent { self?.settings.ratingSent = true }
        }
    }

    private func tick() {
        sendHeard()
        sendRating()
        guard !sending, Self.isDue(last: settings.countedAt, now: Date()) else { return }
        sending = true
        let request = Self.request(version: Self.version, macOS: ProcessInfo.processInfo.operatingSystemVersion,
                                   first: settings.countedAt == nil)
        send(request) { [weak self] sent in
            self?.sending = false
            if sent { self?.settings.countedAt = Date() }
        }
    }

    /// On the main queue, whether it went.
    private func send(_ request: URLRequest, done: @escaping (Bool) -> Void) {
        session.dataTask(with: request) { _, response, _ in
            let sent = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async { done(sent) }
        }.resume()
    }
}

/// The one question the panel asks: where the person heard about us. It tells us which places
/// bring people who install, not just people who look. A tap on an answer sends it (DailyCount).
/// The first Skip puts the question away for a week; the second is final and goes out as "skip".
enum HeardFrom {
    /// The owner's list, in two rows to fit the panel.
    static let rows = [["Product Hunt", "Facebook", "X", "Bluesky", "Reddit"], ["GitHub", "Google", "A friend", "Other"]]
    /// Kept in place of an answer when the person skipped twice, and sent as the answer.
    static let skipped = "skip"
    /// How long the first Skip waits before the question comes back.
    static let askAgainAfter: TimeInterval = 7 * 86_400

    static func asks(release: Bool, counting: Bool, answer: String?, skippedAt: Date?, now: Date) -> Bool {
        release && counting && answer == nil && weekOver(since: skippedAt, now: now)
    }

    /// No first skip yet, or a week since it.
    static func weekOver(since skippedAt: Date?, now: Date) -> Bool {
        skippedAt.map { now.timeIntervalSince($0) >= askAgainAfter } ?? true
    }

    /// Answered or skipped for good, and not gone out yet. A skip with no date is from 0.3.23,
    /// which told the person Skip sends nothing: it never goes out.
    static func due(answer: String?, sent: Bool, skippedAt: Date?) -> Bool {
        answer != nil && !sent && (answer != skipped || skippedAt != nil)
    }
}

/// The star rating, a week after the heard box is done. The words go on a page of the site; the
/// app sends only the stars. Skip works as in HeardFrom: the first waits a week, the second is final.
enum AppRating {
    /// Kept in place of the stars when the person skipped twice.
    static let skipped = 0

    static func asks(release: Bool, counting: Bool, heardDone: Bool, clockAt: Date?, rating: Int?, skippedAt: Date?, now: Date) -> Bool {
        guard release, counting, heardDone, rating == nil, let clockAt else { return false }
        return HeardFrom.weekOver(since: clockAt, now: now) && HeardFrom.weekOver(since: skippedAt, now: now)
    }

    static func due(rating: Int?, sent: Bool) -> Bool { rating != nil && !sent }

    static func reviewURL(stars: Int) -> URL { URL(string: "https://agentvalley.app/review?stars=\(stars)")! }
}
