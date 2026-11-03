import XCTest
@testable import AgentValley

/// A login paid per use: how the app tells, what today cost, and how it is shown.
final class PayPerUseTests: XCTestCase {
    private let million = 1_000_000

    // MARK: - The Keychain's login

    // A Console login keeps a Keychain item too, with no plan and no right to chat on one.
    func testAKeychainLoginWithoutAPlanIsNotSubscribed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func login(_ oauth: String) -> Result<String, LimitsFailure> {
            PlanLimitsReader.login(fromKeychainItem: Data(#"{"claudeAiOauth":{"accessToken":"t"\#(oauth)}}"#.utf8), now: now)
        }
        XCTAssertEqual(login(#","subscriptionType":"max","scopes":["user:profile"]"#), .success("t"))
        XCTAssertEqual(login(#","scopes":["user:inference","user:profile"]"#), .success("t"))
        XCTAssertEqual(login(#","scopes":["org:create_api_key","user:profile"]"#), .failure(.notSubscribed))
        XCTAssertEqual(login(#","subscriptionType":"","scopes":["user:profile"]"#), .failure(.notSubscribed))
        // An item from an older Claude Code names neither: taken as a plan, as before.
        XCTAssertEqual(login(""), .success("t"))
    }

    // No item at all is not proof of pay per use: a plan kept under another Keychain name, with
    // CLAUDE_CONFIG_DIR set, misses the same way, and must not be shown as "API".
    func testNoKeychainItemIsNoLoginNotPayPerUse() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = Data(#"{"claudeAiOauth":{"accessToken":"t","subscriptionType":"max"}}"#.utf8)
        XCTAssertEqual(PlanLimitsReader.login(securityStatus: 44, item: Data(), now: now), .failure(.noLogin))
        XCTAssertEqual(PlanLimitsReader.login(securityStatus: 51, item: Data(), now: now), .failure(.noLogin))
        XCTAssertEqual(PlanLimitsReader.login(securityStatus: 0, item: item, now: now), .success("t"))
    }

    // MARK: - Prices of cloud model ids

    private func cost(_ model: String) -> Double? {
        Pricing.cost(of: LedgerAnswer(id: "m", at: Date(timeIntervalSince1970: 1_791_900_005), model: model, output: million))
    }

    // Bedrock and Vertex name the same models their own way; each costs what the plain id costs.
    func testCloudModelIdsCostWhatThePlainIdCosts() throws {
        let opus = try XCTUnwrap(cost("claude-opus-5-5"))
        for id in ["anthropic.claude-opus-5-5-v1:0", "us.anthropic.claude-opus-5-5-v1:0", "global.anthropic.claude-opus-5-5-v1",
                   "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-opus-5-5-v1:0",
                   "claude-opus-5-5@20261001"] {
            XCTAssertEqual(cost(id), opus, id)
        }
        let haiku = try XCTUnwrap(cost("claude-haiku-4-5"))
        XCTAssertEqual(cost("eu.anthropic.claude-haiku-4-5-20251001-v1:0"), haiku)
        XCTAssertEqual(cost("claude-haiku-4-5@20251001"), haiku)
        // Still no guess for a model with no price.
        for id in ["us.anthropic.claude-opus-5-7-v1:0", "claude-opus-5-7@20270101", "anthropic.", "@", "-v1:0"] {
            XCTAssertNil(cost(id), id)
        }
    }

    // MARK: - Today's spend from the token history

    func testTodaysSpendStartsAtMidnightAndLeavesOutWhatHasNoPrice() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_791_901_800) // 2026-10-13 14:30 UTC
        let midnight = now.addingTimeInterval(-(14 * 3600 + 30 * 60))
        func answer(_ session: String, _ at: Date, _ model: String = "claude-haiku-4-5") -> LedgerAnswer {
            LedgerAnswer(id: UUID().uuidString, at: at, session: session, model: model, output: million)
        }
        let spend = Usage.spend(of: [
            answer("a", now),
            answer("a", midnight),                              // midnight to the second: today
            answer("a", midnight.addingTimeInterval(-1)),       // yesterday
            answer("a", now.addingTimeInterval(60)),            // a clock that ran ahead
            answer("b", now, "claude-opus-5-7"),                // no price: flagged, not counted
            answer("c", midnight.addingTimeInterval(-1), "claude-opus-5-7"), // yesterday's: not flagged
        ], now: now, calendar: utc)
        XCTAssertEqual(spend.spent.keys.sorted(), ["a"])
        XCTAssertEqual(try XCTUnwrap(spend.spent["a"]), 2 * (try XCTUnwrap(cost("claude-haiku-4-5"))), accuracy: 1e-9)
        XCTAssertEqual(spend.unpriced, ["b"])
        XCTAssertTrue(Usage.spend(of: [], now: now, calendar: utc).spent.isEmpty)
    }

    // MARK: - The file `crew status` reads

    func testTheSpendFileCarriesTheKindAndTodaysDollarsOnly() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let data = CrewSetup.spendData(["s1": PayPerUse(via: "API", spentToday: 4.27),
                                        "s2": PayPerUse(via: "Bedrock", spentToday: nil)], now: now)
        XCTAssertEqual(CrewSetup.spend(for: "s1", in: data, now: now)?.via, "API")
        XCTAssertEqual(CrewSetup.spend(for: "s1", in: data, now: now)?.today, 4.27)
        XCTAssertEqual(CrewSetup.spend(for: "s2", in: data, now: now)?.via, "Bedrock")
        XCTAssertNil(CrewSetup.spend(for: "s2", in: data, now: now)?.today)
        XCTAssertNil(CrewSetup.spend(for: "s3", in: data, now: now))
        XCTAssertNil(CrewSetup.spend(for: "s1", in: nil, now: now))
        // Tomorrow, yesterday's dollars are not today's: the kind stays, the amount goes.
        let tomorrow = now.addingTimeInterval(86_400)
        XCTAssertEqual(CrewSetup.spend(for: "s1", in: data, now: tomorrow)?.via, "API")
        XCTAssertNil(CrewSetup.spend(for: "s1", in: data, now: tomorrow)?.today)
    }

    // The file is plain JSON anyone can write: nothing in it reaches the terminal but a short word and a sum.
    func testAnOddSpendFileShowsNothingOdd() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = try XCTUnwrap(SafeJSON.object(CrewSetup.spendData([:], now: now))?["day"] as? String)
        func read(_ row: String) -> (via: String, today: Double?)? {
            CrewSetup.spend(for: "s", in: Data(#"{"day":"\#(day)","sessions":{"s":\#(row)}}"#.utf8), now: now)
        }
        for row in [#"{"via":""}"#, #"{"via":"ThirteenChars"}"#, #"{"via":"A\u001b[31m"}"#, #"{"via":"A B"}"#, #"{"via":7}"#, #"{}"#] {
            XCTAssertNil(read(row), row)
        }
        XCTAssertNil(read(#"{"via":"API","today":-1}"#)?.today)
        XCTAssertNil(read(#"{"via":"API","today":"4"}"#)?.today)
        XCTAssertEqual(read(#"{"via":"API","today":0}"#)?.today, 0)
    }

    // MARK: - The terminal's status line

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private lazy var input: [String: Any] = ["model": ["display_name": "Opus 5.5"]]

    private func line(_ spend: (via: String, today: Double?)?, newFont: Bool = false) -> String {
        CrewLine.status(input, columns: 102, plan: "Max", look: LeadLook(), newFont: newFont, spend: spend, now: now)
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    func testThePayPerUseLineShowsTheKindAndToday() {
        XCTAssertEqual(line(("API", 4.27)), "\u{3F015}  Opus 5.5 · API · Today $4.27")
        XCTAssertEqual(line(("Bedrock", nil)), "\u{3F015}  Opus 5.5 · Bedrock")
        // No plan badge beside a login that has no plan.
        XCTAssertFalse(line(("API", 0), newFont: true).contains(CrewFont.Badge.max.text))
        XCTAssertTrue(line(("API", 0), newFont: true).hasSuffix("API · Today $0.00"))
    }

    // Limits in the input mean a plan, whatever the file says.
    func testLimitsWinOverTheSpend() {
        input["rate_limits"] = ["five_hour": ["used_percentage": 6.0]]
        let lines = line(("API", 4.27)).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasPrefix("Max  5h "), lines[1])
        XCTAssertFalse(lines.joined().contains("Today"))
    }

    // MARK: - Words

    func testSpendWords() {
        XCTAssertEqual(Format.spentToday(nil), "—")
        XCTAssertEqual(Format.spentToday(4.271), "$4.27")
        XCTAssertEqual(Format.spentToday(0), "$0.00")
        // Four characters at most on the shut bar.
        for (dollars, text) in [(0.0, "$0.0"), (4.27, "$4.3"), (9.96, "$10"), (42, "$42"), (999.4, "$999"), (999.6, "$1k"), (1234, "$1k"), (9_400, "$9k")] {
            XCTAssertEqual(Format.barSpend(dollars), text, "\(dollars)")
        }
        XCTAssertEqual(Format.payPerUseHelp(PayPerUse(via: "API", spentToday: nil)),
                       "Paid per use (API), so there are no plan limits. Turn on Token use in Settings to count what today cost.")
        XCTAssertEqual(Format.payPerUseHelp(PayPerUse(via: "Vertex", spentToday: 4.27)),
                       "Paid per use (Vertex), so there are no plan limits. Spent today: $4.27, at API prices, counted on this Mac.")
        XCTAssertTrue(Format.payPerUseHelp(PayPerUse(via: "API", spentToday: 1, unpriced: true)).hasSuffix("no known price and are not counted."))
        XCTAssertEqual(Format.limitsReason(.notSubscribed), "The Claude Code login in Keychain has no Claude plan, so there are no plan limits to show.")
    }

    // MARK: - The hook

    func testTheHeaderNamesTheLoginKindOrNothing() {
        func parse(_ value: String) -> HTTPRequest {
            AnswerProtocol.parse(Data("POST /crew-intro HTTP/1.1\r\nX-Claude-Login: \(value)\r\nContent-Length: 2\r\n\r\n{}".utf8))
        }
        XCTAssertEqual(parse("api"), .complete(path: .crewIntro(pid: nil, terminal: nil, login: .api), body: Data("{}".utf8)))
        XCTAssertEqual(parse("bedrock"), .complete(path: .crewIntro(pid: nil, terminal: nil, login: .bedrock), body: Data("{}".utf8)))
        for value in ["", "nope", "API key"] {
            XCTAssertEqual(parse(value), .complete(path: .crewIntro(pid: nil, terminal: nil), body: Data("{}".utf8)), value)
        }
    }

    private let key = "sk-ant-api03-PRIVATEPRIVATEPRIVATE-abcdefghij0123456789"

    /// Runs the intro hook with `environment` against a stand-in for curl, and returns the kind it
    /// sent and everything that left the script.
    private func intro(_ environment: [String: String], config: String? = nil) throws -> (login: String, sent: String) {
        let home = try shortTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("Library/Application Support/AgentValley")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        makeStaleSocket(at: folder.appendingPathComponent("answers.sock").path)
        if let config { try Data(config.utf8).write(to: home.appendingPathComponent(".claude.json")) }
        let curl = home.appendingPathComponent("curl")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$HOME/args\"\ncat > \"$HOME/body\"\n".utf8).write(to: curl)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)
        let script = home.appendingPathComponent("intro.sh")
        let text = try String(contentsOf: PluginTests.introScript, encoding: .utf8)
        XCTAssertTrue(text.contains("/usr/bin/curl "))
        try Data(text.replacingOccurrences(of: "/usr/bin/curl ", with: curl.path + " ").utf8).write(to: script)
        _ = try runHookScript(script, home: home, input: #"{"session_id":"s1"}"#,
                              environment: environment.merging(["CLAUDE_CODE_ENTRYPOINT": "cli"]) { given, _ in given })
        let args = try String(contentsOf: home.appendingPathComponent("args"), encoding: .utf8)
        let body = try String(contentsOf: home.appendingPathComponent("body"), encoding: .utf8)
        let header = try XCTUnwrap(args.split(separator: "\n").first { $0.hasPrefix("X-Claude-Login:") })
        return (header.dropFirst("X-Claude-Login:".count).trimmingCharacters(in: .whitespaces), args + body)
    }

    // Only the kind leaves the hook: never the key, nor the part of it Claude Code keeps.
    func testTheHookSendsTheKindAndNeverTheKey() throws {
        let sent = try intro(["ANTHROPIC_API_KEY": key])
        XCTAssertEqual(sent.login, "api")
        XCTAssertFalse(sent.sent.contains(key))
        XCTAssertFalse(sent.sent.contains(String(key.suffix(20))))
        XCTAssertFalse(sent.sent.contains("PRIVATE"))
        XCTAssertFalse(try intro(["ANTHROPIC_AUTH_TOKEN": "gateway-PRIVATE"]).sent.contains("PRIVATE"))
        XCTAssertFalse(try intro(["CLAUDE_CODE_OAUTH_TOKEN": "oauth-PRIVATE"]).sent.contains("PRIVATE"))
    }

    // Same order Claude Code picks a login in.
    func testTheHookPicksTheLoginAsClaudeCodeDoes() throws {
        XCTAssertEqual(try intro([:]).login, "")
        XCTAssertEqual(try intro(["CLAUDE_CODE_OAUTH_TOKEN": "t"]).login, "plan")
        XCTAssertEqual(try intro(["ANTHROPIC_API_KEY": key, "CLAUDE_CODE_OAUTH_TOKEN": "t"]).login, "api")
        XCTAssertEqual(try intro(["ANTHROPIC_AUTH_TOKEN": "t", "ANTHROPIC_API_KEY": key]).login, "gateway")
        XCTAssertEqual(try intro(["CLAUDE_CODE_USE_BEDROCK": "1", "ANTHROPIC_API_KEY": key]).login, "bedrock")
        XCTAssertEqual(try intro(["CLAUDE_CODE_USE_BEDROCK": "true"]).login, "bedrock")
        XCTAssertEqual(try intro(["CLAUDE_CODE_USE_VERTEX": "yes"]).login, "vertex")
        XCTAssertEqual(try intro(["CLAUDE_CODE_USE_FOUNDRY": "ON"]).login, "foundry")
        // Off is off, however it is written.
        XCTAssertEqual(try intro(["CLAUDE_CODE_USE_BEDROCK": "0", "ANTHROPIC_API_KEY": key]).login, "api")
        XCTAssertEqual(try intro(["CLAUDE_CODE_USE_VERTEX": "false"]).login, "")
    }

    // A key the person turned down at Claude Code's prompt is not the login in use.
    func testARejectedKeyIsNotTheLogin() throws {
        let rejected = #"{"customApiKeyResponses":{"approved":[],"rejected":["\#(key.suffix(20))"]}}"#
        XCTAssertEqual(try intro(["ANTHROPIC_API_KEY": key], config: rejected).login, "")
        XCTAssertEqual(try intro(["ANTHROPIC_API_KEY": key, "CLAUDE_CODE_OAUTH_TOKEN": "t"], config: rejected).login, "plan")
        let approved = #"{"customApiKeyResponses":{"approved":["\#(key.suffix(20))"],"rejected":["zzzzzzzzzzzzzzzzzzzz"]}}"#
        XCTAssertEqual(try intro(["ANTHROPIC_API_KEY": key], config: approved).login, "api")
        XCTAssertEqual(try intro(["ANTHROPIC_API_KEY": key], config: "not json").login, "api")
    }
}
