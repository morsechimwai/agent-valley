import Foundation

/// One usage window of the Claude plan.
struct PlanLimit: Equatable {
    enum Level: Equatable {
        case normal, high, critical
    }

    let usedPercent: Double
    let resetsAt: Date?

    var level: Level {
        usedPercent >= 95 ? .critical : usedPercent >= 80 ? .high : .normal
    }

    /// Whether the time until reset is the thing to know: near the limit, the question is when
    /// work can go on. Its reset time is the last to give way when room runs out.
    var resetMatters: Bool { level != .normal }

    var percentLabel: String { "\(Int(usedPercent.rounded()))%" }

    /// How much of its track the bar fills. Over the limit still fills the track and no more.
    var fraction: Double { min(max(usedPercent / 100, 0), 1) }

    /// "45m", "2h 10m" or "3d 4h" until the window resets; nil once that time has passed.
    func resetLabel(now: Date) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        let minutes = Int(resetsAt.timeIntervalSince(now) / 60)
        if minutes < 60 { return "\(max(1, minutes))m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" }
        return "\(minutes / 1440)d \(minutes % 1440 / 60)h"
    }
}

struct PlanLimits: Equatable {
    var fiveHour: PlanLimit?
    var week: PlanLimit?
    /// The plan's name, as the terminal's status line has it: "Ultra".
    var plan: String?

    /// The window that has run out and comes back last, or nil while there is room: Claude Code
    /// waits for it. Out once its meter reads 100%. Past its reset time it is back, whatever the
    /// last numbers said.
    func runOut(now: Date) -> RunOut? {
        let out = [(false, fiveHour), (true, week)].compactMap { weekly, limit -> RunOut? in
            guard let limit, limit.usedPercent.rounded() >= 100, limit.resetsAt.map({ $0 > now }) ?? true else { return nil }
            return RunOut(weekly: weekly, resetsAt: limit.resetsAt)
        }
        return out.max { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
    }
}

/// A plan window that has run out: the crew has gone fishing until it resets.
struct RunOut: Equatable {
    let weekly: Bool
    let resetsAt: Date?
}

/// What the ring on the shut bar draws: the 5-hour window, the one that stops work soonest, or
/// the weekly one on a plan without a 5-hour window.
struct LimitRing: Equatable {
    let limit: PlanLimit
    /// The latest refresh failed and this is the number from before it.
    let stale: Bool
    var weekly = false
}

/// Why there are no numbers. It names a cause the person can act on and nothing else: no part
/// of the login or of a reply is ever carried in it.
enum LimitsFailure: Error, Equatable {
    /// No Claude Code item in the Keychain, or it could not be read.
    case noLogin
    /// The login in it has run out. Only Claude Code renews it; this app never does.
    case loginExpired
    /// The Keychain's login has no Claude plan: a Console sign-in, billed per use.
    case notSubscribed
    /// No answer from the usage endpoint.
    case offline
    /// It answered with this HTTP status.
    case refused(Int)
    /// It answered with something that holds no limits.
    case unreadable
    /// A fetch was given up on after a minute.
    case noAnswer
}

/// Reads what Claude Code keeps in the Keychain and what the usage endpoint replies. Pure:
/// it never touches the Keychain or the network itself.
enum PlanLimitsReader {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain = ISO8601DateFormatter()

    /// The access token in the Keychain item, or nil when it is missing, malformed or expired.
    /// The item looks like `{"claudeAiOauth":{"accessToken":…,"expiresAt":<milliseconds>}}`.
    static func token(fromKeychainItem data: Data, now: Date) -> String? {
        try? login(fromKeychainItem: data, now: now).get()
    }

    /// The same, saying why when there is none: the person is told different things for a login
    /// that is missing and one that has expired.
    static func login(fromKeychainItem data: Data, now: Date) -> Result<String, LimitsFailure> {
        guard let object = SafeJSON.object(data),
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return .failure(.noLogin) }
        // A Console login keeps an item too, without a plan or the right to chat on one. An item
        // that names neither, from an older Claude Code, is taken as a plan as before.
        let plan = (oauth["subscriptionType"] as? String).map { !$0.isEmpty } ?? false
        if !plan, let scopes = oauth["scopes"] as? [String], !scopes.contains("user:inference") { return .failure(.notSubscribed) }
        if let expires = oauth["expiresAt"] as? NSNumber,
           Date(timeIntervalSince1970: expires.doubleValue / 1000) <= now { return .failure(.loginExpired) }
        return .success(token)
    }

