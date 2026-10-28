import Combine
import XCTest
@testable import AgentValley

final class LedgerTests: XCTestCase {
    /// 2026-10-13 14:30:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_791_901_800)
    private let all = DateInterval(start: .distantPast, end: .distantFuture)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func line(id: String, at: String, input: Int = 0, output: Int = 0, session: String = "s1", cwd: String = "/Users/me/app") -> String {
        #"{"type":"assistant","timestamp":"\#(at)","cwd":"\#(cwd)","sessionId":"\#(session)","message":{"id":"\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":\#(output)},"content":[]}}"#
    }

    /// A folder of its own: transcripts under `projects`, the database under `support`.
    private func folder() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("agent-valley-ledger-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return base
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func ledger(_ base: URL, piece: Int = 1 << 20) -> UsageLedger {
        UsageLedger(root: base.appendingPathComponent("projects"), database: base.appendingPathComponent("support/history.sqlite"), piece: piece)
    }

    func testTheLastDayIsAddedUpForTheLineAndEveryAnswerIsKept() throws {
        let base = try folder()
        let main = base.appendingPathComponent("projects/proj/s1.jsonl")
        try write(line(id: "a", at: "2026-10-13T14:00:00.000Z", input: 10, output: 100) + "\n"
            + line(id: "b", at: "2026-10-13T13:00:00.000Z", input: 20, output: 200) + "\n"
            // Two days before: in the history, not on the line.
            + line(id: "old", at: "2026-10-11T14:00:00.000Z", output: 7000) + "\n", to: main)
        // A sub-agent's transcript can carry answers of the session it was started from.
        try write(line(id: "x", at: "2026-10-13T14:10:00.000Z", input: 1, output: 1000) + "\n"
            + line(id: "a", at: "2026-10-13T14:00:00.000Z", input: 10, output: 100) + "\n",
                  to: base.appendingPathComponent("projects/proj/s1/subagents/agent-x.jsonl"))
        // Not a transcript the list knows: not read.
        try write(line(id: "j", at: "2026-10-13T14:00:00.000Z", output: 5000) + "\n", to: base.appendingPathComponent("projects/proj/s1/journal.jsonl"))

        let ledger = ledger(base)
        var pass = ledger.scan(now: now, calendar: utc)
        XCTAssertTrue(pass.added)
        XCTAssertNil(pass.problem)
        // a, b and x: the copy of a in the sub-agent's transcript is not a fourth.
        XCTAssertEqual(pass.summary.fiveHours, TokenTotals(input: 31, output: 1300))
        XCTAssertEqual(pass.summary.hourly.last, 1100)
        XCTAssertEqual(pass.summary.hourly[10], 200)
        XCTAssertEqual(try ledger.slice(all).answers.map(\.id).sorted(), ["a", "b", "old", "x"])

        // Read again with nothing new: nothing is added.
        pass = ledger.scan(now: now, calendar: utc)
        XCTAssertFalse(pass.added)
        XCTAssertEqual(pass.summary.fiveHours, TokenTotals(input: 31, output: 1300))

        // More is written: one whole line, and one that is not finished yet.
        let half = line(id: "d", at: "2026-10-13T14:20:00.000Z", output: 9000)
        try append(line(id: "c", at: "2026-10-13T14:20:00.000Z", input: 5, output: 50) + "\n" + String(half.prefix(40)), to: main)
        XCTAssertEqual(ledger.scan(now: now, calendar: utc).summary.fiveHours, TokenTotals(input: 36, output: 1350))
        // The rest of that line arrives: it is counted whole, once.
        try append(String(half.dropFirst(40)) + "\n", to: main)
        XCTAssertEqual(ledger.scan(now: now, calendar: utc).summary.fiveHours, TokenTotals(input: 36, output: 10_350))
        XCTAssertEqual(ledger.scan(now: now, calendar: utc).summary.fiveHours, TokenTotals(input: 36, output: 10_350))
    }

    func testAnAnswerIsKeptOnceAndSaysWhichAgentGaveIt() throws {
        let base = try folder()
        let sub = base.appendingPathComponent("projects/proj/s1/subagents/agent-x.jsonl")
        // The sub-agent's transcript is read before its meta file is there.
        try write(line(id: "x1", at: "2026-10-13T14:00:00.000Z", output: 8) + "\n"
            + line(id: "a", at: "2026-10-13T14:00:00.000Z", output: 100) + "\n", to: sub)
        let ledger = ledger(base)
        _ = ledger.scan(now: now, calendar: utc)
        func agents() throws -> [String: String] {
            Dictionary(uniqueKeysWithValues: try ledger.slice(all).answers.map { ($0.id, $0.agent) })
        }
        XCTAssertEqual(try agents(), ["x1": "subagent", "a": "subagent"])
        // Then its meta file, and the rest of its first answer: the answer takes the type.
        try write(#"{"agentType":"Explore","description":"Find the tests"}"#, to: base.appendingPathComponent("projects/proj/s1/subagents/agent-x.meta.json"))
        try append(line(id: "x1", at: "2026-10-13T14:00:01.000Z", output: 497) + "\n", to: sub)
        // And the session's own transcript, where "a" was its main agent's.
        try write(line(id: "a", at: "2026-10-13T14:00:00.000Z", output: 90) + "\n", to: base.appendingPathComponent("projects/proj/s1.jsonl"))
        _ = ledger.scan(now: now, calendar: utc)
        XCTAssertEqual(try agents(), ["x1": "Explore", "a": "main"])
        let answers = try ledger.slice(all).answers
        // The larger of each count, and the later time.
        XCTAssertEqual(answers.first { $0.id == "x1" }?.output, 497)
        XCTAssertEqual(answers.first { $0.id == "x1" }?.at, Date(timeIntervalSince1970: 1_791_900_001))
        XCTAssertEqual(answers.first { $0.id == "a" }?.output, 100)
    }

    func testALedgerOpenedAgainReadsOnFromWhereTheLastStopped() throws {
        let base = try folder()
        let main = base.appendingPathComponent("projects/proj/s1.jsonl")
        try write(line(id: "a", at: "2026-10-13T14:00:00.000Z", output: 100) + "\n", to: main)
        XCTAssertTrue(ledger(base).scan(now: now, calendar: utc).added)
        // As after the app was quit and opened again: what was read is not read again ...
        XCTAssertFalse(ledger(base).scan(now: now, calendar: utc).added)
        // ... and what came while it was shut is.
        try append(line(id: "b", at: "2026-10-13T14:05:00.000Z", output: 5) + "\n", to: main)
        let again = ledger(base)
        let pass = again.scan(now: now, calendar: utc)
        XCTAssertTrue(pass.added)
        XCTAssertEqual(pass.summary.fiveHours.output, 105)
        XCTAssertEqual(try again.slice(all).answers.count, 2)
    }

    func testAFileWrittenAnewIsReadFromItsStartAndAGoneOneKeepsItsAnswers() throws {
        let base = try folder()
        let main = base.appendingPathComponent("projects/proj/s1.jsonl")
        try write(line(id: "a", at: "2026-10-13T14:00:00.000Z", output: 100) + "\n" + line(id: "b", at: "2026-10-13T14:01:00.000Z", output: 200) + "\n", to: main)
        let ledger = ledger(base)
        XCTAssertEqual(ledger.scan(now: now, calendar: utc).summary.fiveHours.output, 300)
        try write(line(id: "z", at: "2026-10-13T14:02:00.000Z", output: 7) + "\n", to: main)
        // The history keeps what it has seen: a and b, and now z.
        XCTAssertEqual(ledger.scan(now: now, calendar: utc).summary.fiveHours.output, 307)
        try FileManager.default.removeItem(at: main)
        XCTAssertEqual(ledger.scan(now: now, calendar: utc).summary.fiveHours.output, 307)
        XCTAssertEqual(try ledger.slice(all).answers.map(\.id).sorted(), ["a", "b", "z"])
    }

    // A transcript is read a piece at a time, so that a large one is never held whole. A line
    // cut by the end of a piece is put together with the rest of it, and counted once.
    func testATranscriptReadInPiecesCountsTheSame() throws {
        let base = try folder()
        let lines = (1...40).map { line(id: "m\($0)", at: "2026-10-13T14:00:00.000Z", input: $0, output: $0 * 10) }
        try write(lines.joined(separator: "\n") + "\n", to: base.appendingPathComponent("projects/proj/s1.jsonl"))
        for piece in [1, 7, 64, 300, 1000, 1 << 20] {
            let ledger = UsageLedger(root: base.appendingPathComponent("projects"),
                                     database: base.appendingPathComponent("piece-\(piece)/history.sqlite"), piece: piece)
            XCTAssertEqual(ledger.scan(now: now, calendar: utc).summary.fiveHours, TokenTotals(input: 820, output: 8200), "\(piece)")
            XCTAssertFalse(ledger.scan(now: now, calendar: utc).added, "\(piece)")
        }
    }

    func testASessionKeepsTheLastNameClaudeCodeGaveIt() throws {
        let base = try folder()
        try write([
            #"{"type":"ai-title","aiTitle":"First name","sessionId":"s1"}"#,
            line(id: "a", at: "2026-10-13T14:00:00.000Z", output: 1),
            #"{"type":"ai-title","aiTitle":"Better name","sessionId":"s1"}"#,
        ].joined(separator: "\n") + "\n", to: base.appendingPathComponent("projects/proj/s1.jsonl"))
        // Without the id, the line is its own transcript's: named for its session.
        try write([
            #"{"type":"ai-title","aiTitle":"Named by its file"}"#,
            line(id: "b", at: "2026-10-13T14:00:00.000Z", output: 1, session: "s2"),
        ].joined(separator: "\n") + "\n", to: base.appendingPathComponent("projects/proj/s2.jsonl"))
        let ledger = ledger(base)
        _ = ledger.scan(now: now, calendar: utc)
        XCTAssertEqual(try ledger.slice(all).titles, ["s1": "Better name", "s2": "Named by its file"])
    }

    // Most folders are gone by the time History names them, so each one's checkout is kept
    // while the folder is there to ask, and for good.
    func testEachFoldersCheckoutIsKeptWhileTheFolderIsThere() throws {
        let base = try folder()
        let repo = base.path + "/agent-valley", ws = base.path + "/AgentValley/ws"
        try FileManager.default.createDirectory(atPath: repo + "/.git/worktrees/ws", withIntermediateDirectories: true)
        try write("gitdir: \(repo)/.git/worktrees/ws\n", to: URL(fileURLWithPath: ws + "/.git"))
        try FileManager.default.createDirectory(atPath: base.path + "/loose", withIntermediateDirectories: true)
        let transcript = base.appendingPathComponent("projects/proj/s1.jsonl")
        try write([line(id: "a", at: "2026-10-13T10:00:00.000Z", output: 1, cwd: ws),
                   line(id: "b", at: "2026-10-13T10:01:00.000Z", output: 1, cwd: repo),
                   line(id: "c", at: "2026-10-13T10:02:00.000Z", output: 1, cwd: base.path + "/loose"),
                   line(id: "d", at: "2026-10-13T10:03:00.000Z", output: 1, cwd: base.path + "/gone")].joined(separator: "\n") + "\n", to: transcript)
        _ = ledger(base).scan(now: now, calendar: utc)
        // The worktree is gone: what was learned stays, in a ledger opened afresh.
        try FileManager.default.removeItem(atPath: base.path + "/AgentValley")
        let again = ledger(base)
        _ = again.scan(now: now, calendar: utc)
        XCTAssertEqual(try again.slice(all).checkouts, [ws: repo, repo: repo])
        // A folder first met on a later pass is asked about then.
        let side = base.path + "/agent-valley/site"
        try FileManager.default.createDirectory(atPath: side, withIntermediateDirectories: true)
        try append(line(id: "e", at: "2026-10-13T10:04:00.000Z", output: 1, cwd: side) + "\n", to: transcript)
        _ = again.scan(now: now, calendar: utc)
        XCTAssertEqual(try again.slice(all).checkouts, [ws: repo, repo: repo, side: repo])
    }

    // A checkout's remote is kept too, read on the first pass for those met before there was a
    // place to keep it, and without who signs in. Each session says where it began, and each
    // folder when it was last worked in.
    func testEachCheckoutsRemoteIsKeptAndWhereEachSessionBegan() throws {
        let base = try folder()
        let repo = base.path + "/app", plain = base.path + "/plain"
        try FileManager.default.createDirectory(atPath: repo + "/.git", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: plain + "/.git", withIntermediateDirectories: true)
        try write([line(id: "a", at: "2026-10-13T10:00:00.000Z", output: 1, cwd: repo),
                   line(id: "b", at: "2026-10-13T10:01:00.000Z", output: 1, cwd: repo + "/site"),
                   line(id: "c", at: "2026-10-13T10:02:00.000Z", output: 1, session: "s2", cwd: plain)].joined(separator: "\n") + "\n",
                  to: base.appendingPathComponent("projects/proj/s1.jsonl"))
        _ = ledger(base).scan(now: now, calendar: utc)
        // The remote added after the checkout was first met: read on the next first pass.
        try write("[remote \"origin\"]\n\turl = https://me:ghp_secret@github.com/me/app.git\n", to: URL(fileURLWithPath: repo + "/.git/config"))
        let again = ledger(base)
        _ = again.scan(now: now, calendar: utc)
        let slice = try again.slice(all)
        XCTAssertEqual(slice.remotes, [repo: "github.com/me/app"])
        XCTAssertEqual(slice.starts, ["s1": repo, "s2": plain])
        XCTAssertEqual(slice.lastUsed[repo], TranscriptReader.date(from: "2026-10-13T10:00:00.000Z"))
        XCTAssertEqual(slice.lastUsed[repo + "/site"], TranscriptReader.date(from: "2026-10-13T10:01:00.000Z"))
        // A session of another stretch is not said.
        let later = try again.slice(DateInterval(start: TranscriptReader.date(from: "2026-10-13T10:01:30.000Z")!, duration: 3600))
        XCTAssertEqual(later.starts, ["s2": plain])
    }

    // A session that went on from its folder into one new to the history, and never back, saw
    // the folder renamed. Not one that came back, nor one that went into a folder worked in
    // before, nor into a scratch folder.
    func testAFolderRenamedUnderASessionIsSaid() throws {
        let base = try folder()
        let lines = [
            line(id: "a", at: "2026-10-13T10:00:00.000Z", output: 1, session: "s1", cwd: "/Users/me/old"),
            line(id: "b", at: "2026-10-13T10:01:00.000Z", output: 1, session: "s1", cwd: "/Users/me/old/site"),
            line(id: "c", at: "2026-10-13T10:02:00.000Z", output: 1, session: "s1", cwd: "/private/tmp/claude-501/-Users-me-old/x/scratchpad"),
            line(id: "d", at: "2026-10-13T10:03:00.000Z", output: 1, session: "s1", cwd: "/Users/me/new"),
            // Went into another project for a while, and came back to its own the next day.
            line(id: "e", at: "2026-10-13T11:00:00.000Z", output: 1, session: "s2", cwd: "/Users/me/keep"),
            line(id: "f", at: "2026-10-13T11:01:00.000Z", output: 1, session: "s2", cwd: "/Users/me/side"),
            line(id: "g", at: "2026-10-14T09:00:00.000Z", output: 1, session: "s3", cwd: "/Users/me/keep"),
            // Went into a folder worked in before.
            line(id: "h", at: "2026-10-14T10:00:00.000Z", output: 1, session: "s4", cwd: "/Users/me/done"),
            line(id: "i", at: "2026-10-14T10:01:00.000Z", output: 1, session: "s4", cwd: "/Users/me/keep"),
        ]
        try write(lines.joined(separator: "\n") + "\n", to: base.appendingPathComponent("projects/proj/s1.jsonl"))
        let ledger = ledger(base)
        _ = ledger.scan(now: now, calendar: utc)
        XCTAssertEqual(try ledger.slice(all).moves, ["/Users/me/old": "/Users/me/new"])
    }

    func testASliceIsItsStretchOfTime() throws {
        let base = try folder()
        try write(line(id: "a", at: "2026-10-12T23:59:59.000Z", output: 1) + "\n" + line(id: "b", at: "2026-10-13T00:00:00.000Z", output: 1) + "\n"
            + line(id: "c", at: "2026-10-13T23:59:59.000Z", output: 1, session: "s2") + "\n" + line(id: "d", at: "2026-10-14T00:00:00.000Z", output: 1) + "\n",
                  to: base.appendingPathComponent("projects/proj/s1.jsonl"))
        try write(#"{"type":"ai-title","aiTitle":"Two","sessionId":"s2"}"# + "\n", to: base.appendingPathComponent("projects/proj/s2.jsonl"))
        let ledger = ledger(base)
        _ = ledger.scan(now: now, calendar: utc)
        let day = try ledger.slice(utc.dateInterval(of: .day, for: Date(timeIntervalSince1970: 1_791_900_000))!)
        XCTAssertEqual(day.answers.map(\.id).sorted(), ["b", "c"])
        XCTAssertEqual(day.titles, ["s2": "Two"])
        XCTAssertEqual(day.folders, ["/Users/me/app"])
        XCTAssertEqual(day.since, TranscriptReader.date(from: "2026-10-12T23:59:59.000Z"))
    }

    func testAFileThatIsNotADatabaseIsPutAsideAndTheHistoryBegunAgain() throws {
        let base = try folder()
        try write(line(id: "a", at: "2026-10-13T14:00:00.000Z", output: 100) + "\n", to: base.appendingPathComponent("projects/proj/s1.jsonl"))
        let support = base.appendingPathComponent("support")
        try write(String(repeating: "not a database ", count: 400), to: support.appendingPathComponent("history.sqlite"))
        let ledger = ledger(base)
        let pass = ledger.scan(now: now, calendar: utc)
        let aside = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: support.path).first { $0.hasPrefix("history.sqlite.broken-") })
        XCTAssertEqual(pass.problem, "An earlier history file could not be read. It was kept as \(aside).")
        // Not deleted: what it held is still there to get back.
        XCTAssertEqual(try String(contentsOf: support.appendingPathComponent(aside), encoding: .utf8).prefix(15), "not a database ")
        XCTAssertEqual(pass.summary.fiveHours.output, 100)
        // Said on every pass while the app runs.
        XCTAssertEqual(ledger.scan(now: now, calendar: utc).problem, pass.problem)
    }

    func testAPlaceItCannotWriteToIsSaid() throws {
        let base = try folder()
        try write(line(id: "a", at: "2026-10-13T14:00:00.000Z", output: 100) + "\n", to: base.appendingPathComponent("projects/proj/s1.jsonl"))
        // Where the database's folder should be, a file.
        try write("in the way", to: base.appendingPathComponent("support"))
        let pass = ledger(base).scan(now: now, calendar: utc)
        XCTAssertTrue(pass.problem?.hasPrefix("History can't be saved: ") ?? false, pass.problem ?? "no problem said")
        XCTAssertFalse(pass.added)
    }

    func testTheFolderItMakesIsOnlyThisAccounts() throws {
        let base = try folder()
        _ = ledger(base).scan(now: now, calendar: utc)
        // The folder is the one "Answer from the notch" puts its socket in, and that refuses a
        // folder others can enter.
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: base.appendingPathComponent("support").path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue & 0o077, 0)
    }

