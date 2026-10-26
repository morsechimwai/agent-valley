import XCTest
@testable import AgentValley

final class PluginPlaceTests: XCTestCase {
    /// Claude Code's list of marketplaces, as `claude plugin marketplace add` writes it for a folder.
    static func registry(agentValleyAt path: String? = nil) -> Data {
        var list: [String: Any] = ["caveman": ["source": ["source": "github", "repo": "x/caveman"], "installLocation": "/Users/me/.claude/plugins/marketplaces/caveman"]]
        if let path { list["agent-valley"] = ["source": ["source": "directory", "path": path], "installLocation": path] }
        return try! JSONSerialization.data(withJSONObject: list)
    }

    let plugin = URL(fileURLWithPath: "/Applications/AgentValley.app/Contents/Resources/claude-plugin")
    /// A copy of the app that is gone: 0.1 after brew uninstall, a dmg after it was ejected.
    static let gone = "/Volumes/AgentValley-\(UUID().uuidString)/AgentValley.app/Contents/Resources/claude-plugin"

    func testLost() {
        XCTAssertFalse(PluginPlace.lost(nil, plugin: plugin), "no list: Claude Code has no plugins at all")
        XCTAssertFalse(PluginPlace.lost(Self.registry(), plugin: plugin), "never installed")
        XCTAssertTrue(PluginPlace.lost(Self.registry(agentValleyAt: Self.gone), plugin: plugin))
        XCTAssertFalse(PluginPlace.lost(Self.registry(agentValleyAt: plugin.path), plugin: plugin))
        XCTAssertFalse(PluginPlace.lost(Self.registry(agentValleyAt: plugin.path + "/"), plugin: plugin))
        XCTAssertFalse(PluginPlace.lost(Data("not json".utf8), plugin: plugin))
    }

    /// Claude Code's list of plugins put in, as `claude plugin install` writes it.
    static func installedList(scope: String? = nil) -> Data {
        var plugins: [String: Any] = ["caveman@caveman": [["scope": "user", "version": "1.0.0"]]]
        if let scope { plugins["notch-answers@agent-valley"] = [["scope": scope, "version": "0.2.0", "installPath": "/x"]] }
        return try! JSONSerialization.data(withJSONObject: ["version": 2, "plugins": plugins])
    }

    func testInstalled() {
        XCTAssertFalse(PluginPlace.installed(nil), "no list: no plugins at all")
        XCTAssertFalse(PluginPlace.installed(Self.installedList()), "others only")
        XCTAssertTrue(PluginPlace.installed(Self.installedList(scope: "user")))
        XCTAssertFalse(PluginPlace.installed(Self.installedList(scope: "project")), "one project only: other sessions ask in the terminal")
        XCTAssertFalse(PluginPlace.installed(Data("not json".utf8)))
    }

    // Where Claude Code's installers put `claude` is looked at before any shell is asked.
    func testClaudeFoundWhereItsInstallerPutsIt() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let claude = home.appendingPathComponent(".local/bin/claude")
        try FileManager.default.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("#!/bin/sh\n".utf8).write(to: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        XCTAssertEqual(PluginInstall.claude(home: home)?.path, claude.path)
    }

    // Another copy that is still there (a build being worked on, 0.1 not yet uninstalled) still
    // takes the plugin to the one socket: Allow and Deny work, so nothing is said.
    func testAnotherCopyStillThereIsNotLost() throws {
        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/claude-plugin")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: other.deletingLastPathComponent()) }
        XCTAssertFalse(PluginPlace.lost(Self.registry(agentValleyAt: other.path), plugin: plugin))
    }

    // /tmp and /private/tmp, or a link someone made: one folder, however it is named.
    func testLostFollowsSymlinks() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let real = base.appendingPathComponent("real/claude-plugin")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: base.appendingPathComponent("real"))
        XCTAssertFalse(PluginPlace.lost(Self.registry(agentValleyAt: link.appendingPathComponent("claude-plugin").path), plugin: real))
    }
}
