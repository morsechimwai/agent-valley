import XCTest

/// Runs a shell script the way Claude Code runs a hook: JSON on stdin, a chosen HOME.
func runHookScript(_ script: URL, home: URL, input: String, environment: [String: String] = [:]) throws -> (output: String, status: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script.path]
    process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"].merging(environment) { _, given in given }
    let stdin = Pipe()
    let stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    try process.run()
    stdin.fileHandleForWriting.write(Data(input.utf8))
    try stdin.fileHandleForWriting.close()
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (String(decoding: output, as: UTF8.self), process.terminationStatus)
}

/// A short folder under /tmp: a Unix socket path may not exceed 104 bytes, which the usual temp folder would.
func shortTempFolder() throws -> URL {
    let url = URL(fileURLWithPath: "/tmp/av-" + UUID().uuidString.prefix(8))
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Leaves a socket file with nothing listening on it, as a crashed app would.
func makeStaleSocket(at path: String) {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, size) } }
    close(descriptor)
}

final class PluginTests: XCTestCase {
    /// The repo root, found from this file's own path.
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let marketplace = root.appendingPathComponent("plugin")
    static let plugin = marketplace.appendingPathComponent("notch-answers")
    static let script = plugin.appendingPathComponent("ask.sh")
    static let stopScript = plugin.appendingPathComponent("stop.sh")
    static let introScript = plugin.appendingPathComponent("intro.sh")

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // Four hooks and no more: every extra event is code that runs inside someone's Claude Code.
    func testThePluginRegistersItsFourHooks() throws {
        let hooks = try XCTUnwrap(json(Self.plugin.appendingPathComponent("hooks/hooks.json"))["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["PermissionRequest", "Stop", "SessionStart", "SubagentStart"])
        for event in ["SessionStart", "SubagentStart"] {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]], event)
            XCTAssertEqual(groups.count, 1, event)
            XCTAssertNil(groups[0]["matcher"], event)
            let handlers = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]], event)
            XCTAssertEqual(handlers.count, 1, event)
            XCTAssertEqual(handlers[0]["type"] as? String, "command", event)
            XCTAssertEqual(handlers[0]["command"] as? String, "\"${CLAUDE_PLUGIN_ROOT}\"/intro.sh", event)
            XCTAssertEqual(handlers[0]["timeout"] as? Int, 5, event)
        }
        let groups = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0]["matcher"] as? String, "*")
        let handlers = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(handlers.count, 1)
        XCTAssertEqual(handlers[0]["type"] as? String, "command")
        XCTAssertEqual(handlers[0]["command"] as? String, "\"${CLAUDE_PLUGIN_ROOT}\"/ask.sh")
        XCTAssertEqual(handlers[0]["timeout"] as? Int, 600)
        let stopGroups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopGroups.count, 1)
        XCTAssertNil(stopGroups[0]["matcher"])
        let stopHandlers = try XCTUnwrap(stopGroups[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(stopHandlers.count, 1)
        XCTAssertEqual(stopHandlers[0]["type"] as? String, "command")
        XCTAssertEqual(stopHandlers[0]["command"] as? String, "\"${CLAUDE_PLUGIN_ROOT}\"/stop.sh")
        XCTAssertEqual(stopHandlers[0]["timeout"] as? Int, 86400)
    }

    func testTheManifestsNameWhatTheInstallCommandsUse() throws {
        let market = try json(Self.marketplace.appendingPathComponent(".claude-plugin/marketplace.json"))
        XCTAssertEqual(market["name"] as? String, "agent-valley")
        let listed = try XCTUnwrap(market["plugins"] as? [[String: Any]])
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0]["name"] as? String, "notch-answers")
        XCTAssertEqual(listed[0]["source"] as? String, "./notch-answers")
        let manifest = try json(Self.plugin.appendingPathComponent(".claude-plugin/plugin.json"))
        XCTAssertEqual(manifest["name"] as? String, "notch-answers")
        for key in ["version", "description", "author"] { XCTAssertNotNil(manifest[key], key) }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Self.script.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Self.stopScript.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Self.introScript.path))
    }

    // A new version is how Claude Code learns the plugin has hooks it did not have before.
    func testThePluginVersionIs030() throws {
        XCTAssertEqual(try json(Self.plugin.appendingPathComponent(".claude-plugin/plugin.json"))["version"] as? String, "0.3.0")
    }

    func testIntroIsSilentWithoutTheApp() throws {
        let home = try shortTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let input = #"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/w"}"#
        let result = try runHookScript(Self.introScript, home: home, input: input, environment: ["CLAUDE_CODE_ENTRYPOINT": "cli"])
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
    }

    // Without the app there must be no trace of the plugin in a session: no output, no error.
    func testTheHookScriptSaysNothingWhenTheAppIsNotThere() throws {
        let home = try shortTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let result = try runHookScript(Self.script, home: home, input: #"{"tool_name":"Bash"}"#)
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
    }

    func testTheHookScriptSaysNothingWhenNothingListensOnTheSocket() throws {
        let home = try shortTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("Library/Application Support/AgentValley")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        makeStaleSocket(at: folder.appendingPathComponent("answers.sock").path)
        let result = try runHookScript(Self.script, home: home, input: #"{"tool_name":"Bash"}"#)
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
    }

    // Stop has its own script: with no app, or an empty answer, Claude Code ends the turn as usual.
    func testTheStopScriptSaysNothingWhenTheAppIsNotThere() throws {
        let home = try shortTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let input = #"{"hook_event_name":"Stop","transcript_path":"/x/abc.jsonl","last_assistant_message":"done"}"#
        let result = try runHookScript(Self.stopScript, home: home, input: input)
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
    }

    func testTheStopScriptSaysNothingWhenNothingListensOnTheSocket() throws {
        let home = try shortTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("Library/Application Support/AgentValley")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        makeStaleSocket(at: folder.appendingPathComponent("answers.sock").path)
        // Away on, as far as the script can tell: the socket is the only thing missing.
        FileManager.default.createFile(atPath: folder.appendingPathComponent("away").path, contents: nil)
        let input = #"{"hook_event_name":"Stop","transcript_path":"/x/abc.jsonl","last_assistant_message":"done"}"#
        let result = try runHookScript(Self.stopScript, home: home, input: input)
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
    }
}