    /// What `security find-generic-password` gave. No item at all (status 44) is not taken as
    /// pay per use: a plan login kept under another name, with CLAUDE_CONFIG_DIR set, looks the same.
    static func login(securityStatus: Int32, item: Data, now: Date) -> Result<String, LimitsFailure> {
        guard securityStatus == 0 else { return .failure(.noLogin) }
        return login(fromKeychainItem: item, now: now)
    }

    /// The 5-hour and weekly limits in a usage reply, or nil when it holds neither. The reply is
    /// undocumented: it has come as a `limits` list and, before that, as top-level windows.
    static func parse(_ data: Data) -> PlanLimits? {
        guard let object = SafeJSON.object(data) else { return nil }
        var limits = PlanLimits()
        for item in object["limits"] as? [[String: Any]] ?? [] {
            guard let percent = number(item["percent"]) else { continue }
            let limit = PlanLimit(usedPercent: percent, resetsAt: date(item["resets_at"]))
            switch item["kind"] as? String {
            case "session": if limits.fiveHour == nil { limits.fiveHour = limit }
            case "weekly_all": if limits.week == nil { limits.week = limit }
            default: break
            }
        }
        func legacy(_ key: String) -> PlanLimit? {
            guard let item = object[key] as? [String: Any], let used = number(item["utilization"]) else { return nil }
            return PlanLimit(usedPercent: used, resetsAt: date(item["resets_at"]))
        }
        if limits.fiveHour == nil { limits.fiveHour = legacy("five_hour") }
        if limits.week == nil { limits.week = legacy("seven_day") }
        return limits.fiveHour == nil && limits.week == nil ? nil : limits
    }

    /// A percentage the app can show. "nan", "inf" and absurd magnitudes are no data: rounding
    /// one to an Int would trap, and the status row is drawn even while the panel is closed.
    private static func number(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else if let text = value as? String {
            number = Double(text)
        } else {
            number = nil
        }
        guard let number, number.isFinite, (0...100_000).contains(number) else { return nil }
        return number
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
        // A fraction the formatter will not take: read the time without it.
        return plain.date(from: text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
    }
}

/// Refuses every redirect, so a request carrying the token can never follow one to another host.
/// The 3xx reply then ends the task and reads as a failed fetch.
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Where the limits come from. `fetch` answers on the main thread, once, unless it is cancelled
/// first; it returns the way to cancel.
protocol PlanLimitsSource {
    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void
}

/// The real source: the Claude Code login in the Keychain, then Anthropic's usage endpoint.
/// The only code that runs `security` and touches the network.
final class KeychainLimitsSource: PlanLimitsSource {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"
    /// `security` is stopped if it has not answered by then, for instance while it waits on a prompt.
    static let securityTimeout: TimeInterval = 10

    private let session = KeychainLimitsSource.makeSession()

    /// Ephemeral: nothing about these requests is cached or stored on disk. Redirects are refused.
    static func makeSession() -> URLSession {
        URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
    }

    static func request(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentValley", forHTTPHeaderField: "User-Agent")
        return request
    }

    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void {
        let flight = Flight()
        let answer: (Result<PlanLimits, LimitsFailure>) -> Void = { result in
            DispatchQueue.main.async {
                if !flight.isCancelled { done(result) }
            }
        }
        DispatchQueue.global(qos: .utility).async { [session] in
            // The token exists only inside this closure: read, used for one request, gone.
            // It is never refreshed here; that would sign Claude Code out.
            let token: String
            switch Self.readToken(for: flight) {
            case .success(let read): token = read
            case .failure(let reason): return answer(.failure(reason))
            }
            let task = session.dataTask(with: Self.request(token: token)) { data, response, error in
                answer(Self.outcome(data: data, response: response, failed: error != nil).map { limits in
                    var limits = limits
                    limits.plan = Self.plan()
                    return limits
                })
            }
            if flight.begin({ task.cancel() }) { task.resume() }
        }
        return flight.cancel
    }

