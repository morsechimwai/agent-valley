import XCTest
@testable import AgentValley

final class MascotTests: XCTestCase {
    private let everyone: [MascotKind] = Person.leads.indices.map { .lead(LeadLook(face: $0)) } + [.general, .explore, .plan, .other(shirt: 0)]

    private func pose(_ kind: MascotKind, _ status: AgentStatus, callsOut: Bool = false, blink: Bool = false, wave: Int = 0) -> [String] {
        MascotView.pose(kind.person, status: status, callsOut: callsOut, blink: blink, wave: wave).map { String($0) }
    }

    private func eyes(_ rows: [String]) -> [[Int]] {
        rows.enumerated().flatMap { y, row in row.enumerated().filter { $0.element == "o" }.map { [y, $0.offset] } }
    }

    func testEveryPersonIsTwelveByTwelveInColoursOfTheirOwn() {
        for kind in everyone {
            let person = kind.person
            XCTAssertEqual(person.rows.count, 12, "\(kind)")
            for row in person.rows {
                XCTAssertEqual(row.count, 12, "\(kind)")
                for cell in row where cell != "." {
                    XCTAssertNotNil(person.colour(cell), "\(kind): \(cell)")
                }
            }
        }
        XCTAssertEqual(Set(everyone.dropLast().map(\.person.rows)).count, Person.leads.count + 3)
    }

    // With nothing left to do the bar shows a coffee, its steam swaying between two frames.
    func testTheMugSwaysItsSteamAndNothingElse() {
        XCTAssertEqual(Mug.frames.count, 2)
        for frame in Mug.frames {
            XCTAssertEqual(frame.count, 12)
            for row in frame {
                XCTAssertEqual(row.count, 12)
                for cell in row where cell != "." { XCTAssertNotNil(Mug.colour(cell), "\(cell)") }
            }
        }
        let changed = Mug.frames[0].indices.filter { Mug.frames[0][$0] != Mug.frames[1][$0] }
        XCTAssertFalse(changed.isEmpty)
        XCTAssertTrue(changed.allSatisfy { !Mug.frames[0][$0].contains { "pPn".contains($0) } }, "only the steam moves")
    }

    // Once a plan limit has run out the bar shows a fish on the line, flicking its tail.
    func testTheFishFlicksItsTailAndNothingElse() {
        XCTAssertEqual(Fish.frames.count, 2)
        for frame in Fish.frames {
            XCTAssertEqual(frame.count, 12)
            for row in frame {
                XCTAssertEqual(row.count, 12)
                for cell in row where cell != "." { XCTAssertNotNil(Fish.colour(cell), "\(cell)") }
            }
        }
        let moved = (0..<12).flatMap { y in (0..<12).compactMap { x in
            Array(Fish.frames[0][y])[x] != Array(Fish.frames[1][y])[x] ? x : nil } }
        XCTAssertFalse(moved.isEmpty)
        XCTAssertTrue(moved.allSatisfy { $0 >= 9 }, "only the tail moves")
    }

    // Once the weekly limit has run out the bar shows the crew's van, the road going by under it.
    func testTheVanDrivesOnAndOnlyTheRoadMoves() {
        XCTAssertEqual(Van.frames.count, 2)
        for frame in Van.frames {
            XCTAssertEqual(frame.count, 12)
            for row in frame {
                XCTAssertEqual(row.count, 12)
                for cell in row where cell != "." { XCTAssertNotNil(Van.colour(cell), "\(cell)") }
            }
        }
        let changed = Van.frames[0].indices.filter { Van.frames[0][$0] != Van.frames[1][$0] }
        XCTAssertEqual(changed, [11], "only the road moves")
    }

    // A beard in nearly the colour of the shirt under it runs into it: of all the hair and
    // shirts, these two pairs are that close, and only these.
    func testOnlyGingerOnOrangeAndBlondeOnGoldAreTooClose() {
        let close = Person.leadHair.flatMap { hair in Person.leadShirts.filter { Person.close(hair, $0) }.map { [hair, $0] } }
        XCTAssertEqual(close, [[0xC0622A, 0xE07B39], [0xD8B26A, 0xE5B630]])
    }

