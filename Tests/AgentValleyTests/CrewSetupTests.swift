import XCTest
@testable import AgentValley

/// `crew install` and `crew uninstall` edit files people care about. Every test works in a home
/// of its own under the temp folder, never in the real `~/.claude`, `~/Library/Fonts` or Ghostty's config.
final class CrewSetupTests: XCTestCase {
    let exe = "/opt/homebrew/opt/agent-valley/AgentValley.app/Contents/MacOS/AgentValley"
    var home: URL!
    var font: URL!
    let files = FileManager.default

    override func setUpWithError() throws {
        home = files.temporaryDirectory.appendingPathComponent("crew-" + UUID().uuidString)
        try files.createDirectory(at: home, withIntermediateDirectories: true)
        font = home.appendingPathComponent("bundled.ttf")
        try Data("the font".utf8).write(to: font)
    }

    override func tearDownWithError() throws {
        try? files.removeItem(at: home)
    }

    func url(_ path: String) -> URL { home.appendingPathComponent(path) }
    var settingsURL: URL { url(".claude/settings.json") }
    var installedFont: URL { url("Library/Fonts/AgentValleyCrew.ttf") }
    var backup: URL { url("Library/Application Support/AgentValley/crew-backup.json") }
    let appSupportConfig = "Library/Application Support/com.mitchellh.ghostty/config"

