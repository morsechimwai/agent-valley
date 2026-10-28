import XCTest
@testable import AgentValley

final class ProjectsTests: XCTestCase {
    private let home = "/Users/me"

    // Every kind of folder sessions worked in on the owner's Mac, 2026-10-15, under made-up names.
    func testEveryKindOfFolderOnTheOwnersMac() {
        let known = Projects.known([
            "/Users/me/.superset/projects/agents-visualizer",
            "/Users/me/.superset/worktrees/mobile-app/brave-otter-d8de43d5",
        ])
        let cases: [(String, String)] = [
            ("/Users/me/.superset/projects/agents-visualizer", "agents-visualizer"),
            // A worktree of Claude Code's is its repository's.
            ("/Users/me/.superset/projects/agents-visualizer/.claude/worktrees/token-use", "agents-visualizer"),
            // A workspace of Superset's is its repository's, whatever its own made-up name.
            ("/Users/me/.superset/worktrees/shop-web/brave-otter-d8de43d5", "shop-web"),
            ("/Users/me/.superset/worktrees/shop.web/quiet-heron-01813747", "shop.web"),
            ("/Users/me/.superset/worktrees/api/tidy-lark/packages/web", "api"),
            ("/Users/me/.superset/sessions/calm-river", "Superset sessions"),
            // A session's scratch folder names its session's folder only in encoded form.
            ("/private/tmp/claude-501/-Users-me--superset-projects-agents-visualizer/6496ec8c-5e10/scratchpad/spike/proj", "agents-visualizer"),
            ("/private/tmp/claude-501/-Users-me--superset-worktrees-mobile-app-brave-otter-d8de43d5/9b5cc18a/scratchpad/eu", "mobile-app"),
            ("/tmp/claude-501/-Users-me--superset-projects-agents-visualizer/6496ec8c/scratchpad", "agents-visualizer"),
            ("/private/tmp/claude-501/-Users-me--superset-projects-gone-long-ago/0b15/scratchpad/ptest", "Scratch"),
            ("/private/tmp/claude-501", "Scratch"),
            ("/private/var/folders/ab/1cd2ef3gh4ij5kl6mn7op8qr0000gn/T/tmpab1cd2ef", "Temporary folders"),
            ("/private/tmp", "Temporary folders"),
            ("/var/folders/ab/T", "Temporary folders"),
            ("/Users/me", "~"),
            ("/Users/me/Documents/work/docs", "docs"),
            ("/Users/me/Documents/work/docs/", "docs"),
            // Its own folder name: a tool's worktree this app does not know.
            ("/Users/me/.othertool/worktrees/demo-4b2f35/run-20260927-2051/backend", "backend"),
            ("", "Unknown folder"),
        ]
        for (folder, name) in cases {
            XCTAssertEqual(Projects.name(of: folder, home: home, known: known), name, folder)
        }
    }

    // A folder git was asked about while it was there goes by its checkout's folder: Superset
    // names its worktrees' folders by its own name for the project, which need not be that one.
    // A worktree gone before git was asked goes by any worktree of the same Superset project
    // that was asked about.
    func testAFolderGitWasAskedAboutGoesByItsCheckout() {
        let checkouts = [
            "/Users/me/.superset/worktrees/AgentValley/live-ws": "/Users/me/.superset/projects/agent-valley",
            "/Users/me/.superset/projects/agent-valley": "/Users/me/.superset/projects/agent-valley",
            "/Users/me/.superset/worktrees/Other/ws": "/Users/me/.superset/worktrees/Other/ws",
            // A home folder kept in git, for its settings, is no project.
            "/Users/me/notes": "/Users/me",
            "/Users/me/.superset/worktrees/Dots/ws": "/Users/me",
        ]
        let known = Projects.known(["/Users/me/.superset/worktrees/AgentValley/old-ws"])
        let cases: [(String, String)] = [
            ("/Users/me/.superset/worktrees/AgentValley/live-ws", "agent-valley"),
            ("/Users/me/.superset/projects/agent-valley", "agent-valley"),
            ("/Users/me/.superset/worktrees/AgentValley/old-ws", "agent-valley"),
            ("/Users/me/.superset/worktrees/AgentValley/old-ws/site", "agent-valley"),
            ("/private/tmp/claude-501/-Users-me--superset-worktrees-AgentValley-old-ws/9b5c/scratchpad", "agent-valley"),
            // Not a worktree of the project, though its name starts the same.
            ("/Users/me/.superset/worktrees/AgentValleyKit/ws", "AgentValleyKit"),
            ("/Users/me/.superset/worktrees/Never/ws", "Never"),
            ("/Users/me/notes", "notes"),
            ("/Users/me/.superset/worktrees/Dots/old", "Dots"),
        ]
        for (folder, name) in cases {
            XCTAssertEqual(Projects.name(of: folder, home: home, known: known, checkouts: checkouts), name, folder)
        }
    }

