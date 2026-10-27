import XCTest
@testable import AgentValley

final class CrewLineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    lazy var input: [String: Any] = ["model": ["display_name": "Opus 5.5"], "session_id": "s1",
        "context_window": ["used_percentage": 22.0, "context_window_size": 1_000_000],
        "rate_limits": ["five_hour": ["used_percentage": 6.0, "resets_at": now.timeIntervalSince1970 + 9_750],
                        "seven_day": ["used_percentage": 70.0, "resets_at": now.timeIntervalSince1970 + 226_830]]]

    func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    func lines(_ columns: Int, plan: String? = "Max 20x") -> [String] {
        plain(CrewLine.status(input, columns: columns, plan: plan, look: LeadLook(), now: now)).components(separatedBy: "\n")
    }

    func testTheTopLineIsTheLeadModelAndPlan() {
        let lines = lines(102)
        XCTAssertEqual(lines[0], "\u{3F015}  Opus 5.5 · Max 20x")
        XCTAssertEqual(lines[1], "context ━━━━━━━━━━ 22% 220k/1.0m  │  5h ━━━━━━━━━━ 6% ↻ 2h 42m  │  7d ━━━━━━━━━━ 70% ↻ 2d 15h")
    }

    func testNoPlanDropsTheDot() {
        XCTAssertEqual(lines(98, plan: nil)[0], "\u{3F015}  Opus 5.5")
    }

    func testNoModelKeepsFaceAndPlan() {
        input["model"] = nil
        XCTAssertEqual(lines(98)[0], "\u{3F015}  Max 20x")
        XCTAssertEqual(lines(98, plan: nil)[0], "\u{3F015}")
    }

    func testTheLayoutShrinksToFit() {
        func bottom(_ columns: Int) -> String { lines(columns)[1] }
        XCTAssertTrue(bottom(102).contains("  │  ") && bottom(102).contains("━━━━━━━━━━"))
        XCTAssertTrue(bottom(101).contains(" │ ") && !bottom(101).contains("  │  ") && bottom(101).contains("━━━━━━━━ ") && !bottom(101).contains("━━━━━━━━━"))
        XCTAssertTrue(bottom(91).contains("220k/1.0m") && bottom(91).contains("━━━━━━ ") && !bottom(91).contains("━━━━━━━"))
        XCTAssertFalse(bottom(85).contains("220k")); XCTAssertTrue(bottom(85).contains("━━━━━━ "))
        XCTAssertTrue(bottom(75).contains("━━━━ ") && !bottom(75).contains("━━━━━"))
        for columns in [102, 101, 91, 85, 75] { XCTAssertLessThanOrEqual(CrewLine.width(bottom(columns)), columns - 9) }
        XCTAssertTrue(bottom(40).contains("━━━━ ") && !bottom(40).contains("━━━━━"))
    }

    func testBarFill() {
        XCTAssertTrue(CrewLine.bar(0, cells: 10) == (0, 10)); XCTAssertTrue(CrewLine.bar(0.4, cells: 10) == (1, 9))
        XCTAssertTrue(CrewLine.bar(22, cells: 10) == (2, 8)); XCTAssertTrue(CrewLine.bar(130, cells: 10) == (10, 0))
    }

    func testHighAndCriticalNumbers() {
        func render(_ percent: Double) -> String {
            input["rate_limits"] = ["five_hour": ["used_percentage": percent]]
            return CrewLine.status(input, columns: 98, plan: nil, look: LeadLook(), now: now)
        }
        let high = render(80)
        XCTAssertTrue(high.contains(CrewLine.Style.yellow + "80%"), high)
        XCTAssertFalse(render(20).contains(CrewLine.Style.yellow))
        let critical = render(96)
        XCTAssertTrue(plain(critical).contains("[96%]"))
        for text in [high, critical, CrewLine.status(self.input, columns: 98, plan: "Max", look: LeadLook(), now: now)] {
            XCTAssertFalse(text.contains("38;2;255;69;59")); XCTAssertFalse(text.contains("38;2;255;255;255"))
        }
    }

    func testMissingPiecesAreSkipped() {
        input["rate_limits"] = nil
        let ctxOnly = lines(98)
        XCTAssertEqual(ctxOnly.count, 2)
        XCTAssertTrue(ctxOnly[1].hasPrefix("context") && !ctxOnly[1].contains("5h") && !ctxOnly[1].contains("7d"))
        let empty = plain(CrewLine.status([:], columns: 98, plan: nil, look: LeadLook(), now: now))
        XCTAssertEqual(empty, "\u{3F015}")
    }

    func testPlanName() {
        XCTAssertEqual(CrewLine.plan(fromClaudeJSON: ["oauthAccount": ["organizationType": "claude_max", "organizationRateLimitTier": "default_claude_max_20x"]]), "Max 20x")
        XCTAssertEqual(CrewLine.plan(fromClaudeJSON: ["oauthAccount": ["organizationType": "claude_pro"]]), "Pro")
        XCTAssertNil(CrewLine.plan(fromClaudeJSON: nil)); XCTAssertNil(CrewLine.plan(fromClaudeJSON: ["oauthAccount": [:]]))
    }

    func testWidthAndCut() {
        XCTAssertEqual(CrewLine.width("\u{3F000}  ab"), 6); XCTAssertEqual(CrewLine.width("กี่"), 1); XCTAssertEqual(CrewLine.width("代码"), 4)
        XCTAssertEqual(CrewLine.width(CrewLine.Style.bold + "ab" + CrewLine.Style.reset), 2)
        XCTAssertEqual(CrewLine.cut("abcdef", to: 4), "abc…"); XCTAssertEqual(CrewLine.cut("代码代码", to: 5), "代码…")
        XCTAssertEqual(CrewLine.width("🚀"), 2); XCTAssertEqual(CrewLine.width("🪐"), 2)
        // Emoji drawn as pictures take two cells, also when U+FE0F asks for the picture.
        XCTAssertEqual(CrewLine.width("✅⭐⚡⏳"), 8); XCTAssertEqual(CrewLine.width("⚠️"), 2); XCTAssertEqual(CrewLine.width("❤️a"), 3)
        XCTAssertEqual(CrewLine.width("1"), 1); XCTAssertEqual(CrewLine.width("#"), 1)
    }

    func task(_ extra: [String: Any] = [:]) -> [String: Any] {
        ["id": "a1", "agentType": "Explore", "status": "running", "description": "Find the login code",
         "label": "Read login.ts", "startTime": (now.timeIntervalSince1970 - 272) * 1000,
         "model": "claude-opus-5-5", "cwd": "/Users/me/agents-visualizer"].merging(extra) { $1 }
    }

    func content(_ tasks: [[String: Any]], columns: Int = 100) -> [String] {
        CrewLine.rows(["tasks": tasks, "columns": columns], now: now, branch: { _ in "main" }).map { line in
            let json = try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            return json["content"] as! String
        }
    }

    func testARowIsThreeLinesLikeThePanel() throws {
        XCTAssertEqual(plain(content([task()])[0]).split(separator: "\n"),
                       ["\u{3F003}  Find the login code  4m 32s  Opus 5.5", "    ▭ agents-visualizer  ⑂ main", "    > Read login.ts"])
        let line = CrewLine.rows(["tasks": [task()]], now: now, branch: { _ in "main" })[0]
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any])["id"] as? String, "a1")
    }

    /// With the font that has them, the folder and branch wear the panel's marks, and a worktree's
    /// branch the panel's worktree mark after it.
    func testThePlaceWearsThePanelsMarks() {
        let (folder, branch, worktree) = (CrewFont.Mark.folder.character, CrewFont.Mark.branch.character, CrewFont.Mark.worktree.character)
        func place(_ worktreeFolder: Bool, branch name: String = "main") -> String {
            let line = CrewLine.rows(["tasks": [task()], "columns": 100], now: now, branch: { _ in name },
                                     newFont: true, worktree: { _ in worktreeFolder })[0]
            let json = try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            return plain(json["content"] as! String).components(separatedBy: "\n")[1]
        }
        XCTAssertEqual(place(false), "    " + folder + "agents-visualizer  " + branch + "main")
        XCTAssertEqual(place(true), "    " + folder + "agents-visualizer  " + branch + "main" + worktree)
        // No branch, no branch mark and no worktree mark, as in the panel.
        XCTAssertEqual(place(true, branch: ""), "    " + folder + "agents-visualizer")
    }

    func testTimeKeepsItsSecondsLikeClaudeCode() {
        XCTAssertEqual(CrewLine.elapsed(45.9), "45s")
        XCTAssertEqual(CrewLine.elapsed(600), "10m 0s")
        XCTAssertEqual(CrewLine.elapsed(623), "10m 23s")
        XCTAssertEqual(CrewLine.elapsed(3723), "1h 2m 3s")
        XCTAssertEqual(CrewLine.elapsed(90_061), "1d 1h 1m")
        let row = content([task(["startTime": (now.timeIntervalSince1970 - 623) * 1000])])[0]
        XCTAssertTrue(plain(row).contains("  10m 23s  "))
    }

    func testNoStepLineBeforeTheAgentStarts() {
        XCTAssertEqual(content([task(["label": "Find the login code"])])[0].components(separatedBy: "\n").count, 2)
    }

    func testWaitingNeedsYou() {
        let row = content([task(["status": "waiting"])])[0]
        XCTAssertTrue(row.contains(CrewLine.Style.needsYou + "needs you"))
        XCTAssertTrue(row.hasPrefix("\u{3F004}"))
    }

    func testFinishedRowsFade() {
        for status in ["completed", "failed", "killed", "idle"] {
            let row = content([task(["status": status])])[0]
            XCTAssertTrue(plain(row).contains("  done  "))
            XCTAssertTrue(plain(row).hasPrefix("\u{3F005}") || row.hasPrefix(CrewLine.Style.faint + "\u{3F005}"))
            for line in row.components(separatedBy: "\n") { XCTAssertTrue(line.hasPrefix(CrewLine.Style.faint)) }
        }
    }

    func testFromThreeAgentsEachRowIsOneLine() {
        XCTAssertTrue(content(Array(repeating: task(), count: 3)).allSatisfy { !$0.contains("\n") })
        XCTAssertTrue(content(Array(repeating: task(), count: 2)).allSatisfy { $0.contains("\n") })
        // Finished agents count too: their rows take room all the same.
        let mixed = [task(), task(["status": "completed"]), task(["status": "completed"])]
        XCTAssertTrue(content(mixed).allSatisfy { !$0.contains("\n") })
    }

    func testOnOneLineTheStepFollowsTheTitle() {
        let tasks = [task(), task(), task(["status": "completed"])]
        let rows = CrewLine.rows(["tasks": tasks, "columns": 100], now: now, branch: { _ in "main" }, step: { _ in "Read MascotView.swift" })
            .map { plain((try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any])["content"] as! String) }
        XCTAssertEqual(rows[0], "\u{3F003}  Find the login code · Read MascotView.swift  4m 32s")
        // Claude Code's label stands in where the transcript says nothing; a finished row has no step.
        XCTAssertTrue(plain(content(tasks)[0]).contains("Find the login code · Read login.ts  "))
        XCTAssertFalse(rows[2].contains("Read"))
        // Short of room, the title gives up its half first, so the step still shows.
        let narrow = CrewLine.rows(["tasks": [task(["description": String(repeating: "x", count: 80)]), task(), task()], "columns": 60],
                                   now: now, branch: { _ in "main" }, step: { _ in "Read MascotView.swift" })[0]
        XCTAssertTrue(plain((try! JSONSerialization.jsonObject(with: Data(narrow.utf8)) as! [String: Any])["content"] as! String).contains("· Read Mascot"))
    }

    func testOnOneLineTheModelShowsOnlyWhenTheAgentsDiffer() {
        XCTAssertTrue(content([task(), task(), task()]).allSatisfy { !plain($0).contains("Opus") })
        let mixed = content([task(), task(), task(["model": "claude-haiku-5-5"])]).map(plain)
        XCTAssertTrue(mixed[0].hasSuffix("  Opus 5.5") && mixed[2].hasSuffix("  Haiku 5.5"), "\(mixed)")
        // With room for more lines, the model stays.
        XCTAssertTrue(plain(content([task(), task()])[0]).contains("  Opus 5.5"))
    }

    func testTheStepLineIsTheTranscriptsLastStep() {
        let row = CrewLine.rows(["tasks": [task()], "columns": 100], now: now, branch: { _ in "main" }, step: { _ in "Grep coffee" })[0]
        XCTAssertTrue(plain(row).contains("> Grep coffee"))
    }

    func testAFinishedRowIsOneLine() {
        let rows = content([task(), task(["status": "completed"])])
        XCTAssertTrue(rows[0].contains("\n"))
        XCTAssertFalse(rows[1].contains("\n"))
    }

    func testOtherTypesWearAShirtFromThePool() {
        let face = CrewFont.character(MascotKind(type: "code-reviewer"), .working)
        XCTAssertTrue(plain(content([task(["agentType": "code-reviewer"])])[0]).hasPrefix(face))
    }

    func testThaiAndChineseDescriptionsAreCutByCells() {
        for text in ["ตรวจสอบโค้ดที่เกี่ยวกับการเข้าสู่ระบบทั้งหมดของแอพพลิเคชัน", "检查所有与登录有关的代码和测试文件"] {
            let lines = content([task(["description": text])], columns: 40)[0].components(separatedBy: "\n")
            XCTAssertTrue(lines.allSatisfy { CrewLine.width($0) <= 34 })
            XCTAssertTrue(lines[0].contains("…"))
        }
    }

    func testEveryLineFitsTheColumns() {
        let long = String(repeating: "x", count: 200)
        let lines = content([task(["description": long, "label": long + "y", "cwd": "/a/" + long])], columns: 50)[0].components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.allSatisfy { CrewLine.width($0) <= 44 })
    }

    func testNoFixedWhite() {
        for status in ["running", "waiting", "completed"] {
            XCTAssertFalse(content([task(["status": status])])[0].contains("38;2;255;255;255"))
        }
    }

    func testControlCharactersInOutsideTextAreDropped() {
        let row = content([task(["description": "a\nb\u{1B}[31mc", "label": "x\ry", "cwd": "/u/f\u{1B}o\u{9B}31m\u{202E}"])])[0]
        let lines = row.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        // A control character stands for a space, so the words either side stay apart.
        XCTAssertEqual(plain(lines[0]).dropFirst(1), "  a b [31mc  4m 32s  Opus 5.5")
        XCTAssertEqual(plain(lines[2]), "    > x y")
        XCTAssertEqual(row.components(separatedBy: "\u{1B}").count, row.components(separatedBy: "\u{1B}[").count)
        XCTAssertFalse(row.contains("\u{1B}o"))
        XCTAssertFalse(row.contains("\u{9B}")); XCTAssertFalse(row.contains("\u{202E}"))
    }

    func testOddTextNeverLeavesABlankTitleOrHiddenMarks() {
        let blank = content([task(["description": " \n\t ", "label": ""])])[0]
        XCTAssertTrue(plain(blank).dropFirst(1).hasPrefix("  Explore  "))
        let marked = content([task(["description": "Fix\u{2028}it\u{200F}\u{200E}\u{061C} now", "label": ""])])[0]
        XCTAssertTrue(plain(marked).dropFirst(1).hasPrefix("  Fix it now  "))
    }

    func testBranchFromGit() throws {
        let root = NSTemporaryDirectory() + "crewbranch-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/repo/.git/worktrees/w", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/repo/sub/dir", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/w", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/bare/.git", withIntermediateDirectories: true)
        try "ref: refs/heads/feature/x\n".write(toFile: root + "/repo/.git/HEAD", atomically: true, encoding: .utf8)
        try "ref: refs/heads/w\n".write(toFile: root + "/repo/.git/worktrees/w/HEAD", atomically: true, encoding: .utf8)
        try "gitdir: ../repo/.git/worktrees/w\n".write(toFile: root + "/w/.git", atomically: true, encoding: .utf8)
        try "0123456789abcdef0123456789abcdef01234567\n".write(toFile: root + "/bare/.git/HEAD", atomically: true, encoding: .utf8)
        XCTAssertEqual(CrewLine.branch(of: root + "/repo/sub/dir"), "feature/x")
        XCTAssertEqual(CrewLine.branch(of: root + "/w"), "w")
        XCTAssertEqual(CrewLine.branch(of: root + "/bare"), "")
        XCTAssertEqual(CrewLine.branch(of: "/"), "")
    }

    func testCutInNoRoomAndStrayEscape() {
        XCTAssertEqual(CrewLine.cut("abc", to: 0), "")
        XCTAssertEqual(CrewLine.width("a\u{1B}bc"), 4)
    }

    func testSaraAmTakesItsOwnCell() {
        XCTAssertEqual(CrewLine.width("น้ำทำ"), 4); XCTAssertEqual(CrewLine.width("กี่"), 1)
        let text = String(repeating: "ทำความสำคัญน้ำทำงานซ้ำคำนำทำนองจำนำ", count: 4)
        let lines = content([task(["description": text])], columns: 40)[0].components(separatedBy: "\n")
        XCTAssertTrue(lines.allSatisfy { CrewLine.width($0) <= 34 })
        XCTAssertTrue(lines[0].contains("…"))
    }

    func testOddStartTimesDoNotCrash() {
        for start in [-1e300, 1e300] { XCTAssertEqual(content([task(["startTime": start])]).count, 1) }
    }

    func testTinyColumnsStillFit() {
        let lines = content([task()], columns: 12)[0].components(separatedBy: "\n")
        XCTAssertTrue(lines.allSatisfy { CrewLine.width($0) <= 6 })
    }

    func top(look: LeadLook? = LeadLook(), atWork: Bool = false, newFont: Bool = true, plan: String? = "Max 20x") -> String {
        plain(CrewLine.status(input, columns: 102, plan: plan, look: look, atWork: atWork, newFont: newFont, now: now))
            .components(separatedBy: "\n")[0]
    }

    // A session the app has given no lead yet: nobody has sat down, and the bar's mug waits.
    func testNoLookShowsTheMugOnStandby() {
        XCTAssertEqual(top(look: nil), CrewFont.Picture.mug.character + "  Opus 5.5 · Max 20x · On standby")
        XCTAssertEqual(top(look: nil, plan: nil), CrewFont.Picture.mug.character + "  Opus 5.5 · On standby")
        input["model"] = nil
        XCTAssertEqual(top(look: nil, plan: nil), CrewFont.Picture.mug.character + "  On standby")
    }

    // A limit run out sends the crew off, as on the bar: fishing for the 5 hours, the van for the week.
    func testARunOutLimitSendsTheCrewOff() {
        input["rate_limits"] = ["five_hour": ["used_percentage": 100.0, "resets_at": now.timeIntervalSince1970 + 600],
                                "seven_day": ["used_percentage": 70.0, "resets_at": now.timeIntervalSince1970 + 226_830]]
        XCTAssertEqual(top(), CrewFont.Picture.fish.character + "  Opus 5.5 · Max 20x · Gone fishin\u{2019}")
        XCTAssertEqual(top(look: nil), CrewFont.Picture.fish.character + "  Opus 5.5 · Max 20x · Gone fishin\u{2019}")
        // Both out: the one back last.
        input["rate_limits"] = ["five_hour": ["used_percentage": 100.0, "resets_at": now.timeIntervalSince1970 + 600],
                                "seven_day": ["used_percentage": 100.0, "resets_at": now.timeIntervalSince1970 + 226_830]]
        XCTAssertEqual(top(), CrewFont.Picture.van.character + "  Opus 5.5 · Max 20x · On vacation")
        // Someone works on past the limit: the face stays.
        XCTAssertEqual(top(atWork: true), "\u{3F015}  Opus 5.5 · Max 20x")
        // Past its reset it is back, whatever the last numbers said.
        input["rate_limits"] = ["five_hour": ["used_percentage": 100.0, "resets_at": now.timeIntervalSince1970 - 1]]
        XCTAssertEqual(top(), "\u{3F015}  Opus 5.5 · Max 20x")
    }

    // A terminal that has not seen the new font gets faces only, Sunny where there is no look.
    func testAnOldFontGetsFacesAndNoWords() {
        XCTAssertEqual(top(look: nil, newFont: false), "\u{3F015}  Opus 5.5 · Max 20x")
        input["rate_limits"] = ["seven_day": ["used_percentage": 100.0, "resets_at": now.timeIntervalSince1970 + 600]]
        XCTAssertEqual(top(look: LeadLook(face: 3, hair: 5, shirt: 6), newFont: false), "\u{3F0BC}  Opus 5.5 · Max 20x")
    }

    // The lead and each working sub-agent hold what the notch has them hold.
    func testTheFaceHoldsWhatTheAgentIsDoing() {
        let top = plain(CrewLine.status(input, columns: 98, plan: nil, look: LeadLook(), holding: .typing, now: now))
        XCTAssertTrue(top.hasPrefix(CrewFont.character(.lead(LeadLook()), .working, holding: .typing)), top)
        let rows = CrewLine.rows(["tasks": [task(), task(["id": "a2", "status": "waiting"])], "columns": 100], now: now,
                                 branch: { _ in "main" }, holding: { _ in .searching })
            .map { (try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any])["content"] as! String }
        XCTAssertTrue(rows[0].hasPrefix(CrewFont.character(.explore, .working, holding: .searching)))
        XCTAssertTrue(rows[1].hasPrefix("\u{3F004}"), "nothing in hand while it calls the person")
    }

    // What an agent is doing, read off the end of its transcript.
    func testTheTranscriptSaysWhatIsInHand() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("crew-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let at = "2026-10-12T02:00:05.000Z", then = Date(timeIntervalSince1970: 1_791_684_010)
        let call = #"{"type":"assistant","timestamp":"\#(at)","message":{"model":"claude-haiku-5-5","content":[{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}"#
        let result = #"{"type":"user","timestamp":"\#(at)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#
        let answer = #"{"type":"assistant","timestamp":"\#(at)","message":{"model":"claude-haiku-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"Done."}]}}"#
        func after(_ lines: String...) throws -> Activity? {
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
            return CrewLine.activity(transcript: file, now: then)
        }
        XCTAssertEqual(try after(call), .reading)
        XCTAssertEqual(try after(call, result), .thinking)
        XCTAssertNil(try after(call, result, answer))
        // Two minutes without a line: quiet, and the mascot holds nothing.
        XCTAssertNil(CrewLine.activity(transcript: file, now: then + 600))
        // A long file is read from its end, a line cut in half at the front left out.
        XCTAssertEqual(try after(String(repeating: "x", count: Int(CrewLine.tail)), call), .reading)
        XCTAssertNil(CrewLine.activity(transcript: file.appendingPathExtension("missing"), now: then))
    }

    // A row names the call still open, not one already answered; with none open it thinks.
    func testARowSaysTheCallStillOpen() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("crew-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let at = "2026-10-12T02:00:05.000Z", then = Date(timeIntervalSince1970: 1_791_684_010)
        let calls = #"{"type":"assistant","timestamp":"\#(at)","message":{"model":"claude-haiku-5-5","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a/login.ts"}},{"type":"tool_use","id":"t2","name":"Grep","input":{"pattern":"session"}}]}}"#
        func result(_ id: String) -> String {
            #"{"type":"user","timestamp":"\#(at)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"ok"}]}}"#
        }
        func doing(_ lines: String...) throws -> String? {
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
            return CrewLine.openTurn(transcript: file, now: then).map(CrewLine.doing)
        }
        XCTAssertEqual(try doing(calls), "Grep session")
        XCTAssertEqual(try doing(calls, result("t2")), "Read login.ts")
        XCTAssertEqual(try doing(calls, result("t2"), result("t1")), "Thinking")
    }

    func testSubAgentTranscriptsAreFoundByTheirRowID() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("crew-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("s1/subagents/workflows/w1")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for url in [root.appendingPathComponent("s1/subagents/agent-a1.jsonl"), nested.appendingPathComponent("agent-a2.jsonl"),
                    root.appendingPathComponent("s1/subagents/agent-a1.meta.json")] {
            try Data().write(to: url)
        }
        let found = CrewLine.agentTranscripts(session: root.appendingPathComponent("s1.jsonl"))
        XCTAssertEqual(Set(found.keys), ["a1", "a2"])
        XCTAssertEqual(found["a2"]?.lastPathComponent, "agent-a2.jsonl")
    }
}
