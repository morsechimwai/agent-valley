import Foundation

/// What `crew install` and `crew uninstall` do to Claude Code's settings, the crew's font and
/// Ghostty's config. The app never runs these itself: they run only when the person pastes the
/// command. After an update the app only brings the font and Ghostty's line that install put in
/// place up to date, and only where they are. Every file is read and checked before any is
/// written, so a refusal changes nothing. Paths all start from `home`, so tests can work in a
/// home of their own.
enum CrewSetup {
    enum Failure: Error, Equatable {
        case unreadableSettings(String)
        case missingFont
    }

    static let leadLooksName = "crew-leads.json", backupName = "crew-backup.json", rosterName = "crew-roster.json"
    static let ghosttyLines = ["# AgentValley: the crew's faces in Claude Code come from this font",
                               "font-codepoint-map = U+3F000-U+3F7FF=AgentValley Crew"]
    /// The narrower map of the versions before the faces with things in hand. Install and the
    /// app after an update put today's in its place; uninstall takes out either.
    static let oldGhosttyLines = ["font-codepoint-map = U+3F000-U+3F3FF=AgentValley Crew"]

    /// The settings keys the crew takes over, with the `crew` mode each one runs.
    private static let keys = [("statusLine", "status"), ("subagentStatusLine", "agents")]

    static func folder(_ home: URL) -> URL { home.appendingPathComponent("Library/Application Support/AgentValley") }

    /// The app's folder, made if missing so that only this account can enter it: the socket of
    /// "Answer from the notch" shares it and refuses a folder other accounts can open.
    private static func makeFolder(_ home: URL) throws {
        try FileManager.default.createDirectory(at: folder(home), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private static func fontURL(_ home: URL) -> URL { home.appendingPathComponent("Library/Fonts/" + CrewFont.fileName) }


    private static func configDir(_ environment: [String: String]) -> URL? {
        environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }

    private static func settingsURL(_ home: URL, _ environment: [String: String]) -> URL {
        (configDir(environment) ?? home.appendingPathComponent(".claude")).appendingPathComponent("settings.json")
    }

    /// Claude Code's own state, the plan among it. It sits in the home folder, not in `~/.claude`,
    /// except under `CLAUDE_CONFIG_DIR`, where it moves into that folder with the settings.
    static func claudeJSON(home: URL, environment: [String: String]) -> URL {
        (configDir(environment) ?? home).appendingPathComponent(".claude.json")
    }

    /// The `oauthAccount` object of `.claude.json`, cut out and parsed alone: a heavy user's file
    /// runs to megabytes, and parsing all of it would take the status line past its 50 ms. An
    /// unescaped `"oauthAccount":` can only be a key, since inside a string its quotes would be
    /// escaped. Its braces are matched outside strings, as `SafeJSON.nests` counts them. nil when
    /// the key is missing, holds no object, or the braces never close.
    static func oauthAccount(in data: Data) -> [String: Any]? {
        guard let key = data.range(of: Data("\"oauthAccount\":".utf8)) else { return nil }
        var index = key.upperBound
        while index < data.endIndex, [0x20, 0x09, 0x0A, 0x0D].contains(data[index]) { index += 1 }
        guard index < data.endIndex, data[index] == UInt8(ascii: "{") else { return nil }
        let start = index
        var depth = 0, inString = false, escaped = false
        while index < data.endIndex {
            let byte = data[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 { return SafeJSON.object(data[start...index]) }
            }
            index += 1
        }
        return nil
    }

    /// Ghostty's config files, in the order Ghostty 1.3 looks for them.
    private static func ghosttyConfigs(_ home: URL, _ environment: [String: String]) -> [URL] {
        let appSupport = home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty")
        let xdg = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".config")
        return [appSupport.appendingPathComponent("config.ghostty"), appSupport.appendingPathComponent("config"),
                xdg.appendingPathComponent("ghostty/config.ghostty"), xdg.appendingPathComponent("ghostty/config")]
    }

    /// The file a path names, past any symbolic links. Settings kept in a dotfiles repository are
    /// often linked in; writing to the link's own path would replace the link with a plain file
    /// and quietly cut it off from the repository. The folder is resolved before a link's target
    /// is read against it: with `~/.claude` itself a link, "../x" means beside the real folder.
    private static func realFile(_ url: URL) -> URL {
        var url = url
        for _ in 0..<32 {
            let folder = url.deletingLastPathComponent().resolvingSymlinksInPath()
            url = folder.appendingPathComponent(url.lastPathComponent)
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { break }
            url = URL(fileURLWithPath: target, relativeTo: folder).absoluteURL
        }
        return url.standardizedFileURL
    }

    /// What install saved, filed under each settings file it took over, so that two Claude config
    /// folders never share or overwrite each other's old status lines.
    private static func readBackups(_ url: URL) throws -> [String: [String: Any]] {
        guard let backups = try readObject(url) as? [String: [String: Any]] else { throw Failure.unreadableSettings(url.path) }
        return backups
    }

    /// A JSON object from disk: none for a missing or blank file. Anything else that is not an
    /// object is refused, since writing back what was understood would lose what was not.
    private static func readObject(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadableSettings(url.path) }
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        guard let object = SafeJSON.object(data) else { throw Failure.unreadableSettings(url.path) }
        return object
    }

