import AppKit

/// Where the panel goes on a screen with Apple's Dynamic Island instead of a notch: a pill that floats
/// around the camera, a taller pill for an alert, a card grown down out of the island. Every size here is a
/// guess, made before any such Mac was at hand, and waits to be measured on one.
enum IslandGeometry {
    /// The room around the open card's top row, over it as beside it.
    static let openPad: CGFloat = 16
    /// What the card adds beside the top row, on top of the 8 the row keeps to its ends anyway.
    static let openSide: CGFloat = openPad - 8
    /// The room and the 10 of the cards inside it: one curve within the other.
    static let openRadius: CGFloat = 26
    /// The tabs, the tallest thing always drawn in the top row.
    private static let rowItem: CGFloat = 24
    static let alertRadius: CGFloat = 24
    /// Room beside the island in the alert's first row, and the least width the alert has.
    static let alertSide: CGFloat = 115
    static let alertMinWidth: CGFloat = 340
    /// The alert's second row, under the island.
    static let alertRow: CGFloat = 32
    /// How long the alert stays, in seconds.
    static let alertShown: TimeInterval = 3.2

    /// An alert shows only on a shut island: an open card or the welcome already says it.
    static func shouldAlert(island: Bool, expanded: Bool, welcoming: Bool) -> Bool {
        island && !expanded && !welcoming
    }

    /// The island, when the screen says that what is cut from its top is one and not a notch, in
    /// the coordinates of all screens. Whether AppKit gives it in those or in the screen's own is not
    /// known yet: both are tried, and the one inside the screen and nearer its middle wins.
    static func appleIsland(safeAperture: Bool?, cutout: CGRect?, screen: CGRect) -> CGRect? {
        guard safeAperture == true, let cutout, !cutout.isEmpty else { return nil }
        return [cutout, cutout.offsetBy(dx: screen.minX, dy: screen.minY)]
            .filter { screen.contains($0) }
            .min { abs($0.midX - screen.midX) < abs($1.midX - screen.midX) }
    }

    /// A frame of this size centred on the island and kept inside the screen.
    private static func centred(width: CGFloat, height: CGFloat, top: CGFloat, screen: CGRect, apple: CGRect) -> CGRect {
        let width = min(width, screen.width)
        let x = min(max(apple.midX - width / 2, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    static func pill(screen: CGRect, apple: CGRect) -> CGRect {
        centred(width: apple.width + NotchGeometry.wing * 2, height: apple.height, top: apple.maxY, screen: screen, apple: apple)
    }

    static func alert(screen: CGRect, apple: CGRect) -> CGRect {
        centred(width: max(alertMinWidth, apple.width + alertSide * 2), height: apple.height + alertRow,
                top: apple.maxY, screen: screen, apple: apple)
    }

    /// What the open card adds above its top row, as tall as the island, for `openPad` over the tabs.
    static func openRoom(apple: CGRect) -> CGFloat {
        max(0, openPad - (apple.height - rowItem) / 2)
    }

    /// Grown out of the island, as Apple's own is: its top where the island's is.
    static func open(screen: CGRect, apple: CGRect, contentHeight: CGFloat) -> CGRect {
        let size = NotchGeometry.openFrame(screen: screen, barHeight: apple.height, contentHeight: contentHeight).size
        return centred(width: size.width, height: size.height + openRoom(apple: apple), top: apple.maxY, screen: screen, apple: apple)
    }

    static func welcome(screen: CGRect, apple: CGRect) -> CGRect {
        let size = NotchGeometry.welcomeFrame(screen: screen).size
        return centred(width: size.width, height: size.height, top: apple.maxY, screen: screen, apple: apple)
    }

    /// The frame grown upward to the top of the screen, so the pointer pushed against that edge is still over it.
    static func reach(_ frame: CGRect, screen: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: screen.maxY - frame.minY)
    }

    /// The hover bar, the island as it stands now, and the window that holds it, each reaching the top edge.
    static func frames(screen: CGRect, apple: CGRect, expanded: Bool, alerting: Bool, welcoming: Bool,
                       contentHeight: CGFloat) -> (bar: CGRect, island: CGRect, window: CGRect) {
        let shut = pill(screen: screen, apple: apple)
        let card = welcoming ? welcome(screen: screen, apple: apple) : open(screen: screen, apple: apple, contentHeight: contentHeight)
        let island = reach(welcoming || expanded ? card : alerting ? alert(screen: screen, apple: apple) : shut, screen: screen)
        let window = welcoming || expanded ? reach(NotchGeometry.stageFrame(around: card), screen: screen) : island
        // The alert pill is all of it a way in, not only the pill's own area.
        let bar = alerting && !expanded && !welcoming ? island : reach(shut, screen: screen)
        return (bar, island, window)
    }

    /// The gap between the top of the screen and the island's shape, shut or open: it sits where the island does.
    static func top(screen: CGRect, apple: CGRect) -> CGFloat {
        screen.maxY - apple.maxY
    }

    static func radius(height: CGFloat, open: Bool, alerting: Bool) -> CGFloat {
        open ? openRadius : alerting ? alertRadius : height / 2
    }
}
