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
