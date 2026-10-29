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

    // Where the person heard about us goes out once: the answer and the version, nothing else.
    func testTheHeardAnswerCarriesOnlyTheAnswerAndVersion() throws {
        let request = DailyCount.heardRequest(answer: "Facebook", version: "0.3.23")
        XCTAssertEqual(request.url?.absoluteString, "https://agentvalley.app/ingest/i/v0/e/")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["api_key", "event", "distinct_id", "properties"])
        XCTAssertEqual(body["event"] as? String, "app heard from")
        let properties = try XCTUnwrap(body["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["answer", "version", "$process_person_profile"])
        XCTAssertEqual(properties["answer"] as? String, "Facebook")
        XCTAssertEqual(properties["version"] as? String, "0.3.23")
        XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
    }

    // Asked by a release that counts, until it has an answer or a skip. A build to work on the
    // app sends nothing, and with the daily count off the person has said no to sending us anything.
    func testAskedOnlyByAReleaseThatCountsAndOnlyOnce() {
        XCTAssertTrue(HeardFrom.asks(release: true, counting: true, answer: nil))
        XCTAssertFalse(HeardFrom.asks(release: false, counting: true, answer: nil))
        XCTAssertFalse(HeardFrom.asks(release: true, counting: false, answer: nil))
        XCTAssertFalse(HeardFrom.asks(release: true, counting: true, answer: "X"))
        XCTAssertFalse(HeardFrom.asks(release: true, counting: true, answer: HeardFrom.skipped))
    }

    func testAPickedAnswerWaitsToGoOutAndASkipNeverDoes() {
        XCTAssertFalse(HeardFrom.due(answer: nil, sent: false))
        XCTAssertTrue(HeardFrom.due(answer: "Reddit", sent: false))
        XCTAssertFalse(HeardFrom.due(answer: "Reddit", sent: true))
        XCTAssertFalse(HeardFrom.due(answer: HeardFrom.skipped, sent: false))
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
}
