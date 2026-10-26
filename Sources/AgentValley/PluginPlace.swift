import Foundation

/// Whether Claude Code's plugin list still points at this copy of the app. 0.1 lived in
/// /opt/homebrew; after its users install 0.2 in /Applications, their list still names the old
/// place, and Allow and Deny stop with nothing said. Read only: the app never writes into ~/.claude.
enum PluginPlace {
    static let marketplace = "agent-valley"
    /// The plugin inside this copy of the app.
    static var here: URL { (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("claude-plugin") }
    static let registry = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins/known_marketplaces.json")
    /// Claude Code's list of the plugins put in, as `claude plugin install` writes it.
    static let installedList = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins/installed_plugins.json")
    static let plugin = "notch-answers@agent-valley"

    /// Whether the list has our plugin for the person, so that each new session has it. One put in
    /// for a single project only works there: not counted. No list, or one that cannot be read: not in.
    /// ponytail: a plugin turned off with /plugin still counts; read `enabledPlugins` if that comes up.
    static func installed(_ list: Data?) -> Bool {
        guard let list, let object = try? JSONSerialization.jsonObject(with: list) as? [String: Any],
              let entries = (object["plugins"] as? [String: Any])?[plugin] as? [[String: Any]] else { return false }
        return entries.contains { ($0["scope"] as? String ?? "user") == "user" }
    }

    /// True when the list has this app's marketplace and it names a folder other than `plugin`
    /// that is gone. Another copy still there takes the plugin to the same socket, so it works.
    /// No list, no entry, or a list that cannot be read: not lost, there is nothing to fix.
    static func lost(_ registry: Data?, plugin: URL) -> Bool {
        guard let registry, let list = try? JSONSerialization.jsonObject(with: registry) as? [String: Any],
              let entry = list[marketplace] as? [String: Any] else { return false }
        let path = ((entry["source"] as? [String: Any])?["path"] as? String) ?? (entry["installLocation"] as? String)
        guard let path else { return false }
        return same(URL(fileURLWithPath: path)) != same(plugin) && !FileManager.default.fileExists(atPath: path)
    }

    private static func same(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// Puts the plugin in for the person, when they press Install: the same command they could paste
/// in a terminal, run by Claude Code's own `claude`. The app writes nothing into ~/.claude itself.
enum PluginInstall {
    enum Result: Equatable {
        case installed
        /// No `claude` where its installers put it, nor where the person's shell finds it.
        case noClaude
        case failed(String)
    }

    static func run(_ command: String) -> Result {
        guard let claude = claude() else { return .noClaude }
        // A GUI app's PATH has none of the person's folders, and `claude` from npm needs the
        // `node` that sits beside it.
        // ponytail: only claude's own folder is added; take the shell's whole PATH if a setup needs more.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = claude.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        let run = ScriptRun.run(URL(fileURLWithPath: "/bin/sh"), ["-c", command], timeout: 60, environment: environment)
        guard run.status == 0 else {
            let said = (run.err.isEmpty ? run.out : run.err).split(separator: "\n").last.map(String.init)
            return .failed(run.timedOut ? "it took over a minute" : said ?? "claude stopped with code \(run.status)")
        }
        return .installed
    }

    /// Where `claude` is: first where Claude Code's installers put it, then wherever the person's
    /// own shell finds it (npm, a version manager).
    static func claude(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let known = [".local/bin/claude", ".claude/local/claude"].map { home.appendingPathComponent($0).path }
            + ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let path = known.first(where: FileManager.default.isExecutableFile(atPath:)) { return URL(fileURLWithPath: path) }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let run = ScriptRun.run(URL(fileURLWithPath: shell), ["-l", "-i", "-c", "command -v claude"], timeout: 10)
        // The last line: what a shell's start-up prints comes first.
        guard run.status == 0, let path = run.out.split(separator: "\n").last.map(String.init),
              path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
