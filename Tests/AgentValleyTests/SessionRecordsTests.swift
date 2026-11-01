import XCTest
@testable import AgentValley

final class SessionRecordsTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_791_787_807.982)
    private let alive: (Int32) -> Date? = { _ in Date(timeIntervalSince1970: 0) }

    private func json(pid: Int = 123, session: String = "s1", startedAt: Int = 1_791_787_807_982, status: String = "busy", extra: String = "") -> Data {
        Data(#"{"pid":\#(pid),"sessionId":"\#(session)","cwd":"/Users/me/web-app","startedAt":\#(startedAt),"status":"\#(status)"\#(extra)}"#.utf8)
    }

    private func record(_ data: Data) -> SessionRecord { SessionRecords.parse(data)! }

    // The folder also holds `.key` secrets: only `<pid>.json` may ever be opened.
    func testOnlyPidNamedJsonFilesAreRecords() {
        XCTAssertTrue(SessionRecords.isRecordName("123.json"))
        XCTAssertTrue(SessionRecords.isRecordName("8007.json"))
        for name in ["123.abc.key", "notes.json", "123.json.bak", ".json", "12a.json", "123.JSON", "-1.json", "１２３.json", "123"] {
            XCTAssertFalse(SessionRecords.isRecordName(name), name)
        }
    }

    func testParsesTheFieldsItUses() {
        let waiting = SessionRecords.parse(json(status: "waiting", extra: #","statusUpdatedAt":1791789998096,"waitingFor":"dialog open""#))
        XCTAssertEqual(waiting, SessionRecord(
            pid: 123, sessionId: "s1", startedAt: started,
            state: SessionState(activity: .waiting, since: Date(timeIntervalSince1970: 1_791_789_998.096))
        ))
        XCTAssertEqual(record(json(status: "busy")).state, SessionState(activity: .busy, since: nil))
        XCTAssertEqual(record(json(status: "idle")).state?.activity, .idle)
        // Since 2.1.312: the turn ended with a background shell or monitor still running.
        XCTAssertEqual(record(json(status: "shell")).state?.activity, .idle)
    }

    // A status this app does not know yet: the session is still the process's, and what it does is not said.
    func testAnUnknownStatusKeepsTheRecordButSaysNothingOfIt() {
        let unknown = record(json(status: "thinking"))
        XCTAssertEqual(unknown.pid, 123)
        XCTAssertNil(unknown.state)
        XCTAssertEqual(SessionRecords.states(from: [unknown], processStart: alive), [:])
        XCTAssertEqual(SessionRecords.live(from: [unknown], processStart: alive)["s1"]?.pid, 123)
    }

    // Claude Code documents none of this: a record the app cannot read in full counts as absent.
    func testARecordItCannotReadInFullIsNoRecord() {
        XCTAssertNil(SessionRecords.parse(Data("{not json".utf8)))
        XCTAssertNil(SessionRecords.parse(Data()))
        XCTAssertNil(SessionRecords.parse(Data("[1,2]".utf8)))
        XCTAssertNil(SessionRecords.parse(json(session: "")))
        XCTAssertNil(SessionRecords.parse(Data(#"{"pid":"123","sessionId":"s1","startedAt":1791787807982,"status":"busy"}"#.utf8)))
        XCTAssertNil(SessionRecords.parse(Data(#"{"pid":123,"sessionId":"s1","startedAt":"today","status":"busy"}"#.utf8)))
        XCTAssertNil(SessionRecords.parse(Data(#"{"pid":123,"sessionId":"s1","status":"busy"}"#.utf8)))
        XCTAssertNil(SessionRecords.parse(Data(#"{"pid":123,"sessionId":"s1","startedAt":1791787807982}"#.utf8)))
        XCTAssertNil(SessionRecords.parse(Data(#"{"pid":123,"sessionId":7,"startedAt":1791787807982,"status":"busy"}"#.utf8)))
        // An odd `statusUpdatedAt` costs only the duration, not the record.
        XCTAssertEqual(record(json(extra: #","statusUpdatedAt":"soon""#)).state, SessionState(activity: .busy, since: nil))
    }

    func testARecordCountsOnlyWhileItsOwnProcessIsAlive() {
        let records = [record(json())]
        func states(_ start: Date?) -> [String: SessionState] {
            SessionRecords.states(from: records, processStart: { pid in pid == 123 ? start : nil })
        }
        let busy = ["s1": SessionState(activity: .busy, since: nil)]
        XCTAssertEqual(states(started.addingTimeInterval(-2)), busy)
        XCTAssertEqual(states(started), busy)
        // No such process: Claude Code was killed and left its record behind.
        XCTAssertEqual(states(nil), [:])
        // Another program took over the pid: it started after the record was written.
        XCTAssertEqual(states(started.addingTimeInterval(1)), [:])
    }

    func testTheNewestLiveRecordSpeaksForASession() {
        let old = record(json(pid: 1, status: "busy"))
        let new = record(json(pid: 2, startedAt: 1_791_787_900_000, status: "idle"))
        XCTAssertEqual(SessionRecords.states(from: [old, new], processStart: alive)["s1"]?.activity, .idle)
        XCTAssertEqual(SessionRecords.states(from: [new, old], processStart: alive)["s1"]?.activity, .idle)
        // The newer one's process is gone: the older, live one stands.
        let onlyFirst: (Int32) -> Date? = { $0 == 1 ? Date(timeIntervalSince1970: 0) : nil }
        XCTAssertEqual(SessionRecords.states(from: [old, new], processStart: onlyFirst)["s1"]?.activity, .busy)
        XCTAssertEqual(SessionRecords.states(from: [], processStart: alive), [:])
        // The record that speaks for the session is the one whose process to look up.
        XCTAssertEqual(SessionRecords.live(from: [old, new], processStart: alive)["s1"]?.pid, 2)
        XCTAssertEqual(SessionRecords.live(from: [old, new], processStart: onlyFirst)["s1"]?.pid, 1)
    }
}
