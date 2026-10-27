import Foundation

/// `AgentValley crew …`: what Claude Code runs for its status line and sub-agent rows, and the
/// install and uninstall lines the person pastes. It answers and exits; the app never starts.
enum CrewCommand {
    static func run(_ arguments: [String]) -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let home = URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory())
        switch arguments.first {
        case "status":
            // Whatever arrives, a face is printed and the exit is clean: Claude Code shows a
            // failed status line as nothing at all.
            let input = SafeJSON.object(FileHandle.standardInput.readDataToEndOfFile()) ?? [:]
            let columns = environment["COLUMNS"].flatMap { Int($0) } ?? 80
            let claude = (try? Data(contentsOf: CrewSetup.claudeJSON(home: home, environment: environment)))
                .flatMap(CrewSetup.oauthAccount).map { ["oauthAccount": $0] }
            let leads = try? Data(contentsOf: CrewSetup.folder(home).appendingPathComponent(CrewSetup.leadLooksName))
            let look = CrewSetup.look(for: input["session_id"] as? String ?? "", in: leads)
            let now = Date()
            // Things in hand and the bar's pictures need the font they came in.
            let newFont = drawsThingsInHand(home, environment)
            let turn = newFont ? transcript(input).flatMap { CrewLine.openTurn(transcript: $0, now: now) } : nil
            print(CrewLine.status(input, columns: columns, plan: CrewLine.plan(fromClaudeJSON: claude), look: look,
                                  holding: turn.flatMap { Activity(tool: $0.openTools.last?.tool) }, atWork: turn != nil,
                                  newFont: newFont, now: now))
            return 0
        case "agents":
            let input = SafeJSON.object(FileHandle.standardInput.readDataToEndOfFile()) ?? [:]
            let now = Date()
            let agents = transcript(input).map(CrewLine.agentTranscripts(session:)) ?? [:]
            // Each agent's open turn, read once: its last step, and what it holds where the font draws it.
            var turns: [String: AgentInfo?] = [:]
            let turn = { (id: String) -> AgentInfo? in
                if let known = turns[id] { return known }
                let info = agents[id].flatMap { CrewLine.openTurn(transcript: $0, now: now) }
                turns[id] = info
                return info
            }
            let newFont = drawsThingsInHand(home, environment)
            let holding = { (id: String) in newFont ? turn(id).flatMap { Activity(tool: $0.openTools.last?.tool) } : nil }
            for row in CrewLine.rows(input, now: now, branch: CrewLine.branch(of:), holding: holding, step: { turn($0).map(CrewLine.doing) }) {
                print(row)
            }
            return 0
        case "install":
            let executable = Format.stablePath(Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            let apps = [URL(fileURLWithPath: "/Applications/Ghostty.app"), home.appendingPathComponent("Applications/Ghostty.app")]
            return finish { try CrewSetup.install(home: home, environment: environment, executable: executable, font: bundledFont, ghosttyApps: apps) }
        case "uninstall":
            return finish { try CrewSetup.uninstall(home: home, environment: environment) }
        default:
            FileHandle.standardError.write(Data("Usage: AgentValley crew status|agents|install|uninstall\n".utf8))
            return 2
        }
    }

    private static var bundledFont: URL {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent(CrewFont.fileName)
    }

    private static func drawsThingsInHand(_ home: URL, _ environment: [String: String]) -> Bool {
        CrewSetup.drawsThingsInHand(home: home, environment: environment, bundled: bundledFont, terminalStart: terminalStart())
    }

    /// When the terminal this runs in opened: the start of the last process up the parent chain
    /// before launchd. nil when the chain can't be read.
    /// ponytail: under tmux this finds the tmux server, which can outlive a font update; things
    /// in hand then wait for the server to restart.
    static func terminalStart() -> Date? {
        var pid = getppid()
        for _ in 0..<64 {
            var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
            guard info.kp_eproc.e_ppid > 1 else {
                let start = info.kp_proc.p_starttime
                return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
            }
            pid = info.kp_eproc.e_ppid
        }
        return nil
    }

    /// The session's transcript that Claude Code names, if it is a transcript at all.
    private static func transcript(_ input: [String: Any]) -> URL? {
        guard let path = input["transcript_path"] as? String, path.hasSuffix(".jsonl") else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Prints what the step says it did, or why it stopped.
    private static func finish(_ step: () throws -> String) -> Int32 {
        let reason: String
        do {
            print(try step())
            return 0
        } catch CrewSetup.Failure.unreadableSettings(let path) {
            reason = "Can't read \(path): it isn't valid JSON. Nothing was changed. Fix the file and run this again."
        } catch CrewSetup.Failure.missingFont {
            reason = "Can't find the crew's font inside the app. Nothing was changed. Reinstall AgentValley and run this again."
        } catch {
            reason = error.localizedDescription
        }
        FileHandle.standardError.write(Data((reason + "\n").utf8))
        return 1
    }
}
