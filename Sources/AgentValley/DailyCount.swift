import Foundation

/// What the app sends us: once a day, that a release ran. Its version, the macOS version, and
/// whether this is the Mac's first count. No name and no id: each count carries a new random
/// one, so two days can't be tied together. It goes through agentvalley.app to PostHog, which
/// reads the country from the IP address and then drops the address. A build to work on the app
/// never starts it; the switch is Send a daily count in About. The same switch carries the one
/// answer to where the person heard about us (HeardFrom), sent once.
final class DailyCount {
    static let endpoint = URL(string: "https://agentvalley.app/ingest/i/v0/e/")!
    /// The site's public PostHog key: it can only send events, never read them.
    static let token = "phc_BW9fdvDdnyfQmKArTiTCJnQdBwXEFqi7LALhqcYQpAqb" // gitleaks:allow
    static let event = "app daily"
    static let heardEvent = "app heard from"

    private let settings: Settings
    private let session = URLSession(configuration: .ephemeral)
    private var timer: Timer?
    private var sending = false
    private var sendingHeard = false

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

    static func heardRequest(answer: String, version: String) -> URLRequest {
        post(event: heardEvent, properties: ["answer": answer, "version": version])
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

    /// The person picked where they heard about us: it goes now, while the count is on. One that
    /// fails goes again with the next hourly tick, or at the next launch.
    // ponytail: a reply lost after PostHog took the answer sends it again; rare, and there is no
    // id to tell the two apart. Dedupe in PostHog by time if it ever shows in the numbers.
    func sendHeard() {
        guard timer != nil, !sendingHeard, HeardFrom.due(answer: settings.heardFrom, sent: settings.heardSent),
              let answer = settings.heardFrom else { return }
        sendingHeard = true
        send(Self.heardRequest(answer: answer, version: Self.version)) { [weak self] sent in
            self?.sendingHeard = false
            if sent { self?.settings.heardSent = true }
        }
    }

    private func tick() {
        sendHeard()
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

/// The one question the panel asks, once per Mac: where the person heard about us. It tells us
/// which places bring people who install, not just people who look. A tap on an answer sends it
/// (DailyCount); Skip sends nothing. Both put the question away for good.
enum HeardFrom {
    /// The owner's list, in two rows to fit the panel.
    static let rows = [["Product Hunt", "Facebook", "X", "Bluesky", "Reddit"], ["GitHub", "Google", "A friend", "Other"]]
    /// Kept in place of an answer when the person skipped: asked, and never sent.
    static let skipped = "skip"

    static func asks(release: Bool, counting: Bool, answer: String?) -> Bool {
        release && counting && answer == nil
    }

    /// Picked, not skipped, and not gone out yet.
    static func due(answer: String?, sent: Bool) -> Bool {
        answer != nil && answer != skipped && !sent
    }
}
