import SwiftUI

/// The green terminal the crew holds when it runs `Bash`, shown on the bar while a background job
/// still runs. Its output scrolls up a line per frame; the case, stand and keyboard hold still.
/// `still` stops the scroll and dims it, for jobs that have run a long while.
struct JobScreen: View {
    var size: CGFloat = 17
    var still = false

    static let frames: [[String]] = [
        [
            "............",
            "............",
            "............",
            ".vvvvvvvvvv.",
            ".veggggeeev.",
            ".veeeeeeeev.",
            ".veggegggev.",
            ".veeeeeeeev.",
            ".vegeeeeeev.",
            ".vvvvvvvvvv.",
            "...dvvvvd...",
            ".dddddddddd.",
        ],
        [
            "............",
            "............",
            "............",
            ".vvvvvvvvvv.",
            ".veggegggev.",
            ".veeeeeeeev.",
            ".vegggggeev.",
            ".veeeeeeeev.",
            ".veggeeeeev.",
            ".vvvvvvvvvv.",
            "...dvvvvd...",
            ".dddddddddd.",
        ],
        [
            "............",
            "............",
            "............",
            ".vvvvvvvvvv.",
            ".vegggggeev.",
            ".veeeeeeeev.",
            ".vegegggeev.",
            ".veeeeeeeev.",
            ".vegeeeeeev.",
            ".vvvvvvvvvv.",
            "...dvvvvd...",
            ".dddddddddd.",
        ],
        [
            "............",
            "............",
            "............",
            ".vvvvvvvvvv.",
            ".vegegggeev.",
            ".veeeeeeeev.",
            ".vegggeggev.",
            ".veeeeeeeev.",
            ".veggeeeeev.",
            ".vvvvvvvvvv.",
            "...dvvvvd...",
            ".dddddddddd.",
        ],
        [
            "............",
            "............",
            "............",
            ".vvvvvvvvvv.",
            ".vegggeggev.",
            ".veeeeeeeev.",
            ".veggggggev.",
            ".veeeeeeeev.",
            ".vegeeeeeev.",
            ".vvvvvvvvvv.",
            "...dvvvvd...",
            ".dddddddddd.",
        ],
        [
            "............",
            "............",
            "............",
            ".vvvvvvvvvv.",
            ".veggggggev.",
            ".veeeeeeeev.",
            ".veggggeeev.",
            ".veeeeeeeev.",
            ".veggeeeeev.",
            ".vvvvvvvvvv.",
            "...dvvvvd...",
            ".dddddddddd.",
        ],
    ]

    /// The same colours the crew's own terminal uses, so the two read as one thing.
    static func hex(_ cell: Character) -> UInt32? {
        Person.guru.hex(cell)
    }

    static func colour(_ cell: Character) -> Color? {
        hex(cell).map(rgb)
    }

    var body: some View {
        Flipbook(frames: still ? [Self.frames[0]] : Self.frames, colour: Self.colour, size: size)
            .opacity(still ? 0.5 : 1)
    }
}

/// A small server rack sending waves out, in place of the terminal for a shell that serves on a
/// port: open for visitors, not work anyone waits on. The first frame shows both waves, so the
/// still one and Reduce Motion's still say it too.
struct JobServer: View {
    var size: CGFloat = 17
    var still = false

    static let frames: [[String]] = [
        [
            "............",
            "............",
            ".vvvvv..g...",
            ".vddgv...g..",
            ".vvvvv.g..g.",
            ".vddgv..g.g.",
            ".vvvvv..g.g.",
            ".vddgv.g..g.",
            ".vvvvv...g..",
            "..d.d...g...",
            "............",
            "............",
        ],
        [
            "............",
            "............",
            ".vvvvv..Q...",
            ".vddgv...Q..",
            ".vvvvv....Q.",
            ".vddgv....Q.",
            ".vvvvv....Q.",
            ".vddgv....Q.",
            ".vvvvv...Q..",
            "..d.d...Q...",
            "............",
            "............",
        ],
        [
            "............",
            "............",
            ".vvvvv......",
            ".vddgv......",
            ".vvvvv......",
            ".vddgv......",
            ".vvvvv......",
            ".vddgv......",
            ".vvvvv......",
            "..d.d.......",
            "............",
            "............",
        ],
        [
            "............",
            "............",
            ".vvvvv......",
            ".vddgv......",
            ".vvvvv.g....",
            ".vddgv..g...",
            ".vvvvv..g...",
            ".vddgv.g....",
            ".vvvvv......",
            "..d.d.......",
            "............",
            "............",
        ],
    ]

    var body: some View {
        Flipbook(frames: still ? [Self.frames[0]] : Self.frames, colour: JobScreen.colour, size: size)
            .opacity(still ? 0.5 : 1)
    }
}

/// A watching eye, the icon of a `Monitor` job on a session card.
struct JobEye: View {
    var size: CGFloat = 14

    static let cells: [String] = [
        "............",
        "............",
        "............",
        "...wwwwww...",
        "..wwwkkwww..",
        ".wwwkkkkwww.",
        ".wwwkkkkwww.",
        "..wwwkkwww..",
        "...wwwwww...",
        "............",
        "............",
        "............",
    ]

    static func hex(_ cell: Character) -> UInt32? {
        switch cell {
        case "w": 0xCFC6A8  // the white of the eye
        case "k": 0x1E1E1E  // the pupil
        default: nil
        }
    }

    var body: some View {
        Pixels(cells: Self.cells.map(Array.init), size: size, colour: { Self.hex($0).map(rgb) })
            .accessibilityHidden(true)
    }
}
