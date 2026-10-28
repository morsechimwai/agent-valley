import Foundation

/// The seven who can speak. The first four are the leads, in the order of `Person.leads`.
enum Crew: String, CaseIterable {
    case sunny, walt, norm, pearl, judy, faye, felix

    /// In the order of `Person.leads`: guru, walrus, engineer, pearls.
    static let leads: [Crew] = [.sunny, .walt, .norm, .pearl]

    /// The lead whose face a session's agent wears.
    static func lead(_ look: LeadLook) -> Crew { leads[look.face % leads.count] }

    /// Who a sub-agent of `type` is: whoever `MascotKind` draws it as.
    static func sub(type: String) -> Crew {
        switch MascotKind(type: type) {
        case .plan: .judy
        case .explore: .faye
        default: .felix
        }
    }

    /// The name the person sees: "Sunny".
    var name: String { rawValue.capitalized }
}

/// What someone is waiting for, which picks the line a lead says.
enum WaitTopic: String, CaseIterable { case run, edit, web, generic, question, plan, first }
/// How the work ended, which picks the line a lead says.
enum DoneTopic: String, CaseIterable { case short, long, night, first, group }
/// The crew leaving for the water or the road, and coming back.
enum CrewScene: String, CaseIterable { case fishout, fishback, vanout, vanback }

/// The clips in the bundle's `crew` folder, found by name: `<who>-<group>-<n>.m4a`.
struct CrewSounds {
    /// The bundle's `crew` folder. Tests point it at the repo's `sounds/crew`.
    static let folder = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("crew")

    let folder: URL
    /// Names in the folder; empty when it is missing.
    let files: Set<String>

    init(folder: URL = CrewSounds.folder) {
        self.folder = folder
        files = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    /// Names "<who>-<group>-<n>.m4a", sorted by n. The group is matched whole: `remind-1`
    /// does not take `remind-10-1`.
    func lines(_ who: Crew, _ group: String) -> [String] {
        let head = "\(who.rawValue)-\(group)-", tail = ".m4a"
        let numbered = files.compactMap { name -> (Int, String)? in
            guard name.hasPrefix(head), name.hasSuffix(tail), name.count > head.count + tail.count,
                  let n = Int(name.dropFirst(head.count).dropLast(tail.count)) else { return nil }
            return (n, name)
        }
        return numbered.sorted { $0.0 < $1.0 }.map(\.1)
    }

    func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    static func group(_ topic: WaitTopic) -> String { "need-\(topic.rawValue)" }
    static func group(remind level: Int) -> String { "remind-\(min(max(level, 1), 3))" }
    static func group(_ topic: DoneTopic) -> String { "done-\(topic.rawValue)" }
    /// What a lead says when the person turns sounds on: that they are, not that someone waits.
    static let turnedOn = "on"
}
