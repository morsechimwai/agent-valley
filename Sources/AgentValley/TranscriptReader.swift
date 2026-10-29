import Foundation

enum AgentStatus: Equatable {
    /// `needsYou`: a question, a plan or a permission prompt is on screen waiting for the person.
    case working, quiet, needsYou, done
}

/// One task of a session's task list, as Claude Code draws it under its spinner.
struct TaskItem: Equatable {
    let id: String
    /// The model's own words: untrusted, and drawn verbatim.
    var subject: String
    var status: String
    var done: Bool { status == "completed" }
}

/// A tool call the transcript has no result for yet.
struct OpenTool: Equatable {
    let id: String
    let tool: String
    let input: NSDictionary

    /// Worked out only when a request has to be matched: hashing every tool call of every
    /// transcript as it is read would slow the launch for something that is rarely needed.
    var digest: String { AnswerProtocol.digest(tool: tool, input: input) }
}

/// A tool call that got its result, and when. Kept briefly: a request can arrive after the call
/// was written and be answered in the terminal before the app has read either line.
struct ClosedTool: Equatable {
    let tool: OpenTool
    let at: Date
}

struct AgentInfo: Equatable {
    var type = "agent"
    var task = ""
    /// The session's title as Claude Code last wrote it, or empty.
    var title = ""
    var model = ""
    var cwd = ""
    /// The directory of its latest line: where the agent is now, and what `branch` is the branch of.
    var folder = ""
    var branch = ""
    /// How the session was started: "cli" for a person at a terminal, "sdk-…" for a headless script.
    var entrypoint = ""
    var startedAt: Date?
    /// When the conversation last moved: the newest user/assistant line. Claude Code also appends
    /// housekeeping lines to idle sessions, so the file's modification time says nothing.
    var lastActivity: Date?
    /// When the person last sent a prompt: where the turn under way began. A session can be days old.
    var turnStartedAt: Date?
    var steps = 0
    var lastStep = ""
    /// The first line of what it last thought or wrote in the turn under way: a thought Claude Code
    /// kept, or words of its own. Where it is headed while no call is open. Empty as a turn begins.
    var thought = ""
    /// What a row says while no call is open: where it is headed, else the step it just finished.
    var betweenCalls: String {
        if !thought.isEmpty { return thought }
        return lastStep.isEmpty ? "Thinking" : "Thinking · after " + lastStep
    }
    /// The same step by what it runs, where that is not what it is called: a Bash call's
    /// command, in place of the model's description of it. For a row that waits on the person.
    var lastStepAsRun = ""
    /// The latest user/assistant line is a finished assistant answer: text, no tool call, and a stop reason.
    var turnEnded = false
    /// Its last message handed in its result with StructuredOutput: how a workflow's sub-agent
    /// ends. It writes no closing answer after that, and nothing else either.
    var returned = false
    /// The agent's first prompt: what its lead asked of it. Line breaks kept.
    var asked = ""
    /// The text of the latest line that ended a turn: what it handed back. Line breaks kept.
    var handedBack = ""
    /// When it last handed back, by a closing answer or by a result handed in.
    var handedBackAt: Date?
    /// The agent's work is over, by a closing answer or by a result handed in. The model writes
    /// the names of its calls: a result handed in while another call still waits, for a
    /// permission or for an answer, is not the end.
    var finished: Bool { turnEnded || (returned && openTools.allSatisfy { $0.tool == TranscriptReader.returnTool }) }
    /// The latest line is a call that puts a question or a plan in front of the person, not yet answered.
    var asking = false
    /// Tool calls still waiting for their result, newest last. One of them is what a permission
    /// request is about; its result arriving means the request was answered.
    var openTools: [OpenTool] = []
    /// The calls that most recently got their result, newest last.
    var closedTools: [ClosedTool] = []
    /// Background shells and monitors started in this file and not seen ending in it, newest last.
    var jobs: [BackgroundJob] = []
    /// Task ids seen ending in this file, newest last: a start written again must not bring one back.
    var endedJobs: [String] = []
    /// The session's sub-agents that Claude Code told this file wait on work of their own, by agent
    /// id, with when it said so. Claude Code wakes such an agent when that work ends.
    var waitingAgents: [String: Date] = [:]
    /// The session's task list in the order the tasks were made, as TaskCreate, TaskUpdate and
    /// TodoWrite wrote it.
    var tasks: [TaskItem] = []
    /// Changes what is given of a task, or adds it at the end while the list has room.
    mutating func setTask(_ id: String, status: String? = nil, subject: String? = nil) {
        if let i = tasks.firstIndex(where: { $0.id == id }) {
            if let status { tasks[i].status = status }
            if let subject { tasks[i].subject = subject }
        } else if tasks.count < TranscriptReader.maxTasks {
            tasks.append(TaskItem(id: id, subject: subject ?? "", status: status ?? "pending"))
        }
    }
}

