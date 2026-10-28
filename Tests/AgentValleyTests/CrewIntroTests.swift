import XCTest
@testable import AgentValley

final class CrewIntroTests: XCTestCase {
    // The name Claude is told must be the face the notch draws for that agent type.
    func testSubAgentNamesFollowTheFaceTheyAreDrawnWith() {
        for type in ["Plan", "plan"] { XCTAssertEqual(Crew.sub(type: type), .judy, type) }
        for type in ["Explore", "explore"] { XCTAssertEqual(Crew.sub(type: type), .faye, type) }
        for type in ["general-purpose", "", "code-reviewer"] { XCTAssertEqual(Crew.sub(type: type), .felix, type) }
    }

    func testLeadNoteNamesTheLeadAndTheCrew() {
        let note = CrewIntro.leadNote(.norm)
        for part in ["draws this session as Norm", CrewIntro.voice(.norm), "Judy takes Plan jobs", "Faye takes Explore jobs",
                     "Felix takes general-purpose jobs", "the way a sharp engineer works with a team they trust",
                     // Names in the talk, never in the work.
                     "commit messages",
                     // Sent again after compaction: a "drop the names" from before must hold.
                     "if the person already asked you to drop the names, keep them dropped"] {
            XCTAssertTrue(note.contains(part), part)
        }
        // Owner 2026-10-27: the crew talks freely like good engineers, not only at handoffs.
        XCTAssertFalse(note.contains("only at handoffs"))
        XCTAssertFalse(note.contains("{"))
    }

    func testSubNoteNamesBothAndHandsBack() {
        let note = CrewIntro.subNote(.faye, lead: .pearl)
        for part in ["draws you as Faye", "Hand your report back to Pearl", CrewIntro.voice(.faye),
                     // A job that wants its reply in an exact shape gets it untouched.
                     "If the job asks for an exact reply format, keep to it and leave the names out."] {
            XCTAssertTrue(note.contains(part), part)
        }
        XCTAssertFalse(note.contains("{"))
    }

    func testEveryOneHasAVoice() {
        let voices = Crew.allCases.map(CrewIntro.voice)
        XCTAssertFalse(voices.contains(where: \.isEmpty))
        XCTAssertEqual(Set(voices).count, Crew.allCases.count)
        XCTAssertEqual(Crew.allCases.map(\.name), ["Sunny", "Walt", "Norm", "Pearl", "Judy", "Faye", "Felix"])
    }

    // The exact shape Claude Code reads from a SessionStart or SubagentStart hook.
    func testBodyIsTheHookOutputClaudeCodeReads() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: CrewIntro.body(event: "SubagentStart", note: "x")) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["hookSpecificOutput"])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "SubagentStart")
        XCTAssertEqual(output["additionalContext"] as? String, "x")
    }
}
