import XCTest
@testable import AgentValley

/// Stands in for the Keychain and the network: counts what the client asks for and answers on demand.
private final class FakeSource: PlanLimitsSource {
    private(set) var fetches = 0
    private(set) var cancels = 0
    private var waiting: [(Result<PlanLimits, LimitsFailure>) -> Void] = []

    func fetch(_ done: @escaping (Result<PlanLimits, LimitsFailure>) -> Void) -> () -> Void {
        fetches += 1
        waiting.append(done)
        return { [weak self] in self?.cancels += 1 }
    }

    /// Answers the fetch at `index`, or the latest one.
    /// A nil answer is a failed fetch, for `reason`.
    func answer(_ limits: PlanLimits?, because reason: LimitsFailure = .offline, fetch index: Int? = nil) {
        let index = index ?? waiting.count - 1
        guard waiting.indices.contains(index) else { return XCTFail("fetch \(index) was never started") }
        waiting[index](limits.map(Result.success) ?? .failure(reason))
    }
}

final class PlanLimitsClientTests: XCTestCase {
    private var source: FakeSource!
    private var client: PlanLimitsClient!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private let some = PlanLimits(fiveHour: PlanLimit(usedPercent: 40, resetsAt: nil), week: nil)

    private let suite = "PlanLimitsClientTests." + UUID().uuidString
    private var defaults: UserDefaults!

    override func setUp() {
        source = FakeSource()
        defaults = UserDefaults(suiteName: suite)
        client = PlanLimitsClient(source: source, now: { [unowned self] in self.clock }, defaults: defaults)
    }