/// Turns Claude Code transcript lines into `AgentInfo`. Never touches the disk or the clock.
enum TranscriptReader {
    static let doneAfter: TimeInterval = 10
    static let quietAfter: TimeInterval = 120
    /// Enough for any row; the view truncates to the room it has, with an ellipsis.
    static let stepDetailLimit = 120
    /// Tool calls that wait for the person by design.
    static let askingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
    /// A file keeps at most this many open tool calls; a call can lose its result to an interrupt.
    static let openToolLimit = 16
    static let closedToolLimit = 8
    /// A session's task list holds at most this many ids.
    static let maxTasks = 200

    /// Over a hundred times quicker than `ISO8601DateFormatter`, which took more of a first read
    /// than parsing the JSON did.
    private static let timestamps = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// When a transcript line says it was written, or nil when that is not a time.
    static func date(from text: String) -> Date? {
        try? timestamps.parse(text)
    }

    /// The newline-terminated lines at the front of `data`, and how many bytes they cover. Each
    /// line is a slice of `data`, not a copy.
    static func completeLines(in data: Data) -> (lines: [Data], consumed: Int) {
        var lines: [Data] = []
        var consumed = 0
        // By memchr: Data's own split went a byte at a time, and took longer than the JSON parse.
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else { return }
            while consumed < bytes.count, let newline = memchr(base + consumed, 0x0A, bytes.count - consumed) {
                let end = base.distance(to: newline)
                if end > consumed { lines.append(data[data.startIndex + consumed ..< data.startIndex + end]) }
                consumed = end + 1
            }
        }
        return (lines, consumed)
    }

    /// Reads `handle` from where it stands to its end, `piece` bytes at a time, and hands each
    /// whole line to `body`: a transcript of a hundred megabytes is never in memory at once.
    /// How many bytes the whole lines cover; a line caught half-written is left for next time.
    static func readLines(from handle: FileHandle, piece: Int = 1 << 20, _ body: (Data) throws -> Void) rethrows -> UInt64 {
        var consumed: UInt64 = 0
        // What follows a piece's last newline is carried into the next piece.
        var rest = Data()
        var more = true
        while more {
            more = try autoreleasepool {
                guard let next = try? handle.read(upToCount: piece), !next.isEmpty else { return false }
                rest.append(next)
                let (lines, count) = completeLines(in: rest)
                for line in lines { try body(line) }
                consumed += UInt64(count)
                rest.removeSubrange(rest.startIndex..<rest.startIndex + count)
                return true
            }
        }
        return consumed
    }

    /// Folds one transcript line into `info`. Read: user and assistant lines, the session's title,
    /// and the job ends in a notice queued for the model, as a `queue-operation` enqueue or a
    /// `queued_command` attachment. Any other line, and one that is not valid JSON, is skipped.
    static func apply(line: Data, to info: inout AgentInfo) {
        guard let object = SafeJSON.object(line),
              let type = object["type"] as? String else { return }
        // Claude Code names the session itself and rewrites the name as the work changes; the latest stands.
        if type == "ai-title", let title = object["aiTitle"] as? String, !title.isEmpty {
            info.title = clipped(title)
        }
        let at = (object["timestamp"] as? String).flatMap(Self.date(from:))
        if type == "queue-operation", object["operation"] as? String == "enqueue", let text = object["content"] as? String {
            for id in BackgroundJobs.ended(in: text) { info.endJob(id) }
            info.readWaits(in: text, at: at)
        }
        // A notice can be queued as an attachment alone. That kind only: a snapshot of the system
        // prompt is an attachment too, and holds the words of a notice.
        if type == "attachment", let attachment = object["attachment"] as? [String: Any],
           attachment["type"] as? String == "queued_command", let text = attachment["prompt"] as? String {
            for id in BackgroundJobs.ended(in: text) { info.endJob(id) }
            info.readWaits(in: text, at: at)
        }
        guard type == "user" || type == "assistant" else { return }
        let date = (object["timestamp"] as? String).flatMap(Self.date(from:))
        if let date {
            if info.startedAt == nil { info.startedAt = date }
            info.lastActivity = date
        }
        // The first directory names the project: an agent that changes directory later must not rename its card.
        if info.cwd.isEmpty, let cwd = object["cwd"] as? String { info.cwd = cwd }
        // Where it is now is kept beside it: the branch is that directory's, not the first one's.
        if let cwd = object["cwd"] as? String, !cwd.isEmpty { info.folder = cwd }
        // Outside a repository Claude Code writes "HEAD", which names no branch.
        if let branch = object["gitBranch"] as? String, !branch.isEmpty { info.branch = branch == "HEAD" ? "" : clipped(branch) }
        if let entrypoint = object["entrypoint"] as? String, !entrypoint.isEmpty { info.entrypoint = entrypoint }
        guard type == "assistant", let message = object["message"] as? [String: Any] else {
            if type == "user" {
                info.readJobs(in: object, at: date)
                // TaskCreate's id is known only from the result that follows it.
                if let task = (object["toolUseResult"] as? [String: Any])?["task"] as? [String: Any], let id = task["id"] as? String,
                   !info.tasks.contains(where: { $0.id == id }) {
                    info.setTask(id, status: "pending", subject: clipped(task["subject"] as? String ?? ""))
                }
            }
            // A user line normally means work is about to start. The notice Claude Code writes when
            // the user presses Esc means it just stopped.
            info.turnEnded = type == "user" && isInterruptNotice(object["message"] as? [String: Any])
            // An answer, a new prompt or an interrupt: whatever was asked is no longer pending.
            info.asking = false
            // The person's own prompt begins a turn. A tool's result, a note Claude Code adds
            // and the interrupt notice do not.
            if type == "user", !info.turnEnded, isPrompt(object) {
                // Work starts again, whatever was handed in before: an old hand-back is not this turn's.
                info.returned = false
                info.handedBack = ""
                info.handedBackAt = nil
                info.thought = ""
                if let date { info.turnStartedAt = date }
                if info.asked.isEmpty { info.asked = HandBack.kept(text(of: object["message"] as? [String: Any]), limit: HandBack.askedLimit) }
            }
            if info.turnEnded {
                info.openTools = []
            } else if type == "user", let blocks = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] {
                let answered = Set(blocks.filter { $0["type"] as? String == "tool_result" }.compactMap { $0["tool_use_id"] as? String })
                if !answered.isEmpty {
                    let at = info.lastActivity ?? .distantPast
                    info.closedTools += info.openTools.filter { answered.contains($0.id) }.map { ClosedTool(tool: $0, at: at) }
                    info.closedTools.removeFirst(max(0, info.closedTools.count - closedToolLimit))
                    info.openTools.removeAll { answered.contains($0.id) }
                }
            }
            return
        }
        // Claude Code writes "<synthetic>" for messages it makes up itself, such as API errors.
        if let model = message["model"] as? String, !model.isEmpty, model != "<synthetic>" {
            // "claude-opus-4-5-20251101" reads as "Opus 4.5", as on the History page.
            info.model = Format.model(clipped(model))
        }
        var hasText = false
        var hasTool = false
        var asking = false
        var returned = false
        var words: [String] = []
        for block in message["content"] as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "tool_use":
                hasTool = true
                let tool = block["name"] as? String ?? ""
                asking = askingTools.contains(tool)
                if tool == returnTool { returned = true }
                if let id = block["id"] as? String, !id.isEmpty {
                    info.openTools.append(OpenTool(id: id, tool: tool, input: block["input"] as? NSDictionary ?? [:]))
                    info.openTools.removeFirst(max(0, info.openTools.count - openToolLimit))
                }
                let input = block["input"] as? [String: Any] ?? [:]
                if tool == "TaskUpdate", let id = input["taskId"] as? String {
                    let status = input["status"] as? String
                    if status == "deleted" {
                        info.tasks.removeAll { $0.id == id }
                    } else if status != nil || input["subject"] is String {
                        info.setTask(id, status: status, subject: (input["subject"] as? String).map { clipped($0) })
                    }
                } else if tool == "TodoWrite", let todos = input["todos"] as? [[String: Any]] {
                    info.tasks = todos.prefix(maxTasks).enumerated().map { n, todo in
                        TaskItem(id: "todo-\(n)", subject: clipped(todo["content"] as? String ?? ""), status: todo["status"] as? String ?? "pending")
                    }
                }
                info.steps += 1
                info.lastStep = stepLabel(tool: tool, input: block["input"] as? [String: Any] ?? [:])
                info.lastStepAsRun = stepLabel(tool: tool, input: block["input"] as? [String: Any] ?? [:], asRun: true)
            case "text":
                hasText = true
                if let text = block["text"] as? String { words.append(text) }
                if let line = firstLine(block["text"]) { info.thought = line }
            case "thinking":
                // Claude Code keeps the words of only some thoughts; the rest come empty.
                if let line = firstLine(block["thinking"]) { info.thought = line }
            default:
                break
            }
        }
        // A text block is written before the rest of its message exists. Only a stop reason says the
        // message is over, and "tool_use" means a tool call follows.
        let stop = message["stop_reason"] as? String
        info.turnEnded = hasText && !hasTool && stop != nil && stop != "tool_use"
        info.returned = returned
        info.asking = asking
        // An API error ends the turn too, and hands nothing back.
        guard message["model"] as? String != "<synthetic>", object["isApiErrorMessage"] as? Bool != true else { return }
        if info.turnEnded {
            info.handedBack = HandBack.kept(words.joined(separator: "\n"), limit: HandBack.resultLimit)
            info.handedBackAt = date
        } else if returned {
            info.handedBackAt = date
        }
    }

    /// A message's text: its content when that is a string, else its text blocks joined by line breaks.
    private static func text(of message: [String: Any]?) -> String {
        let content = message?["content"]
        if let string = content as? String { return string }
        return (content as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private static func isPrompt(_ line: [String: Any]) -> Bool {
        guard line["isMeta"] as? Bool != true, line["isCompactSummary"] as? Bool != true else { return false }
        let content = (line["message"] as? [String: Any])?["content"]
        if content is String { return true }
        guard let blocks = content as? [[String: Any]], !blocks.isEmpty else { return false }
        return !blocks.contains { $0["type"] as? String == "tool_result" }
    }

    private static func isInterruptNotice(_ message: [String: Any]?) -> Bool {
        let content = message?["content"]
        let text = content as? String ?? (content as? [[String: Any]])?.first?["text"] as? String ?? ""
        return text.hasPrefix("[Request interrupted by user")
    }

    /// Returns false when `data` is not a complete JSON object yet.
    @discardableResult
    static func applyMeta(_ data: Data, to info: inout AgentInfo) -> Bool {
        guard let object = SafeJSON.object(data) else { return false }
        if let type = object["agentType"] as? String, !type.isEmpty { info.type = clipped(type) }
        if let task = object["description"] as? String { info.task = clipped(task) }
        return true
    }

    /// The call a workflow's sub-agent hands its result in with.
    static let returnTool = "StructuredOutput"

    /// What a plan put in front of the person is called, as a step and as a request.
    static let planReady = "Plan ready for review"

    /// Text out of a transcript as the panel draws it: one line of at most `stepDetailLimit`
    /// characters, with nothing in it that draws as nothing or steers the direction of what
    /// stands beside it. A title that began with a right-to-left override was drawn back to
    /// front, and read as something its letters did not say. What a request's own text is held
    /// to before it can be allowed, except that this is cut out and the rest is shown: a row
    /// says what a session is doing and allows nothing. Letters of right-to-left scripts stay,
    /// as a title in Arabic or Hebrew is one; only the marks that steer direction go.
    /// A text's first line that has words, as a row shows it: without markdown's bold and code
    /// marks or the heading, list or quote mark it begins with, cut to a step's length. nil when there is none.
    static func firstLine(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        return text.split(whereSeparator: \.isNewline).lazy
            .map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "") }
            .map { clipped(String($0.drop { "#-*> \t".contains($0) })).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    static func clipped(_ text: String, limit: Int = stepDetailLimit) -> String {
        var scalars = String.UnicodeScalarView()
        var kept = 0
        var afterReturn = false
        for scalar in text.unicodeScalars {
            // Enough for the characters that are kept, however many marks each carries: a
            // command can be a whole script, and only its start is drawn.
            if kept >= limit * 8 { break }
            switch scalar.properties.generalCategory {
            // A line break or a tab, which would cut the row or widen it: a space, and one for
            // a return and the line feed after it. Any other control draws as nothing.
            case .control:
                if scalar == "\r" || scalar == "\t" || (scalar == "\n" && !afterReturn) {
                    scalars.append(" ")
                    kept += 1
                }
            case .lineSeparator, .paragraphSeparator, .spaceSeparator:
                scalars.append(" ")
                kept += 1
            // Marks that steer direction, zero-width characters, and what has no drawing at all.
            case .format, .privateUse, .surrogate, .unassigned:
                break
            default:
                scalars.append(scalar)
                kept += 1
            }
            afterReturn = scalar == "\r"
        }
        // A stack of combining marks paints over the lines above and below: four to a character.
        let characters = String(scalars).prefix(limit).map { character in
            character.unicodeScalars.count <= 4 ? character : Character(String(String.UnicodeScalarView(character.unicodeScalars.prefix(4))))
        }
        return String(characters)
    }

    /// `asRun`: by what the call runs and not by what the model calls it. A Bash call carries
    /// both a command and a description of it, and a row at work shows the description, which
    /// reads better. A row that waits on the person shows the command: that is what is being
    /// asked, and the description is only the model's word for it. Cut short, it says so: on
    /// the lines a waiting row has, the view would not.
    static func stepLabel(tool: String, input: [String: Any], asRun: Bool = false) -> String {
        // A call that waits on the person: what it asks is the step, not the name of the tool.
        if tool == "ExitPlanMode" { return planReady }
        if tool == "AskUserQuestion", let questions = input["questions"] as? [[String: Any]] {
            // Several: how many, in the app's own words alone, as the request says it.
            if questions.count > 1 { return "\(questions.count) questions" }
            // The model wrote the question: text that would not draw as written, or that says
            // nothing, is not put on the row.
            if let question = questions.first?["question"] as? String,
               !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Ask.isShowable(question, multiline: true) {
                return clipped(question)
            }
        }
        var detail = ""
        for key in (asRun ? ["command"] : []) + ["description", "file_path", "pattern", "query", "url", "command"] {
            guard let value = input[key] as? String, !value.isEmpty else { continue }
            detail = key == "file_path" ? (value as NSString).lastPathComponent : value
            break
        }
        if asRun {
            let whole = clipped(detail, limit: stepDetailLimit + 1)
            detail = whole.count > stepDetailLimit ? String(whole.prefix(stepDetailLimit)) + "…" : whole
        } else {
            detail = clipped(detail)
        }
        // A tool of an MCP server is "mcp__<server>__<tool>". What it does comes first and where
        // it comes from last, where the row cuts: the server's name used to take the whole line.
        // One line whatever the name holds: a line break in it would cut the row there.
        var name = clipped(tool)
        var origin = ""
        let parts = tool.components(separatedBy: "__")
        if parts.count >= 3, parts[0] == "mcp", let last = parts.last, !last.isEmpty {
            let server = parts[1..<(parts.count - 1)].joined(separator: "__")
            if !server.isEmpty {
                name = clipped(last)
                origin = " (\(clipped(server)))"
            }
        }
        return (detail.isEmpty ? name : "\(name) \(detail)") + origin
    }

    /// `session` is what Claude Code's own record says about this row, when there is a live one. It
    /// outranks anything read out of silence: the transcript stays empty while the model thinks, while
    /// a command runs and while a permission prompt is open.
    // ponytail: without a record, "done" waits for the file to go quiet after a finished answer, because
    // the transcript cannot say whether another turn follows, and two silent minutes read as quiet.
    /// `waits`: a sub-agent Claude Code says ended its turn to wait on work of its own. Until it
    /// answers again it is never done: at work while it waits, and by the usual rules once woken.
    static func status(of info: AgentInfo, lastActivity: Date, now: Date, session: SessionActivity? = nil, waits: Bool = false) -> AgentStatus {
        // Ahead of the done check: a prompt for a background sub-agent can open after the main turn ended.
        if session == .waiting { return .needsYou }
        if waits && info.finished { return .working }
        let idle = now.timeIntervalSince(lastActivity)
        // The record can trail a new prompt by a moment, so an idle one waits like a finished answer does.
        if !waits && (info.finished || session == .idle) && idle >= doneAfter { return .done }
        // No waiting period: the question is on screen from the moment the call is written. Ahead of
        // the busy check: an unanswered call is in the transcript in so many words, and what the
        // record says while a question is open is known from one version of Claude Code only.
        if info.asking { return .needsYou }
        if session == .busy { return .working }
        if idle >= quietAfter { return .quiet }
        return .working
    }

    static func elapsed(of info: AgentInfo, lastActivity: Date, now: Date, session: SessionActivity? = nil, waits: Bool = false) -> TimeInterval {
        guard let start = info.turnStartedAt ?? info.startedAt else { return 0 }
        let end = status(of: info, lastActivity: lastActivity, now: now, session: session, waits: waits) == .done ? lastActivity : now
        return max(0, end.timeIntervalSince(start))
    }
}
