import XCTest
@testable import AgentValley

final class InShortTests: XCTestCase {
    // The box at the top of a chapter is the first paragraph, label off, and the body keeps the rest.
    func testSplitTakesTheFirstInShortParagraph() {
        let r = InShort.split("\n In short: Fixed the bug.\nIt was a typo.\n\n\nDetails here.\n")
        XCTAssertEqual(r.short, "Fixed the bug.\nIt was a typo.")
        XCTAssertEqual(r.rest, "Details here.\n")
    }

    // Claude often bolds the label; both bold forms count.
    func testSplitAcceptsBoldLabel() {
        XCTAssertEqual(InShort.split("**In short:** All good.\n\nMore").short, "All good.")
        XCTAssertEqual(InShort.split("**In short**: All good.\n\nMore").short, "All good.")
    }

    // A report without the paragraph must come back untouched, or text would be lost.
    func testSplitLeavesTextWithoutInShortWhole() {
        for text in ["  Hello.\n\nin short: no", "In short:\n\nBody", "In shorter: x", ""] {
            let r = InShort.split(text)
            XCTAssertNil(r.short, text)
            XCTAssertEqual(r.rest, text)
        }
    }

    // Only the opening paragraph is lifted; a later one is just prose.
    func testSplitIgnoresInShortFurtherDown() {
        let text = "Intro.\n\nIn short: later."
        let r = InShort.split(text)
        XCTAssertNil(r.short)
        XCTAssertEqual(r.rest, text)
    }
}
