import Foundation

/// The one thing the app sends us: once a day, that a release ran. Its version, the macOS
/// version, and whether this is the Mac's first count. No name and no id: each count carries a
/// new random one, so two days can't be tied together. It goes through agentvalley.app to
/// PostHog, which reads the country from the IP address and then drops the address. A build to
/// work on the app never starts it; the switch is Send a daily count in About.
final class DailyCount {
    static let endpoint = URL(string: "https://agentvalley.app/ingest/i/v0/e/")!
    /// The site's public PostHog key: it can only send events, never read them.
    static let token = "phc_BW9fdvDdnyfQmKArTiTCJnQdBwXEFqi7LALhqcYQpAqb" // gitleaks:allow
    static let event = "app daily"

    private let settings: Settings
    private let session = URLSession(configuration: .ephemeral)
    private var timer: Timer?
    private var sending = false

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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AgentValley", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "api_key": token,
            "event": event,
            "distinct_id": UUID().uuidString,
            "properties": [
                "version": version,
                "macos": "\(macOS.majorVersion).\(macOS.minorVersion)",
                "first": first,
                // No person in PostHog for it, only the event.
                "$process_person_profile": false,
            ] as [String: Any],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func tick() {
        guard !sending, Self.isDue(last: settings.countedAt, now: Date()) else { return }
        sending = true
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let request = Self.request(version: version, macOS: ProcessInfo.processInfo.operatingSystemVersion,
                                   first: settings.countedAt == nil)
        session.dataTask(with: request) { [weak self] _, response, _ in
            let sent = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async {
                guard let self else { return }
                self.sending = false
                if sent { self.settings.countedAt = Date() }
            }
        }.resume()
    }
}