    // Every pose works on every face: eyes to shut and turn, a mouth to open with a row under it.
    func testEveryFaceHasEyesAndAMouth() {
        for kind in everyone {
            let rows = kind.person.rows
            XCTAssertEqual(eyes(rows).count % 2, 0, "\(kind) needs two matching eyes")
            XCTAssertGreaterThan(eyes(rows).count, 0, "\(kind)")
            let mouth = rows.firstIndex { $0.contains("m") }
            XCTAssertNotNil(mouth, "\(kind)")
            XCTAssertLessThan((mouth ?? 11) + 1, rows.count, "\(kind): the open mouth takes the row under it")
        }
    }

    // The person says what kind of agent it is.
    func testBuiltInAgentTypesHaveTheirOwnPerson() {
        XCTAssertEqual(MascotKind(type: "main"), .lead(LeadLook()))
        XCTAssertEqual(MascotKind(type: "main", look: LeadLook(face: 2, hair: 1, shirt: 3)), .lead(LeadLook(face: 2, hair: 1, shirt: 3)))
        XCTAssertEqual(MascotKind(type: "general-purpose"), .general)
        XCTAssertEqual(MascotKind(type: "Explore"), .explore)
        XCTAssertEqual(MascotKind(type: "Plan"), .plan)
        // Before the agent's meta file has been read there is no type yet.
        XCTAssertEqual(MascotKind(type: ""), .general)
    }

    // Any other type is the general-purpose person, in a shirt picked by the type's name: the
    // same on every launch, and never the general-purpose one's own.
    func testACustomTypeIsTheGeneralPersonInAShirtOfItsOwn() {
        for type in ["acme:code-reviewer", "implementer", "design-reviewer", "explorer", "x"] {
            let kind = MascotKind(type: type)
            guard case .other = kind else { XCTFail(type); continue }
            XCTAssertEqual(kind, MascotKind(type: type), type)
            XCTAssertEqual(kind.person.rows, MascotKind.general.person.rows, type)
            XCTAssertNotEqual(kind.person.shirt, MascotKind.general.person.shirt, type)
        }
        // Pinned: a change to how names are hashed would recolour everyone's agents.
        XCTAssertEqual(MascotKind(type: "implementer"), .other(shirt: 1))
        XCTAssertEqual(MascotKind(type: "acme:code-reviewer"), .other(shirt: 2))
    }

    // The one that calls the person opens its mouth and waves, on every face.
    func testCallingOutOpensTheMouthAndWaves() {
        for kind in everyone {
            XCTAssertFalse(pose(kind, .needsYou).joined().contains("M"), "\(kind)")
            XCTAssertTrue(pose(kind, .needsYou, callsOut: true).joined().contains("M"), "\(kind)")
            XCTAssertNotEqual(pose(kind, .needsYou, callsOut: true, wave: 0), pose(kind, .needsYou), "\(kind): a hand goes up")
            XCTAssertNotEqual(pose(kind, .needsYou, callsOut: true, wave: 0), pose(kind, .needsYou, callsOut: true, wave: 1), "\(kind): and moves")
        }
    }

    // Quiet: it may be waiting, it may be stuck. It looks aside, both eyes the same way.
    func testAQuietPersonLooksAside() {
        for kind in everyone {
            let working = eyes(pose(kind, .working)), quiet = eyes(pose(kind, .quiet))
            XCTAssertEqual(quiet.count, working.count, "\(kind)")
            XCTAssertNotEqual(quiet, working, "\(kind)")
            XCTAssertTrue(zip(working, quiet).allSatisfy { $1[1] >= $0[1] }, "\(kind): never towards the other side")
        }
    }

    func testABlinkShutsEveryEyeAndDoneShutsThemHalfway() {
        for kind in everyone {
            XCTAssertTrue(eyes(pose(kind, .working, blink: true)).isEmpty, "\(kind)")
            XCTAssertLessThan(eyes(pose(kind, .done)).count, eyes(pose(kind, .working)).count, "\(kind)")
        }
    }

    // Under Reduce Motion nothing moves, so the three states must differ while standing still.
    func testWorkingQuietAndDoneLookDifferentWithoutMotion() {
        XCTAssertFalse(MascotView.fade(.working) == MascotView.fade(.quiet))
        XCTAssertFalse(MascotView.fade(.working) == MascotView.fade(.done))
        XCTAssertFalse(MascotView.fade(.quiet) == MascotView.fade(.done))
        // Done keeps its own colours, faint: who it was still shows.
        XCTAssertEqual(MascotView.fade(.done), 0.4)
    }