    private static func writeObject(_ object: [String: Any], to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(Data("\n".utf8))
        try write(data, to: url)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Whether a settings value is the crew's own command for `mode`, from this or any other copy of the app.
    private static func isOurs(_ value: Any?, _ mode: String) -> Bool {
        guard let command = (value as? [String: Any])?["command"] as? String else { return false }
        return command.contains("AgentValley") && command.hasSuffix(" crew \(mode)")
    }

    /// Lines compared without the spaces or carriage return around them.
    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func install(home: URL, environment: [String: String], executable: String, font: URL, ghosttyApps: [URL]) throws -> String {
        let files = FileManager.default
        let settingsLink = settingsURL(home, environment)
        var settings = try readObject(realFile(settingsLink))
        let backupFile = folder(home).appendingPathComponent(backupName)
        var backups = try readBackups(backupFile)
        guard let fontData = try? Data(contentsOf: font) else { throw Failure.missingFont }

        // Ghostty is read now too, so that a file it cannot read stops the command before anything is written.
        let configs = ghosttyConfigs(home, environment)
        var ghostty: (shown: URL, file: URL, text: String)?
        if let config = configs.first(where: { files.fileExists(atPath: $0.path) }) {
            let file = realFile(config)
            let original = try String(contentsOf: file, encoding: .utf8)
            let text = widened(original)
            let missing = ghosttyLines.filter { !lines(text).contains($0) }
            if !missing.isEmpty {
                let start = text.isEmpty || text.hasSuffix("\n") ? text : text + "\n"
                ghostty = (config, file, start + missing.joined(separator: "\n") + "\n")
            } else if text != original {
                ghostty = (config, file, text)
            }
        } else if ghosttyApps.contains(where: { files.fileExists(atPath: $0.path) }) {
            ghostty = (configs[1], configs[1], ghosttyLines.joined(separator: "\n") + "\n")
        }

        // Every check has passed. The folder is made before the saved values are filed under the
        // settings file's path: a folder that does not exist yet keeps the links above it
        // unresolved, and uninstall, finding it there, would look under another name.
        try files.createDirectory(at: settingsLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settingsFile = realFile(settingsLink)

        // A key that is already ours keeps the value saved when it was taken; pasting the command
        // again after an update must not save our own command as the person's.
        var saved = backups[settingsFile.path] ?? [:]
        for (key, mode) in keys {
            if !isOurs(settings[key], mode) { saved[key] = settings[key] }
            var value: [String: Any] = ["type": "command", "command": Format.crewCommand(executable: executable, mode)]
            if key == "statusLine" { value["padding"] = 1; value["refreshInterval"] = 30 }
            settings[key] = value
        }
        // Filed even when there is nothing to put back: the entry says this settings file runs the crew.
        backups[settingsFile.path] = saved

        try makeFolder(home)
        try writeObject(backups, to: backupFile)
        try write(fontData, to: fontURL(home))
        try writeObject(settings, to: settingsFile)
        if let ghostty { try write(Data(ghostty.text.utf8), to: ghostty.file) }

        var message = ["The crew is in. Start Claude Code again to see us under the prompt."]
        if !saved.isEmpty { message.append("Your old status line is saved and comes back if you take the crew out.") }
        if let ghostty { message.append("Ghostty: added our font line to \(ghostty.shown.path). Quit and reopen Ghostty to see our faces.") }
        return message.joined(separator: "\n")
    }

    static func uninstall(home: URL, environment: [String: String]) throws -> String {
        let files = FileManager.default
        let settingsFile = realFile(settingsURL(home, environment))
        var settings = try readObject(settingsFile)
        let backupFile = folder(home).appendingPathComponent(backupName)
        var backups = try readBackups(backupFile)
        let saved = backups.removeValue(forKey: settingsFile.path)
        // The font and Ghostty's line are shared: they go only with the last settings file that runs the crew.
        let last = backups.isEmpty

        var edits: [(shown: URL, file: URL, text: String)] = []
        for config in ghosttyConfigs(home, environment) where last && files.fileExists(atPath: config.path) {
            let file = realFile(config)
            let text = try String(contentsOf: file, encoding: .utf8)
            let kept = text.components(separatedBy: "\n").filter { !(ghosttyLines + oldGhosttyLines).contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let edited = kept.joined(separator: "\n")
            if edited != text { edits.append((config, file, edited)) }
        }

        // Only keys that still run the crew go back; one the person has changed since is theirs.
        var ours = false, restored = false
        for (key, mode) in keys where isOurs(settings[key], mode) {
            settings[key] = saved?[key]
            ours = true
            restored = restored || saved?[key] != nil
        }
        // The settings are written before the saved values go, so a failed write loses nothing.
        if ours { try writeObject(settings, to: settingsFile) }
        if last {
            try? files.removeItem(at: backupFile)
            try? files.removeItem(at: fontURL(home))
            for edit in edits { try write(Data(edit.text.utf8), to: edit.file) }
        } else if saved != nil {
            try writeObject(backups, to: backupFile)
        }

        var message = ["The crew is out of the terminal. Start Claude Code again."]
        if restored { message.append("Your old status line is back.") }
        for edit in edits { message.append("Ghostty: removed our font line from \(edit.shown.path). Quit and reopen Ghostty.") }
        return message.joined(separator: "\n")
    }

    /// A config with the old map line swapped for today's, where it stands.
    private static func widened(_ text: String) -> String {
        text.components(separatedBy: "\n").map {
            oldGhosttyLines.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) ? ghosttyLines[1] : $0
        }.joined(separator: "\n")
    }

    /// Whether the terminal can draw the faces with things in hand and the mug, which older fonts lack.
    /// The installed font must be this app's, and the terminal must have opened after it was put
    /// in place: a terminal keeps the fonts it has seen until it quits, and would draw a face the
    /// old font lacks as an empty box. Ghostty draws our faces only through its font line, and
    /// the line of older versions stops short of these.
    static func drawsThingsInHand(home: URL, environment: [String: String], bundled: URL, terminalStart: Date?) -> Bool {
        let installed = fontURL(home)
        guard FileManager.default.contentsEqual(atPath: installed.path, andPath: bundled.path),
              let placed = (try? FileManager.default.attributesOfItem(atPath: installed.path))?[.modificationDate] as? Date,
              let terminalStart, terminalStart > placed else { return false }
        guard environment["TERM_PROGRAM"] == "ghostty" else { return true }
        return ghosttyConfigs(home, environment).contains { config in
            (try? String(contentsOf: realFile(config), encoding: .utf8)).map { lines($0).contains(ghosttyLines[1]) } ?? false
        }
    }

    /// After an update the app widens the font line an older install put in Ghostty's config. A
    /// config without our line is left as it is. Run before `refreshFont`, so that a Ghostty
    /// opened after the new font was put in place has read the new line too.
    static func refreshGhosttyLine(home: URL, environment: [String: String]) {
        for config in ghosttyConfigs(home, environment) {
            let file = realFile(config)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let wide = widened(text)
            if wide != text { try? write(Data(wide.utf8), to: file) }
        }
    }

    /// After an update the app replaces the font, but only where the person installed it.
    static func refreshFont(home: URL, bundled: URL) {
        let installed = fontURL(home)
        guard let old = try? Data(contentsOf: installed), let new = try? Data(contentsOf: bundled), old != new else { return }
        try? new.write(to: installed, options: .atomic)
    }

    /// Each session's lead as `{"<session uuid>": [face, hair, shirt]}`, for `crew status` to read
    /// by the `session_id` Claude Code gives it. Only the app knows who sits where: `Roster`.
    static func leadLooksData(_ looks: [String: LeadLook]) -> Data {
        let byID = looks.mapValues { [$0.face, $0.hair, $0.shirt] }
        return (try? JSONSerialization.data(withJSONObject: byID, options: .sortedKeys)) ?? Data("{}".utf8)
    }

    /// Puts the looks where `crew status` reads them.
    static func writeLeadLooks(_ data: Data, home: URL) throws {
        try makeFolder(home)
        try data.write(to: folder(home).appendingPathComponent(leadLooksName), options: .atomic)
    }

    /// The look the app gave a session's lead, or nil when it has given none: before the first
    /// prompt, while the session is put away, or while the app is closed.
    static func look(for sessionID: String, in data: Data?) -> LeadLook? {
        guard let data, let parts = SafeJSON.object(data)?[sessionID] as? [Int], parts.count == 3,
              parts.allSatisfy({ $0 >= 0 }) else { return nil }
        return LeadLook(face: parts[0], hair: parts[1], shirt: parts[2])
    }
}
