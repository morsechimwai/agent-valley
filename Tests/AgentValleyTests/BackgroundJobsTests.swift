import XCTest
@testable import AgentValley

/// Lines shaped like Claude Code 2.1.310's own: see the spec, "อ่านข้อมูลจากไฟล์บันทึก".
enum JobLines {
    static func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    static func call(_ tool: String, id: String, input: [String: Any], at: String = "2026-10-24T15:00:00.000Z") -> String {
        json(["type": "assistant", "timestamp": at, "message": ["model": "claude-opus-5-5", "stop_reason": "tool_use",
              "content": [["type": "tool_use", "id": id, "name": tool, "input": input]]]])
    }
    static func result(call: String, toolUseResult: Any, error: Bool = false, at: String? = "2026-10-24T15:00:01.000Z") -> String {
        var line: [String: Any] = ["type": "user", "message": ["role": "user", "content": [
            ["type": "tool_result", "tool_use_id": call, "content": "ok", "is_error": error]]], "toolUseResult": toolUseResult]
        if let at { line["timestamp"] = at }
        return json(line)
    }
    static func bash(_ task: String = "bfbr6r6ou", description: String? = "Run CadQuery benchmark", command: String = "python bench.py",
                     at: String? = "2026-10-24T15:00:01.000Z") -> [String] {
        var input: [String: Any] = ["command": command, "run_in_background": true]
        if let description { input["description"] = description }
        return [call("Bash", id: "call-" + task, input: input),
                result(call: "call-" + task, toolUseResult: ["stdout": "", "stderr": "", "interrupted": false, "isImage": false,
                                                            "noOutputExpected": false, "backgroundTaskId": task], at: at)]
    }
    static func monitor(_ task: String = "b66ml5arc", timeoutMs: Int = 900_000, persistent: Bool = false,
                        at: String = "2026-10-24T15:00:03.000Z") -> [String] {
        [call("Monitor", id: "call-" + task, input: ["description": "CadQuery benchmark completion", "timeout_ms": timeoutMs, "command": "tail -f out.log"]),
         result(call: "call-" + task, toolUseResult: ["taskId": task, "timeoutMs": timeoutMs, "persistent": persistent], at: at)]
    }
    /// One `<task-notification>`. No status: a Monitor event, which ends nothing.
    static func notice(_ task: String, status: String?) -> String {
        "<task-notification>\n<task-id>\(task)</task-id>\n" + (status.map { "<status>\($0)</status>\n" } ?? "")
            + "<summary>Background command finished</summary>\n</task-notification>"
    }
    /// What Claude Code queues for a lead when one of its background sub-agents stops.
    static func agentNotice(_ agent: String, summary: String) -> String {
        "<task-notification>\n<task-id>\(agent)</task-id>\n<status>completed</status>\n<summary>\(summary)</summary>\n</task-notification>"
    }
    static func told(_ text: String) -> String {
        json(["type": "user", "timestamp": "2026-10-24T15:03:00.000Z", "message": ["role": "user", "content": text]])
    }
    static func queued(_ text: String) -> String {
        json(["type": "queue-operation", "operation": "enqueue", "timestamp": "2026-10-24T15:03:00.000Z", "sessionId": "s", "content": text])
    }
    /// A notice queued for the model as an attachment line, with no queue-operation or user line for it.
    static func attached(_ text: String, type: String = "queued_command") -> String {
        json(["type": "attachment", "timestamp": "2026-10-24T15:03:00.000Z", "sessionId": "s",
              "attachment": ["type": type, "prompt": text]])
    }
    static func stop(_ task: String, error: Bool = false) -> [String] {
        [call("TaskStop", id: "stop-" + task, input: ["task_id": task]),
         result(call: "stop-" + task, toolUseResult: error ? "Error: No task found with ID: \(task)" as Any
                : ["message": "Successfully stopped task: \(task) (python bench.py)", "task_id": task, "task_type": "local_bash", "command": "python bench.py"],
                error: error)]
    }
    static func read(_ lines: [String]) -> AgentInfo {
        var info = AgentInfo()
        for line in lines { TranscriptReader.apply(line: Data(line.utf8), to: &info) }
        return info
    }
    static func date(_ text: String) -> Date { TranscriptReader.date(from: text)! }
}

