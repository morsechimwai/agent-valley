import XCTest
@testable import AgentValley

final class TranscriptReaderTests: XCTestCase {
    private let prompt = #"{"type":"user","timestamp":"2026-10-12T02:00:00.000Z","cwd":"/Users/me/web-app","gitBranch":"main","message":{"role":"user","content":"find auth files"}}"#
    private let toolUse = #"{"type":"assistant","timestamp":"2026-10-12T02:00:05.000Z","message":{"id":"msg_1","model":"claude-haiku-5-5","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/Users/me/web-app/src/login.ts"}}],"usage":{"input_tokens":10,"cache_creation_input_tokens":200,"cache_read_input_tokens":3000,"output_tokens":40}}}"#
    private let toolResult = #"{"type":"user","timestamp":"2026-10-12T02:00:06.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#
    private let answer = #"{"type":"assistant","timestamp":"2026-10-12T02:00:09.000Z","message":{"id":"msg_2","model":"claude-haiku-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"Found 3 files."}],"usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":4000,"output_tokens":20}}}"#

    private func read(_ lines: String...) -> AgentInfo {
        var info = AgentInfo()
        for line in lines { TranscriptReader.apply(line: Data(line.utf8), to: &info) }
        return info
    }

    private func date(_ stamp: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: stamp)!
    }

    private func create(_ n: Int, _ subject: String = "s") -> [String] {
        [#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"c\#(n)","name":"TaskCreate","input":{"subject":"\#(subject)","description":"d"}}]}}"#,
         #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"c\#(n)","content":"ok"}]},"toolUseResult":{"task":{"id":"\#(n)","subject":"\#(subject)"}}}"#]
    }

    private func update(_ id: String, _ status: String) -> String {
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u\#(id)\#(status)","name":"TaskUpdate","input":{"taskId":"\#(id)","status":"\#(status)"}}]}}"#
    }

    private func todos(_ json: String) -> String {
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w","name":"TodoWrite","input":{"todos":\#(json)}}]}}"#
    }

    /// Done and all.
    private func done(_ info: AgentInfo) -> [Int] { [info.tasks.filter(\.done).count, info.tasks.count] }

    private func apply(_ lines: [String], to info: inout AgentInfo) {
        for line in lines { TranscriptReader.apply(line: Data(line.utf8), to: &info) }
    }

    func testTaskCreateAndUpdateCountProgress() {
        var info = AgentInfo()
        apply(create(1) + create(2) + create(3) + [update("1", "completed"), update("2", "in_progress")], to: &info)
        XCTAssertEqual(done(info), [1, 3])
        apply([update("3", "deleted")], to: &info)
        XCTAssertEqual(done(info), [1, 2])
    }

    func testTheTaskListKeepsWhatEachTaskIsInOrder() {
        var info = AgentInfo()
        apply(create(1, "Map the call sites") + create(2, "Plan the fix") + [update("2", "in_progress")], to: &info)
        XCTAssertEqual(info.tasks, [TaskItem(id: "1", subject: "Map the call sites", status: "pending"),
                                    TaskItem(id: "2", subject: "Plan the fix", status: "in_progress")])
        // A task renamed keeps its status and its place.
        apply([#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"r1","name":"TaskUpdate","input":{"taskId":"1","subject":"Map every call site"}}]}}"#], to: &info)
        XCTAssertEqual(info.tasks.first, TaskItem(id: "1", subject: "Map every call site", status: "pending"))
        apply([todos(#"[{"content":"a","status":"completed"},{"content":"b","status":"in_progress"}]"#)], to: &info)
        XCTAssertEqual(info.tasks.map(\.subject), ["a", "b"])
        XCTAssertEqual(info.tasks.map(\.status), ["completed", "in_progress"])
    }

    func testTodoWriteReplacesTheList() {
        var info = AgentInfo()
        apply([todos(#"[{"content":"a","status":"completed"},{"content":"b","status":"in_progress"},{"content":"c","status":"pending"}]"#)], to: &info)
        XCTAssertEqual(done(info), [1, 3])
        apply([todos("[]")], to: &info)
        XCTAssertTrue(info.tasks.isEmpty)
    }

    func testOddTaskInputStaysBounded() {
        var info = AgentInfo()
        apply([update("9", "completed")], to: &info)
        XCTAssertEqual(done(info), [1, 1])
        apply([update("8", "blocked")], to: &info)
        XCTAssertEqual(done(info), [1, 2])
        apply([todos(#""x""#)], to: &info)
        XCTAssertEqual(done(info), [1, 2])
        var many = AgentInfo()
        for n in 1...300 { apply(create(n), to: &many) }
        XCTAssertEqual(many.tasks.count, 200)
        XCTAssertEqual(TranscriptReader.maxTasks, 200)
    }

    // A call that waits on the person says what it asks, not the name of the tool that asks it.
    func testAStepThatAsksThePersonSaysWhatItAsks() {
        let input: [String: Any] = ["questions": [["question": "Which rounding rule\nshould totals use?", "options": [String]()], ["question": "And the second?"]]]
        // More than one question: the step says how many, as the request does, in the app's
        // own words alone. The model's text is not run on behind them.
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "AskUserQuestion", input: input), "2 questions")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "AskUserQuestion", input: ["questions": [["question": "Which rounding rule\nshould totals use?"]]]), "Which rounding rule should totals use?")
        // The model wrote the question. Text that would not draw as written, or that says
        // nothing, is not put on the row at all.
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "AskUserQuestion", input: ["questions": [["question": "safe\u{202E}live"]]]), "AskUserQuestion")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "AskUserQuestion", input: ["questions": [["question": "zero\u{200B}width"]]]), "AskUserQuestion")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "AskUserQuestion", input: ["questions": [["question": "   "]]]), "AskUserQuestion")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "AskUserQuestion", input: ["questions": [String]()]), "AskUserQuestion")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "AskUserQuestion", input: ["questions": [["question": String(repeating: "q", count: 300)]]]).count, TranscriptReader.stepDetailLimit)
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "ExitPlanMode", input: ["plan": "1. do it"]), "Plan ready for review")
    }

    // A session can be days old. How long its agent has been at it counts from the latest prompt.
    func testATurnBeginsAtThePersonsPromptAndNothingElse() {
        let second = #"{"type":"user","timestamp":"2026-10-12T03:00:00.000Z","message":{"role":"user","content":[{"type":"text","text":"now fix it"}]}}"#
        let note = #"{"type":"user","isMeta":true,"timestamp":"2026-10-12T03:00:20.000Z","message":{"role":"user","content":"<system-reminder>note</system-reminder>"}}"#
        let laterResult = #"{"type":"user","timestamp":"2026-10-12T03:00:40.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t9","content":"ok"}]}}"#
        let stopped = #"{"type":"user","timestamp":"2026-10-12T03:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        XCTAssertEqual(read(prompt, toolUse, toolResult).turnStartedAt, date("2026-10-12T02:00:00.000Z"))
        XCTAssertEqual(read(prompt, toolUse, toolResult, answer, second).turnStartedAt, date("2026-10-12T03:00:00.000Z"))
        XCTAssertEqual(read(prompt, answer, second, note, laterResult, stopped).turnStartedAt, date("2026-10-12T03:00:00.000Z"))
        // Elapsed counts from there.
        let info = read(prompt, toolUse, toolResult, answer, second)
        let now = date("2026-10-12T03:02:00.000Z")
        XCTAssertEqual(TranscriptReader.elapsed(of: info, lastActivity: date("2026-10-12T03:00:00.000Z"), now: now, session: .busy), 120)
    }

    /// The name tags Claude writes are the terminal's: the panel shows the names.
    func testNameTagsReadAsNames() {
        let tagged = read(#"{"type":"assistant","message":{"id":"m","stop_reason":"end_turn","content":[{"type":"text","text":"\#(CrewFont.Tag.text(.general)) is back. Next, \#(CrewFont.Tag.text(.explore))."}]}}"#)
        XCTAssertEqual(tagged.thought, "Felix is back. Next, Faye.")
        XCTAssertEqual(tagged.handedBack, "Felix is back. Next, Faye.")
    }

    // "> Thinking" told the person nothing. Between calls a row says where the agent is headed:
    // the first line of what it last thought or wrote this turn, else the step it just finished.
    func testBetweenCallsARowSaysWhereItIsHeaded() {
        func thinking(_ text: String) -> String {
            #"{"type":"assistant","message":{"id":"m","content":[{"type":"thinking","thinking":"\#(text)","signature":"s"}]}}"#
        }
        func text(_ text: String) -> String {
            #"{"type":"assistant","message":{"id":"m","content":[{"type":"text","text":"\#(text)"}]}}"#
        }
        XCTAssertEqual(read(prompt).betweenCalls, "Thinking")
        XCTAssertEqual(read(prompt, toolUse, toolResult).betweenCalls, "Thinking · after Read login.ts")
        // Most thoughts come with their words left out: those say nothing.
        XCTAssertEqual(read(prompt, toolUse, toolResult, thinking("")).betweenCalls, "Thinking · after Read login.ts")
        XCTAssertEqual(read(prompt, thinking(#"The door swings in.\n\n"#), toolUse, toolResult).betweenCalls, "The door swings in.")
        // The newest wins, thought or words, by its first line, without markdown's marks.
        XCTAssertEqual(read(prompt, thinking("Old."), text(#"\n**Next**, check `login.ts`.\nMore."#)).thought, "Next, check login.ts.")
        XCTAssertEqual(read(prompt, text("Old."), thinking("กำลังเช็กราคา")).thought, "กำลังเช็กราคา")
        // An answer that opens on a list or a heading reads from its words, not its marks.
        XCTAssertEqual(read(prompt, text(#"- Data in: stdin JSON\n- Out: rows"#)).thought, "Data in: stdin JSON")
        XCTAssertEqual(read(prompt, text("## Findings")).thought, "Findings")
        XCTAssertEqual(read(prompt, text(#"---\nReal line."#)).thought, "Real line.")
        XCTAssertEqual(read(prompt, text(String(repeating: "x", count: 200))).thought.count, TranscriptReader.stepDetailLimit)
        // A new prompt starts the turn over: the last turn's thought is not where this one is headed.
        XCTAssertEqual(read(prompt, text("Old."), answer, prompt).thought, "")

        func row(_ status: AgentStatus, _ info: AgentInfo) -> AgentRow { AgentRow(id: "r", info: info, status: status, elapsed: 0) }
        let headed = read(prompt, text("Checking the door."), toolUse)
        // A call open: the row names it, as before.
        XCTAssertEqual(row(.working, headed).step, "Read login.ts")
        let between = read(prompt, text("Checking the door."), toolUse, toolResult)
        XCTAssertEqual(row(.working, between).step, "Checking the door.")
        XCTAssertEqual(row(.quiet, between).step, "Read login.ts")
        // Before its first step a row has no step line, as before.
        XCTAssertEqual(row(.working, read(prompt)).step, "")
    }

    func testReadsModelStepsAndLastStep() {
        let info = read(prompt, toolUse)
        XCTAssertEqual(info.model, "Haiku 5.5")
        XCTAssertEqual(info.steps, 1)
        XCTAssertEqual(info.lastStep, "Read login.ts")
        XCTAssertEqual(info.cwd, "/Users/me/web-app")
        XCTAssertEqual(info.branch, "main")
        XCTAssertEqual(info.startedAt, date("2026-10-12T02:00:00.000Z"))
        XCTAssertFalse(info.turnEnded)
    }

    func testEndsWithTextOnlyAfterAnAnswerWithNoToolCall() {
        XCTAssertFalse(read(prompt, toolUse, toolResult).turnEnded)
        let finished = read(prompt, toolUse, toolResult, answer)
        XCTAssertTrue(finished.turnEnded)
        XCTAssertFalse(read(prompt, toolUse, toolResult, answer, toolUse).turnEnded)
    }

    // Claude Code writes one line per content block: the text block lands first, and the tool call
    // of the same message can follow many seconds later.
    func testATextBlockIsNotAnAnswerUntilTheMessageStops() {
        let streaming = #"{"type":"assistant","message":{"model":"claude-haiku-5-5","stop_reason":null,"content":[{"type":"text","text":"Let me write that file."}]}}"#
        let beforeTool = #"{"type":"assistant","message":{"model":"claude-haiku-5-5","stop_reason":"tool_use","content":[{"type":"text","text":"Let me write that file."}]}}"#
        XCTAssertFalse(read(prompt, streaming).turnEnded)
        XCTAssertFalse(read(prompt, beforeTool).turnEnded)
        XCTAssertTrue(read(prompt, answer).turnEnded)
    }

    // Esc is recorded as a user line. The agent has stopped and waits for the next prompt.
    func testInterruptNoticeEndsTheTurn() {
        let interrupted = #"{"type":"user","interruptedMessageId":"msg_1","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        let forToolUse = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
        XCTAssertTrue(read(prompt, toolUse, interrupted).turnEnded)
        XCTAssertTrue(read(prompt, toolUse, forToolUse).turnEnded)
        XCTAssertFalse(read(prompt, toolUse, interrupted, prompt).turnEnded)
    }

    // A question on screen is the one moment the transcript proves an agent is waiting on the
    // person. It must not sit as "working" for two minutes first.
    func testAPendingQuestionOrPlanNeedsThePersonAtOnce() {
        let ask = #"{"type":"assistant","timestamp":"2026-10-12T02:00:05.000Z","message":{"model":"claude-haiku-5-5","stop_reason":"tool_use","content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{"questions":[]}}]}}"#
        let plan = #"{"type":"assistant","timestamp":"2026-10-12T02:00:05.000Z","message":{"model":"claude-haiku-5-5","stop_reason":"tool_use","content":[{"type":"tool_use","id":"p1","name":"ExitPlanMode","input":{"plan":"1. do it"}}]}}"#
        let answered = #"{"type":"user","timestamp":"2026-10-12T02:03:00.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"q1","content":"yes"}]}}"#
        XCTAssertTrue(read(prompt, ask).asking)
        XCTAssertTrue(read(prompt, plan).asking)
        XCTAssertFalse(read(prompt, toolUse).asking)
        XCTAssertFalse(read(prompt, ask, answered).asking)

        let info = read(prompt, ask)
        let last = info.lastActivity!
        XCTAssertEqual(TranscriptReader.status(of: info, lastActivity: last, now: last), .needsYou)
        XCTAssertEqual(TranscriptReader.status(of: info, lastActivity: last, now: last.addingTimeInterval(3000)), .needsYou)
        XCTAssertEqual(TranscriptReader.status(of: read(prompt, ask, answered), lastActivity: last, now: last), .working)
    }

    // A permission request names a tool and its input but not who asked. The call with no result
    // yet in a transcript is how a request finds its agent, and the result arriving is how the app
    // learns the question was answered in the terminal.
    func testToolCallsStayOpenUntilTheirResultArrives() {
        let digest = AnswerProtocol.digest(tool: "Read", input: ["file_path": "/Users/me/web-app/src/login.ts"])
        XCTAssertEqual(read(prompt).openTools, [])
        XCTAssertEqual(read(prompt, toolUse).openTools.map(\.id), ["t1"])
        XCTAssertEqual(read(prompt, toolUse).openTools.first?.digest, digest)
        XCTAssertEqual(read(prompt, toolUse, toolResult).openTools, [])
        let second = #"{"type":"assistant","timestamp":"2026-10-12T02:00:05.500Z","message":{"model":"claude-haiku-5-5","stop_reason":"tool_use","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"ls"}}]}}"#
        XCTAssertEqual(read(prompt, toolUse, second, toolResult).openTools.map(\.id), ["t2"])
        // A new prompt answers nothing; an interrupt ends every call still waiting.
        XCTAssertEqual(read(prompt, toolUse, prompt).openTools.map(\.id), ["t1"])
        let interrupted = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
        XCTAssertEqual(read(prompt, toolUse, interrupted).openTools, [])
        let nameless = #"{"type":"assistant","message":{"model":"claude-haiku-5-5","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#
        XCTAssertEqual(read(prompt, nameless).openTools, [])
    }

    // A call can be answered before the app ever saw it open. What closed, and when, is kept
    // for a while so a request that arrived in between can still be told it is over.
    func testAnsweredToolCallsAreRememberedWithTheirTime() {
        let info = read(prompt, toolUse, toolResult)
        XCTAssertEqual(info.closedTools.map(\.tool.id), ["t1"])
        XCTAssertEqual(info.closedTools.first?.tool.digest, AnswerProtocol.digest(tool: "Read", input: ["file_path": "/Users/me/web-app/src/login.ts"]))
        XCTAssertEqual(info.closedTools.first?.at, info.lastActivity)
        var many = AgentInfo()
        for index in 0..<(TranscriptReader.closedToolLimit + 3) {
            let call = #"{"type":"assistant","message":{"model":"claude-haiku-5-5","content":[{"type":"tool_use","id":"t\#(index)","name":"Bash","input":{"command":"ls"}}]}}"#
            let result = #"{"type":"user","timestamp":"2026-10-12T02:00:06.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t\#(index)","content":"ok"}]}}"#
            TranscriptReader.apply(line: Data(call.utf8), to: &many)
            TranscriptReader.apply(line: Data(result.utf8), to: &many)
        }
        XCTAssertEqual(many.closedTools.count, TranscriptReader.closedToolLimit)
        XCTAssertEqual(many.closedTools.last?.tool.id, "t\(TranscriptReader.closedToolLimit + 2)")
    }

    func testOnlyTheLatestOpenToolCallsAreKept() {
        var info = AgentInfo()
        for index in 0...TranscriptReader.openToolLimit {
            let line = #"{"type":"assistant","message":{"model":"claude-haiku-5-5","content":[{"type":"tool_use","id":"t\#(index)","name":"Bash","input":{"command":"ls \#(index)"}}]}}"#
            TranscriptReader.apply(line: Data(line.utf8), to: &info)
        }
        XCTAssertEqual(info.openTools.count, TranscriptReader.openToolLimit)
        XCTAssertEqual(info.openTools.first?.id, "t1")
        XCTAssertEqual(info.openTools.last?.id, "t\(TranscriptReader.openToolLimit)")
    }

    func testTheSessionTitleIsTheLatestOneClaudeCodeWrote() {
        let first = #"{"type":"ai-title","aiTitle":"Fix checkout rounding","sessionId":"s1"}"#
        let second = #"{"type":"ai-title","aiTitle":"Fix checkout\nrounding and tax","sessionId":"s1"}"#
        let empty = #"{"type":"ai-title","aiTitle":"","sessionId":"s1"}"#
        XCTAssertEqual(read(prompt).title, "")
        XCTAssertEqual(read(prompt, first).title, "Fix checkout rounding")
        XCTAssertEqual(read(prompt, first, second, empty).title, "Fix checkout rounding and tax")
        // A title line is housekeeping: it must not look like the agent doing something.
        XCTAssertEqual(read(prompt, first).lastActivity, read(prompt).lastActivity)
    }

    // An agent that changes directory mid-session must not rename its card.
    func testProjectFolderStaysWhereTheSessionStarted() {
        let moved = #"{"type":"user","cwd":"/Users/me/web-app/packages/api","gitBranch":"feat/x","message":{"role":"user","content":"next"}}"#
        let info = read(prompt, moved)
        XCTAssertEqual(info.cwd, "/Users/me/web-app")
        XCTAssertEqual(info.branch, "feat/x")
        // Where it is now is kept beside it: the branch is the branch of that directory.
        XCTAssertEqual(info.folder, "/Users/me/web-app/packages/api")
        // Outside a repository Claude Code writes "HEAD": no branch, and not the last one either.
        let outside = #"{"type":"user","cwd":"/Users/me/notes","gitBranch":"HEAD","message":{"role":"user","content":"next"}}"#
        XCTAssertEqual(read(prompt, moved, outside).branch, "")
    }

    // Claude Code appends housekeeping lines to idle sessions; only the conversation counts as activity.
    func testLastActivityFollowsConversationLinesOnly() {
        let housekeeping = #"{"type":"system","timestamp":"2026-10-12T09:00:00.000Z","content":"x"}"#
        XCTAssertNil(read(housekeeping).lastActivity)
        XCTAssertEqual(read(prompt, toolUse, housekeeping).lastActivity, date("2026-10-12T02:00:05.000Z"))
        XCTAssertEqual(read(prompt).lastActivity, date("2026-10-12T02:00:00.000Z"))
    }

    func testModelNameDropsItsDateSuffix() {
        func model(_ id: String) -> String {
            read(#"{"type":"assistant","message":{"model":"\#(id)","content":[]}}"#).model
        }
        XCTAssertEqual(model("claude-opus-4-5-20251101"), "Opus 4.5")
        XCTAssertEqual(model("claude-haiku-5-5"), "Haiku 5.5")
        XCTAssertEqual(model("claude-3-5-sonnet-20241022"), "3-5-sonnet")
        XCTAssertEqual(model("some-model-12345"), "some-model-12345")
    }

    func testReadsEntrypoint() {
        let headless = #"{"type":"user","entrypoint":"sdk-py","message":{"role":"user","content":"Review this change"}}"#
        XCTAssertEqual(read(headless).entrypoint, "sdk-py")
        XCTAssertEqual(read(prompt).entrypoint, "")
    }

    // A workflow's sub-agent hands in its result by calling StructuredOutput and writes nothing
    // after: no closing answer. On the owner's screen seven such agents stood as "working" for
    // ten minutes each. The call is the end of their work.
    func testAnAgentThatHandedInItsResultHasFinished() {
        let call = #"{"type":"assistant","timestamp":"2026-10-13T08:00:00.000Z","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","id":"t9","name":"StructuredOutput","input":{"result":"ok"}}]}}"#
        let result = #"{"type":"user","timestamp":"2026-10-13T08:00:01.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t9","content":"ok"}]}}"#
        let more = #"{"type":"assistant","timestamp":"2026-10-13T08:00:05.000Z","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","id":"t10","name":"Read","input":{"file_path":"/a/b.ts"}}]}}"#
        let done = read(call, result)
        XCTAssertTrue(done.finished)
        let at = date("2026-10-13T08:00:01.000Z")
        // Done once it has been still for a moment, whatever Claude Code says of the session.
        XCTAssertEqual(TranscriptReader.status(of: done, lastActivity: at, now: at.addingTimeInterval(30), session: .busy), .done)
        XCTAssertEqual(TranscriptReader.status(of: done, lastActivity: at, now: at.addingTimeInterval(2), session: .busy), .working)
        // It went on working after all: not finished.
        XCTAssertFalse(read(call, result, more).finished)
        XCTAssertFalse(read(more).finished)
    }

    // The name of a tool is the model's to write. A result handed in beside a call that still
    // waits, for a permission prompt in the terminal or for an answer, is not the end: the row
    // would turn "done" and leave the list while the person is being waited for.
    func testAResultHandedInBesideACallThatStillWaitsIsNotTheEnd() {
        func call(_ id: String, _ tool: String) -> String {
            #"{"type":"assistant","timestamp":"2026-10-13T08:00:00.000Z","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","id":"\#(id)","name":"\#(tool)","input":{}}]}}"#
        }
        func result(_ id: String) -> String {
            #"{"type":"user","timestamp":"2026-10-13T08:00:01.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"ok"}]}}"#
        }
        // Claude Code writes each call of one message on a line of its own.
        let waiting = read(call("t1", "Bash"), call("t2", "StructuredOutput"))
        XCTAssertFalse(waiting.finished)
        let at = date("2026-10-13T08:00:00.000Z")
        XCTAssertNotEqual(TranscriptReader.status(of: waiting, lastActivity: at, now: at.addingTimeInterval(30)), .done)
        // In one line, either way round.
        let both = #"{"type":"assistant","timestamp":"2026-10-13T08:00:00.000Z","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","id":"t1","name":"AskUserQuestion","input":{}},{"type":"tool_use","id":"t2","name":"StructuredOutput","input":{}}]}}"#
        XCTAssertFalse(read(both).finished)
        // Once the other call has its result, the handing in stands.
        XCTAssertTrue(read(call("t1", "Bash"), call("t2", "StructuredOutput"), result("t1")).finished)
        XCTAssertTrue(read(call("t1", "Bash"), call("t2", "StructuredOutput"), result("t1"), result("t2")).finished)
    }

    // A new prompt in the same transcript starts the work again: what was handed in before no
    // longer says the agent has finished.
    func testAPromptAfterAResultStartsTheWorkAgain() {
        let call = #"{"type":"assistant","timestamp":"2026-10-13T08:00:00.000Z","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","id":"t9","name":"StructuredOutput","input":{}}]}}"#
        let result = #"{"type":"user","timestamp":"2026-10-13T08:00:01.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t9","content":"ok"}]}}"#
        let again = #"{"type":"user","timestamp":"2026-10-13T08:05:00.000Z","message":{"role":"user","content":"One more thing"}}"#
        XCTAssertTrue(read(call, result).finished)
        let info = read(call, result, again)
        XCTAssertFalse(info.finished)
        let at = date("2026-10-13T08:05:00.000Z")
        XCTAssertEqual(TranscriptReader.status(of: info, lastActivity: at, now: at.addingTimeInterval(30), session: .busy), .working)
    }

    // A tool from an MCP server is named "mcp__<server>__<tool>", and on a row the server's
    // name took the whole line: "mcp__plugin_playwright_playwright__browser_nav…". What it is
    // doing comes first, and where the tool comes from last, where the cut falls.
    func testAStepByAnMCPToolLeadsWithWhatItDoes() {
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "mcp__plugin_playwright_playwright__browser_navigate", input: ["url": "https://example.com"]),
                       "browser_navigate https://example.com (plugin_playwright_playwright)")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "mcp__posthog__exec", input: [:]), "exec (posthog)")
        // Not that shape: left as it is.
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "mcp__odd", input: [:]), "mcp__odd")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "my__tool", input: ["url": "u"]), "my__tool u")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "mcp____", input: [:]), "mcp____")
        // One line whatever the name holds: a line break in it would cut the row there.
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "mcp__ser\nver__do\nit", input: [:]), "do it (ser ver)")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "odd\nname", input: [:]), "odd name")
    }

    func testStepLabelPicksFirstAvailableField() {
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: ["command": "npm test", "description": "Run tests"]), "Bash Run tests")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Edit", input: ["file_path": "/a/b/Button.tsx", "old_string": "x"]), "Edit Button.tsx")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Grep", input: ["pattern": "auth", "path": "/a"]), "Grep auth")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "WebSearch", input: ["query": "swift notch"]), "WebSearch swift notch")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "WebFetch", input: ["url": "https://a.dev", "prompt": "p"]), "WebFetch https://a.dev")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: ["command": "ls"]), "Bash ls")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "TaskList", input: [:]), "TaskList")
    }

    // The view truncates to the room it has, with an ellipsis; the reader only bounds what it keeps.
    func testStepLabelIsOneBoundedLine() {
        let long = String(repeating: "a", count: 150)
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: ["command": long]), "Bash " + String(repeating: "a", count: 120))
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: ["command": "line one\nline two"]), "Bash line one line two")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: ["command": "a\r\nb\rc\u{2028}d\u{2029}e"]), "Bash a b c d e")
    }

    // A session that waited for leave to run `git push origin preview` showed the model's
    // description of it, "Push the preview branch". Three testers had come to see what the
    // agent wants to run, and had to switch answering on to find out. A row that waits on the
    // person shows the step by what it runs; a row at work keeps the description.
    func testARowThatWaitsShowsItsStepByWhatItRuns() {
        let push: [String: Any] = ["command": "git push origin preview", "description": "Push the preview branch"]
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: push), "Bash Push the preview branch")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: push, asRun: true), "Bash git push origin preview")
        // A call that runs no command is called the same either way.
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Edit", input: ["file_path": "/a/b/login.ts"], asRun: true), "Edit login.ts")
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "ExitPlanMode", input: [:], asRun: true), TranscriptReader.planReady)
        // Cut short, it says so: a command the person is asked about must not end unseen.
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: ["command": String(repeating: "a", count: 120)], asRun: true), "Bash " + String(repeating: "a", count: 120))
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: ["command": String(repeating: "a", count: 121) + "; rm -rf ~"], asRun: true),
                       "Bash " + String(repeating: "a", count: 120) + "…")
        // And it is drawn as written, like every other text out of a transcript.
        XCTAssertEqual(TranscriptReader.stepLabel(tool: "Bash", input: ["command": "git\u{200B} push \u{202E}niam\nnow"], asRun: true), "Bash git push niam now")

        let line = #"{"type":"assistant","timestamp":"2026-10-12T02:00:05.000Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"git push origin preview","description":"Push the preview branch"}}]}}"#
        let info = read(line)
        XCTAssertEqual(info.lastStep, "Bash Push the preview branch")
        XCTAssertEqual(info.lastStepAsRun, "Bash git push origin preview")
        func row(_ status: AgentStatus, _ info: AgentInfo) -> AgentRow { AgentRow(id: "r", info: info, status: status, elapsed: 0) }
        XCTAssertEqual(row(.working, info).step, "Bash Push the preview branch")
        XCTAssertEqual(row(.quiet, info).step, "Bash Push the preview branch")
        XCTAssertEqual(row(.needsYou, info).step, "Bash git push origin preview")
        // A question it wrote down is what it shows while it asks, as before.
        var asking = info
        asking.asking = true
        asking.lastStep = "Which fix do you want?"
        XCTAssertEqual(row(.needsYou, asking).step, "Which fix do you want?")
        // A row put together without the second label falls back on the first.
        var bare = AgentInfo()
        bare.lastStep = "Read a.ts"
        XCTAssertEqual(row(.needsYou, bare).step, "Read a.ts")
    }

    // A title that began with a right-to-left override was drawn back to front, and a step with
    // zero-width characters in it read as words its letters did not spell: a tester wrote both
    // into a transcript. Everything the panel draws out of a transcript is drawn as written.
    func testTextOutOfATranscriptIsDrawnAsWritten() {
        // The override, an embedding and the isolates: gone, and the letters stay in their order.
        XCTAssertEqual(TranscriptReader.clipped("\u{202E}niam nigiro hsup tig"), "niam nigiro hsup tig")
        XCTAssertEqual(TranscriptReader.clipped("a\u{202B}b\u{2067}c\u{2069}d\u{200F}e\u{061C}f"), "abcdef")
        // Zero-width characters, a soft hyphen and a byte order mark draw as nothing.
        XCTAssertEqual(TranscriptReader.clipped("git\u{200B}push\u{200D}\u{00AD}\u{FEFF}"), "gitpush")
        // Escape, bell and backspace, with what stood around them left as it is.
        XCTAssertEqual(TranscriptReader.clipped("deploy\u{1B}[31m rm\u{07}\u{08}"), "deploy[31m rm")
        // Spaces of other widths are spaces, and a tab is one.
        XCTAssertEqual(TranscriptReader.clipped("a\u{00A0}b\u{3000}c\td"), "a b c d")
        // Private use, and a stack of combining marks cut to what one character may carry.
        XCTAssertEqual(TranscriptReader.clipped("a\u{E000}b"), "ab")
        XCTAssertEqual(TranscriptReader.clipped("e" + String(repeating: "\u{0301}", count: 30)).unicodeScalars.count, 4)
        // What people write stays: Thai with its marks, an emoji with its selector, Arabic and Hebrew letters.
        for text in ["แก้ที่หน้าชำระเงิน", "Fix it ❤️", "إصلاح الدفع", "תיקון"] {
            XCTAssertEqual(TranscriptReader.clipped(text), text)
        }
        // Counted after the cutting: what is not drawn takes none of the room.
        XCTAssertEqual(TranscriptReader.clipped(String(repeating: "\u{200B}", count: 500) + "abc"), "abc")
    }

    // The same for each place a transcript's text is drawn: the session's name, its folder and
    // branch, its model, a step, and a sub-agent's type and task.
    func testEveryDrawnFieldOfATranscriptGoesThroughIt() {
        let title = #"{"type":"ai-title","aiTitle":"\u202Ehsup\u200B tig"}"#
        let line = #"{"type":"assistant","timestamp":"2026-10-12T02:00:05.000Z","cwd":"/Users/me/web\u202E-app","gitBranch":"ma\u200Bin","message":{"model":"claude-opus\u202E-5-5","content":[{"type":"tool_use","id":"t1","name":"Ba\u200Bsh","input":{"command":"git\u200B push \u202Eniam"}}]}}"#
        var info = read(title, line)
        XCTAssertEqual(info.title, "hsup tig")
        XCTAssertEqual(info.branch, "main")
        XCTAssertEqual(info.model, "Opus 5.5")
        XCTAssertEqual(info.lastStep, "Bash git push niam")
        TranscriptReader.applyMeta(Data(#"{"agentType":"Exp\u202Elore","description":"Find\u200B auth \u202Efiles"}"#.utf8), to: &info)
        XCTAssertEqual(info.type, "Explore")
        XCTAssertEqual(info.task, "Find auth files")
        // The folder is still the one the transcript names, for the disk: only its drawing is cut.
        XCTAssertEqual(info.cwd, "/Users/me/web\u{202E}-app")
        var file = TrackedFile(session: "/r/p/s1", isMain: true)
        file.info = info
        let now = date("2026-10-12T02:00:10.000Z")
        file.modified = now
        XCTAssertEqual(AgentStore.cards(from: ["/r/p/s1.jsonl": file], now: now).first?.project, "web-app")
    }

    func testStatusRules() {
        let now = date("2026-10-12T03:00:00.000Z")
        var info = AgentInfo()
        func status(idle: TimeInterval) -> AgentStatus {
            TranscriptReader.status(of: info, lastActivity: now.addingTimeInterval(-idle), now: now)
        }
        XCTAssertEqual(status(idle: 0), .working)
        XCTAssertEqual(status(idle: 119), .working)
        XCTAssertEqual(status(idle: 120), .quiet)
        info.turnEnded = true
        XCTAssertEqual(status(idle: 9), .working)
        XCTAssertEqual(status(idle: 10), .done)
        XCTAssertEqual(status(idle: 500), .done)
    }

    // Claude Code's own record of a session says what silence cannot.
    func testASessionRecordOutranksWhatSilenceSuggests() {
        let now = date("2026-10-12T03:00:00.000Z")
        var info = AgentInfo()
        func status(_ session: SessionActivity?, idle: TimeInterval) -> AgentStatus {
            TranscriptReader.status(of: info, lastActivity: now.addingTimeInterval(-idle), now: now, session: session)
        }
        // Busy: thinking, composing a large file and running a long command all leave the transcript silent.
        XCTAssertEqual(status(.busy, idle: 120), .working)
        XCTAssertEqual(status(.busy, idle: 3600), .working)
        // Waiting: a permission prompt never reaches the transcript.
        XCTAssertEqual(status(.waiting, idle: 0), .needsYou)
        XCTAssertEqual(status(.waiting, idle: 3600), .needsYou)
        // Idle: nothing is running, whatever the last line was. The record can trail a new prompt by a moment.
        XCTAssertEqual(status(.idle, idle: 9), .working)
        XCTAssertEqual(status(.idle, idle: 10), .done)
        // No record: the transcript rules, with nothing guessed.
        XCTAssertEqual(status(nil, idle: 119), .working)
        XCTAssertEqual(status(nil, idle: 120), .quiet)

        info.turnEnded = true
        // Busy with the turn over means only sub-agents are running.
        XCTAssertEqual(status(.busy, idle: 10), .done)
        // Waiting with the turn over: a background sub-agent's prompt is open.
        XCTAssertEqual(status(.waiting, idle: 10), .needsYou)

        info.turnEnded = false
        info.asking = true
        // An open question is written in the transcript, not read out of silence: a busy record does not hide it.
        XCTAssertEqual(status(.busy, idle: 5), .needsYou)
        XCTAssertEqual(status(.busy, idle: 3600), .needsYou)
        XCTAssertEqual(status(.idle, idle: 10), .done)
        XCTAssertEqual(status(nil, idle: 5), .needsYou)
    }

    func testElapsedStopsAtLastWriteOnceDone() {
        let now = date("2026-10-12T03:00:00.000Z")
        var info = AgentInfo()
        XCTAssertEqual(TranscriptReader.elapsed(of: info, lastActivity: now, now: now), 0)
        info.startedAt = now.addingTimeInterval(-300)
        XCTAssertEqual(TranscriptReader.elapsed(of: info, lastActivity: now.addingTimeInterval(-5), now: now), 300)
        info.turnEnded = true
        XCTAssertEqual(TranscriptReader.elapsed(of: info, lastActivity: now.addingTimeInterval(-60), now: now), 240)
        info.turnEnded = false
        XCTAssertEqual(TranscriptReader.elapsed(of: info, lastActivity: now.addingTimeInterval(-60), now: now, session: .idle), 240)
        XCTAssertEqual(TranscriptReader.elapsed(of: info, lastActivity: now.addingTimeInterval(-60), now: now, session: .busy), 300)
    }

    func testSkipsBadLinesAndOtherLineTypes() {
        let info = read(
            "{not json",
            #"{"type":"ai-title","title":"x"}"#,
            toolUse,
            answer,
            #"{"type":"attachment","attachment":{}}"#
        )
        XCTAssertEqual(info.steps, 1)
        XCTAssertTrue(info.turnEnded)
    }

    func testToleratesMissingAndOddlyShapedFields() {
        let info = read(
            #"{"type":"assistant"}"#,
            #"{"type":"assistant","message":{"content":"plain string"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use"}],"usage":null}}"#
        )
        XCTAssertEqual(info.steps, 1)
        XCTAssertEqual(info.model, "")
    }

    func testSyntheticLineKeepsRealModel() {
        let synthetic = #"{"type":"assistant","timestamp":"2026-10-12T02:00:10.000Z","message":{"id":"msg_3","model":"<synthetic>","content":[{"type":"text","text":"API Error"}],"usage":{"input_tokens":0,"output_tokens":0}}}"#
        let info = read(prompt, toolUse, synthetic)
        XCTAssertEqual(info.model, "Haiku 5.5")
    }

    func testCompleteLinesLeavesPartialLineUnread() {
        let (lines, consumed) = TranscriptReader.completeLines(in: Data("one\ntwo\npart".utf8))
        XCTAssertEqual(lines, [Data("one".utf8), Data("two".utf8)])
        XCTAssertEqual(consumed, 8)
        XCTAssertEqual(TranscriptReader.completeLines(in: Data("part".utf8)).consumed, 0)
        XCTAssertEqual(TranscriptReader.completeLines(in: Data()).consumed, 0)
        // A slice that does not start at zero, with blank lines, which are skipped.
        let slice = Data("xx\n\none\n\ntwo\n".utf8).dropFirst(3)
        let cut = TranscriptReader.completeLines(in: slice)
        XCTAssertEqual(cut.lines, [Data("one".utf8), Data("two".utf8)])
        XCTAssertEqual(cut.consumed, 10)
    }

    func testReadLinesAcrossPiecesLeavesHalfWrittenLine() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("first line\n\nsecond\nhalf".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var lines: [String] = []
        let consumed = TranscriptReader.readLines(from: handle, piece: 3) { lines.append(String(decoding: $0, as: UTF8.self)) }
        XCTAssertEqual(lines, ["first line", "second"])
        XCTAssertEqual(consumed, 19)
    }

    func testMetaSetsTypeAndTask() {
        var info = AgentInfo()
        TranscriptReader.applyMeta(Data("oops".utf8), to: &info)
        XCTAssertEqual(info.type, "agent")
        XCTAssertEqual(info.task, "")
        TranscriptReader.applyMeta(Data(#"{"agentType":"Explore","description":"Find auth files","toolUseId":"t"}"#.utf8), to: &info)
        XCTAssertEqual(info.type, "Explore")
        XCTAssertEqual(info.task, "Find auth files")
    }

    // What the lead asked is the sub-agent's first prompt, whole, line breaks and all.
    func testAnAgentKeepsWhatItWasAskedAndWhatItHandedBack() {
        let ask = #"{"type":"user","timestamp":"2026-10-12T02:00:00.000Z","message":{"role":"user","content":"Find every PaymentIntent.\nDon't change code."}}"#
        let back = #"{"type":"assistant","timestamp":"2026-10-12T02:03:00.000Z","message":{"id":"m9","stop_reason":"end_turn","content":[{"type":"text","text":"14 call sites in 6 files.\n3 skip the retry wrapper."}]}}"#
        let info = read(ask, toolUse, toolResult, back)
        XCTAssertEqual(info.asked, "Find every PaymentIntent.\nDon't change code.")
        XCTAssertEqual(info.handedBack, "14 call sites in 6 files.\n3 skip the retry wrapper.")
        XCTAssertEqual(info.handedBackAt, date("2026-10-12T02:03:00.000Z"))
        // A later prompt (the lead continuing it) does not replace what was first asked.
        XCTAssertEqual(read(ask, back, prompt).asked, "Find every PaymentIntent.\nDon't change code.")
    }

    func testNothingIsHandedBackMidTurnOrOnAnInterrupt() {
        XCTAssertNil(read(prompt, toolUse).handedBackAt)
        let interrupted = #"{"type":"user","interruptedMessageId":"msg_1","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        XCTAssertNil(read(prompt, toolUse, interrupted).handedBackAt)
    }

    func testAResultHandedInIsAHandBackWithoutWords() {
        let handIn = #"{"type":"assistant","timestamp":"2026-10-13T08:00:00.000Z","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","id":"t9","name":"StructuredOutput","input":{}}]}}"#
        let info = read(prompt, handIn)
        XCTAssertEqual(info.handedBack, "")
        XCTAssertEqual(info.handedBackAt, date("2026-10-13T08:00:00.000Z"))
    }

    // An API error ends the turn and hands nothing back: no box, a plain done line.
    func testAnApiErrorIsNoHandBack() {
        let flagged = #"{"type":"assistant","timestamp":"2026-10-12T02:00:10.000Z","isApiErrorMessage":true,"error":"server_error","message":{"id":"e1","model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","content":[{"type":"text","text":"API Error: 529 Overloaded"}]}}"#
        let synthetic = #"{"type":"assistant","timestamp":"2026-10-12T02:00:10.000Z","message":{"id":"e2","model":"<synthetic>","stop_reason":"stop_sequence","content":[{"type":"text","text":"API Error: 529 Overloaded"}]}}"#
        let flagOnly = #"{"type":"assistant","timestamp":"2026-10-12T02:00:10.000Z","isApiErrorMessage":true,"message":{"id":"e3","stop_reason":"stop_sequence","content":[{"type":"text","text":"API Error: 529 Overloaded"}]}}"#
        for error in [flagged, synthetic, flagOnly] {
            let info = read(prompt, toolUse, toolResult, error)
            XCTAssertTrue(info.turnEnded)
            XCTAssertNil(info.handedBackAt)
            XCTAssertEqual(info.handedBack, "")
        }
    }

    // The lead continued it: what it handed back before is not what this turn ends with.
    func testANewPromptTakesTheOldHandBackAway() {
        let again = #"{"type":"user","timestamp":"2026-10-12T03:00:00.000Z","message":{"role":"user","content":"now fix it"}}"#
        let stopped = #"{"type":"user","timestamp":"2026-10-12T03:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        let error = #"{"type":"assistant","timestamp":"2026-10-12T03:01:00.000Z","isApiErrorMessage":true,"message":{"id":"e1","model":"<synthetic>","stop_reason":"stop_sequence","content":[{"type":"text","text":"API Error: 529 Overloaded"}]}}"#
        for end in [stopped, error] {
            let info = read(prompt, toolUse, toolResult, answer, again, toolUse, end)
            XCTAssertNil(info.handedBackAt)
            XCTAssertEqual(info.handedBack, "")
            XCTAssertEqual(info.asked, "find auth files")
        }
        // Handed back again: the latest stands.
        let fixed = #"{"type":"assistant","timestamp":"2026-10-12T03:05:00.000Z","message":{"id":"m5","stop_reason":"end_turn","content":[{"type":"text","text":"Fixed."}]}}"#
        let info = read(prompt, answer, again, toolUse, toolResult, fixed)
        XCTAssertEqual(info.handedBack, "Fixed.")
        XCTAssertEqual(info.handedBackAt, date("2026-10-12T03:05:00.000Z"))
    }

    func testLongTextIsCutWithAMark() {
        let cut = HandBack.kept(String(repeating: "a", count: 50_000), limit: HandBack.resultLimit)
        XCTAssertEqual(cut.count, 8193)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertEqual(HandBack.kept("  one\ntwo \n", limit: 10), "one\ntwo")
    }

    private func meta(_ kind: String, _ content: String, at time: String) -> String {
        #"{"type":"user","isMeta":true,"origin":{"kind":"\#(kind)"},"timestamp":"\#(time)","message":{"role":"user","content":"\#(content)"}}"#
    }
    private func endTurn(_ text: String, at time: String) -> String {
        #"{"type":"assistant","timestamp":"\#(time)","message":{"id":"m","stop_reason":"end_turn","content":[{"type":"text","text":"\#(text)"}]}}"#
    }
    private func promptLine(_ text: String) -> String {
        #"{"type":"user","timestamp":"2026-10-12T02:00:00.000Z","message":{"role":"user","content":"\#(text)"}}"#
    }

    // The Library stores each hand-back as a chapter, so none may be cut or lost when the lead continues the agent.
    func testEachHandBackIsRecordedWhole() {
        let big = String(repeating: "x", count: 10_000)
        let msg = "The coordinator sent a message while you were working:\\nNow check tests."
        let info = read(promptLine("Find calls"), endTurn(big, at: "2026-10-12T02:03:00.000Z"),
                        meta("coordinator", msg, at: "2026-10-12T02:04:00.000Z"), endTurn("done", at: "2026-10-12T02:05:00.000Z"))
        XCTAssertEqual(info.records.count, 2)
        XCTAssertEqual(info.records[0].asked, "Find calls")
        XCTAssertEqual(info.records[0].text.count, 10_000)
        XCTAssertEqual(info.records[1].asked, "The coordinator sent a message while you were working:\nNow check tests.")
        XCTAssertEqual(info.records[1].at, date("2026-10-12T02:05:00.000Z"))
    }

    // A wake-up after background work is a second ask too.
    func testATaskNotificationWakeUpBecomesTheAsk() {
        let note = "[SYSTEM NOTIFICATION - NOT USER INPUT]\\nBuild finished."
        let info = read(promptLine("Build it"), endTurn("a", at: "2026-10-12T02:03:00.000Z"),
                        meta("task-notification", note, at: "2026-10-12T02:04:00.000Z"), endTurn("b", at: "2026-10-12T02:05:00.000Z"))
        XCTAssertEqual(info.records.map(\.asked), ["Build it", "[SYSTEM NOTIFICATION - NOT USER INPUT]\nBuild finished."])
    }

    // A result handed in with no words has no chapter to store.
    func testAResultHandedInWithNoTextIsNotRecorded() {
        let call = #"{"type":"assistant","timestamp":"2026-10-13T08:00:00.000Z","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","id":"t9","name":"StructuredOutput","input":{"result":"ok"}}]}}"#
        let info = read(promptLine("Go"), call)
        XCTAssertTrue(info.records.isEmpty)
        XCTAssertNotNil(info.handedBackAt)
    }

    // The panel cuts the task to one short line; the Library keeps the description whole.
    func testFullTaskKeepsTheWholeDescription() {
        var info = AgentInfo()
        let long = String(repeating: "a", count: 300)
        TranscriptReader.applyMeta(Data(#"{"agentType":"Explore","description":"\#(long)"}"#.utf8), to: &info)
        XCTAssertEqual(info.fullTask.count, 300)
        XCTAssertLessThanOrEqual(info.task.count, 120)
    }
}
