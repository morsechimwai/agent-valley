import CoreText
import XCTest
@testable import AgentValley

final class CrewFontTests: XCTestCase {
    func testEveryFaceHasItsOwnCodepointInOrder() {
        XCTAssertEqual(CrewFont.faces.map(\.scalar), Array(UInt32(0x3F000)...0x3F4D6))
        XCTAssertLessThanOrEqual(CrewFont.faces.last!.scalar, CrewFont.lastScalar, "past the end of Ghostty's font line")
        // The bar's pictures come after every face.
        XCTAssertEqual(CrewFont.Picture.allCases.map(\.character), ["\u{3F4D7}", "\u{3F4D8}", "\u{3F4D9}"])
        XCTAssertLessThanOrEqual(CrewFont.Picture.van.scalar, CrewFont.lastScalar, "past the end of Ghostty's font line")
        // The panel's marks come after the pictures.
        XCTAssertEqual(CrewFont.Mark.allCases.map(\.character), ["\u{3F4DA}", "\u{3F4DB}", "\u{3F4DC}"])
        XCTAssertLessThanOrEqual(CrewFont.Mark.worktree.scalar, CrewFont.lastScalar, "past the end of Ghostty's font line")
    }

    func testUntaggedGivesEachTagBackItsName() {
        let walt = CrewFont.Tag.text(.lead(LeadLook(face: 1, hair: 4, shirt: 6))), judy = CrewFont.Tag.text(.plan)
        let felix = CrewFont.Tag.text(.other(shirt: 2)), mug = CrewFont.Picture.mug.character
        XCTAssertEqual(CrewFont.untagged("\(walt) hands it to \(judy), then \(felix)\(mug)."), "Walt hands it to Judy, then Felix.")
        XCTAssertEqual(CrewFont.untagged("No tags here."), "No tags here.")
    }

    // Three characters a tag, each its own: a head for every look, two name parts for every name in every shirt.
    func testEveryTagHasItsOwnCharactersAfterTheMarks() {
        let tags = CrewFont.Tag.kinds.map(CrewFont.Tag.text)
        XCTAssertEqual(tags.count, 7 + 4 * 6 * 7)
        XCTAssertTrue(tags.allSatisfy { $0.unicodeScalars.count == 3 })
        XCTAssertEqual(tags.map { $0.unicodeScalars.first!.value }, Array(CrewFont.Tag.firstScalar..<CrewFont.Tag.firstScalar + UInt32(tags.count)))
        XCTAssertEqual(CrewFont.Tag.firstScalar, CrewFont.Mark.worktree.scalar + 1)
        let parts = Set(tags.flatMap { $0.unicodeScalars.dropFirst().map(\.value) })
        XCTAssertEqual(parts, Set(CrewFont.Tag.firstScalar + UInt32(tags.count)...CrewFont.Tag.lastScalar))
        XCTAssertLessThanOrEqual(CrewFont.Tag.lastScalar, CrewFont.lastScalar, "past the end of Ghostty's font line")
        // A lead's hair changes the face, not the name parts; its shirt changes both.
        let one = CrewFont.Tag.text(.lead(LeadLook(face: 2, hair: 0, shirt: 3))), other = CrewFont.Tag.text(.lead(LeadLook(face: 2, hair: 5, shirt: 3)))
        XCTAssertNotEqual(one.unicodeScalars.first, other.unicodeScalars.first)
        XCTAssertEqual(Array(one.unicodeScalars.dropFirst()), Array(other.unicodeScalars.dropFirst()))
        XCTAssertNotEqual(Array(one.unicodeScalars.dropFirst()), Array(CrewFont.Tag.text(.lead(LeadLook(face: 2, shirt: 4))).unicodeScalars.dropFirst()))
        // Every head says whose it is.
        XCTAssertEqual(CrewFont.Tag.kinds.map { CrewFont.Tag.who(head: CrewFont.Tag.text($0).unicodeScalars.first!.value) }, CrewFont.Tag.kinds.map(CrewFont.Tag.who))
    }

