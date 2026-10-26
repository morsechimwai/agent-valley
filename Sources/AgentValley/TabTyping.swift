import Foundation

/// What one `osascript` run came to.
struct ScriptRun: Equatable {
    let status: Int32
    /// Standard output, trimmed of whitespace at both ends.
    let out: String
    let err: String
    let timedOut: Bool
}

enum TypingResult: Equatable {
    case typed, stoppedBeforeText, stoppedBeforeEnter, tabNotFound, ambiguous, notAllowed, timedOut
    case failed(String)
}

/// Types a message into the tab where Claude Code runs: the text first, then after a pause
/// and a second look, Enter on its own. Nothing is selected or brought forward.
enum TabTyping {
    static let pause: TimeInterval = 0.5
    /// What starts a tab's name while Claude Code holds that tab (idle mark, or a working spinner).
    static let claudeTitleMarks: Set<Character> = ["✳", "◐", "◓", "◑", "◒"]

    /// A fixed text, as `TabPlace.script` is: the key and the message are handed over beside it
    /// and never written into it. Its argv is action, key, text. Every action answers `ok`,
    /// `no tab`, or in Ghostty (which finds a tab by folder) `ambiguous` when two share it.
    static func script(_ terminal: TabPlace.Terminal) -> String {
        switch terminal {
        // ponytail: `do script` sends Return with the text, so a prompt that opens between the
        // first check and the text landing would get it; AppleScript types nothing without one.
        case .terminal:
            return """
            on run argv
                set action to item 1 of argv
                set target to item 2 of argv
                tell application "Terminal"
                    repeat with w in windows
                        repeat with t in tabs of w
                            set itsTTY to ""
                            try
                                set itsTTY to tty of t
                            end try
                            if itsTTY is target then
                                if action is "text" then
                                    do script (item 3 of argv) in t
                                else if action is "enter" then
                                    do script "" in t
                                end if
                                return "ok"
                            end if
                        end repeat
                    end repeat
                    return "no tab"
                end tell
            end run
            """
        case .iterm:
            return """
            on run argv
                set action to item 1 of argv
                set target to item 2 of argv
                tell application id "com.googlecode.iterm2"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                set itsTTY to ""
                                try
                                    set itsTTY to tty of s
                                end try
                                if itsTTY is target then
                                    if action is "text" then
                                        tell s to write text (item 3 of argv) newline NO
                                    else if action is "enter" then
                                        tell s to write text (ASCII character 13) newline NO
                                    end if
                                    return "ok"
                                end if
                            end repeat
                        end repeat
                    end repeat
                    return "no tab"
                end tell
            end run
            """
        case .ghostty:
            // With or without a slash at its end: both are the same folder.
            return """
            on run argv
                set action to item 1 of argv
                set target to item 2 of argv
                tell application "Ghostty"
                    set found to {}
                    repeat with t in terminals
                        try
                            set itsFolder to working directory of t
                            if itsFolder is target or itsFolder is (target & "/") then set end of found to contents of t
                        end try
                    end repeat
                    if (count of found) is 0 then return "no tab"
                    if action is "probe" then return ((count of found) as text) & (character id 9) & (name of item 1 of found)
                    if (count of found) > 1 then return "ambiguous"
                    set t to item 1 of found
                    if action is "text" then
                        input text (item 3 of argv) to t
                    else if action is "enter" then
                        send key "enter" to t
                    end if
                    return "ok"
                end tell
            end run
            """
        }
    }

    /// After a divider, so nothing in the key or the text is read as an option.
    static func arguments(_ terminal: TabPlace.Terminal, action: String, key: String, text: String) -> [String] {
        ["-e", script(terminal), "--", action, key, text]
    }

    /// `text` is already cleaned by `PhoneText.clean`; only the terminal's own form is made here.
    /// `check` is whether Claude still holds the tab; it is asked before the text and again before Enter.
    static func send(_ text: String, to place: TabPlace, check: () -> Bool,
                     run: ([String]) -> ScriptRun, wait: (TimeInterval) -> Void) -> TypingResult {
        func ask(_ action: String, _ text: String = "") -> ScriptRun {
            run(arguments(place.terminal, action: action, key: place.key, text: text))
        }
        guard check() else { return .stoppedBeforeText }
        if place.terminal == .ghostty {
            let probe = ask("probe")
            if let bad = failure(of: probe) { return bad }
            if probe.out == "no tab" { return .tabNotFound }
            let parts = probe.out.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let count = Int(parts[0]) else { return .failed(probe.out) }
            if count != 1 { return .ambiguous }
            guard let first = parts[1].first, claudeTitleMarks.contains(first) else { return .stoppedBeforeText }
        }
        if let bad = failure(of: ask("text", PhoneText.typed(text, for: place.terminal))) { return bad }
        wait(pause)
        guard check() else { return .stoppedBeforeEnter }
        if let bad = failure(of: ask("enter")) { return bad }
        return .typed
    }

    /// nil when the script said `ok`.
    private static func failure(of run: ScriptRun) -> TypingResult? {
        if run.timedOut { return .timedOut }
        if run.status != 0 {
            if run.err.contains("-1743") || run.err.contains("Not authorized") { return .notAllowed }
            return .failed(String(run.err.split(separator: "\n", omittingEmptySubsequences: true).first ?? "osascript failed"))
        }
        switch run.out {
        case "no tab": return .tabNotFound
        case "ambiguous": return .ambiguous
        default: return nil
        }
    }

    /// Runs `/usr/bin/osascript`, no shell. Waits 10 s at most, then ends it.
    static func osascript(_ arguments: [String]) -> ScriptRun {
        ScriptRun.run(URL(fileURLWithPath: "/usr/bin/osascript"), arguments, timeout: 10)
    }
}

extension ScriptRun {
    /// Runs one program, nothing on stdin. Waits `timeout` seconds at most, then ends it.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval, environment: [String: String]? = nil) -> ScriptRun {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return ScriptRun(status: -1, out: "", err: "\(error)", timedOut: false) }
        // Read on the side so a full pipe never holds the process back.
        var outData = Data(), errData = Data()
        let lock = NSLock()
        let reads = DispatchGroup()
        for (pipe, keep) in [(out, 0), (err, 1)] {
            DispatchQueue.global().async(group: reads) {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                if keep == 0 { outData = data } else { errData = data }
                lock.unlock()
            }
        }
        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            // One that ignores that is ended, so the reads below always finish.
            if exited.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
        }
        // A child it left running can hold the pipes open for as long as it likes: 2 s, then go on without.
        // ponytail: such a run comes back with no output; read in chunks if that output is ever needed.
        _ = reads.wait(timeout: .now() + 2)
        lock.lock()
        let (outBytes, errBytes) = (outData, errData)
        lock.unlock()
        let trimmed = CharacterSet.whitespacesAndNewlines
        return ScriptRun(
            status: timedOut ? -1 : process.terminationStatus,
            out: (String(data: outBytes, encoding: .utf8) ?? "").trimmingCharacters(in: trimmed),
            err: (String(data: errBytes, encoding: .utf8) ?? "").trimmingCharacters(in: trimmed),
            timedOut: timedOut)
    }
}