    /// The plan's name from what Claude Code keeps in `~/.claude.json`: the usage reply has none.
    static func plan(home: URL = URL(fileURLWithPath: NSHomeDirectory()),
                     environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        (try? Data(contentsOf: CrewSetup.claudeJSON(home: home, environment: environment)))
            .flatMap(CrewSetup.oauthAccount).flatMap { CrewLine.plan(fromClaudeJSON: ["oauthAccount": $0]) }
    }

    /// Sorts a reply into numbers or the reason there are none. The reason is a category and at
    /// most a status code; nothing of the reply's content is kept.
    static func outcome(data: Data?, response: URLResponse?, failed: Bool) -> Result<PlanLimits, LimitsFailure> {
        guard !failed, let status = (response as? HTTPURLResponse)?.statusCode else { return .failure(.offline) }
        // Only Claude Code can renew its login, so a refused login is the person's to fix there.
        if status == 401 { return .failure(.loginExpired) }
        guard status == 200 else { return .failure(.refused(status)) }
        return data.flatMap(PlanLimitsReader.parse).map(Result.success) ?? .failure(.unreadable)
    }

    /// Asks the Keychain through `security`, which Claude Code's own item already trusts.
    /// Cancelling the flight stops `security` at once: with Plan limits off it must not keep running.
    private static func readToken(for flight: Flight) -> Result<String, LimitsFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard flight.begin({ if process.isRunning { process.terminate() } }) else { return .failure(.noLogin) }
        do { try process.run() } catch { return .failure(.noLogin) }
        // Cancelled between the two lines above: the stop ran before there was anything to stop.
        if flight.isCancelled, process.isRunning { process.terminate() }
        let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + securityTimeout, execute: stop)
        let item = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stop.cancel()
        return PlanLimitsReader.login(securityStatus: process.terminationStatus, item: item, now: Date())
    }

    /// One fetch, shared between the thread that runs it and the one that may cancel it.
    final class Flight {
        private let lock = NSLock()
        private var cancelled = false
        /// Stops the step now under way: the Keychain read, then the request.
        private var stop: (() -> Void)?

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        /// Takes the way to stop the next step; false if the fetch was cancelled before it began.
        func begin(_ stop: @escaping () -> Void) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if cancelled { return false }
            self.stop = stop
            return true
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let stop = self.stop
            self.stop = nil
            lock.unlock()
            stop?()
        }
    }
}

/// How a session pays: by plan, or per use through one of these. Only this word ever leaves
/// the session's hook; never a key or a token.
enum LoginKind: String {
    case plan, api, gateway, bedrock, vertex, foundry

    var payPerUse: Bool { self != .plan }

    /// Shown where a plan's name goes.
    var badge: String {
        switch self {
        case .plan: return "Plan"
        case .api: return "API"
        case .gateway: return "Gateway"
        case .bedrock: return "Bedrock"
        case .vertex: return "Vertex"
        case .foundry: return "Foundry"
        }
    }
}

/// A login billed per use rather than by plan: how it pays, and what today has cost so far at API prices.
struct PayPerUse: Equatable {
    /// "API", "Bedrock", "Vertex": shown where a plan's name goes.
    let via: String
    /// nil while Token use is off: then nothing on this Mac counts it.
    let spentToday: Double?
    /// Some of today's answers came from a model with no known price, and are left out of the sum.
    var unpriced = false
}

/// Decides when to fetch and what to show. Touches neither the Keychain nor the network itself,
/// and asks its source for nothing while disabled. All state lives on the main thread.
final class PlanLimitsClient: ObservableObject {
    static let refreshEvery: TimeInterval = 300
    /// Opening the panel refreshes only if the last attempt is older than this.
    static let staleAfter: TimeInterval = 60
    /// A failed fetch keeps showing the last numbers for this long.
    static let keepLastFor: TimeInterval = 900
    /// A fetch still unanswered after this long is abandoned so the next one can start.
    static let giveUpAfter: TimeInterval = 60

    /// What the status row shows where the limits go.
    enum Display: Equatable {
        case off
        /// On, and the first answer has not come back yet.
        case loading
        /// On, but there are no numbers to show, and why.
        case unavailable(LimitsFailure)
        /// `asOf`: set when the latest refresh failed, to the time these older numbers are from.
        case limits(PlanLimits, asOf: Date?)
        /// Logged in with an API key or a cloud platform: no plan limits, so what today has cost.
        case payPerUse(PayPerUse)