    /// Each mark stands inside its two cells, from a little under the line to below the top.
    func testMarksFitTheirCells() {
        for mark in CrewFont.Mark.allCases {
            let points = mark.contours.flatMap { $0 }
            XCTAssertGreaterThan(points.map(\.x).min()!, 0, "\(mark)")
            XCTAssertLessThan(points.map(\.x).max()!, 1440, "\(mark)")
            XCTAssertGreaterThan(points.map(\.y).min()!, -200, "\(mark)")
            XCTAssertLessThan(points.map(\.y).max()!, 1000, "\(mark)")
        }
    }

    func testCodepointsFollowTheFixedOrder() {
        XCTAssertEqual(CrewFont.character(.general, .working), "\u{3F000}")
        XCTAssertEqual(CrewFont.character(.explore, .working), "\u{3F003}")
        XCTAssertEqual(CrewFont.character(.plan, .needsYou), "\u{3F007}")
        XCTAssertEqual(CrewFont.character(.other(shirt: 3), .done), "\u{3F014}")
        XCTAssertEqual(CrewFont.character(.lead(LeadLook()), .working), "\u{3F015}")
        XCTAssertEqual(CrewFont.character(.lead(LeadLook(face: 3, hair: 5, shirt: 6)), .working), "\u{3F0BC}")
        XCTAssertEqual(CrewFont.character(.lead(LeadLook(face: 3, hair: 5, shirt: 6)), .done), "\u{3F0BC}")
        // At work with a thing in hand: the crew, then the leads, six things each, after all the rest.
        XCTAssertEqual(CrewFont.character(.general, .working, holding: .thinking), "\u{3F0BD}")
        XCTAssertEqual(CrewFont.character(.explore, .working, holding: .searching), "\u{3F0C7}")
        XCTAssertEqual(CrewFont.character(.lead(LeadLook()), .working, holding: .reading), "\u{3F0E8}")
        XCTAssertEqual(CrewFont.character(.lead(LeadLook(face: 3, hair: 5, shirt: 6)), .working, holding: .calling), "\u{3F4D6}")
        // Nothing is held while it calls the person or once it is done.
        XCTAssertEqual(CrewFont.character(.plan, .needsYou, holding: .typing), "\u{3F007}")
    }

    /// `character` counts in fixed strides through these pools: a pool of another size would
    /// point every face after it at someone else, and the font's hash would not notice.
    func testEveryKindFindsItsOwnFace() {
        XCTAssertEqual(Person.otherShirts.count, 4)
        XCTAssertEqual(Person.leads.count, 4)
        XCTAssertEqual(Person.leadHair.count, 6)
        XCTAssertEqual(Person.leadShirts.count, 7)
        var kinds: [MascotKind] = [.general, .explore, .plan] + (0..<Person.otherShirts.count).map { .other(shirt: $0) }
        for face in 0..<Person.leads.count {
            for hair in 0..<Person.leadHair.count {
                for shirt in 0..<Person.leadShirts.count { kinds.append(.lead(LeadLook(face: face, hair: hair, shirt: shirt))) }
            }
        }
        for kind in kinds {
            let scalar = CrewFont.character(kind, .working).unicodeScalars.first!.value
            XCTAssertEqual(CrewFont.faces[Int(scalar - CrewFont.firstScalar)].person, kind.person, "\(kind)")
            for activity in Activity.allCases {
                let face = CrewFont.faces[Int(CrewFont.character(kind, .working, holding: activity).unicodeScalars.first!.value - CrewFont.firstScalar)]
                XCTAssertEqual(face.person, kind.person, "\(kind) \(activity)")
                XCTAssertEqual(face.holding, activity, "\(kind) \(activity)")
            }
        }
    }

