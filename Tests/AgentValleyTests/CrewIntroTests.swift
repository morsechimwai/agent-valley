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

    // Owner 2026-10-29: a name in the talk is a tag with the face of who it means, where the terminal draws it.
    func testNamesBecomeTagsWhenTheTerminalDrawsThem() {
        let look = LeadLook(face: 1, hair: 0, shirt: 0)
        let tag = { (kind: MascotKind) in CrewFont.Tag.text(kind) }
        let lead = CrewIntro.leadNote(.walt, tags: CrewIntro.tags(lead: look))
        XCTAssertTrue(lead.contains("\(tag(.lead(look))) = Walt, \(tag(.plan)) = Judy, \(tag(.explore)) = Faye, \(tag(.general)) = Felix."), lead)
        XCTAssertTrue(lead.contains("tool inputs"))
        // A sub-agent of a type of its own wears the shirt the notch gives that type.
        let sub = CrewIntro.subNote(.felix, lead: .walt, tags: CrewIntro.tags(sub: "code-reviewer", lead: look))
        XCTAssertTrue(sub.contains("\(tag(.lead(look))) = Walt, \(tag(MascotKind(type: "code-reviewer"))) = Felix."), sub)
        // A type that reads as a session's own agent is still Felix, and never takes the lead's place.
        XCTAssertEqual(CrewIntro.tags(sub: "main", lead: LeadLook()), [.sunny: tag(.lead(LeadLook())), .felix: tag(.general)])
        // No font, no tags: an empty box helps no one.
        for note in [CrewIntro.leadNote(.walt), CrewIntro.subNote(.felix, lead: .walt)] {
            XCTAssertFalse(note.unicodeScalars.contains { (CrewFont.firstScalar...CrewFont.lastScalar).contains($0.value) })
            XCTAssertFalse(note.contains("tag"))
        }
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

    // The owner approved this wording; a drifting copy would change what every report opens with.
    func testInShortNoteIsTheApprovedWording() {
        XCTAssertEqual(CrewIntro.inShortNote, "AgentValley keeps your report in a library that people read later, often people who don't code. Start your report with one short paragraph that begins with \"In short:\" and says, in two or three plain sentences, what you did and what you found. No file paths, code or jargon in that paragraph. Then write the rest of your report as you normally would. If the job asks for an exact reply format, follow it and leave this paragraph out.")
    }

    // With names off a session gets no name, but every sub-agent still gets the In short note, so the store must hear it.
    func testOnlyASubagentStartReachesTheStoreWithNamesOff() {
        XCTAssertTrue(CrewIntro.reachesStore(event: "SessionStart", names: true))
        XCTAssertFalse(CrewIntro.reachesStore(event: "SessionStart", names: false))
        XCTAssertTrue(CrewIntro.reachesStore(event: "SubagentStart", names: true))
        XCTAssertTrue(CrewIntro.reachesStore(event: "SubagentStart", names: false))
    }
}
