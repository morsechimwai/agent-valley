import Foundation

/// A `Bash` or `Monitor` the model left running after its turn: it keeps going while the card looks idle.
struct BackgroundJob: Equatable, Identifiable {
    enum Kind: Equatable { case shell, monitor }
    let id: String
    let kind: Kind
    let name: String
    let startedAt: Date
    /// When a Monitor's own timeout stops it; nil for a shell and for a persistent monitor.
    let endsBy: Date?
    /// A shell whose words read like a server left open on a port: `BackgroundJobs.serves`.
    var serves = false

    func isLong(now: Date) -> Bool { now.timeIntervalSince(startedAt) >= BackgroundJobs.longAfter }
}

/// Reads job starts and ends out of Claude Code's transcript lines. The formats are undocumented,
/// so only positive evidence counts: a line that does not match means no job.
enum BackgroundJobs {
    /// A job this old is taken for something left running on purpose, not work being waited on.
    static let longAfter: TimeInterval = 1800
    /// Ended ids kept so a start written again after its end does not bring the job back. Also
    /// how a job started in another file ends: a sub-agent's shell can end only in the main
    /// file, which in a long session has ended a hundred others since.
    // ponytail: 4096 ids of about 9 bytes, checked by a linear `contains`; `forget` drops a file a
    // day after its session goes silent. A Set beside the array if a session ever ends that many.
    static let endedLimit = 4096

    /// The ids of the jobs that `<task-notification>`s in `text` say are over. A notification
    /// without a status is a Monitor event and ends nothing.
    static func ended(in text: String) -> [String] {
        text.components(separatedBy: "<task-notification>").compactMap { piece in
            guard piece.contains("<status>"),
                  let open = piece.range(of: "<task-id>"),
                  let close = piece.range(of: "</task-id>", range: open.upperBound..<piece.endIndex) else { return nil }
            let id = String(piece[open.upperBound..<close.lowerBound])
            return id.isEmpty ? nil : id
        }
    }

    /// How Claude Code's notice to a lead ends the summary of a sub-agent that stopped with work of
    /// its own still running: it wakes the agent when that work ends, and what it said may be interim.
    static let waitsSummary = " is waiting on its own background work"

    /// The agents that `<task-notification>`s in `text` report on, each with whether it now waits on work of its own.
    static func agentWaits(in text: String) -> [(id: String, waits: Bool)] {
        func tag(_ name: String, in piece: String) -> String? {
            guard let open = piece.range(of: "<\(name)>"),
                  let close = piece.range(of: "</\(name)>", range: open.upperBound..<piece.endIndex) else { return nil }
            return String(piece[open.upperBound..<close.lowerBound])
        }
        return text.components(separatedBy: "<task-notification>").compactMap { piece in
            guard piece.contains("<status>"), let id = tag("task-id", in: piece), !id.isEmpty,
                  let summary = tag("summary", in: piece) else { return nil }
            return (id, summary.hasSuffix(waitsSummary))
        }
    }

    /// The job a tool result starts, if it is one. `call` is the call it answers, for the name.
    static func started(by result: [String: Any], call: OpenTool?, at: Date) -> BackgroundJob? {
        func name() -> String {
            for key in ["description", "command"] {
                if let text = call?.input[key] as? String, !text.isEmpty { return TranscriptReader.clipped(text) }
            }
            return ""
        }
        if let id = result["backgroundTaskId"] as? String, !id.isEmpty {
            let words = ["command", "description"].compactMap { call?.input[$0] as? String }.joined(separator: "\n")
            return BackgroundJob(id: id, kind: .shell, name: name(), startedAt: at, endsBy: nil, serves: serves(words))
        }
        if let id = result["taskId"] as? String, !id.isEmpty, let timeout = result["timeoutMs"] as? NSNumber {
            let persistent = result["persistent"] as? Bool == true
            return BackgroundJob(id: id, kind: .monitor, name: name(), startedAt: at,
                                 endsBy: persistent ? nil : at + timeout.doubleValue / 1000)
        }
        return nil
    }