final class BackgroundJobsTests: XCTestCase {
    func testABackgroundBashStartsAJob() {
        XCTAssertEqual(JobLines.read(JobLines.bash()).jobs,
                       [BackgroundJob(id: "bfbr6r6ou", kind: .shell, name: "Run CadQuery benchmark", startedAt: JobLines.date("2026-10-24T15:00:01.000Z"), endsBy: nil)])
        // No description: the command names it.
        XCTAssertEqual(JobLines.read(JobLines.bash(description: nil, command: "npm run dev")).jobs.first?.name, "npm run dev")
    }
    func testAShellThatServesOnAPortIsMarked() {
        XCTAssertTrue(JobLines.read(JobLines.bash(description: "Start Next.js dev server", command: "cd site && npm run dev")).jobs[0].serves)
        // By the command alone, too.
        XCTAssertTrue(JobLines.read(JobLines.bash(description: nil, command: "python3 -m http.server 8000")).jobs[0].serves)
        XCTAssertFalse(JobLines.read(JobLines.bash()).jobs[0].serves)
        XCTAssertFalse(JobLines.read(JobLines.monitor()).jobs[0].serves)
    }
    func testTheServerWords() {
        for words in ["npm run dev", "pnpm dev", "yarn start", "bun run preview", "npx next dev -p 3001", "next start",
                      "npx vite", "vite --host", "npx serve out", "ng serve", "bundle exec jekyll serve", "uvicorn app:app --reload",
                      "python manage.py runserver", "flask run", "rails s", "hugo server -D", "php -S localhost:8000",
                      "docker compose up", "npx remotion studio", "npx storybook dev", "PORT=4000 node index.js",
                      "node server.js --port 8080", "Start Next.js dev server", "Serve the docs site", "Start API server on port 8080"] {
            XCTAssertTrue(BackgroundJobs.serves(words), words)
        }
        for words in ["npm run build", "npm test", "swift test", "vite build", "cat vite.config.ts", "cd server && npm run build",
                      "Run server tests", "tsc --watch", "sleep 30", "python bench.py", "Run CadQuery benchmark", "npm run lint"] {
            XCTAssertFalse(BackgroundJobs.serves(words), words)
        }
    }
    func testAMonitorStartsAJobWithItsCeiling() {
        let start = JobLines.date("2026-10-24T15:00:03.000Z")
        XCTAssertEqual(JobLines.read(JobLines.monitor()).jobs,
                       [BackgroundJob(id: "b66ml5arc", kind: .monitor, name: "CadQuery benchmark completion", startedAt: start, endsBy: start + 900)])
        XCTAssertNil(JobLines.read(JobLines.monitor(persistent: true)).jobs.first?.endsBy)
    }
    func testTheSameStartWrittenAgainIsOneJob() {
        XCTAssertEqual(JobLines.read(JobLines.bash() + [JobLines.bash()[1]]).jobs.count, 1)
        // Claude Code's copy without a timestamp starts nothing.
        XCTAssertTrue(JobLines.read([JobLines.bash(at: nil)[0], JobLines.bash(at: nil)[1]]).jobs.isEmpty)
    }
    func testEveryStatusEndsTheJobFromEitherPlace() {
        for status in ["completed", "failed", "killed", "stopped"] {
            let notice = JobLines.notice("bfbr6r6ou", status: status)
            XCTAssertTrue(JobLines.read(JobLines.bash() + [JobLines.told(notice)]).jobs.isEmpty, status)
            let queued = JobLines.read(JobLines.bash() + [JobLines.queued(notice)])
            XCTAssertTrue(queued.jobs.isEmpty, status)
            XCTAssertEqual(queued.endedJobs, ["bfbr6r6ou"])
        }
    }
    func testAQueuedCommandAttachmentEndsTheJob() {
        let notice = JobLines.notice("bp5ojl2mq", status: "completed")
        let info = JobLines.read(JobLines.bash("bp5ojl2mq") + [JobLines.attached(notice)])
        XCTAssertTrue(info.jobs.isEmpty)
        XCTAssertEqual(info.endedJobs, ["bp5ojl2mq"])
    }
    func testAnAttachmentOfAnotherKindEndsNothing() {
        // A snapshot of the system prompt holds the words of a notice too.
        let notice = JobLines.notice("bp5ojl2mq", status: "completed")
        let info = JobLines.read(JobLines.bash("bp5ojl2mq") + [JobLines.attached(notice, type: "prompt_snapshot")])
        XCTAssertEqual(info.jobs.map(\.id), ["bp5ojl2mq"])
        XCTAssertEqual(info.endedJobs, [])
    }
    func testOnlyNotificationsWithAStatusEndTheirOwnJob() {
        let text = JobLines.notice("b66ml5arc", status: nil) + "\n" + JobLines.notice("aba059b9972ba673b", status: "completed")
        XCTAssertEqual(BackgroundJobs.ended(in: text), ["aba059b9972ba673b"])
        XCTAssertEqual(JobLines.read(JobLines.bash() + JobLines.monitor() + [JobLines.told(text)]).jobs.map(\.id), ["bfbr6r6ou", "b66ml5arc"])
    }
    func testTaskStopEndsTheJobUnlessItFailed() {
        XCTAssertTrue(JobLines.read(JobLines.bash() + JobLines.stop("bfbr6r6ou")).jobs.isEmpty)
        XCTAssertEqual(JobLines.read(JobLines.bash() + JobLines.stop("bfbr6r6ou", error: true)).jobs.count, 1)
    }
    func testAnInterruptDoesNotEndABackgroundJob() {
        let esc = JobLines.json(["type": "user", "timestamp": "2026-10-24T15:01:00.000Z",
                                 "message": ["role": "user", "content": [["type": "text", "text": "[Request interrupted by user]"]]]])
        XCTAssertEqual(JobLines.read(JobLines.bash() + [esc]).jobs.count, 1)
    }
    func testAJobNameIsClipped() {
        XCTAssertEqual(JobLines.read(JobLines.bash(description: "Run\nbench\u{202E}mark")).jobs.first?.name, "Run benchmark")
    }
    func testAFileKeepsAtMostSixteenJobs() {
        let jobs = JobLines.read((0..<20).flatMap { JobLines.bash("j\($0)") }).jobs
        XCTAssertEqual(jobs.count, 16)
        XCTAssertEqual(jobs.first?.id, "j4")
    }
    func testTheScreenRestsOnlyOnceEveryJobIsHalfAnHourOld() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func job(_ age: TimeInterval) -> BackgroundJob { BackgroundJob(id: "\(age)", kind: .shell, name: "", startedAt: now - age, endsBy: nil) }
        XCTAssertFalse(job(1799).isLong(now: now))
        XCTAssertTrue(job(1800).isLong(now: now))
        XCTAssertTrue(BackgroundJobs.resting([job(1800), job(4000)], now: now))
        XCTAssertFalse(BackgroundJobs.resting([job(1800), job(60)], now: now))
        XCTAssertTrue(BackgroundJobs.resting([], now: now))
    }

    private func file(_ session: String, main: Bool, _ lines: [String]) -> TrackedFile {
        TrackedFile(session: session, isMain: main, info: JobLines.read(lines))
    }
    private let start = JobLines.date("2026-10-24T15:00:01.000Z")

    func testJobsOfASessionComeFromEveryFileOldestFirst() {
        let files = ["s.jsonl": file("/p/s", main: true, JobLines.bash(at: "2026-10-24T15:00:05.000Z")),
                     "s/subagents/agent-a.jsonl": file("/p/s", main: false, JobLines.monitor(persistent: true))]
        XCTAssertEqual(BackgroundJobs.bySession(files, now: start + 60, running: nil)["/p/s"]?.map(\.id), ["b66ml5arc", "bfbr6r6ou"])
    }
    func testAJobStartedInOneFileEndsInAnother() {
        let notice = JobLines.notice("bfbr6r6ou", status: "completed")
        let subToMain = ["m": file("/p/s", main: true, [JobLines.queued(notice)]), "a": file("/p/s", main: false, JobLines.bash())]
        let mainToSub = ["m": file("/p/s", main: true, JobLines.bash()), "a": file("/p/s", main: false, [JobLines.told(notice)])]
        XCTAssertEqual(BackgroundJobs.bySession(subToMain, now: start, running: nil)["/p/s"] ?? [], [])
        XCTAssertEqual(BackgroundJobs.bySession(mainToSub, now: start, running: nil)["/p/s"] ?? [], [])
    }
    func testAnEndInTheMainFileOutlastsManyLaterEnds() {
        // A sub-agent's shell ends only in the main file, and a busy session ends many more after it.
        let later = (0..<100).map { JobLines.queued(JobLines.notice("later\($0)", status: "completed")) }
        let files = ["m": file("/p/s", main: true, [JobLines.queued(JobLines.notice("bfbr6r6ou", status: "completed"))] + later),
                     "a": file("/p/s", main: false, JobLines.bash())]
        XCTAssertEqual(BackgroundJobs.bySession(files, now: start, running: nil)["/p/s"] ?? [], [])
    }
    func testTheSameJobInTwoFilesIsOneJob() {
        let files = ["m": file("/p/s", main: true, JobLines.bash()), "a": file("/p/s", main: false, JobLines.bash(at: "2026-10-24T15:00:05.000Z"))]
        XCTAssertEqual(BackgroundJobs.bySession(files, now: start + 60, running: nil)["/p/s"]?.map(\.startedAt), [start])
    }
    func testAJobEndedBeforeItsStartWasReadIsNotRunning() {
        // The main file's queue line was read first; the sub-agent's start comes after.
        var files = ["m": file("/p/s", main: true, [JobLines.queued(JobLines.notice("bfbr6r6ou", status: "completed"))])]
        files["a"] = file("/p/s", main: false, JobLines.bash())
        XCTAssertEqual(BackgroundJobs.bySession(files, now: start, running: nil)["/p/s"] ?? [], [])
    }
    func testAMonitorPastItsTimeoutHasEnded() {
        let monitorStart = JobLines.date("2026-10-24T15:00:03.000Z")
        let files = ["m": file("/p/s", main: true, JobLines.monitor())]
        XCTAssertEqual(BackgroundJobs.bySession(files, now: monitorStart + 899, running: nil)["/p/s"]?.count, 1)
        XCTAssertEqual(BackgroundJobs.bySession(files, now: monitorStart + 900, running: nil)["/p/s"] ?? [], [])
        let held = ["m": file("/p/s", main: true, JobLines.monitor(persistent: true))]
        XCTAssertEqual(BackgroundJobs.bySession(held, now: monitorStart + 86_000, running: nil)["/p/s"]?.count, 1)
    }
    func testAClosedSessionAndAnEarlierProcessLeaveNoJobs() {
        let files = ["m": file("/p/s", main: true, JobLines.bash())]
        XCTAssertEqual(BackgroundJobs.bySession(files, now: start, running: [:])["/p/s"] ?? [], [])          // rule 4
        XCTAssertEqual(BackgroundJobs.bySession(files, now: start, running: ["s": start + 5])["/p/s"] ?? [], []) // rule 5
        XCTAssertEqual(BackgroundJobs.bySession(files, now: start, running: ["s": start - 5])["/p/s"]?.count, 1)
    }

    // Claude Code tells the lead when a sub-agent ends its turn with work of its own still running.
    func testTheLeadHearsWhichSubAgentsWaitOnTheirOwnWork() {
        let waits = JobLines.agentNotice("aa9f3fd2ca39e53c3", summary: "Agent \"Slow sub-agent\" is waiting on its own background work")
        let done = JobLines.agentNotice("aa9f3fd2ca39e53c3", summary: "Agent \"Slow sub-agent\" finished")
        let at = JobLines.date("2026-10-24T15:03:00.000Z")
        // Queued, attached or told: each way a notice comes counts.
        for line in [JobLines.queued(waits), JobLines.attached(waits), JobLines.told(waits)] {
            XCTAssertEqual(JobLines.read([line]).waitingAgents, ["aa9f3fd2ca39e53c3": at])
        }
        XCTAssertEqual(JobLines.read([JobLines.queued(waits), JobLines.attached(done)]).waitingAgents, [:])
        // A job's own notice says nothing of an agent.
        XCTAssertEqual(JobLines.read([JobLines.queued(JobLines.notice("bp5ojl2mq", status: "completed"))]).waitingAgents, [:])
        // A copy with no time leaves what an earlier one said.
        let copy = JobLines.json(["type": "user", "message": ["role": "user", "content": waits]])
        XCTAssertEqual(JobLines.read([JobLines.queued(waits), copy]).waitingAgents, ["aa9f3fd2ca39e53c3": at])
        // Nor a snapshot of the system prompt that holds the words.
        XCTAssertEqual(JobLines.read([JobLines.attached(waits, type: "prompt_snapshot")]).waitingAgents, [:])
    }
}