        /// The ring for the shut bar: the 5-hour window, else the weekly one, else nil. An empty
        /// ring would say that nothing has been used.
        var ring: LimitRing? {
            guard case .limits(let limits, let asOf) = self, let limit = limits.fiveHour ?? limits.week else { return nil }
            return LimitRing(limit: limit, stale: asOf != nil, weekly: limits.fiveHour == nil)
        }

        /// Whether the panel has numbers to go by.
        var hasNumbers: Bool {
            if case .limits = self { return true }
            return false
        }

        func runOut(now: Date) -> RunOut? {
            guard case .limits(let limits, _) = self else { return nil }
            return limits.runOut(now: now)
        }
    }

    @Published private(set) var limits: PlanLimits?
    @Published private(set) var enabled = false
    /// Why the latest fetch brought no numbers, or nil when it did or none has finished yet.
    @Published private(set) var failure: LimitsFailure?
    /// Sessions in the order they started, and how each pays as its hook saw it: nil when the
    /// hook could not tell, which leaves it to the Keychain.
    // ponytail: never pruned and not kept across launches; a few dozen a day. Prune by `live` if it ever matters.
    @Published private var started: [Start] = []
    /// The sessions still open, by id.
    @Published private var live: Set<String> = []
    /// What the latest session's hook said, kept across launches: sessions the app never saw
    /// start, from before it opened, are taken to pay the same way.
    @Published private var lastHook: LoginKind?
    /// Today's cost so far by session, at API prices, and the sessions with answers no price is
    /// known for. `spent` is nil while Token use is off.
    @Published private var spent: [String: Double]?
    @Published private var unpriced: Set<String> = []

    private struct Start: Equatable {
        let session: String
        let kind: LoginKind?
    }

    /// What the Keychain says, or nil while it has not said: a plan when it has numbers or any
    /// trouble that is not about the plan itself.
    private var keychainKind: LoginKind? {
        if limits != nil { return .plan }
        switch failure {
        case nil, .noLogin: return nil
        case .notSubscribed: return .api
        default: return .plan
        }
    }

    /// The kinds of the open sessions the app saw start.
    private var liveKinds: [LoginKind?] {
        started.filter { live.contains($0.session) }.map(\.kind)
    }

    /// How the open sessions pay. A plan wins over pay per use: its limits are the thing to watch.
    var login: LoginKind? {
        let kinds = liveKinds.map { $0 ?? keychainKind }
        guard !kinds.isEmpty else { return lastHook ?? keychainKind }
        if kinds.contains(.plan) { return .plan }
        if kinds.contains(nil) { return nil }
        return kinds.last ?? nil
    }

    /// Whether anything open, or about to open, could be on a plan: only then is the Keychain asked.
    private var needsKeychain: Bool {
        let kinds = liveKinds
        guard !kinds.isEmpty else { return lastHook == nil || lastHook == .plan }
        return kinds.contains { $0 == nil || $0 == .plan }
    }

    /// How one session pays: as its hook said, else as the latest hook said, else the Keychain.
    func kind(of session: String) -> LoginKind? {
        if let start = started.last(where: { $0.session == session }) { return start.kind ?? keychainKind }
        return lastHook ?? keychainKind
    }

    /// What today has cost in the sessions that pay this way, or nil while Token use is off.
    func spend(_ kind: LoginKind) -> (dollars: Double, unpriced: Bool)? {
        guard let spent else { return nil }
        let dollars = spent.reduce(0) { $0 + (self.kind(of: $1.key) == kind ? $1.value : 0) }
        return (dollars, unpriced.contains { self.kind(of: $0) == kind })
    }

    /// How each of these sessions pays, for those paid per use, with today's cost that way.
    func payPerUse(of sessions: some Sequence<String>) -> [String: PayPerUse] {
        var out: [String: PayPerUse] = [:]
        for id in sessions {
            guard let kind = kind(of: id), kind.payPerUse else { continue }
            let cost = spend(kind)
            out[id] = PayPerUse(via: kind.badge, spentToday: cost?.dollars, unpriced: cost?.unpriced ?? false)
        }
        return out
    }

    var display: Display {
        guard enabled else { return .off }
        if let login, login.payPerUse {
            let cost = self.spend(login)
            return .payPerUse(PayPerUse(via: login.badge, spentToday: cost?.dollars, unpriced: cost?.unpriced ?? false))
        }
        if let limits { return .limits(limits, asOf: failure == nil ? nil : fetchedAt) }
        return failure.map(Display.unavailable) ?? .loading
    }