    func testSwitchedOnItReadsAndSwitchedOffItLetsGo() throws {
        let base = try folder()
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try write(line(id: "a", at: stamp.string(from: Date().addingTimeInterval(-60)), output: 100) + "\n", to: base.appendingPathComponent("projects/proj/s1.jsonl"))
        let ledger = ledger(base)
        // Never switched on: nothing to give, and no file made.
        let empty = expectation(description: "empty before")
        ledger.load(all) { slice in
            XCTAssertEqual(slice, LedgerSlice(interval: self.all))
            empty.fulfill()
        }
        wait(for: [empty], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("support/history.sqlite").path))

        var watch = Set<AnyCancellable>()
        let counted = expectation(description: "counted")
        ledger.$summary.compactMap { $0 }.filter { $0.fiveHours.output == 100 }.first().sink { _ in counted.fulfill() }.store(in: &watch)
        ledger.setEnabled(true)
        wait(for: [counted], timeout: 10)
        XCTAssertGreaterThan(ledger.revision, 0)

        let gone = expectation(description: "let go")
        ledger.$summary.dropFirst().filter { $0 == nil }.first().sink { _ in gone.fulfill() }.store(in: &watch)
        ledger.setEnabled(false)
        wait(for: [gone], timeout: 10)
        let after = expectation(description: "empty after")
        ledger.load(all) { slice in
            XCTAssertTrue(slice.answers.isEmpty)
            after.fulfill()
        }
        wait(for: [after], timeout: 5)
    }
}
