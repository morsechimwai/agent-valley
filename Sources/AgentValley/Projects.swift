import Foundation

/// Which project a folder belongs to, told by its path, and by git where it was asked while the
/// folder was there: most folders sessions worked in are gone by the time anyone asks (144 of
/// 163 on the owner's Mac on 2026-10-15), so git cannot be asked then.
enum Projects {
    static let scratch = "Scratch"
    static let temporary = "Temporary folders"
    static let supersetSessions = "Superset sessions"
    static let unknown = "Unknown folder"

    /// A project as History counts it. `key` tells it apart from every other; `name` is what is
    /// shown, and `parent` the folder it is in, to tell two of one name apart.
    struct Place: Equatable {
        let key: String
        let name: String
        let parent: String
    }

    /// A folder as Claude Code spells it in the names of its own folders: everything but
    /// letters and digits as "-".
    static func encoded(_ folder: String) -> String {
        String(folder.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
    }

    /// Encoded folders back to the folders, to name a session's scratch folder by.
    static func known(_ folders: [String]) -> [String: String] {
        Dictionary(folders.map { (encoded($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The project's name, by the first rule of `place` that fits.
    static func name(of folder: String, home: String, known: [String: String] = [:], checkouts: [String: String] = [:]) -> String {
        place(of: folder, home: home, known: known, checkouts: checkouts).name
    }

    /// The project of a folder, by the first rule that fits. `start`: the folder its session
    /// began in. `checkouts`: folders to the checkouts git said they were in, while they were
    /// there to ask. `remotes`: checkouts to the address of their remote, which stays the same
    /// when the checkout is moved or renamed. `moves`: folders renamed while a session worked in
    /// them, old to new.
    static func place(of folder: String, start: String? = nil, home: String, known: [String: String] = [:],
                      checkouts: [String: String] = [:], remotes: [String: String] = [:], moves: [String: String] = [:]) -> Place {
        func again(_ folder: String) -> Place {
            place(of: folder, home: home, known: known, checkouts: checkouts, remotes: remotes, moves: moves)
        }
        func fixed(_ name: String) -> Place { Place(key: name, name: name, parent: "") }
        // A checkout with a remote goes by it, wherever it is reached from.
        func at(_ path: String) -> Place {
            let parent = (path as NSString).deletingLastPathComponent
            return Place(key: remotes[path].map { "git:" + $0 } ?? path, name: (path as NSString).lastPathComponent,
                         parent: parent == home ? "~" : (parent as NSString).lastPathComponent)
        }
        if folder.isEmpty { return fixed(unknown) }
        // Each move is to a folder first worked in after the old one's last answer: no way back round.
        for (old, new) in moves where old != home && new != home && (folder == old || folder.hasPrefix(old + "/")) {
            return again(new)
        }
        // A home folder kept in git, for its settings, is no project.
        if let checkout = checkouts[folder], checkout != home { return at(checkout) }
        // A session's scratch folder: /tmp/claude-<uid>/<its session's folder, encoded>/<session>/…
        for tmp in ["/tmp/claude-", "/private/tmp/claude-"] where folder.hasPrefix(tmp) {
            let parts = folder.dropFirst(tmp.count).split(separator: "/")
            guard parts.count >= 2, let real = known[String(parts[1])], !isTemporary(real) else { return fixed(scratch) }
            return again(real)
        }
        if isTemporary(folder) { return fixed(temporary) }
        var path = folder
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if let worktrees = path.range(of: "/.claude/worktrees/") { path = String(path[..<worktrees.lowerBound]) }
        let superset = home + "/.superset/worktrees/"
        if path.hasPrefix(superset), let repo = path.dropFirst(superset.count).split(separator: "/").first {
            // Superset names the folder by its own name for the project, which need not be the
            // checkout's: a worktree of the same project that git was asked about says which.
            // With none asked, a checkout of the same name is the project's, as most are; and with
            // none of those, a project folder of the same name worked in. Superset's own folder
            // for the project goes first; two others of the name would be a coin toss, so neither.
            let workspaces = superset + repo + "/"
            if let asked = checkouts.filter({ $0.key.hasPrefix(workspaces) && $0.value != home }).min(by: { $0.key < $1.key })?.value {
                return at(asked)
            }
            // A worktree of the project that moved: the project was renamed, and its worktrees with it.
            if let moved = moves.filter({ $0.key.hasPrefix(workspaces) && $0.value != home }).min(by: { $0.key < $1.key })?.value {
                return again(moved)
            }
            let own = home + "/.superset/projects/" + repo
            let tail = "/" + repo
            let named = { (folder: String) in folder != home && folder.hasSuffix(tail) }
            let sameName = Set(checkouts.values.filter(named))
            if let checkout = sameName.contains(own) ? own : sameName.count == 1 ? sameName.first : nil { return at(checkout) }
            if sameName.isEmpty {
                // A project of that name, not a folder of that name in another project.
                let found = known.values.filter { named($0) && !$0.hasPrefix(superset) && !isTemporary($0) }
                    .map { (folder: $0, place: again($0)) }
                    .filter { $0.place.name == repo }
                if let pick = found.first(where: { $0.folder == own }) ?? (Set(found.map(\.place.key)).count == 1 ? found.first : nil) {
                    return pick.place
                }
            }
            return Place(key: superset + repo, name: String(repo), parent: "")
        }
        if path.hasPrefix(home + "/.superset/sessions/") { return fixed(supersetSessions) }
        if path == home { return fixed("~") }
        // A session begins in its project and goes into the folders under it.
        if let start, path.hasPrefix(start + "/"), start != home, !isTemporary(start) {
            return again(start)
        }
        return at(path)
    }

    /// The address of a checkout's remote, origin's else the first one's, from its own config.
    static func remote(of checkout: String) -> String? {
        remote(inConfig: AgentStore.head(ofPlainFile: checkout + "/.git/config", limit: 1 << 16))
    }

    static func remote(inConfig text: String) -> String? {
        var section = ""
        var urls: [(section: String, url: String)] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard section.hasPrefix("[remote \""), parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "url" else { continue }
            urls.append((section, parts[1].trimmingCharacters(in: .whitespaces)))
        }
        let url = urls.first { $0.section == "[remote \"origin\"]" }?.url ?? urls.first?.url
        return url.flatMap { normalized(remote: $0) }
    }

    /// One remote however git was told it: "git@github.com:me/app.git" and
    /// "https://github.com/me/app" are both "github.com/me/app". Who signs in, and with what,
    /// is cut away and never kept. The host is any case, the path as written: some hosts tell
    /// "Team/App" from "team/app". nil for one said from where the repository stands.
    static func normalized(remote url: String) -> String? {
        var text = url.trimmingCharacters(in: .whitespaces)
        let scheme = text.range(of: "://")
        if let scheme {
            text = String(text[scheme.upperBound...])
            // To the last "@": a password can hold a "/" before it.
            if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        } else if let at = text.prefix(while: { $0 != "/" }).lastIndex(of: "@") {
            text = String(text[text.index(after: at)...])
        }
        // "host:path", as ssh takes it.
        if scheme == nil, let colon = text.firstIndex(of: ":"), !text[..<colon].contains("/") {
            text.replaceSubrange(colon...colon, with: "/")
        }
        let host = text.prefix { $0 != "/" }
        text = host.lowercased() + text.dropFirst(host.count)
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        return text.isEmpty || text.hasPrefix(".") ? nil : text
    }

    private static func isTemporary(_ folder: String) -> Bool {
        ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"].contains { folder == $0 || folder.hasPrefix($0 + "/") }
    }
}