    // Two projects of one name are two, and say the folder each is in, to tell them apart.
    func testTwoProjectsOfOneNameAreTwo() {
        let work = Projects.place(of: "/Users/me/work/app", home: home)
        let play = Projects.place(of: "/Users/me/play/app/", home: home)
        XCTAssertEqual(work, Projects.Place(key: "/Users/me/work/app", name: "app", parent: "work"))
        XCTAssertEqual(play, Projects.Place(key: "/Users/me/play/app", name: "app", parent: "play"))
        XCTAssertEqual(Projects.place(of: "/Users/me/app", home: home).parent, "~")
        XCTAssertEqual(Projects.place(of: "/private/tmp", home: home), Projects.Place(key: "Temporary folders", name: "Temporary folders", parent: ""))
    }

    // A checkout moved or renamed is still the project it was: the address of its remote says so.
    func testACheckoutGoesByItsRemoteWhereItHasOne() {
        let checkouts = ["/Users/me/old-name": "/Users/me/old-name", "/Users/me/code/new-name/site": "/Users/me/code/new-name",
                         "/Users/me/local": "/Users/me/local"]
        let remotes = ["/Users/me/old-name": "github.com/me/app", "/Users/me/code/new-name": "github.com/me/app"]
        let old = Projects.place(of: "/Users/me/old-name", home: home, checkouts: checkouts, remotes: remotes)
        let new = Projects.place(of: "/Users/me/code/new-name/site", home: home, checkouts: checkouts, remotes: remotes)
        XCTAssertEqual(old, Projects.Place(key: "git:github.com/me/app", name: "old-name", parent: "~"))
        XCTAssertEqual(new, Projects.Place(key: "git:github.com/me/app", name: "new-name", parent: "code"))
        // No remote: the checkout's folder.
        XCTAssertEqual(Projects.place(of: "/Users/me/local", home: home, checkouts: checkouts, remotes: remotes).key, "/Users/me/local")
        // A checkout reached by its path, not by what git said of the folder, goes by its remote too.
        XCTAssertEqual(Projects.place(of: "/Users/me/gone/site", start: "/Users/me/old-name", home: home, remotes: remotes).key, "/Users/me/gone/site")
        XCTAssertEqual(Projects.place(of: "/Users/me/old-name/site", start: "/Users/me/old-name", home: home, remotes: remotes).key, "git:github.com/me/app")
    }

    // A folder renamed while a session worked in it is the new folder's project, and so is all
    // under it; a Superset worktree that moved takes its project's other worktrees with it.
    func testARenamedFolderIsTheNewOnesProject() {
        let moves = ["/Users/me/old": "/Users/me/new",
                     "/Users/me/.superset/worktrees/first-name/ws": "/Users/me/.superset/worktrees/second-name/ws",
                     "/Users/me/away": "/Users/me"]
        let checkouts = ["/Users/me/new": "/Users/me/new", "/Users/me/.superset/worktrees/second-name/ws": "/Users/me/.superset/projects/second-name"]
        let remotes = ["/Users/me/new": "github.com/me/app"]
        func key(_ folder: String) -> String {
            Projects.place(of: folder, home: home, known: Projects.known(["/Users/me/old"]), checkouts: checkouts, remotes: remotes, moves: moves).key
        }
        XCTAssertEqual(key("/Users/me/old"), "git:github.com/me/app")
        XCTAssertEqual(key("/Users/me/old/site/src"), "git:github.com/me/app")
        XCTAssertEqual(key("/Users/me/old/.claude/worktrees/fix"), "git:github.com/me/app")
        XCTAssertEqual(key("/private/tmp/claude-501/-Users-me-old/0b15/scratchpad"), "git:github.com/me/app")
        XCTAssertEqual(key("/Users/me/older"), "/Users/me/older")
        XCTAssertEqual(key("/Users/me/.superset/worktrees/first-name/other-ws"), "/Users/me/.superset/projects/second-name")
        // Never onto the home folder.
        XCTAssertEqual(key("/Users/me/away"), "/Users/me/away")
    }