    override func tearDown() {
        client.setEnabled(false)
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: - How the sessions pay

    // One session on a plan is enough: its limits are what to watch.
    func testAPlanAmongPayPerUseSessionsShowsTheLimits() {
        client.record(session: "a", login: .api)
        client.record(session: "b", login: .plan)
        client.setLive(["a", "b"])
        client.setEnabled(true)
        source.answer(some)
        XCTAssertEqual(client.login, .plan)
        XCTAssertEqual(client.display, .limits(some, asOf: nil))
        // The plan session closes: what is left pays per use.
        client.setLive(["a"])
        XCTAssertEqual(client.login, .api)
        XCTAssertEqual(client.display, .payPerUse(PayPerUse(via: "API", spentToday: nil)))
    }

    // Nothing open is on a plan: the Keychain and the network are left alone.
    func testPayPerUseAloneNeverAsksTheKeychain() {
        client.record(session: "a", login: .api)
        client.setLive(["a"])
        client.setSpend(["a": 4.27], unpriced: [])
        client.setEnabled(true)
        XCTAssertEqual(source.fetches, 0)
        XCTAssertEqual(client.display, .payPerUse(PayPerUse(via: "API", spentToday: 4.27)))
        clock += 3600
        client.refreshIfStale()
        client.tick()
        XCTAssertEqual(source.fetches, 0)
        // A plan session opens: now the limits are wanted.
        client.record(session: "b", login: .plan)
        client.setLive(["a", "b"])
        XCTAssertEqual(source.fetches, 1)
        // A session that cannot tell leaves it to the Keychain, so that asks too.
        source.answer(some)
        client.setLive(["a"])
        clock += 3600
        client.record(session: "c", login: nil)
        client.setLive(["a", "c"])
        XCTAssertEqual(source.fetches, 2)
    }

    // Sessions from before the app opened pay as the latest hook said, even after a restart.
    func testTheLatestLoginOutlivesARestart() {
        client.record(session: "a", login: .bedrock)
        client.setEnabled(false)
        let later = PlanLimitsClient(source: source, now: { [unowned self] in self.clock }, defaults: defaults)
        later.setEnabled(true)
        XCTAssertEqual(source.fetches, 0)
        XCTAssertEqual(later.login, .bedrock)
        XCTAssertEqual(later.display, .payPerUse(PayPerUse(via: "Bedrock", spentToday: nil)))
        later.setEnabled(false)
    }

    // A Console login in the Keychain has no plan: shown as paid by API, not as trouble.
    func testAKeychainLoginWithNoPlanPaysPerUse() {
        client.setEnabled(true)
        source.answer(nil, because: .notSubscribed)
        XCTAssertEqual(client.login, .api)
        XCTAssertEqual(client.display, .payPerUse(PayPerUse(via: "API", spentToday: nil)))
    }

    func testNoLoginAtAllSaysSo() {
        client.setEnabled(true)
        source.answer(nil, because: .noLogin)
        XCTAssertNil(client.login)
        XCTAssertEqual(client.display, .unavailable(.noLogin))
    }

    // Each way of paying adds up its own sessions; plan sessions cost nothing extra.
    func testTodaysSpendAddsUpBySessionKind() {
        client.record(session: "a", login: .api)
        client.record(session: "b", login: .api)
        client.record(session: "c", login: .bedrock)
        client.record(session: "d", login: .plan)
        client.setSpend(["a": 1, "b": 2.5, "c": 4, "d": 8], unpriced: ["c"])
        XCTAssertEqual(client.spend(.api)?.dollars, 3.5)
        XCTAssertEqual(client.spend(.api)?.unpriced, false)
        XCTAssertEqual(client.spend(.bedrock)?.dollars, 4)
        XCTAssertEqual(client.spend(.bedrock)?.unpriced, true)
        // "e" never seen start pays as the latest hook said: the plan, so it is left out with "d".
        XCTAssertEqual(client.payPerUse(of: ["a", "c", "d", "e"]), [
            "a": PayPerUse(via: "API", spentToday: 3.5),
            "c": PayPerUse(via: "Bedrock", spentToday: 4, unpriced: true),
        ])
        client.setSpend(nil, unpriced: [])
        XCTAssertNil(client.spend(.api))
        XCTAssertEqual(client.payPerUse(of: ["a"]), ["a": PayPerUse(via: "API", spentToday: nil)])
    }

    // "Plan limits" off: the Keychain and the network are never asked.
    func testWhileOffTheSourceIsNeverAsked() {
        client.refreshIfStale()
        client.tick()
        XCTAssertEqual(source.fetches, 0)

        client.setEnabled(true)
        XCTAssertEqual(source.fetches, 1)
        source.answer(some)

        client.setEnabled(false)
        clock += 3600
        client.refreshIfStale()
        client.tick()
        XCTAssertEqual(source.fetches, 1)
        XCTAssertNil(client.limits)
    }

    func testTurningOffCancelsTheFetchInFlightAndIgnoresItsAnswer() {
        client.setEnabled(true)
        client.setEnabled(false)
        XCTAssertEqual(source.cancels, 1)

        source.answer(some)
        XCTAssertNil(client.limits)

        // Back on: a fresh fetch starts, and the old answer arriving late still changes nothing.
        client.setEnabled(true)
        XCTAssertEqual(source.fetches, 2)
        source.answer(some, fetch: 0)
        XCTAssertNil(client.limits)
        source.answer(some, fetch: 1)
        XCTAssertEqual(client.limits, some)
    }

    func testOpeningThePanelRefetchesOnlyAfterAMinute() {
        client.setEnabled(true)
        source.answer(some)
        client.refreshIfStale()
        clock += 59
        client.refreshIfStale()
        XCTAssertEqual(source.fetches, 1)
        clock += 2
        client.refreshIfStale()
        XCTAssertEqual(source.fetches, 2)
    }

    // Numbers must not stay up indefinitely just because nothing ever answers again.
    func testNumbersExpireAfterFifteenMinutesEvenIfNoFetchEverFinishes() {
        client.setEnabled(true)
        source.answer(some)
        clock += 300
        client.tick()
        XCTAssertEqual(client.limits, some)
        clock += 300
        client.tick()
        XCTAssertEqual(client.limits, some)
        clock += 301
        client.tick()
        XCTAssertNil(client.limits)
    }

    // The status row must say why there are no numbers, not just leave a gap.
    func testDisplayFollowsTheFetch() {
        XCTAssertEqual(client.display, .off)
        client.setEnabled(true)
        XCTAssertEqual(client.display, .loading)
        source.answer(some)
        XCTAssertEqual(client.display, .limits(some, asOf: nil))

        // A refresh fails: the last numbers stay, with the time they are from.
        let fetched = clock
        clock += 300
        client.tick()
        source.answer(nil)
        XCTAssertEqual(client.display, .limits(some, asOf: fetched))

        // The next one works again.
        clock += 300
        client.tick()
        source.answer(some)
        XCTAssertEqual(client.display, .limits(some, asOf: nil))

        client.setEnabled(false)
        XCTAssertEqual(client.display, .off)
    }

    func testDisplayIsUnavailableWhenNoFetchHasWorked() {
        client.setEnabled(true)
        source.answer(nil, because: .loginExpired)
        // The reason is kept: "unavailable" alone leaves the person with nothing to do about it.
        XCTAssertEqual(client.display, .unavailable(.loginExpired))

        // Turning it off and on starts clean: loading, not the old failure.
        client.setEnabled(false)
        client.setEnabled(true)
        XCTAssertEqual(client.display, .loading)
    }

    func testDisplayIsUnavailableOnceAFetchIsGivenUpOn() {
        client.setEnabled(true)
        clock += 61
        client.tick()
        XCTAssertEqual(client.display, .unavailable(.noAnswer))
    }

    func testAFetchThatNeverAnswersIsAbandonedSoTheNextCanStart() {
        client.setEnabled(true)
        clock += 59
        client.tick()
        XCTAssertEqual(source.fetches, 1)
        clock += 2
        client.tick()
        XCTAssertEqual(source.cancels, 1)
        XCTAssertEqual(source.fetches, 2)

        source.answer(some, fetch: 0)
        XCTAssertNil(client.limits)
        source.answer(some, fetch: 1)
        XCTAssertEqual(client.limits, some)
    }
}