    // An agent with a question up is not stalled or broken: unfaded, standing still, flagged.
    func testAMascotThatNeedsThePersonIsFlaggedNotDimmed() {
        XCTAssertTrue(MascotView.fade(.needsYou) == MascotView.fade(.working))
        XCTAssertFalse(MascotView.animates(.needsYou, reduceMotion: false))
        // Red is kept for the one state that is certain to need the person; quiet may or may not.
        XCTAssertEqual([AgentStatus.working, .quiet, .needsYou, .done].map(MascotFlag.init(status:)), [nil, .quiet, .needsYou, nil])
    }

    // The hand waves only for the one calling out, and under Reduce Motion it stays up, still.
    func testOnlyTheOneCallingOutWavesAndNeverUnderReduceMotion() {
        XCTAssertTrue(MascotView.waves(.needsYou, reduceMotion: false))
        XCTAssertFalse(MascotView.waves(.needsYou, reduceMotion: true))
        XCTAssertFalse(MascotView.waves(.quiet, reduceMotion: false))
        XCTAssertFalse(MascotView.waves(nil, reduceMotion: false))
    }

    // Red means "needs you" and nothing else. A limit near its end is yellow like a high one,
    // set apart by a filled chip.
    func testALimitNearItsEndIsMarkedWithoutRed() {
        XCTAssertEqual(LimitMeter.color(.critical), LimitMeter.color(.high))
        XCTAssertNotEqual(LimitMeter.color(.high), LimitMeter.color(.normal))
        XCTAssertEqual([PlanLimit.Level.normal, .high, .critical].map(LimitMeter.isChip), [false, false, true])
    }

    func testOnlyAWorkingMascotMovesAndNeverUnderReduceMotion() {
        XCTAssertTrue(MascotView.animates(.working, reduceMotion: false))
        XCTAssertFalse(MascotView.animates(.working, reduceMotion: true))
        XCTAssertFalse(MascotView.animates(.quiet, reduceMotion: false))
        XCTAssertFalse(MascotView.animates(.done, reduceMotion: false))
        // Claude Code calls it busy, but nothing has been written for minutes: it must not go
        // on moving as if all were well.
        XCTAssertFalse(MascotView.animates(.working, reduceMotion: false, still: true))
    }

    // The website draws the people from these numbers, so a dye's paler half is a colour of its own.
    func testCellsHaveColoursAsNumbersAndThePalerDyeIsMixedTowardWhite() {
        XCTAssertEqual(Person.guru.hex("c"), 0xE07B39)
        XCTAssertEqual(Person.guru.hex("C"), paler(0xE07B39, by: 0.45))
        XCTAssertEqual(paler(0x000000, by: 0.45), 0x737373)
        XCTAssertEqual(paler(0xE07B39, by: 0), 0xE07B39)
        XCTAssertEqual(paler(0xFFFFFF, by: 0.45), 0xFFFFFF)
        XCTAssertNil(Person.guru.hex("."))
        XCTAssertEqual(Mug.hex("p"), 0xF2EAD8)
        XCTAssertNil(Mug.hex("."))
    }

    // At work it holds what its open call is about. A call with no picture leaves its hands empty.
    func testTheOpenCallSaysWhatIsInHand() {
        XCTAssertEqual(Activity(tool: nil), .thinking)
        XCTAssertEqual(Activity(tool: "Read"), .reading)
        XCTAssertEqual(Activity(tool: "Edit"), .typing)
        XCTAssertEqual(Activity(tool: "Bash"), .running)
        XCTAssertEqual(Activity(tool: "Grep"), .searching)
        XCTAssertEqual(Activity(tool: "Agent"), .calling)
        XCTAssertNil(Activity(tool: "TodoWrite"))
        XCTAssertNil(Activity(tool: "mcp__github__create_issue"))
    }