    private let source: PlanLimitsSource
    private let now: () -> Date
    private var inFlight = false
    private var cancelFlight: (() -> Void)?
    /// Names the fetch in progress. An answer carrying an older number is dropped.
    private var flight = 0
    private var attemptedAt: Date?
    private var fetchedAt: Date?
    private var timer: Timer?
    private let defaults: UserDefaults
    private static let lastHookKey = "lastLoginKind"

    init(source: PlanLimitsSource = KeychainLimitsSource(), now: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard) {
        self.source = source
        self.now = now
        self.defaults = defaults
        lastHook = defaults.string(forKey: Self.lastHookKey).flatMap(LoginKind.init(rawValue:))
    }

    /// A session has started, and its hook said how it pays (nil: it could not tell).
    func record(session: String, login: LoginKind?) {
        started.removeAll { $0.session == session }
        started.append(Start(session: session, kind: login))
        if lastHook != login {
            lastHook = login
            defaults.set(login?.rawValue, forKey: Self.lastHookKey)
        }
        if login == nil || login == .plan { refreshIfStale() }
    }

    /// The sessions now open. Asks the Keychain when the last one that kept it from asking has closed.
    func setLive(_ sessions: Set<String>) {
        guard sessions != live else { return }
        let needed = needsKeychain
        live = sessions
        if !needed, needsKeychain { refreshIfStale() }
    }

    /// Today's cost by session, from the token history; nil while Token use is off.
    func setSpend(_ spent: [String: Double]?, unpriced: Set<String>) {
        if self.spent != spent { self.spent = spent }
        if self.unpriced != unpriced { self.unpriced = unpriced }
    }

    deinit {
        timer?.invalidate()
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        timer?.invalidate()
        timer = nil
        guard on else {
            abandonFlight()
            limits = nil
            failure = nil
            fetchedAt = nil
            attemptedAt = nil
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshEvery, repeats: true) { [weak self] _ in
            self?.tick()
        }
        refresh()
    }

    /// Called when the panel opens: current numbers without polling harder than needed.
    func refreshIfStale() {
        if let attemptedAt, now().timeIntervalSince(attemptedAt) < Self.staleAfter { return }
        refresh()
    }

    /// The periodic pass: take down numbers that have gone stale, then fetch again.
    func tick() {
        guard enabled else { return }
        show(Self.resolve(result: nil, last: limits, lastFetchedAt: fetchedAt, now: now()))
        refresh()
    }

    /// What to show after a fetch: the new numbers, or the last ones while they are still recent.
    static func resolve(result: PlanLimits?, last: PlanLimits?, lastFetchedAt: Date?, now: Date) -> PlanLimits? {
        if let result { return result }
        guard let lastFetchedAt, now.timeIntervalSince(lastFetchedAt) <= keepLastFor else { return nil }
        return last
    }

    private func refresh() {
        guard enabled, needsKeychain else { return }
        if inFlight, let attemptedAt, now().timeIntervalSince(attemptedAt) >= Self.giveUpAfter {
            abandonFlight()
            failure = .noAnswer
        }
        guard !inFlight else { return }
        inFlight = true
        attemptedAt = now()
        flight += 1
        let mine = flight
        let cancel = source.fetch { [weak self] result in self?.finish(result, flight: mine) }
        // A source may answer before `fetch` returns; only a fetch still under way keeps its cancel.
        if inFlight, flight == mine { cancelFlight = cancel }
    }

    private func finish(_ outcome: Result<PlanLimits, LimitsFailure>, flight answered: Int) {
        guard enabled, inFlight, answered == flight else { return }
        inFlight = false
        cancelFlight = nil
        let time = now()
        let result = try? outcome.get()
        show(Self.resolve(result: result, last: limits, lastFetchedAt: fetchedAt, now: time))
        if result != nil { fetchedAt = time }
        var reason: LimitsFailure?
        if case .failure(let why) = outcome { reason = why }
        if failure != reason { failure = reason }
    }

    /// Stops the fetch under way and disowns it, so an answer already on its way changes nothing.
    private func abandonFlight() {
        cancelFlight?()
        cancelFlight = nil
        inFlight = false
        flight += 1
    }

    private func show(_ next: PlanLimits?) {
        if limits != next { limits = next }
    }
}
