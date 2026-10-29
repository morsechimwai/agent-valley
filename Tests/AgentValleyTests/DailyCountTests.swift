@testable import AgentValley
import XCTest

final class DailyCountTests: XCTestCase {
    func testDueOncePerDay() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9))!
        XCTAssertTrue(DailyCount.isDue(last: nil, now: morning, calendar: calendar))
        XCTAssertFalse(DailyCount.isDue(last: morning, now: morning.addingTimeInterval(10 * 3600), calendar: calendar))
        XCTAssertTrue(DailyCount.isDue(last: morning, now: morning.addingTimeInterval(16 * 3600), calendar: calendar))
    }

    // What the privacy page promises, and nothing more.
    func testTheCountCarriesOnlyWhatThePrivacyPageSays() throws {
        let request = DailyCount.request(version: "0.3.14", macOS: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 2), first: true)
        XCTAssertEqual(request.url?.absoluteString, "https://agentvalley.app/ingest/i/v0/e/")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["api_key", "event", "distinct_id", "properties"])
        XCTAssertEqual(body["event"] as? String, "app daily")
        let properties = try XCTUnwrap(body["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["version", "macos", "first", "$process_person_profile"])
        XCTAssertEqual(properties["version"] as? String, "0.3.14")
        XCTAssertEqual(properties["macos"] as? String, "26.1")
        XCTAssertEqual(properties["first"] as? Bool, true)
        XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
        // A new id each time: two counts can't be tied to one Mac.
        let again = DailyCount.request(version: "0.3.14", macOS: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 2), first: false)
        let id = { (r: URLRequest) in (try? JSONSerialization.jsonObject(with: r.httpBody!) as? [String: Any])?["distinct_id"] as? String }
        XCTAssertNotEqual(id(request), id(again))
    }

    // Where the person heard about us goes out once: the answer, the version and whether it came on the second ask.
    func testTheHeardAnswerCarriesOnlyTheAnswerVersionAndAgain() throws {
        let request = DailyCount.heardRequest(answer: "Facebook", version: "0.3.23", again: true)
        XCTAssertEqual(request.url?.absoluteString, "https://agentvalley.app/ingest/i/v0/e/")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["api_key", "event", "distinct_id", "properties"])
        XCTAssertEqual(body["event"] as? String, "app heard from")
        let properties = try XCTUnwrap(body["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["answer", "version", "again", "$process_person_profile"])
        XCTAssertEqual(properties["answer"] as? String, "Facebook")
        XCTAssertEqual(properties["version"] as? String, "0.3.23")
        XCTAssertEqual(properties["again"] as? Bool, true)
        XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
    }

    // Asked by a release that counts, until it has an answer or a second skip. The first skip
    // waits a week. A build to work on the app sends nothing, and with the daily count off the
    // person has said no to sending us anything.
    func testAskedOnlyByAReleaseThatCountsAndAgainAWeekAfterASkip() {
        let now = Date()
        let day: TimeInterval = 86_400
        func asks(release: Bool = true, counting: Bool = true, answer: String? = nil, skippedAt: Date? = nil) -> Bool {
            HeardFrom.asks(release: release, counting: counting, answer: answer, skippedAt: skippedAt, now: now)
        }
        XCTAssertTrue(asks())
        XCTAssertFalse(asks(release: false))
        XCTAssertFalse(asks(counting: false))
        XCTAssertFalse(asks(answer: "X"))
        XCTAssertFalse(asks(answer: HeardFrom.skipped))
        XCTAssertFalse(asks(skippedAt: now))
        XCTAssertFalse(asks(skippedAt: now - 6 * day))
        XCTAssertTrue(asks(skippedAt: now - 7 * day))
        XCTAssertTrue(asks(skippedAt: now - 30 * day))
        XCTAssertFalse(asks(release: false, skippedAt: now - 30 * day))
        XCTAssertFalse(asks(answer: HeardFrom.skipped, skippedAt: now - 30 * day))
    }

    func testAnAnswerOrAFinalSkipWaitsToGoOut() {
        let skipped = Date()
        XCTAssertFalse(HeardFrom.due(answer: nil, sent: false, skippedAt: nil))
        XCTAssertTrue(HeardFrom.due(answer: "Reddit", sent: false, skippedAt: nil))
        XCTAssertFalse(HeardFrom.due(answer: "Reddit", sent: true, skippedAt: nil))
        XCTAssertTrue(HeardFrom.due(answer: HeardFrom.skipped, sent: false, skippedAt: skipped))
        XCTAssertFalse(HeardFrom.due(answer: HeardFrom.skipped, sent: true, skippedAt: skipped))
    }

    // 0.3.23 said Skip sends nothing: a skip from then has no date, and never goes out.
    func testASkipFromBeforeTheWeekNeverGoesOut() {
        XCTAssertFalse(HeardFrom.due(answer: HeardFrom.skipped, sent: false, skippedAt: nil))
    }

    func testRemembersWhenTheFirstSkipWas() {
        let suite = "DailyCountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        XCTAssertNil(settings.heardSkippedAt)
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        settings.heardSkippedAt = when
        XCTAssertEqual(Settings(defaults: defaults).heardSkippedAt, when)
    }

    func testRemembersTheAnswerAndWhetherItWent() {
        let suite = "DailyCountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        XCTAssertNil(settings.heardFrom)
        XCTAssertFalse(settings.heardSent)
        settings.heardFrom = "Google"
        settings.heardSent = true
        let again = Settings(defaults: defaults)
        XCTAssertEqual(again.heardFrom, "Google")
        XCTAssertTrue(again.heardSent)
    }

    func testOnFromTheStartAndRemembersTheSwitch() {
        let suite = "DailyCountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        XCTAssertTrue(settings.dailyCount)
        XCTAssertNil(settings.countedAt)
        settings.dailyCount = false
        XCTAssertFalse(Settings(defaults: defaults).dailyCount)
    }

    // The rating: stars (or a final skip) go out once, with the version and whether it came on the second ask.
    func testTheRatingCarriesTheStarsOrTheSkip() throws {
        func properties(_ request: URLRequest) throws -> [String: Any] {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["event"] as? String, "app rating")
            return try XCTUnwrap(body["properties"] as? [String: Any])
        }
        let stars = try properties(DailyCount.ratingRequest(stars: 4, version: "0.3.24", again: false))
        XCTAssertEqual(Set(stars.keys), ["stars", "version", "again", "$process_person_profile"])
        XCTAssertEqual(stars["stars"] as? Int, 4)
        XCTAssertEqual(stars["again"] as? Bool, false)
        XCTAssertEqual(stars["$process_person_profile"] as? Bool, false)
        let skip = try properties(DailyCount.ratingRequest(stars: AppRating.skipped, version: "0.3.24", again: true))
        XCTAssertEqual(Set(skip.keys), ["skipped", "version", "again", "$process_person_profile"])
        XCTAssertEqual(skip["skipped"] as? Bool, true)
        XCTAssertEqual(skip["again"] as? Bool, true)
    }

    func testTheRatingAsksAWeekAfterTheHeardBoxIsDone() {
        let now = Date()
        let day: TimeInterval = 86_400
        func asks(release: Bool = true, counting: Bool = true, heardDone: Bool = true, clock: Date? = now - 7 * day,
                  rating: Int? = nil, skippedAt: Date? = nil) -> Bool {
            AppRating.asks(release: release, counting: counting, heardDone: heardDone, clockAt: clock,
                           rating: rating, skippedAt: skippedAt, now: now)
        }
        XCTAssertTrue(asks())
        XCTAssertFalse(asks(release: false))
        XCTAssertFalse(asks(counting: false))
        XCTAssertFalse(asks(heardDone: false))
        XCTAssertFalse(asks(clock: nil))
        XCTAssertFalse(asks(clock: now - 6 * day))
        XCTAssertTrue(asks(clock: now - 30 * day))
        XCTAssertFalse(asks(rating: 5))
        XCTAssertFalse(asks(rating: AppRating.skipped))
        XCTAssertFalse(asks(skippedAt: now - 6 * day))
        XCTAssertTrue(asks(skippedAt: now - 7 * day))
        XCTAssertFalse(asks(clock: now - 30 * day, skippedAt: now))
    }

    func testARatingWaitsToGoOutUntilSent() {
        XCTAssertFalse(AppRating.due(rating: nil, sent: false))
        XCTAssertTrue(AppRating.due(rating: 3, sent: false))
        XCTAssertTrue(AppRating.due(rating: AppRating.skipped, sent: false))
        XCTAssertFalse(AppRating.due(rating: 3, sent: true))
    }

    func testTheClockStartsOnceWhenTheHeardBoxIsDone() {
        let suite = "DailyCountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        settings.startRatingClock(now: first)
        XCTAssertNil(settings.ratingClockAt)
        settings.heardFrom = "X"
        settings.startRatingClock(now: first)
        settings.startRatingClock(now: first + 86_400)
        XCTAssertEqual(settings.ratingClockAt, first)
        XCTAssertEqual(Settings(defaults: defaults).ratingClockAt, first)
    }

    func testRemembersTheRating() {
        let suite = "DailyCountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        XCTAssertNil(settings.rating)
        XCTAssertNil(settings.ratingSkippedAt)
        XCTAssertFalse(settings.ratingSent)
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        settings.rating = 4
        settings.ratingSkippedAt = when
        settings.ratingSent = true
        let again = Settings(defaults: defaults)
        XCTAssertEqual(again.rating, 4)
        XCTAssertEqual(again.ratingSkippedAt, when)
        XCTAssertTrue(again.ratingSent)
    }

    func testTheReviewPageOpensWithTheStars() {
        XCTAssertEqual(AppRating.reviewURL(stars: 5).absoluteString, "https://agentvalley.app/review?stars=5")
        XCTAssertEqual(AppRating.reviewURL(stars: 1).absoluteString, "https://agentvalley.app/review?stars=1")
    }
}
