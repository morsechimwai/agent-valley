import XCTest
@testable import AgentValley

final class PlanLimitsTests: XCTestCase {
    private func date(_ stamp: String) -> Date {
        ISO8601DateFormatter().date(from: stamp)!
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }

    // Why there is no token decides what the person is told to do about it.
    func testTheLoginSaysWhyItCannotBeUsed() {
        let now = date("2026-10-12T02:00:00Z")
        let past = Int(now.timeIntervalSince1970 * 1000) - 1
        XCTAssertEqual(PlanLimitsReader.login(fromKeychainItem: data(#"{"claudeAiOauth":{"accessToken":"tok-9"}}"#), now: now), .success("tok-9"))
        XCTAssertEqual(PlanLimitsReader.login(fromKeychainItem: data(#"{"claudeAiOauth":{"accessToken":"tok","expiresAt":\#(past)}}"#), now: now), .failure(.loginExpired))
        XCTAssertEqual(PlanLimitsReader.login(fromKeychainItem: data(#"{"other":{}}"#), now: now), .failure(.noLogin))
        XCTAssertEqual(PlanLimitsReader.login(fromKeychainItem: data(""), now: now), .failure(.noLogin))
    }

    func testAReplyIsSortedIntoNumbersOrAReason() {
        func reply(_ status: Int) -> HTTPURLResponse { HTTPURLResponse(url: KeychainLimitsSource.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)! }
        let good = data(#"{"limits":[{"kind":"session","percent":40}]}"#)
        XCTAssertEqual(KeychainLimitsSource.outcome(data: good, response: reply(200), failed: false), .success(PlanLimits(fiveHour: PlanLimit(usedPercent: 40, resetsAt: nil), week: nil)))
        XCTAssertEqual(KeychainLimitsSource.outcome(data: nil, response: nil, failed: true), .failure(.offline))
        // Only Claude Code can renew its login; a 401 means it has to.
        XCTAssertEqual(KeychainLimitsSource.outcome(data: data("{}"), response: reply(401), failed: false), .failure(.loginExpired))
        XCTAssertEqual(KeychainLimitsSource.outcome(data: data("{}"), response: reply(529), failed: false), .failure(.refused(529)))
        XCTAssertEqual(KeychainLimitsSource.outcome(data: data("<html>"), response: reply(200), failed: false), .failure(.unreadable))
    }

    // Turning Plan limits off must stop whichever step of the fetch is running, at once: the
    // Keychain read as much as the request. Waiting out a timeout is not "off".
    func testCancellingAFetchStopsTheStepUnderWay() {
        var stopped: [String] = []
        let reading = KeychainLimitsSource.Flight()
        XCTAssertTrue(reading.begin { stopped.append("keychain") })
        reading.cancel()
        XCTAssertEqual(stopped, ["keychain"])

        let requesting = KeychainLimitsSource.Flight()
        XCTAssertTrue(requesting.begin { stopped.append("keychain 2") })
        XCTAssertTrue(requesting.begin { stopped.append("request") })
        requesting.cancel()
        XCTAssertEqual(stopped, ["keychain", "request"])
    }

    func testACancelledFetchStartsNothingMore() {
        var stopped = 0
        let flight = KeychainLimitsSource.Flight()
        flight.cancel()
        XCTAssertTrue(flight.isCancelled)
        XCTAssertFalse(flight.begin { stopped += 1 })
        flight.cancel()
        XCTAssertEqual(stopped, 0)
    }

    func testParsesTheLimitsList() {
        let reply = #"{"limits":[{"kind":"session","percent":42.4,"severity":"normal","resets_at":"2026-10-12T08:00:00.000Z"},{"kind":"weekly_all","percent":18,"resets_at":"2026-10-15T00:00:00Z"},{"kind":"weekly_scoped","percent":61,"scope":{"model":{"display_name":"Opus"}}}]}"#
        let limits = PlanLimitsReader.parse(data(reply))
        XCTAssertEqual(limits?.fiveHour, PlanLimit(usedPercent: 42.4, resetsAt: date("2026-10-12T08:00:00Z")))
        XCTAssertEqual(limits?.week, PlanLimit(usedPercent: 18, resetsAt: date("2026-10-15T00:00:00Z")))
    }

    func testParsesTheLegacyShape() {
        let reply = #"{"five_hour":{"utilization":23.5,"resets_at":"2026-10-12T08:00:00Z"},"seven_day":{"utilization":"41.2","resets_at":null},"seven_day_opus":{"utilization":62.8}}"#
        let limits = PlanLimitsReader.parse(data(reply))
        XCTAssertEqual(limits?.fiveHour, PlanLimit(usedPercent: 23.5, resetsAt: date("2026-10-12T08:00:00Z")))
        XCTAssertEqual(limits?.week, PlanLimit(usedPercent: 41.2, resetsAt: nil))
    }

    // The reply's shape is undocumented and may drift between the two.
    func testAnEmptyLimitsListFallsBackToTheLegacyFields() {
        let reply = #"{"limits":[],"five_hour":{"utilization":7}}"#
        XCTAssertEqual(PlanLimitsReader.parse(data(reply)), PlanLimits(fiveHour: PlanLimit(usedPercent: 7, resetsAt: nil), week: nil))
    }

    func testAReplyWithNoLimitsIsNoDataRatherThanZero() {
        XCTAssertNil(PlanLimitsReader.parse(data("not json")))
        XCTAssertNil(PlanLimitsReader.parse(data("[]")))
        XCTAssertNil(PlanLimitsReader.parse(data(#"{"limits":[{"kind":"weekly_scoped","percent":5}]}"#)))
        XCTAssertNil(PlanLimitsReader.parse(data(#"{"limits":[{"kind":"session"}],"error":"x"}"#)))
    }

    // Rounding a non-finite or absurd percentage to an Int traps. A reply must never be able to crash the app.
    func testNonFiniteOrAbsurdNumbersAreNoData() {
        XCTAssertNil(PlanLimitsReader.parse(data(#"{"limits":[{"kind":"session","percent":1e30}]}"#)))
        XCTAssertNil(PlanLimitsReader.parse(data(#"{"limits":[{"kind":"session","percent":"nan"}]}"#)))
        XCTAssertNil(PlanLimitsReader.parse(data(#"{"five_hour":{"utilization":"inf"}}"#)))
        XCTAssertNil(PlanLimitsReader.parse(data(#"{"five_hour":{"utilization":-1e30}}"#)))
        XCTAssertEqual(PlanLimitsReader.parse(data(#"{"five_hour":{"utilization":250}}"#))?.fiveHour?.percentLabel, "250%")
    }

    func testReadsResetTimesWithSixDigitFractions() {
        let reply = #"{"five_hour":{"utilization":1,"resets_at":"2026-10-12T08:00:00.943648+00:00"}}"#
        let resetsAt = PlanLimitsReader.parse(data(reply))?.fiveHour?.resetsAt
        XCTAssertNotNil(resetsAt)
        XCTAssertEqual(resetsAt?.timeIntervalSince(date("2026-10-12T08:00:00Z")) ?? -99, 0.5, accuracy: 0.6)
    }

    func testReadsTheTokenFromTheKeychainItem() {
        let now = date("2026-10-12T04:00:00Z")
        let later = Int(now.timeIntervalSince1970 * 1000) + 60_000
        let item = #"{"claudeAiOauth":{"accessToken":"tok-123","subscriptionType":"max","expiresAt":\#(later)}}"# + "\n"
        XCTAssertEqual(PlanLimitsReader.token(fromKeychainItem: data(item), now: now), "tok-123")
        XCTAssertEqual(PlanLimitsReader.token(fromKeychainItem: data(#"{"claudeAiOauth":{"accessToken":"tok-9"}}"#), now: now), "tok-9")
    }

    func testAnExpiredOrMalformedKeychainItemGivesNoToken() {
        let now = date("2026-10-12T04:00:00Z")
        let exactlyNow = Int(now.timeIntervalSince1970 * 1000)
        XCTAssertNil(PlanLimitsReader.token(fromKeychainItem: data(#"{"claudeAiOauth":{"accessToken":"tok","expiresAt":\#(exactlyNow)}}"#), now: now))
        XCTAssertNil(PlanLimitsReader.token(fromKeychainItem: data(#"{"claudeAiOauth":{"accessToken":""}}"#), now: now))
        XCTAssertNil(PlanLimitsReader.token(fromKeychainItem: data(#"{"other":{}}"#), now: now))
        XCTAssertNil(PlanLimitsReader.token(fromKeychainItem: data("garbage"), now: now))
    }

    // With no room for both reset times, the one that answers "when can I work again" stays.
    func testATightLimitsResetTimeIsTheLastToGo() {
        XCTAssertFalse(PlanLimit(usedPercent: 79.9, resetsAt: nil).resetMatters)
        XCTAssertTrue(PlanLimit(usedPercent: 80, resetsAt: nil).resetMatters)
        XCTAssertTrue(PlanLimit(usedPercent: 100, resetsAt: nil).resetMatters)
    }

    // As room runs out the reset times go in a set order: first those of limits with room to
    // spare, then of one that is high, and last of one that has all but run out.
    func testResetTimesGiveWayInOrder() {
        func shown(_ percent: Double) -> [Bool] {
            LimitResets.ladder.map { $0.shows(PlanLimit(usedPercent: percent, resetsAt: nil)) }
        }
        XCTAssertEqual(LimitResets.ladder, [.all, .tight, .critical, .none])
        XCTAssertEqual(shown(42), [true, false, false, false])
        XCTAssertEqual(shown(87), [true, true, false, false])
        XCTAssertEqual(shown(100), [true, true, true, false])
    }

    func testLevelThresholds() {
        XCTAssertEqual(PlanLimit(usedPercent: 79.9, resetsAt: nil).level, .normal)
        XCTAssertEqual(PlanLimit(usedPercent: 80, resetsAt: nil).level, .high)
        XCTAssertEqual(PlanLimit(usedPercent: 94.9, resetsAt: nil).level, .high)
        XCTAssertEqual(PlanLimit(usedPercent: 95, resetsAt: nil).level, .critical)
    }

    // Over the limit: the number tells the truth, the bar stays inside its track.
    func testPercentLabelAndBarFraction() {
        XCTAssertEqual(PlanLimit(usedPercent: 41.6, resetsAt: nil).percentLabel, "42%")
        XCTAssertEqual(PlanLimit(usedPercent: 0, resetsAt: nil).percentLabel, "0%")
        XCTAssertEqual(PlanLimit(usedPercent: 130, resetsAt: nil).percentLabel, "130%")
        XCTAssertEqual(PlanLimit(usedPercent: 130, resetsAt: nil).fraction, 1)
        XCTAssertEqual(PlanLimit(usedPercent: -5, resetsAt: nil).fraction, 0)
        XCTAssertEqual(PlanLimit(usedPercent: 42, resetsAt: nil).fraction, 0.42, accuracy: 0.0001)
    }

    func testResetLabel() {
        let now = date("2026-10-12T04:00:00Z")
        func label(_ secondsAhead: TimeInterval) -> String? {
            PlanLimit(usedPercent: 1, resetsAt: now.addingTimeInterval(secondsAhead)).resetLabel(now: now)
        }
        XCTAssertEqual(label(45 * 60), "45m")
        XCTAssertEqual(label(20), "1m")
        XCTAssertEqual(label(2 * 3600 + 10 * 60), "2h 10m")
        XCTAssertEqual(label(2 * 3600 + 5 * 60), "2h 05m")
        XCTAssertEqual(label(3 * 86400 + 4 * 3600), "3d 4h")
        XCTAssertNil(label(0))
        XCTAssertNil(label(-600))
        XCTAssertNil(PlanLimit(usedPercent: 1, resetsAt: nil).resetLabel(now: now))
    }

    // The token must go to Anthropic's API and nowhere else.
    func testRequestCarriesTheTokenOnlyToTheUsageEndpoint() {
        let request = KeychainLimitsSource.request(token: "tok-123")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    // A redirect would carry the request, and perhaps its Authorization header, to another host.
    func testRedirectsAreRefusedSoTheTokenCannotFollowOne() {
        let session = KeychainLimitsSource.makeSession()
        defer { session.invalidateAndCancel() }
        let delegate = session.delegate as? URLSessionTaskDelegate
        XCTAssertTrue(session.delegate is NoRedirects)

        let task = session.dataTask(with: KeychainLimitsSource.request(token: "tok"))
        let elsewhere = URL(string: "https://example.com/")!
        let response = HTTPURLResponse(url: KeychainLimitsSource.endpoint, statusCode: 302, httpVersion: nil, headerFields: ["Location": elsewhere.absoluteString])!
        var answered = false
        var next: URLRequest? = URLRequest(url: elsewhere)
        delegate?.urlSession?(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: elsewhere)) {
            answered = true
            next = $0
        }
        XCTAssertTrue(answered)
        XCTAssertNil(next)
    }

    func testAFailedFetchKeepsTheLastNumbersForFifteenMinutes() {
        let now = date("2026-10-12T04:00:00Z")
        let last = PlanLimits(fiveHour: PlanLimit(usedPercent: 40, resetsAt: nil), week: nil)
        let fresh = PlanLimits(fiveHour: PlanLimit(usedPercent: 41, resetsAt: nil), week: nil)
        func resolve(_ result: PlanLimits?, fetched secondsAgo: TimeInterval?) -> PlanLimits? {
            PlanLimitsClient.resolve(result: result, last: last, lastFetchedAt: secondsAgo.map { now.addingTimeInterval(-$0) }, now: now)
        }
        XCTAssertEqual(resolve(fresh, fetched: 10), fresh)
        XCTAssertEqual(resolve(nil, fetched: 10), last)
        XCTAssertEqual(resolve(nil, fetched: 900), last)
        XCTAssertNil(resolve(nil, fetched: 901))
        XCTAssertNil(resolve(nil, fetched: nil))
    }

    // The ring on the shut bar is the 5-hour window, or the weekly one on a plan without it.
    // Without a number there is no ring: an empty one would read as "nothing used".
    func testTheRingIsTheFiveHourLimitOnceItIsKnown() {
        typealias Display = PlanLimitsClient.Display
        let five = PlanLimit(usedPercent: 62, resetsAt: nil)
        XCTAssertNil(Display.off.ring)
        XCTAssertNil(Display.loading.ring)
        XCTAssertNil(Display.unavailable(.offline).ring)
        let week = PlanLimit(usedPercent: 90, resetsAt: nil)
        XCTAssertEqual(Display.limits(PlanLimits(fiveHour: nil, week: week), asOf: nil).ring, LimitRing(limit: week, stale: false, weekly: true))
        XCTAssertEqual(Display.limits(PlanLimits(fiveHour: five, week: week), asOf: nil).ring, LimitRing(limit: five, stale: false))
        XCTAssertEqual(Display.limits(PlanLimits(fiveHour: five, week: nil), asOf: nil).ring, LimitRing(limit: five, stale: false))
        // Numbers kept from before a refresh that failed: still drawn, and marked as old.
        XCTAssertEqual(Display.limits(PlanLimits(fiveHour: five, week: nil), asOf: Date()).ring, LimitRing(limit: five, stale: true))
    }

    // The usage reply names no plan: it comes from Claude Code's own file, as in the terminal.
    func testThePlanComesFromClaudeCodesFile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertNil(KeychainLimitsSource.plan(home: home, environment: [:]))
        try Data(#"{"oauthAccount": {"planDisplayName": "Ultra"}}"#.utf8).write(to: home.appendingPathComponent(".claude.json"))
        XCTAssertEqual(KeychainLimitsSource.plan(home: home, environment: [:]), "Ultra")
    }

    // The crew goes fishing only while a window has run out, and is back with the later of two.
    func testARunOutWindowIsTheOneThatComesBackLast() {
        let now = date("2026-10-21T08:00:00Z")
        let soon = now.addingTimeInterval(3600), later = now.addingTimeInterval(3 * 86400)
        XCTAssertNil(PlanLimits(fiveHour: PlanLimit(usedPercent: 99, resetsAt: soon), week: nil).runOut(now: now))
        XCTAssertEqual(PlanLimits(fiveHour: PlanLimit(usedPercent: 100, resetsAt: soon), week: PlanLimit(usedPercent: 40, resetsAt: later)).runOut(now: now),
                       RunOut(weekly: false, resetsAt: soon))
        XCTAssertEqual(PlanLimits(fiveHour: PlanLimit(usedPercent: 100, resetsAt: soon), week: PlanLimit(usedPercent: 100, resetsAt: later)).runOut(now: now),
                       RunOut(weekly: true, resetsAt: later))
        // Out as soon as the meter says 100%.
        XCTAssertNotNil(PlanLimits(fiveHour: PlanLimit(usedPercent: 99.6, resetsAt: soon), week: nil).runOut(now: now))
        // Past its reset time it is back, whatever the last numbers said.
        XCTAssertNil(PlanLimits(fiveHour: PlanLimit(usedPercent: 100, resetsAt: now), week: nil).runOut(now: now))
        // With no reset time it is out until new numbers say otherwise.
        XCTAssertEqual(PlanLimits(fiveHour: nil, week: PlanLimit(usedPercent: 104, resetsAt: nil)).runOut(now: now), RunOut(weekly: true, resetsAt: nil))
        typealias Display = PlanLimitsClient.Display
        let out = PlanLimits(fiveHour: PlanLimit(usedPercent: 100, resetsAt: soon), week: nil)
        XCTAssertNil(Display.off.runOut(now: now))
        XCTAssertNotNil(Display.limits(out, asOf: now).runOut(now: now))
    }
}