    /// The rects of Explore's "needs you" face, laid back into a grid, are the cells the notch draws.
    func testTheJSONCarriesTheCellsTheNotchDraws() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: CrewFont.facesJSON()) as? [String: Any])
        let faces = try XCTUnwrap(json["faces"] as? [[String: Any]])
        func face(_ scalar: Int) throws -> [String: Any] {
            try XCTUnwrap(faces.first { $0["codepoint"] as? Int == scalar })
        }
        var grid = [[UInt32?]](repeating: [UInt32?](repeating: nil, count: 12), count: 12)
        for rect in try XCTUnwrap(face(0x3F004)["rects"] as? [[Any]]) {
            let x0 = rect[0] as! Int, x1 = rect[1] as! Int, y = rect[2] as! Int
            let hex = try XCTUnwrap(UInt32(rect[3] as! String, radix: 16))
            for x in x0..<x1 { grid[y][x] = hex }
        }
        let cells = MascotView.pose(.afro, status: .needsYou, callsOut: true, blink: false, wave: 0)
        XCTAssertEqual(grid, cells.map { $0.map(Person.afro.hex) })
        XCTAssertEqual(try face(0x3F005)["opacity"] as? Double, 0.45)

        // A face with a thing in hand is the notch's, standing still.
        grid = [[UInt32?]](repeating: [UInt32?](repeating: nil, count: 12), count: 12)
        for rect in try XCTUnwrap(face(0x3F0C7)["rects"] as? [[Any]]) {
            let x0 = rect[0] as! Int, x1 = rect[1] as! Int, y = rect[2] as! Int
            for x in x0..<x1 { grid[y][x] = try XCTUnwrap(UInt32(rect[3] as! String, radix: 16)) }
        }
        let working = MascotView.pose(.afro, status: .working, callsOut: false, blink: false, wave: 0)
        let held = MascotView.hold(.searching, working, under: Person.afro.underEyes, tick: MascotView.stillTick)
        XCTAssertEqual(grid, held.map { $0.map(Person.afro.hex) })

        // The mug, the fish and the van are the bar's, standing still.
        for (picture, frame, hex) in [(CrewFont.Picture.mug, Mug.frames[0], Mug.hex), (.fish, Fish.frames[0], Fish.hex), (.van, Van.frames[0], Van.hex)] {
            grid = [[UInt32?]](repeating: [UInt32?](repeating: nil, count: 12), count: 12)
            for rect in try XCTUnwrap(face(Int(picture.scalar))["rects"] as? [[Any]]) {
                let x0 = rect[0] as! Int, x1 = rect[1] as! Int, y = rect[2] as! Int
                for x in x0..<x1 { grid[y][x] = try XCTUnwrap(UInt32(rect[3] as! String, radix: 16)) }
            }
            XCTAssertEqual(grid, frame.map { $0.map(hex) }, "\(picture)")
        }
    }

    func testTheCommittedFontWasBuiltFromTheseFaces() throws {
        let url = PluginTests.root.appendingPathComponent(CrewFont.fileName)
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL), "Run testing/crew-font.sh")
        let graphics = try XCTUnwrap(CGFont(provider), "Run testing/crew-font.sh")
        let font = CTFontCreateWithGraphicsFont(graphics, 1200, nil, nil)
        XCTAssertEqual(CTFontCopyName(font, kCTFontUniqueNameKey) as String?, CrewFont.uniqueName, "Run testing/crew-font.sh")
        XCTAssertEqual(CTFontCopyFamilyName(font) as String, CrewFont.family)
        for scalar in CrewFont.faces.map(\.scalar) + CrewFont.Picture.allCases.map(\.scalar) + CrewFont.Mark.allCases.map(\.scalar) {
            let units = Array(String(UnicodeScalar(scalar)!).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), "U+\(String(scalar, radix: 16)) has no glyph")
            XCTAssertNotEqual(glyphs[0], 0)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advance, 1)
            XCTAssertEqual(advance.width, 1440, "U+\(String(scalar, radix: 16))")
        }
    }

    /// Not a test: `testing/crew-font.sh` runs it to hand the faces to the script that builds the font.
    func testWriteTheFacesForTheFont() throws {
        guard let out = ProcessInfo.processInfo.environment["CREW_FACES_OUT"] else {
            throw XCTSkip("Run by testing/crew-font.sh.")
        }
        try CrewFont.facesJSON().write(to: URL(fileURLWithPath: out))
    }
}