    // Every thing fits every face inside the twelve by twelve, in colours the person has, and
    // moves while it is held.
    func testEveryThingInHandFitsEveryFaceAndMoves() {
        for kind in everyone {
            let person = kind.person
            let bare = MascotView.pose(person, status: .working, callsOut: false, blink: false, wave: 0)
            for activity in Activity.allCases {
                let frames = (0..<8).map { MascotView.hold(activity, bare, under: person.underEyes, tick: $0) }
                for cells in frames {
                    XCTAssertEqual(cells.map(\.count), Array(repeating: 12, count: 12), "\(kind) \(activity)")
                    for cell in cells.joined() where cell != "." { XCTAssertNotNil(person.colour(cell), "\(kind) \(activity): \(cell)") }
                    XCTAssertNotEqual(cells, bare, "\(kind) \(activity)")
                }
                XCTAssertGreaterThan(Set(frames).count, 1, "\(kind) \(activity) moves")
            }
        }
    }

    // In hand for most of each round, put down for the rest, and then it thinks: a mascot at work
    // never stands bare, as a bob read as idle. Under Reduce Motion the thing stays in hand.
    func testTheThingIsPutDownForPartOfEachRoundAndAThoughtTakesItsPlace() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let at = { (seconds: TimeInterval, reduced: Bool) in MascotView.inHand(.reading, atWork: true, since: start, at: start + seconds, reduceMotion: reduced) }
        XCTAssertEqual(at(1, false), .reading)
        XCTAssertEqual(at(7, false), .thinking)
        XCTAssertEqual(at(9, false), .reading)
        XCTAssertEqual(at(7, true), .reading)
        // A call with no picture of its own: a thought, moving or not.
        XCTAssertEqual(MascotView.inHand(nil, atWork: true, since: start, at: start, reduceMotion: false), .thinking)
        XCTAssertEqual(MascotView.inHand(nil, atWork: true, since: start, at: start, reduceMotion: true), .thinking)
        // Not at work, stalled, or calling the person: nothing in hand.
        XCTAssertNil(MascotView.inHand(.reading, atWork: false, since: start, at: start + 1, reduceMotion: false))
        XCTAssertNil(MascotView.inHand(nil, atWork: false, since: start, at: start, reduceMotion: false))
    }

    func testTheJobScreenScrollsItsOutputAndNothingElse() {
        XCTAssertEqual(JobScreen.frames.count, 6)
        for frame in JobScreen.frames {
            XCTAssertEqual(frame.count, 12)
            for row in frame {
                XCTAssertEqual(row.count, 12)
                for cell in row where cell != "." { XCTAssertNotNil(JobScreen.colour(cell), "\(cell)") }
            }
            // The case, the stand and the keyboard hold still.
            XCTAssertEqual(Array(frame[0...3]) + Array(frame[9...11]), Array(JobScreen.frames[0][0...3]) + Array(JobScreen.frames[0][9...11]))
        }
        XCTAssertEqual(Array(JobScreen.frames[0][4...8]), [".veggggeeev.", ".veeeeeeeev.", ".veggegggev.", ".veeeeeeeev.", ".vegeeeeeev."])
    }

    func testTheJobScreenIsTheTerminalTheCrewHolds() {
        for cell: Character in ["v", "e", "g", "d"] { XCTAssertEqual(JobScreen.hex(cell), Person.guru.hex(cell), "\(cell)") }
    }

    func testTheServerSendsWavesAndHoldsTheRackStill() {
        for frame in JobServer.frames {
            XCTAssertEqual(frame.count, 12)
            for row in frame {
                XCTAssertEqual(row.count, 12)
                for cell in row where cell != "." { XCTAssertNotNil(JobScreen.colour(cell), "\(cell)") }
            }
            // The rack is the left six columns, the same in every frame.
            XCTAssertEqual(frame.map { $0.prefix(6) }, JobServer.frames[0].map { $0.prefix(6) })
        }
        // The first frame, the still one, shows both waves: three lights, four and eight cells of wave.
        XCTAssertEqual(JobServer.frames[0].joined().filter { $0 == "g" }.count, 3 + 4 + 8)
    }

    func testTheEyeIsTwelveCellsSquare() {
        XCTAssertEqual(JobEye.cells.count, 12)
        XCTAssertTrue(JobEye.cells.allSatisfy { $0.count == 12 })
        XCTAssertEqual(JobEye.hex("w"), 0xCFC6A8)
        XCTAssertEqual(JobEye.hex("k"), 0x1E1E1E)
    }
}
