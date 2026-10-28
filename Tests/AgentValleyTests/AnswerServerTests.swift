import XCTest
@testable import AgentValley

final class AnswerServerTests: XCTestCase {
    private var home: URL!
    private var folder: URL!
    private var servers: [AnswerServer] = []

    override func setUpWithError() throws {
        home = try shortTempFolder()
        folder = home.appendingPathComponent("Library/Application Support/AgentValley")
    }

    override func tearDown() {
        servers.forEach { $0.stop() }
        servers = []
        try? FileManager.default.removeItem(at: home)
    }

    private func server(in directory: URL? = nil, timeout: TimeInterval = 10, onAsk: @escaping (Ask, AnswerConnection) -> Void = { _, _ in }) -> AnswerServer {
        let server = AnswerServer(directory: directory ?? folder, requestTimeout: timeout, onAsk: onAsk)
        servers.append(server)
        return server
    }

    private func hookInput(command: String = "echo spike > out.txt") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest", "session_id": "s1", "transcript_path": "/r/p/s1.jsonl",
            "tool_name": "Bash", "tool_input": ["command": command],
        ] as [String: Any])
    }

    /// Posts to the socket the way the hook script does and reports curl's output and exit status.
    @discardableResult
    private func post(_ body: Data, arguments: [String] = [], to path: String? = nil, route: String = "permission-request", done: @escaping (String, Int32) -> Void) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["--silent", "--fail", "--max-time", "5", "--unix-socket", path ?? folder.appendingPathComponent("answers.sock").path,
                             "--header", "Content-Type: application/json", "--data-binary", "@-"] + arguments + ["http://notch/\(route)"]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async { done(output, finished.terminationStatus) }
        }
        try process.run()
        stdin.fileHandleForWriting.write(body)
        try stdin.fileHandleForWriting.close()
        return process
    }

    private func mode(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    // MARK: where it listens

    func testStartMakesAPrivateFolderAndStopRemovesTheSocket() throws {
        let server = server()
        try server.start()
        XCTAssertEqual(mode(folder), 0o700)
        XCTAssertEqual(mode(URL(fileURLWithPath: server.socketPath)), 0o600)
        XCTAssertTrue(FileManager.default.fileExists(atPath: server.socketPath))
        XCTAssertEqual(server.socketPath, folder.appendingPathComponent("answers.sock").path)
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: server.socketPath))
    }

    // Only this account may reach the socket: it carries the power to approve commands.
    func testAFolderOtherAccountsCanReachIsRefused() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        XCTAssertThrowsError(try server().start()) { XCTAssertEqual($0 as? AnswerServerError, .directoryNotPrivate) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("answers.sock").path))
    }

    func testAPathTooLongForASocketIsRefused() {
        let long = home.appendingPathComponent(String(repeating: "x", count: 100))
        XCTAssertThrowsError(try server(in: long).start()) { XCTAssertEqual($0 as? AnswerServerError, .pathTooLong) }
    }

    func testAStaleSocketIsReplacedButALiveOneIsNotTaken() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        makeStaleSocket(at: folder.appendingPathComponent("answers.sock").path)
        let first = server()
        try first.start()
        XCTAssertThrowsError(try server().start()) { XCTAssertEqual($0 as? AnswerServerError, .inUse) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.socketPath))
    }

    private func inode(_ path: String) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }

    // "Still answering" is not what makes a socket someone's: a copy whose main thread is busy,
    // with its queue of waiting connections full, refuses a probe exactly as a dead one does.
    func testACopyThatIsTooBusyToAnswerKeepsItsSocket() throws {
        let stuck = DispatchQueue(label: "stuck")
        stuck.suspend()
        defer { stuck.resume() }
        let first = AnswerServer(directory: folder, queue: stuck) { _, _ in }
        try first.start()
        // Stopped before its queue runs again: a server is only ever touched from its own queue,
        // and this test stands in for that queue being busy.
        defer { first.stop() }
        let before = inode(first.socketPath)
        var clients: [Int32] = []
        defer { clients.forEach { close($0) } }
        for _ in 0..<40 {
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let path = first.socketPath
            withUnsafeMutablePointer(to: &address.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) } }
            let size = socklen_t(MemoryLayout<sockaddr_un>.size)
            _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, size) } }
            clients.append(descriptor)
        }
        XCTAssertThrowsError(try server().start()) { XCTAssertEqual($0 as? AnswerServerError, .inUse) }
        XCTAssertEqual(inode(first.socketPath), before)
        // Stopping a server that never got the socket must not take the file away from the one that has it.
        servers.last?.stop()
        XCTAssertEqual(inode(first.socketPath), before)
    }

    // Something that is not a socket under the socket's name is not the app's to delete.
    func testAFileInTheSocketsPlaceIsLeftAlone() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = folder.appendingPathComponent("answers.sock")
        try Data("mine".utf8).write(to: path)
        XCTAssertThrowsError(try server().start())
        XCTAssertEqual(try String(contentsOf: path), "mine")
    }

    // MARK: a request and its answer

    func testARequestReachesTheAppAndTheReplyReachesTheHook() throws {
        let answered = expectation(description: "curl got the reply")
        var received: Ask?
        try server { ask, connection in
            received = ask
            connection.reply(Data(#"{"ok":true}"#.utf8))
        }.start()
        try post(hookInput()) { output, status in
            XCTAssertEqual(output, #"{"ok":true}"#)
            XCTAssertEqual(status, 0)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(received?.tool, "Bash")
        XCTAssertEqual(received?.kind, .permission(Ask.Shown(command: "echo spike > out.txt", fields: [])))
    }

    func testAStopWaitReachesOnStopAndItsReplyGoesBack() throws {
        let answered = expectation(description: "curl got the reply")
        var received: StopWait?
        let server = AnswerServer(directory: folder, requestTimeout: 10, onAsk: { _, _ in }, onStop: { stop, connection in
            received = stop
            connection.reply(AnswerProtocol.block(reason: "go"))
        })
        servers.append(server)
        try server.start()
        let input = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop", "session_id": "s1", "transcript_path": "/r/p/s1.jsonl", "last_assistant_message": "Done.",
        ])
        try post(input, route: "stop-wait") { output, status in
            XCTAssertEqual(output, #"{"decision":"block","reason":"go"}"#)
            XCTAssertEqual(status, 0)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(received, StopWait(session: "s1", lastMessage: "Done."))
    }

    func testCrewIntroReachesItsHandler() throws {
        let answered = expectation(description: "curl got the note")
        var received: CrewIntroRequest?
        let note = CrewIntro.body(event: "SessionStart", note: "hi")
        let server = AnswerServer(directory: folder, requestTimeout: 10, onAsk: { _, _ in }, onIntro: { request, connection in
            received = request
            connection.reply(note)
        })
        servers.append(server)
        try server.start()
        let input = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "SessionStart", "session_id": "s1", "transcript_path": "/r/p/s1.jsonl", "cwd": "/w", "source": "startup",
        ])
        try post(input, arguments: ["--header", "X-Claude-Pid: 42"], route: "crew-intro") { output, status in
            XCTAssertEqual(output, String(decoding: note, as: UTF8.self))
            XCTAssertEqual(status, 0)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(received, CrewIntroRequest(event: "SessionStart", session: "s1", cwd: "/w", agentType: "", pid: 42))
    }

    // No decision is an empty answer: the hook prints nothing and the terminal keeps asking.
    func testNoDecisionReachesTheHookAsNothing() throws {
        let answered = expectation(description: "curl finished")
        try server { _, connection in connection.reply(nil) }.start()
        try post(hookInput()) { output, status in
            XCTAssertEqual(output, "")
            XCTAssertEqual(status, 0)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
    }

    func testTheHookScriptCarriesARealSizedRequestWithoutDelay() throws {
        let answered = expectation(description: "the script printed the reply")
        var delivered: Bool?
        try server { _, connection in delivered = connection.reply(Data(#"{"ok":true}"#.utf8)) }.start()
        // Over a kilobyte, as real hook input is: curl would otherwise pause a second for "100 Continue".
        let input = String(decoding: hookInput(command: String(repeating: "x", count: 1500)), as: UTF8.self)
        let started = Date()
        DispatchQueue.global().async { [home] in
            let result = try? runHookScript(PluginTests.script, home: home!, input: input)
            DispatchQueue.main.async {
                XCTAssertEqual(result?.output, #"{"ok":true}"#)
                XCTAssertEqual(result?.status, 0)
                XCTAssertEqual(delivered, true)
                answered.fulfill()
            }
        }
        wait(for: [answered], timeout: 5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8)
    }

    // A person's settings for curl must not leak into what Claude Code reads as the hook's answer.
    func testTheHookScriptIgnoresThePersonsCurlSettings() throws {
        try Data("-w \"\\nHTTP=%{http_code}\\n\"\ninclude\n".utf8).write(to: home.appendingPathComponent(".curlrc"))
        var bodies: [Data?] = [nil, Data(#"{"ok":true}"#.utf8)]
        try server { _, connection in connection.reply(bodies.removeFirst()) }.start()
        for expected in ["", #"{"ok":true}"#] {
            let done = expectation(description: "the script finished")
            DispatchQueue.global().async { [home] in
                let result = try? runHookScript(PluginTests.script, home: home!, input: String(decoding: self.hookInput(), as: UTF8.self))
                DispatchQueue.main.async {
                    XCTAssertEqual(result?.output, expected)
                    XCTAssertEqual(result?.status, 0)
                    done.fulfill()
                }
            }
            wait(for: [done], timeout: 5)
        }
    }

    // A hook that stops reading must not be able to freeze the app when its answer is sent.
    func testAReplyToAClientThatDoesNotReadGivesUp() throws {
        let replied = expectation(description: "the reply returned")
        var took: TimeInterval = 0
        try server { _, connection in
            let started = Date()
            connection.reply(Data(repeating: 0x7B, count: 512 * 1024))
            took = Date().timeIntervalSince(started)
            replied.fulfill()
        }.start()
        let path = folder.appendingPathComponent("answers.sock").path
        let body = hookInput()
        DispatchQueue.global().async {
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &address.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) } }
            let size = socklen_t(MemoryLayout<sockaddr_un>.size)
            _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, size) } }
            let request = Data("POST /permission-request HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n".utf8) + body
            request.withUnsafeBytes { _ = write(descriptor, $0.baseAddress, $0.count) }
            // Never reads. Lets go after six seconds so a server that waits forever still ends the test.
            Thread.sleep(forTimeInterval: 6)
            close(descriptor)
        }
        wait(for: [replied], timeout: 10)
        XCTAssertLessThan(took, 3)
    }

    // The person answered in the terminal with "No", or Claude Code quit: the hook is gone.
    func testAHookThatGoesAwayIsReportedOnce() throws {
        let closed = expectation(description: "the connection reported closing")
        var closes = 0
        var hook: Process?
        var held: AnswerConnection?
        try server { _, connection in
            held = connection
            connection.onClose = { closes += 1; closed.fulfill() }
            hook?.terminate()
        }.start()
        hook = try post(hookInput()) { _, _ in }
        wait(for: [closed], timeout: 5)
        // Nothing can be handed to a hook that has gone, and the caller is told so.
        XCTAssertEqual(held?.reply(Data("{}".utf8)), false)
        XCTAssertEqual(closes, 1)
    }

    // A held Stop hook counts as announced: if its process dies, the app is told.
    func testAHeldStopWaitReportsItsHookGoing() throws {
        let closed = expectation(description: "the held connection reported closing")
        var hook: Process?
        let server = AnswerServer(directory: folder, requestTimeout: 10, onAsk: { _, _ in }, onStop: { _, connection in
            connection.onClose = { closed.fulfill() }
            hook?.terminate()
        })
        servers.append(server)
        try server.start()
        let input = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop", "session_id": "s1", "transcript_path": "/r/p/s1.jsonl", "last_assistant_message": "Done.",
        ])
        hook = try post(input, route: "stop-wait") { _, _ in }
        wait(for: [closed], timeout: 5)
    }

    /// Runs `intro.sh` off the main thread, where the server answers, and hands back its output.
    private func runIntro(entrypoint: String?, pid: String? = nil) -> String? {
        var environment: [String: String] = [:]
        environment["CLAUDE_CODE_ENTRYPOINT"] = entrypoint
        environment["CLAUDE_PID"] = pid
        let done = expectation(description: "intro.sh finished")
        var output: String?
        DispatchQueue.global().async { [home] in
            let result = try? runHookScript(PluginTests.introScript, home: home!, input: #"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/w"}"#,
                                            environment: environment)
            DispatchQueue.main.async {
                XCTAssertEqual(result?.status, 0)
                output = result?.output
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
        return output
    }

    // `claude -p` and other scripted runs (entrypoint sdk-…) get no names: their output is read by scripts.
    func testIntroSkipsScriptedRuns() throws {
        let server = AnswerServer(directory: folder, requestTimeout: 10, onAsk: { _, _ in }, onIntro: { _, connection in
            XCTFail("a scripted run reached the app")
            connection.reply(nil)
        })
        servers.append(server)
        try server.start()
        XCTAssertEqual(runIntro(entrypoint: "sdk-cli"), "")
        XCTAssertEqual(runIntro(entrypoint: nil), "")
    }

    func testIntroPrintsTheAppsNote() throws {
        let note = CrewIntro.body(event: "SessionStart", note: "hi")
        var pids: [Int32?] = []
        let server = AnswerServer(directory: folder, requestTimeout: 10, onAsk: { _, _ in }, onIntro: { request, connection in
            pids.append(request.pid)
            connection.reply(note)
        })
        servers.append(server)
        try server.start()
        XCTAssertEqual(runIntro(entrypoint: "cli", pid: "42"), String(decoding: note, as: UTF8.self))
        XCTAssertEqual(pids, [42])
    }

    // The Stop script asks the app only while Away is on, which the app marks with a file beside
    // the socket. Without it the turn ends at once, whatever the app would say: a hung app never holds it.
    func testTheStopScriptAsksOnlyWhileTheAwayFlagIsThere() throws {
        var stops = 0
        let server = AnswerServer(directory: folder, requestTimeout: 10, onAsk: { _, _ in }, onStop: { _, connection in
            stops += 1
            connection.reply(AnswerProtocol.block(reason: "go"))
        })
        servers.append(server)
        try server.start()
        let input = #"{"hook_event_name":"Stop","transcript_path":"/r/p/s1.jsonl","last_assistant_message":"Done."}"#
        for (flagged, expected) in [(false, ""), (true, #"{"decision":"block","reason":"go"}"#)] {
            if flagged { FileManager.default.createFile(atPath: folder.appendingPathComponent("away").path, contents: nil) }
            let done = expectation(description: "the script finished")
            DispatchQueue.global().async { [home] in
                let result = try? runHookScript(PluginTests.stopScript, home: home!, input: input)
                DispatchQueue.main.async {
                    XCTAssertEqual(result?.output, expected, "flag: \(flagged)")
                    XCTAssertEqual(result?.status, 0)
                    done.fulfill()
                }
            }
            wait(for: [done], timeout: 5)
        }
        XCTAssertEqual(stops, 1)
    }

    func testAStopWaitThatIsNotAStopGetsNoReply() throws {
        var stops = 0
        let server = AnswerServer(directory: folder, requestTimeout: 10, onAsk: { _, _ in }, onStop: { _, _ in stops += 1 })
        servers.append(server)
        try server.start()
        let dropped = expectation(description: "closed with nothing")
        try post(Data(#"{"session_id":"s1"}"#.utf8), route: "stop-wait") { output, status in
            XCTAssertEqual(output, "")
            XCTAssertNotEqual(status, 0)
            dropped.fulfill()
        }
        wait(for: [dropped], timeout: 5)
        XCTAssertEqual(stops, 0)
    }

    // MARK: what is not a request

    func testAnythingElseIsDroppedWithoutReachingTheApp() throws {
        var asks = 0
        try server { _, _ in asks += 1 }.start()
        let wrongMethod = expectation(description: "GET dropped")
        try post(Data(), arguments: ["--request", "GET"]) { output, status in
            XCTAssertEqual(output, "")
            XCTAssertNotEqual(status, 0)
            wrongMethod.fulfill()
        }
        let tooBig = expectation(description: "huge body dropped")
        // A well-formed request in every way but its size, so only the limit can be what drops it.
        try post(hookInput(command: String(repeating: "x", count: 2 * 1024 * 1024))) { output, _ in
            XCTAssertEqual(output, "")
            tooBig.fulfill()
        }
        let notAHookRequest = expectation(description: "unusable JSON dropped")
        try post(Data(#"{"tool_name":"Bash"}"#.utf8)) { output, _ in
            XCTAssertEqual(output, "")
            notAHookRequest.fulfill()
        }
        wait(for: [wrongMethod, tooBig, notAHookRequest], timeout: 10)
        XCTAssertEqual(asks, 0)
    }

    func testAClientThatSaysNothingIsLetGo() throws {
        let server = server(timeout: 0.3)
        try server.start()
        let dropped = expectation(description: "the silent client was disconnected")
        let path = server.socketPath
        DispatchQueue.global().async {
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &address.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) } }
            let size = socklen_t(MemoryLayout<sockaddr_un>.size)
            let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, size) } }
            var byte: UInt8 = 0
            let count = connected == 0 ? read(descriptor, &byte, 1) : -1
            close(descriptor)
            if count == 0 { dropped.fulfill() }
        }
        wait(for: [dropped], timeout: 5)
    }
}