    /// Whether a shell's command or description reads like a server left open on a port: a dev
    /// server, a preview, a file server. Only the picture hangs on it, so a miss shows the plain
    /// terminal and changes nothing else.
    // ponytail: a word list, not the ports the process opened. Ask the system for listening ports
    // if misses pile up.
    static func serves(_ words: String) -> Bool {
        words.range(of: servePattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static let servePattern = [
        #"\b(npm|pnpm|yarn|bun)( run)? (dev|start|serve|preview|storybook)\b"#,
        #"\b(next|nuxt|astro|remix|vite|wrangler|vercel|netlify|expo) (dev|start|preview)\b"#,
        // Not `vite build`, and not a file named after one: vite.config.ts.
        #"\b(vite|serve|http-server|live-server|http\.server|runserver|uvicorn|gunicorn|hypercorn|storybook|studio)\b(?![.-]| build)"#,
        #"\b(flask run|rails (s|server)|hugo server|php -S|docker[- ]compose up)\b"#,
        #"--port\b|\bPORT=\d|\bport \d{2,5}\b"#,
        // A description's own words: "Start Next.js dev server". Not a bare "server": `cd server`.
        #"\b(dev|web|api|http|preview|local|static|backend|frontend|mock|proxy|file|docs?) server\b"#,
    ].joined(separator: "|")

    /// Every job is old enough that nobody is likely waiting on any of them.
    static func resting(_ jobs: [BackgroundJob], now: Date) -> Bool {
        jobs.allSatisfy { $0.isLong(now: now) }
    }

    /// The jobs still running in each session, oldest first, keyed like `TrackedFile.session`.
    /// Every file counts, the finished sub-agents' too: a job started in one file can end in another.
    /// `running`: the process start of each session with a live record, by session id; nil when the
    /// machine keeps no records. A session without a record is closed, and a job older than its
    /// process died with the process before it.
    static func bySession(_ files: [String: TrackedFile], now: Date, running: [String: Date]?) -> [String: [BackgroundJob]] {
        Dictionary(grouping: files.values, by: \.session).mapValues { group in
            let session = group[0].session
            let ended = Set(group.flatMap(\.info.endedJobs))
            var jobs = group.flatMap(\.info.jobs).filter { !ended.contains($0.id) && ($0.endsBy ?? .distantFuture) > now }
            if let running {
                guard let process = running[(session as NSString).lastPathComponent] else { return [] }
                jobs.removeAll { $0.startedAt < process }
            }
            // The same start read in two files is one job: twice, it would count twice and repeat a line.
            var seen = Set<String>()
            return jobs.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }.filter { seen.insert($0.id).inserted }
        }
    }
}

extension AgentInfo {
    mutating func endJob(_ id: String) {
        jobs.removeAll { $0.id == id }
        guard !endedJobs.contains(id) else { return }
        endedJobs.append(id)
        endedJobs.removeFirst(max(0, endedJobs.count - BackgroundJobs.endedLimit))
    }

    /// What notices in `text` say of sub-agents that wait on work of their own: since `date`, or no longer.
    mutating func readWaits(in text: String, at date: Date?) {
        for (id, waits) in BackgroundJobs.agentWaits(in: text) {
            // A copy with no time leaves what an earlier one said.
            if !waits { waitingAgents[id] = nil } else if let date { waitingAgents[id] = date }
        }
    }

    /// What a user line says about jobs: notices that end them, a stopped task, a result that starts one.
    mutating func readJobs(in object: [String: Any], at date: Date?) {
        let content = (object["message"] as? [String: Any])?["content"]
        if let text = content as? String {
            for id in BackgroundJobs.ended(in: text) { endJob(id) }
            readWaits(in: text, at: date)
        }
        let results = (content as? [[String: Any]] ?? []).filter { $0["type"] as? String == "tool_result" }
        for block in results {
            guard block["is_error"] as? Bool != true,
                  let call = openTools.first(where: { $0.id == block["tool_use_id"] as? String }),
                  call.tool == "TaskStop", let id = call.input["task_id"] as? String else { continue }
            endJob(id)
        }
        guard let date, let result = object["toolUseResult"] as? [String: Any] else { return }
        let call = openTools.first { $0.id == results.first?["tool_use_id"] as? String }
        guard let job = BackgroundJobs.started(by: result, call: call, at: date),
              !jobs.contains(where: { $0.id == job.id }), !endedJobs.contains(job.id) else { return }
        jobs.append(job)
        jobs.removeFirst(max(0, jobs.count - TranscriptReader.openToolLimit))
    }
}