    // A Superset worktree gone before git was asked, with none of its project's asked either,
    // is the checkout of its name's, as it was named before.
    func testAGoneSupersetWorktreeIsTheCheckoutOfItsName() {
        let main = "/Users/me/.superset/projects/shop"
        let checkouts = [main: main, "/Users/me/elsewhere/shopkit": "/Users/me/elsewhere/shopkit"]
        let place = Projects.place(of: "/Users/me/.superset/worktrees/shop/calm-otter/site", home: home,
                                   checkouts: checkouts, remotes: [main: "github.com/me/shop"])
        XCTAssertEqual(place, Projects.Place(key: "git:github.com/me/shop", name: "shop", parent: "projects"))
        XCTAssertEqual(Projects.place(of: "/Users/me/.superset/worktrees/shop/calm-otter", home: home, checkouts: checkouts).key, main)
        // Its checkout gone before git was asked too: the folder of its name that was worked in.
        let known = Projects.known(["/Users/me/.superset/projects/blog", "/Users/me/.superset/worktrees/blog/quiet-lark", "/Users/me/blog-old"])
        XCTAssertEqual(Projects.place(of: "/Users/me/.superset/worktrees/blog/quiet-lark", home: home, known: known).key,
                       "/Users/me/.superset/projects/blog")
        // Two checkouts of its name, neither Superset's own: no guess.
        let two = ["/Users/me/a/web": "/Users/me/a/web", "/Users/me/b/web": "/Users/me/b/web"]
        XCTAssertEqual(Projects.place(of: "/Users/me/.superset/worktrees/web/ws", home: home, checkouts: two).key, "/Users/me/.superset/worktrees/web")
        let withOwn = two.merging(["/Users/me/.superset/projects/web": "/Users/me/.superset/projects/web"]) { first, _ in first }
        XCTAssertEqual(Projects.place(of: "/Users/me/.superset/worktrees/web/ws", home: home, checkouts: withOwn).key, "/Users/me/.superset/projects/web")
        // A folder of its name inside another project is not it.
        let inside = Projects.known(["/Users/me/.superset/projects/big/video", "/Users/me/.superset/worktrees/video/ws"])
        XCTAssertEqual(Projects.place(of: "/Users/me/.superset/worktrees/video/ws", home: home, known: inside,
                                      checkouts: ["/Users/me/.superset/projects/big/video": "/Users/me/.superset/projects/big"]).key,
                       "/Users/me/.superset/worktrees/video")
    }

    // A folder inside the one its session began in is that one's project, git or no git:
    // a session begins in its project and goes into the folders under it.
    func testAFolderGoesByTheFolderItsSessionBeganIn() {
        let checkouts = ["/Users/me/repo": "/Users/me/repo"]
        let cases: [(folder: String, start: String?, key: String)] = [
            ("/Users/me/gone/site", "/Users/me/gone", "/Users/me/gone"),
            ("/Users/me/gone/site/public", "/Users/me/gone", "/Users/me/gone"),
            ("/Users/me/repo/docs/out", "/Users/me/repo", "/Users/me/repo"),
            ("/Users/me/gone/.claude/worktrees/x/site", "/Users/me/gone", "/Users/me/gone"),
            // Not inside it: its own.
            ("/Users/me/other", "/Users/me/gone", "/Users/me/other"),
            ("/Users/me/gone-too", "/Users/me/gone", "/Users/me/gone-too"),
            // Begun in the home folder or a temporary one, which are no project.
            ("/Users/me/code/app", "/Users/me", "/Users/me/code/app"),
            ("/private/tmp/x/y", "/private/tmp/x", "Temporary folders"),
            ("/Users/me/code/app", nil, "/Users/me/code/app"),
        ]
        for item in cases {
            XCTAssertEqual(Projects.place(of: item.folder, start: item.start, home: home, checkouts: checkouts).key, item.key, item.folder)
        }
    }

    // One remote spelled the ways git takes it is one project; who signs in is never kept.
    func testARemoteSpelledAnyWayIsOne() {
        for url in ["git@GitHub.com:me/app.git", "https://github.com/me/app", "https://me:ghp_secret@github.com/me/app.git/",
                    "ssh://git@github.com/me/app.git", " https://github.com/me/app.git ", "https://me:pa/ss@github.com/me/app"] {
            XCTAssertEqual(Projects.normalized(remote: url), "github.com/me/app", url)
        }
        // The path as written: some hosts tell these two apart.
        XCTAssertEqual(Projects.normalized(remote: "https://git.example.com/Team/App.git"), "git.example.com/Team/App")
        XCTAssertEqual(Projects.normalized(remote: "/srv/git/app.git"), "/srv/git/app")
        // Said from where the repository stands: no address of its own.
        XCTAssertNil(Projects.normalized(remote: "../app.git"))
        XCTAssertNil(Projects.normalized(remote: ""))
    }

    func testTheRemoteOfAConfigIsOriginsElseTheFirst() {
        let config = """
            [core]
            \turl = not-this
            [remote "upstream"]
            \turl = https://github.com/them/app.git
            [remote "origin"]
            \turl = git@github.com:me/app.git
            \tfetch = +refs/heads/*:refs/remotes/origin/*
            [branch "main"]
            \tremote = origin
            """
        XCTAssertEqual(Projects.remote(inConfig: config), "github.com/me/app")
        XCTAssertEqual(Projects.remote(inConfig: "[remote \"upstream\"]\n  url=https://github.com/them/app\n"), "github.com/them/app")
        XCTAssertNil(Projects.remote(inConfig: "[core]\n\tbare = false\n"))
    }

    func testAFolderEncodedAsClaudeCodeSpellsIt() {
        XCTAssertEqual(Projects.encoded("/Users/me/.superset/projects/agents-visualizer"), "-Users-me--superset-projects-agents-visualizer")
        XCTAssertEqual(Projects.encoded("/a/b_c.d e"), "-a-b-c-d-e")
        // Two folders spelled alike: the first is kept.
        XCTAssertEqual(Projects.known(["/a/b.c", "/a/b-c"]), ["-a-b-c": "/a/b.c"])
    }
}