    func write(_ text: String, to path: String) throws {
        try files.createDirectory(at: url(path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url(path))
    }

    func read(_ path: String) -> String? {
        (try? Data(contentsOf: url(path))).map { String(decoding: $0, as: UTF8.self) }
    }

    func settings(_ file: URL? = nil) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: file ?? settingsURL)) as! [String: Any]
    }

    @discardableResult
    func install(_ environment: [String: String] = [:], apps: [URL] = []) throws -> String {
        try CrewSetup.install(home: home, environment: environment, executable: exe, font: font, ghosttyApps: apps)
    }

    @discardableResult
    func uninstall(_ environment: [String: String] = [:]) throws -> String {
        try CrewSetup.uninstall(home: home, environment: environment)
    }

    func testInstallIntoAFreshHome() throws {
        let message = try install()
        let settings = try settings()
        XCTAssertEqual(settings["statusLine"] as? NSDictionary,
                       ["type": "command", "command": "'\(exe)' crew status", "padding": 1, "refreshInterval": 30] as NSDictionary)
        XCTAssertEqual(settings["subagentStatusLine"] as? NSDictionary, ["type": "command", "command": "'\(exe)' crew agents"] as NSDictionary)
        XCTAssertEqual(try Data(contentsOf: installedFont), try Data(contentsOf: font))
        XCTAssertTrue(message.hasPrefix("The crew is in. Start Claude Code again to see us under the prompt."), message)
        XCTAssertFalse(message.contains("Ghostty"))
        XCTAssertFalse(message.contains("old status line"))
        // Written the way the plan says: sorted, slashes as they are, a newline at the end.
        let text = try XCTUnwrap(read(".claude/settings.json"))
        XCTAssertTrue(text.hasSuffix("}\n"))
        XCTAssertTrue(text.contains("/opt/homebrew/opt/agent-valley"))
    }

    func testInstallKeepsOtherKeysAndTheOldStatusLine() throws {
        try write(#"{"model": "opus", "statusLine": {"type": "command", "command": "mine.sh"}}"#, to: ".claude/settings.json")
        let message = try install()
        XCTAssertEqual(try settings()["model"] as? String, "opus")
        XCTAssertTrue(message.contains("Your old status line is saved and comes back if you take the crew out."), message)

        let out = try uninstall()
        let settings = try settings()
        XCTAssertEqual(settings["statusLine"] as? NSDictionary, ["type": "command", "command": "mine.sh"] as NSDictionary)
        XCTAssertNil(settings["subagentStatusLine"])
        XCTAssertEqual(settings["model"] as? String, "opus")
        XCTAssertFalse(files.fileExists(atPath: installedFont.path))
        XCTAssertFalse(files.fileExists(atPath: backup.path))
        XCTAssertTrue(out.hasPrefix("The crew is out of the terminal. Start Claude Code again."), out)
        XCTAssertTrue(out.contains("Your old status line is back."), out)
    }

    func testInstallingTwiceKeepsTheFirstBackupAndOneGhosttyLine() throws {
        try write(#"{"statusLine": {"type": "command", "command": "mine.sh"}}"#, to: ".claude/settings.json")
        try write("theme = x\n", to: ".config/ghostty/config")
        let first = try install()
        XCTAssertTrue(first.contains("Ghostty: added our font line to \(url(".config/ghostty/config").path). Quit and reopen Ghostty to see our faces."), first)
        try install()
        let ghostty = try XCTUnwrap(read(".config/ghostty/config"))
        XCTAssertEqual(ghostty.components(separatedBy: "\n").filter { $0.hasPrefix("font-codepoint-map") }, [CrewSetup.ghosttyLines[1]])
        XCTAssertEqual(ghostty.components(separatedBy: "\n").filter { $0.hasPrefix("# AgentValley") }, [CrewSetup.ghosttyLines[0]])

        let out = try uninstall()
        XCTAssertEqual(try settings()["statusLine"] as? NSDictionary, ["type": "command", "command": "mine.sh"] as NSDictionary)
        XCTAssertEqual(read(".config/ghostty/config"), "theme = x\n")
        XCTAssertTrue(out.contains("Ghostty: removed our font line from \(url(".config/ghostty/config").path). Quit and reopen Ghostty."), out)
    }

    func testUnreadableSettingsChangeNothing() throws {
        try write("{ not json", to: ".claude/settings.json")
        try write("theme = x\n", to: ".config/ghostty/config")
        XCTAssertThrowsError(try install()) { error in
            XCTAssertEqual(error as? CrewSetup.Failure, .unreadableSettings(self.settingsURL.path))
        }
        XCTAssertEqual(read(".claude/settings.json"), "{ not json")
        XCTAssertEqual(read(".config/ghostty/config"), "theme = x\n")
        XCTAssertFalse(files.fileExists(atPath: installedFont.path))
        XCTAssertFalse(files.fileExists(atPath: backup.path))
        XCTAssertThrowsError(try uninstall()) { error in
            XCTAssertEqual(error as? CrewSetup.Failure, .unreadableSettings(self.settingsURL.path))
        }
        XCTAssertEqual(read(".claude/settings.json"), "{ not json")
        // JSON that is not an object is refused just the same.
        try write("[1, 2]", to: ".claude/settings.json")
        XCTAssertThrowsError(try install())
        XCTAssertEqual(read(".claude/settings.json"), "[1, 2]")
    }

    func testABlankSettingsFileCountsAsEmpty() throws {
        try write(" \n", to: ".claude/settings.json")
        try install()
        XCTAssertNotNil(try settings()["statusLine"])
    }

    func testMissingFontChangesNothing() throws {
        try files.removeItem(at: font)
        XCTAssertThrowsError(try install()) { error in
            XCTAssertEqual(error as? CrewSetup.Failure, .missingFont)
        }
        XCTAssertFalse(files.fileExists(atPath: settingsURL.path))
        XCTAssertFalse(files.fileExists(atPath: backup.path))
    }

    func testASymlinkedSettingsFileStaysALink() throws {
        // Relative, the way GNU Stow and most dotfile tools make it.
        try write(#"{"model": "opus"}"#, to: "dotfiles/settings.json")
        try files.createDirectory(at: url(".claude"), withIntermediateDirectories: true)
        try files.createSymbolicLink(atPath: settingsURL.path, withDestinationPath: "../dotfiles/settings.json")
        try install()
        XCTAssertEqual(try files.destinationOfSymbolicLink(atPath: settingsURL.path), "../dotfiles/settings.json")
        XCTAssertNotNil(try settings(url("dotfiles/settings.json"))["statusLine"])
        XCTAssertEqual(try settings(url("dotfiles/settings.json"))["model"] as? String, "opus")
        try uninstall()
        XCTAssertEqual(try files.destinationOfSymbolicLink(atPath: settingsURL.path), "../dotfiles/settings.json")
        XCTAssertNil(try settings(url("dotfiles/settings.json"))["statusLine"])
    }

    func testUninstallLeavesAStatusLineTheUserChangedSince() throws {
        try install()
        var changed = try settings()
        changed["statusLine"] = ["type": "command", "command": "other.sh"]
        try JSONSerialization.data(withJSONObject: changed).write(to: settingsURL)
        let out = try uninstall()
        XCTAssertEqual(try settings()["statusLine"] as? NSDictionary, ["type": "command", "command": "other.sh"] as NSDictionary)
        XCTAssertNil(try settings()["subagentStatusLine"])
        XCTAssertFalse(out.contains("Your old status line is back."))
    }

    func testClaudeConfigDir() throws {
        let environment = ["CLAUDE_CONFIG_DIR": url("alt").path]
        try install(environment)
        XCTAssertNotNil(try settings(url("alt/settings.json"))["statusLine"])
        XCTAssertFalse(files.fileExists(atPath: settingsURL.path))
        try uninstall(environment)
        XCTAssertNil(try settings(url("alt/settings.json"))["statusLine"])
    }

    func testTwoConfigFoldersKeepTheirOwnOldStatusLines() throws {
        let b = ["CLAUDE_CONFIG_DIR": url("B").path]
        try write(#"{"statusLine": {"type": "command", "command": "mine.sh"}}"#, to: ".claude/settings.json")
        try write(#"{"statusLine": {"type": "command", "command": "work.sh"}}"#, to: "B/settings.json")
        try write("theme = x\n", to: ".config/ghostty/config")
        try install()
        // Taking the crew out of a folder it was never put in changes nothing.
        let backupBytes = try Data(contentsOf: backup)
        try uninstall(["CLAUDE_CONFIG_DIR": url("C").path])
        XCTAssertEqual(try Data(contentsOf: backup), backupBytes)
        XCTAssertTrue(files.fileExists(atPath: installedFont.path))

        try install(b)
        let first = try uninstall()
        XCTAssertEqual(try settings()["statusLine"] as? NSDictionary, ["type": "command", "command": "mine.sh"] as NSDictionary)
        XCTAssertTrue(first.contains("Your old status line is back."), first)
        XCTAssertFalse(first.contains("Ghostty"), first)
        // B still runs the crew, so what it shares stays.
        XCTAssertTrue(files.fileExists(atPath: installedFont.path))
        XCTAssertTrue(files.fileExists(atPath: backup.path))
        XCTAssertTrue(read(".config/ghostty/config")!.contains(CrewSetup.ghosttyLines[1]))
        XCTAssertTrue(((try settings(url("B/settings.json"))["statusLine"] as? [String: Any])?["command"] as? String)?.hasSuffix(" crew status") == true)

        try uninstall(b)
        XCTAssertEqual(try settings(url("B/settings.json"))["statusLine"] as? NSDictionary, ["type": "command", "command": "work.sh"] as NSDictionary)
        XCTAssertEqual(try settings()["statusLine"] as? NSDictionary, ["type": "command", "command": "mine.sh"] as NSDictionary)
        XCTAssertFalse(files.fileExists(atPath: installedFont.path))
        XCTAssertFalse(files.fileExists(atPath: backup.path))
        XCTAssertEqual(read(".config/ghostty/config"), "theme = x\n")
    }

    func testAnUnreadableBackupChangesNothing() throws {
        try write(#"{"statusLine": {"type": "command", "command": "mine.sh"}}"#, to: ".claude/settings.json")
        try write("theme = x\n", to: ".config/ghostty/config")
        try install()
        let before = try [settingsURL, installedFont, url(".config/ghostty/config")].map { try Data(contentsOf: $0) }
        for broken in ["{ not json", #"{"somewhere": "not an object"}"#] {
            try write(broken, to: "Library/Application Support/AgentValley/crew-backup.json")
            XCTAssertThrowsError(try install()) { error in
                XCTAssertEqual(error as? CrewSetup.Failure, .unreadableSettings(self.backup.path))
            }
            XCTAssertThrowsError(try uninstall()) { error in
                XCTAssertEqual(error as? CrewSetup.Failure, .unreadableSettings(self.backup.path))
            }
            XCTAssertEqual(try [settingsURL, installedFont, url(".config/ghostty/config")].map { try Data(contentsOf: $0) }, before)
            XCTAssertEqual(read("Library/Application Support/AgentValley/crew-backup.json"), broken)
        }
    }

    func testALinkedClaudeFolderWithARelativeLinkInside() throws {
        // ~/.claude is a link to dotfiles/claude, and its settings.json a link to ../shared/settings.json:
        // read beside the real folder, that is dotfiles/shared, not a new file beside the link.
        try write(#"{"model": "opus"}"#, to: "dotfiles/shared/settings.json")
        try files.createDirectory(at: url("dotfiles/claude"), withIntermediateDirectories: true)
        try files.createSymbolicLink(atPath: url(".claude").path, withDestinationPath: "dotfiles/claude")
        try files.createSymbolicLink(atPath: url("dotfiles/claude/settings.json").path, withDestinationPath: "../shared/settings.json")
        try install()
        XCTAssertEqual(try settings(url("dotfiles/shared/settings.json"))["model"] as? String, "opus")
        XCTAssertNotNil(try settings(url("dotfiles/shared/settings.json"))["statusLine"])
        XCTAssertFalse(files.fileExists(atPath: url("shared").path))
        XCTAssertEqual(try files.destinationOfSymbolicLink(atPath: url("dotfiles/claude/settings.json").path), "../shared/settings.json")
        try uninstall()
        XCTAssertNil(try settings(url("dotfiles/shared/settings.json"))["statusLine"])
        XCTAssertFalse(files.fileExists(atPath: backup.path))
    }

    func testThePlanIsReadWhereClaudeCodeKeepsIt() {
        XCTAssertEqual(CrewSetup.claudeJSON(home: home, environment: [:]).path, url(".claude.json").path)
        XCTAssertEqual(CrewSetup.claudeJSON(home: home, environment: ["CLAUDE_CONFIG_DIR": ""]).path, url(".claude.json").path)
        XCTAssertEqual(CrewSetup.claudeJSON(home: home, environment: ["CLAUDE_CONFIG_DIR": url("alt").path]).path, url("alt/.claude.json").path)
    }

    func testGhosttyWithoutAConfigGetsOne() throws {
        let message = try install(apps: [url("Nowhere/Ghostty.app")])
        XCTAssertFalse(message.contains("Ghostty"))
        XCTAssertFalse(files.fileExists(atPath: url("Library/Application Support/com.mitchellh.ghostty").path))

        try files.createDirectory(at: url("Applications/Ghostty.app"), withIntermediateDirectories: true)
        let second = try install(apps: [url("Nowhere/Ghostty.app"), url("Applications/Ghostty.app")])
        XCTAssertEqual(read(appSupportConfig), CrewSetup.ghosttyLines.joined(separator: "\n") + "\n")
        XCTAssertTrue(second.contains("Ghostty: added our font line to \(url(appSupportConfig).path)."), second)
    }

    func draws(_ environment: [String: String], openedAt start: Date? = .distantFuture) -> Bool {
        CrewSetup.drawsThingsInHand(home: home, environment: environment, bundled: font, terminalStart: start)
    }

    // The map line of earlier versions stops short of the faces with things in hand. Install
    // puts today's in its place; until then the status line holds nothing back in Ghostty.
    func testInstallWidensTheOldGhosttyLineWhereItStands() throws {
        let old = "theme = x\n" + CrewSetup.ghosttyLines[0] + "\n" + CrewSetup.oldGhosttyLines[0] + "\nfont-size = 13\n"
        try write(old, to: ".config/ghostty/config")
        try write("the font", to: "Library/Fonts/AgentValleyCrew.ttf")
        let ghostty = ["TERM_PROGRAM": "ghostty"]
        XCTAssertFalse(draws(ghostty))
        XCTAssertTrue(draws(["TERM_PROGRAM": "Apple_Terminal"]))
        try install()
        XCTAssertEqual(read(".config/ghostty/config"), "theme = x\n" + CrewSetup.ghosttyLines.joined(separator: "\n") + "\nfont-size = 13\n")
        XCTAssertTrue(draws(ghostty))

        // Uninstall takes the old line out too.
        try write(old, to: ".config/ghostty/config")
        try uninstall()
        XCTAssertEqual(read(".config/ghostty/config"), "theme = x\nfont-size = 13\n")
    }

    // After an update the app widens the old line by itself, and touches no config without it.
    func testTheAppWidensOnlyItsOwnOldGhosttyLine() throws {
        let old = "theme = x\n" + CrewSetup.ghosttyLines[0] + "\n" + CrewSetup.oldGhosttyLines[0] + "\nfont-size = 13"
        try write(old, to: appSupportConfig)
        try write("a = 1\n", to: ".config/ghostty/config")
        CrewSetup.refreshGhosttyLine(home: home, environment: [:])
        XCTAssertEqual(read(appSupportConfig), "theme = x\n" + CrewSetup.ghosttyLines.joined(separator: "\n") + "\nfont-size = 13")
        XCTAssertEqual(read(".config/ghostty/config"), "a = 1\n")
        CrewSetup.refreshGhosttyLine(home: home, environment: [:])
        XCTAssertEqual(read(appSupportConfig), "theme = x\n" + CrewSetup.ghosttyLines.joined(separator: "\n") + "\nfont-size = 13")
    }

    // The name tags ask Ghostty's config by the terminal the hook names: a Ghostty without our
    // font line would draw each tag as boxes, so its sessions get plain names.
    func testNameTagsAskGhosttysConfigByTheTerminalTheHookNames() throws {
        try write("the font", to: "Library/Fonts/AgentValleyCrew.ttf")
        try files.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: installedFont.path)
        func tags(_ terminal: String?, pid: Int32? = getpid()) -> Bool {
            AgentStore.terminalDrawsTags(CrewIntroRequest(event: "SessionStart", session: "s", cwd: "/", agentType: "", pid: pid, terminal: terminal),
                                         home: home, bundled: font)
        }
        XCTAssertTrue(tags("Apple_Terminal"))
        XCTAssertFalse(tags("ghostty"))
        try write(CrewSetup.ghosttyLines.joined(separator: "\n") + "\n", to: ".config/ghostty/config")
        XCTAssertTrue(tags("ghostty"))
        XCTAssertFalse(tags(nil, pid: nil), "no Claude Code process to find the terminal by")
    }

    // A terminal keeps the fonts it has seen until it quits: a face the old font lacks would be
    // an empty box. Things in hand wait for this app's font and a terminal opened after it.
    func testThingsInHandWaitForTheFontAndATerminalOpenedAfterIt() throws {
        let terminal = ["TERM_PROGRAM": "Apple_Terminal"]
        XCTAssertFalse(draws(terminal), "no font installed")
        try write("an older font", to: "Library/Fonts/AgentValleyCrew.ttf")
        XCTAssertFalse(draws(terminal), "the font of an older version")
        CrewSetup.refreshFont(home: home, bundled: font)
        let placed = try XCTUnwrap(files.attributesOfItem(atPath: installedFont.path)[.modificationDate] as? Date)
        XCTAssertFalse(draws(terminal, openedAt: placed.addingTimeInterval(-60)), "opened before the font")
        XCTAssertFalse(draws(terminal, openedAt: nil), "unknown")
        XCTAssertTrue(draws(terminal, openedAt: placed.addingTimeInterval(1)))
    }

    func testTheTerminalOpenedBeforeThisProcess() throws {
        let start = try XCTUnwrap(CrewCommand.terminalStart())
        XCTAssertLessThanOrEqual(start, Date())
        XCTAssertGreaterThan(start, Date(timeIntervalSince1970: 1_000_000_000))
    }

    func testGhosttyPrefersItsOwnOrder() throws {
        try write("a = 1", to: ".config/ghostty/config")
        try write("b = 2\n", to: "xdg/ghostty/config")
        // XDG_CONFIG_HOME stands in for ~/.config.
        try install(["XDG_CONFIG_HOME": url("xdg").path])
        XCTAssertEqual(read("xdg/ghostty/config"), "b = 2\n" + CrewSetup.ghosttyLines.joined(separator: "\n") + "\n")
        XCTAssertEqual(read(".config/ghostty/config"), "a = 1")

        // The App Support file comes before either.
        try write("c = 3\n", to: "Library/Application Support/com.mitchellh.ghostty/config.ghostty")
        try install()
        XCTAssertEqual(read("Library/Application Support/com.mitchellh.ghostty/config.ghostty"), "c = 3\n" + CrewSetup.ghosttyLines.joined(separator: "\n") + "\n")
        XCTAssertEqual(read(".config/ghostty/config"), "a = 1")

        // Taking the crew out cleans every file in the list.
        try uninstall(["XDG_CONFIG_HOME": url("xdg").path])
        XCTAssertEqual(read("xdg/ghostty/config"), "b = 2\n")
        XCTAssertEqual(read("Library/Application Support/com.mitchellh.ghostty/config.ghostty"), "c = 3\n")
    }

    func testRefreshFontReplacesOnlyAnInstalledOldCopy() throws {
        CrewSetup.refreshFont(home: home, bundled: font)
        XCTAssertFalse(files.fileExists(atPath: installedFont.path))
        try write("an older font", to: "Library/Fonts/AgentValleyCrew.ttf")
        CrewSetup.refreshFont(home: home, bundled: font)
        XCTAssertEqual(try Data(contentsOf: installedFont), try Data(contentsOf: font))
    }

    func testLeadLooksRoundTrip() {
        let data = CrewSetup.leadLooksData(["abc": LeadLook(face: 3, hair: 5, shirt: 6), "other": LeadLook(face: 1, hair: 0, shirt: 2)])
        XCTAssertEqual(CrewSetup.look(for: "abc", in: data), LeadLook(face: 3, hair: 5, shirt: 6))
        XCTAssertEqual(CrewSetup.look(for: "other", in: data), LeadLook(face: 1, hair: 0, shirt: 2))
        // No look given: before the first prompt, put away, or the app closed.
        XCTAssertNil(CrewSetup.look(for: "zzz", in: data))
        XCTAssertNil(CrewSetup.look(for: "abc", in: nil))
        XCTAssertNil(CrewSetup.look(for: "abc", in: Data("x".utf8)))
        // A negative number would index before the font's first face.
        XCTAssertNil(CrewSetup.look(for: "abc", in: Data(#"{"abc": [-1, 0, 0]}"#.utf8)))
        XCTAssertEqual(CrewSetup.look(for: "abc", in: Data(#"{"abc": [1, 2, 3]}"#.utf8)), LeadLook(face: 1, hair: 2, shirt: 3))
    }

    func mode(_ url: URL) throws -> Int {
        try XCTUnwrap(files.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    /// The socket of "Answer from the notch" shares the app's folder and refuses one other accounts can enter.
    func testInstallMakesTheAppFolderPrivate() throws {
        try install()
        XCTAssertEqual(try mode(CrewSetup.folder(home)) & 0o077, 0)
    }

    func testTheLeadLooksFolderIsPrivate() throws {
        let data = CrewSetup.leadLooksData(["abc": LeadLook()])
        try CrewSetup.writeLeadLooks(data, home: home)
        XCTAssertEqual(try mode(CrewSetup.folder(home)) & 0o077, 0)
        XCTAssertEqual(try Data(contentsOf: CrewSetup.folder(home).appendingPathComponent(CrewSetup.leadLooksName)), data)
    }

    /// `.claude.json` runs to megabytes, so only the account's object is cut out and parsed. The
    /// noise before it has braces, escaped quotes and the key itself inside strings.
    func testThePlanIsCutOutOfALargeClaudeJSON() throws {
        let noise = (0..<2000).map { #""/p/\#($0)": {"note": "a { b } c \"q\" \"oauthAccount\": {", "n": [1, {"x": "}"}]}"# }.joined(separator: ", ")
        let account = #"{"organizationType": "claude_max", "organizationRateLimitTier": "default_claude_max_20x", "odd": "a } \" {"}"#
        let file = Data(#"{"projects": {\#(noise)}, "oauthAccount": \#(account), "after": 1}"#.utf8)
        XCTAssertNotNil(SafeJSON.object(file))
        let found = try XCTUnwrap(CrewSetup.oauthAccount(in: file))
        XCTAssertEqual(found as NSDictionary, SafeJSON.object(Data(account.utf8))! as NSDictionary)
        XCTAssertEqual(CrewLine.plan(fromClaudeJSON: ["oauthAccount": found]), "Max 20x")
        XCTAssertNil(CrewSetup.oauthAccount(in: Data(#"{"projects": {\#(noise)}}"#.utf8)))
        XCTAssertNil(CrewSetup.oauthAccount(in: Data(#"{"oauthAccount": {"organizationType": "claude_max", "x": {"#.utf8)))
        // A null account is no plan, never the next object along.
        XCTAssertNil(CrewSetup.oauthAccount(in: Data(#"{"oauthAccount": null, "x": {"organizationType": "claude_max"}}"#.utf8)))
    }

    // MARK: The binary itself

    /// The AgentValley executable that `swift test` builds next to the test bundle.
    var binary: URL { Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("AgentValley") }

    func run(_ arguments: [String], input: String = "", columns: String? = nil) throws -> (lines: [String], status: Int32) {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["crew"] + arguments
        // The app finds Sparkle in Contents/Frameworks; the bare binary swift test leaves, beside itself.
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "COLUMNS": columns,
                               "DYLD_FRAMEWORK_PATH": binary.deletingLastPathComponent().path].compactMapValues { $0 }
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: deadline)
        // Nothing is written to a command that may already have gone: that pipe would raise SIGPIPE here.
        if !input.isEmpty { stdin.fileHandleForWriting.write(Data(input.utf8)) }
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        XCTAssertEqual(process.terminationReason, .exit, "crew \(arguments) did not exit on its own within 10 seconds")
        return (String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init), process.terminationStatus)
    }

    func testTheBinaryAnswersAsAStatusLine() throws {
        guard files.isExecutableFile(atPath: binary.path) else {
            return XCTFail("swift test did not leave the AgentValley binary at \(binary.path)")
        }
        let input = #"{"model": {"display_name": "Opus 5.5"}, "session_id": "s1", "context_window": {"used_percentage": 22, "context_window_size": 1000000}, "rate_limits": {"five_hour": {"used_percentage": 6, "resets_at": 1800009750}}}"#
        let status = try run(["status"], input: input, columns: "98")
        XCTAssertEqual(status.status, 0)
        XCTAssertTrue(status.lines.first?.hasPrefix("\u{3F015}") == true, "\(status.lines)")
        XCTAssertEqual(status.lines.count, 2)

        // The look the app wrote for this session, found by its id.
        try write(#"{"s1": [1, 2, 3]}"#, to: "Library/Application Support/AgentValley/crew-leads.json")
        let lead = try run(["status"], input: input, columns: "98")
        XCTAssertTrue(lead.lines.first?.hasPrefix(CrewFont.character(.lead(LeadLook(face: 1, hair: 2, shirt: 3)), .working)) == true, "\(lead.lines)")

        // The plan, from the account in Claude Code's own file.
        try write(#"{"projects": {}, "oauthAccount": {"organizationType": "claude_pro"}}"#, to: ".claude.json")
        XCTAssertTrue(try run(["status"], input: input, columns: "98").lines.first?.contains(" · Pro") == true)

        let garbage = try run(["status"], input: "garbage")
        XCTAssertEqual(garbage.status, 0)
        XCTAssertEqual(garbage.lines.count, 1)

        let tasks = #"{"columns": 100, "tasks": [{"id": "a1", "description": "Find the login code", "status": "running"}, {"id": "a2", "description": "Plan it", "status": "completed"}]}"#
        let agents = try run(["agents"], input: tasks)
        XCTAssertEqual(agents.status, 0)
        XCTAssertEqual(agents.lines.compactMap { SafeJSON.object(Data($0.utf8))?["id"] as? String }, ["a1", "a2"])

        XCTAssertEqual(try run(["nope"]).status, 2)
        XCTAssertEqual(try run([]).status, 2)
    }
}
