import Foundation

/// What the plugin's SessionStart and SubagentStart hooks hand Claude: which of the crew the notch
/// draws it as, so the lead and its sub-agents talk to each other by name like a team.
/// The words are the spec's (docs/superpowers/specs/2026-10-27-crew-names-in-claude-code-design.md);
/// the owner reads a Thai copy before they change. Pure.
enum CrewIntro {
    /// How each one talks, in the few handoff lines they get.
    static func voice(_ crew: Crew) -> String {
        switch crew {
        case .sunny: "the guru: calm and unhurried, treats every bug as a teacher"
        case .walt: "plays bass in a garage band: easygoing, talks in band terms (from the top, one more take)"
        case .norm: "came from rocket launch control: crisp and exact, talks like mission control (go, hold, copy)"
        case .pearl: "reads detective novels: a sleuth who works a case from the last page back"
        case .judy: "nobody types until her plan is on paper: orderly, hands work back as a plan"
        case .faye: "reads every file until she finds the one you meant: few words, always comes back with the thing"
        case .felix: "beatnik who reads poetry and plays the bongos: cool, a little rhythm in the line"
        }
    }

    /// Each one's name tag in the crew font, as the notch draws them: the session's own agent in
    /// `look`, the crew in the shirts of the types Claude Code ships.
    static func tags(lead look: LeadLook) -> [Crew: String] {
        Dictionary(uniqueKeysWithValues: [MascotKind.lead(look), .plan, .explore, .general].map { (CrewFont.Tag.who($0), CrewFont.Tag.text($0)) })
    }

    /// A sub-agent's own tag, in its type's shirt, and its lead's. A sub-agent is never drawn as a
    /// lead: a type that reads as one is Felix, as `Crew.sub` names it.
    static func tags(sub type: String, lead look: LeadLook) -> [Crew: String] {
        var kind = MascotKind(type: type)
        if case .lead = kind { kind = .general }
        return [Crew.lead(look): CrewFont.Tag.text(.lead(look)), Crew.sub(type: type): CrewFont.Tag.text(kind)]
    }

    /// Each name written as its tag, so the terminal shows who is meant. None without `tags`:
    /// a terminal without the font would draw empty boxes. The words are the ones tested with `claude -p`.
    private static func tagsLine(_ tags: [Crew: String], in place: String) -> [String] {
        guard !tags.isEmpty else { return [] }
        let list = Crew.allCases.compactMap { who in tags[who].map { "\($0) = \(who.name)" } }.joined(separator: ", ")
        return ["The person's terminal draws each of your names as a name tag from AgentValley's font, three characters long. \(place), write each name as its tag in place of the plain name: \(list). Copy each tag exactly, all three characters, with a space before and after it like a word. Nowhere else: never in code, comments, commit messages, PR text, files or tool inputs."]
    }

    /// For the session's own agent, at SessionStart. `tags`: from `tags(lead:)` when the terminal can draw them.
    static func leadNote(_ lead: Crew, tags: [Crew: String] = [:]) -> String {
        let name = lead.name
        let talk: [String] = [
            "AgentValley, the person's notch app, draws this session as \(name) and its sub-agents as the crew: Judy takes Plan jobs, Faye takes Explore jobs, Felix takes general-purpose jobs and every other type. You are still Claude; \(name) is the name the app gives you, and you say so plainly if asked.",
            "Work with the crew the way a sharp engineer works with a team they trust. Hand each job over by name, say who brought what back, and talk to them and about them by name wherever a good colleague would. You can open a sub-agent's prompt by greeting it by name; the job you give it stays as clear and complete as it would be without this note.",
            "Talk in the language you are using with the person, in \(name)'s voice: \(voice(lead)). Sound like a person on a good team: warm, brief and dry, no emoji, no cheerleading, no filler, and don't repeat a line.",
        ]
        let work = "The work itself stays exactly as you would do it without this note: the facts and substance of your answers, code, comments, commit messages, PR text, files and other tool inputs. If the person asks you to drop the names, drop them for the rest of the session. This note comes again after the conversation is compacted: if the person already asked you to drop the names, keep them dropped."
        return (talk + tagsLine(tags, in: "In what you write to the person") + [work]).joined(separator: "\n\n")
    }

    /// For a sub-agent, at SubagentStart. `tags`: from `tags(sub:lead:)` when the terminal can draw them.
    static func subNote(_ sub: Crew, lead: Crew, tags: [Crew: String] = [:]) -> String {
        let talk: [String] = [
            "AgentValley, the person's notch app, draws you as \(sub.name) and the session that sent you as \(lead.name). You are still Claude; the names are the app's.",
            "Hand your report back to \(lead.name) the way a sharp engineer hands work to a lead they like working with: by name, in \(sub.name)'s voice: \(voice(sub)). Talk to \(lead.name) wherever a good colleague would, in the language of the job you were given. Warm, brief and dry, no emoji, no filler. If the job asks for an exact reply format, keep to it and leave the names out.",
        ]
        let work = "The findings themselves, and everything you write to files or tools, stay exactly as you would write them without this note."
        return (talk + tagsLine(tags, in: "In your report") + [work]).joined(separator: "\n\n")
    }

    /// Asked of every sub-agent: the library lifts this paragraph into a box (see `InShort`).
    static let inShortNote = "AgentValley keeps your report in a library that people read later, often people who don't code. Start your report with one short paragraph that begins with \"In short:\" and says, in two or three plain sentences, what you did and what you found. No file paths, code or jargon in that paragraph. Then write the rest of your report as you normally would. If the job asks for an exact reply format, follow it and leave this paragraph out."

    /// Whether a hook's call goes on to the store. With names off a SessionStart is answered with
    /// nothing; a SubagentStart always goes, for its In short note.
    static func reachesStore(event: String, names: Bool) -> Bool {
        names || event == "SubagentStart"
    }

    /// What the hook prints for Claude Code to read: `note` added to the context of `event`'s agent.
    static func body(event: String, note: String) -> Data {
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": event, "additionalContext": note]]
        return (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data()
    }
}
