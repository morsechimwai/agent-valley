import XCTest
@testable import AgentValley

final class IslandGeometryTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let apple = CGRect(x: 701, y: 951, width: 110, height: 28)

    func testAnIslandOnlyWhenTheScreenSaysSo() {
        XCTAssertEqual(IslandGeometry.appleIsland(safeAperture: true, cutout: apple, screen: screen), apple)
        XCTAssertNil(IslandGeometry.appleIsland(safeAperture: false, cutout: apple, screen: screen))
        XCTAssertNil(IslandGeometry.appleIsland(safeAperture: nil, cutout: apple, screen: screen))
        XCTAssertNil(IslandGeometry.appleIsland(safeAperture: true, cutout: nil, screen: screen))
        XCTAssertNil(IslandGeometry.appleIsland(safeAperture: true, cutout: .zero, screen: screen))
    }

    // The laptop beside a main display: its island the same in the screen's own coordinates or in
    // those of all screens, and nothing at all when it fits neither.
    func testAnIslandOnAScreenThatIsNotTheMainOne() {
        let left = screen.offsetBy(dx: -1512, dy: 0)
        let there = apple.offsetBy(dx: -1512, dy: 0)
        XCTAssertEqual(IslandGeometry.appleIsland(safeAperture: true, cutout: apple, screen: left), there)
        XCTAssertEqual(IslandGeometry.appleIsland(safeAperture: true, cutout: there, screen: left), there)
        let near = screen.offsetBy(dx: 100, dy: 0)
        XCTAssertEqual(IslandGeometry.appleIsland(safeAperture: true, cutout: apple, screen: near), apple.offsetBy(dx: 100, dy: 0))
        XCTAssertEqual(IslandGeometry.appleIsland(safeAperture: true, cutout: apple.offsetBy(dx: 100, dy: 0), screen: near), apple.offsetBy(dx: 100, dy: 0))
        XCTAssertNil(IslandGeometry.appleIsland(safeAperture: true, cutout: apple.offsetBy(dx: 0, dy: 500), screen: screen.offsetBy(dx: 3000, dy: 0)))
    }

    func testThePillWrapsTheIslandAndFloatsWithIt() {
        XCTAssertEqual(IslandGeometry.pill(screen: screen, apple: apple), CGRect(x: 657, y: 951, width: 198, height: 28))
    }

    func testTheAlertKeepsItsWordsOffTheCamera() {
        let a = IslandGeometry.alert(screen: screen, apple: apple)
        XCTAssertEqual(a.width, 340)
        XCTAssertEqual(a.height, 60)
        XCTAssertEqual(a.maxY, 979)
        XCTAssertEqual(a.midX, 756)
        let narrow = CGRect(x: 663.5, y: 947, width: 185, height: 32)
        XCTAssertEqual(IslandGeometry.alert(screen: screen, apple: narrow).width, 415)
        let left = CGRect(x: 100 - 55, y: 951, width: 110, height: 28)
        XCTAssertGreaterThanOrEqual(IslandGeometry.alert(screen: screen, apple: left).minX, 0)
        let right = CGRect(x: 1412 - 55, y: 951, width: 110, height: 28)
        XCTAssertLessThanOrEqual(IslandGeometry.alert(screen: screen, apple: right).maxX, 1512)
    }

    func testTheOpenCardFloatsUnderTheTop() {
        let card = IslandGeometry.open(screen: screen, apple: apple, contentHeight: 200)
        XCTAssertEqual(card.maxY, 976)
        XCTAssertEqual(card.width, 520)
        XCTAssertEqual(card.height, NotchGeometry.openFrame(screen: screen, barHeight: 28, contentHeight: 200).height)
    }

    func testTheTopEdgeStillReaches() {
        func frames(_ expanded: Bool, _ alerting: Bool, _ welcoming: Bool) -> (bar: CGRect, island: CGRect, window: CGRect) {
            IslandGeometry.frames(screen: screen, apple: apple, expanded: expanded, alerting: alerting, welcoming: welcoming, contentHeight: 200)
        }
        let shut = frames(false, false, false)
        XCTAssertEqual(shut.bar.maxY, 982)
        XCTAssertTrue(NotchGeometry.isOver(shut.bar, cursor: CGPoint(x: 756, y: 982)))
        let alerting = frames(false, true, false)
        XCTAssertEqual(alerting.bar, IslandGeometry.reach(IslandGeometry.alert(screen: screen, apple: apple), screen: screen))
        XCTAssertTrue(NotchGeometry.isOver(alerting.bar, cursor: CGPoint(x: 756 + 150, y: 925)))
        let open = frames(true, false, false)
        XCTAssertEqual(open.island.maxY, 982)
        // Room for the spring to overshoot the card.
        let card = IslandGeometry.open(screen: screen, apple: apple, contentHeight: 200)
        XCTAssertTrue(open.window.contains(NotchGeometry.stageFrame(around: card)))
        XCTAssertTrue(NotchGeometry.isOver(open.island, cursor: CGPoint(x: 756, y: 979)))
        for state in [shut, frames(false, true, false), open, frames(false, false, true)] {
            XCTAssertEqual(state.window.maxY, 982)
        }
    }

    func testRoundness() {
        XCTAssertEqual(IslandGeometry.radius(height: 28, open: false, alerting: false), 14)
        XCTAssertEqual(IslandGeometry.radius(height: 28, open: false, alerting: true), 24)
        XCTAssertEqual(IslandGeometry.radius(height: 28, open: true, alerting: true), 30)
        XCTAssertEqual(IslandGeometry.radius(height: 28, open: true, alerting: false), 30)
        XCTAssertEqual(IslandGeometry.top(screen: screen, apple: apple, open: false), 3)
        XCTAssertEqual(IslandGeometry.top(screen: screen, apple: apple, open: true), 6)
    }

    func testOnlyARectangleIsReadAsOne() {
        XCTAssertEqual(NSScreen.rect(from: NSValue(rect: apple)), apple)
        XCTAssertNil(NSScreen.rect(from: NSValue(point: .zero)))
        XCTAssertNil(NSScreen.rect(from: "x"))
        XCTAssertNil(NSScreen.rect(from: nil))
    }

    func testAnAlertOnlyOnAShutIsland() {
        XCTAssertTrue(IslandGeometry.shouldAlert(island: true, expanded: false, welcoming: false))
        XCTAssertFalse(IslandGeometry.shouldAlert(island: false, expanded: false, welcoming: false))
        XCTAssertFalse(IslandGeometry.shouldAlert(island: true, expanded: true, welcoming: false))
        XCTAssertFalse(IslandGeometry.shouldAlert(island: true, expanded: false, welcoming: true))
    }
}
