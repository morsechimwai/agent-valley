import SwiftUI

/// What a lead asked a sub-agent, in full, under the row that is working on it. Scrolls past
/// `maxHeight`, unless it stands in a scroll of its own: one inside another catches the wheel.
struct AskedBox: View {
    let text: String
    var scrolls = true
    static let maxHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: CardStyle.line) {
            Text(verbatim: "Asked").font(CardStyle.aside).foregroundStyle(.white.opacity(0.6))
            // verbatim: the prompt is the lead's text and must never be read as Markdown or a link.
            let words = Text(verbatim: text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).lineLimit(nil)
            if scrolls {
                ScrollView { words }
                    .frame(maxHeight: Self.maxHeight)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                words
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// What a finished sub-agent handed back, in a box under the envelope: who and how long ago,
/// the first of it, and on Read all what it was asked and the whole of what came back.
struct HandBackBox: View {
    let row: AgentRow
    let reading: Bool
    let toggle: () -> Void
    let now: Date
    static let maxHeight: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: CardStyle.line) {
            // verbatim, all of it: what came back is the model's text, never Markdown or a link.
            VStack(alignment: .leading, spacing: CardStyle.line) {
                HStack(spacing: 8) {
                    Text(verbatim: Format.handedBack(type: row.info.type))
                    Text(verbatim: Format.handedBackAge(now.timeIntervalSince(row.info.handedBackAt ?? now))).foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                if !reading {
                    Text(verbatim: Format.handBackText(row.info)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            // Who, then what: the age and the cut are for the eye.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Format.handBackAloud(row)))
            if reading {
                // One scroll for what it was asked and what came back: a short panel has room for
                // one box of it, and a second scroll inside would catch the wheel.
                ScrollView {
                    VStack(alignment: .leading, spacing: CardStyle.line) {
                        if !row.info.asked.isEmpty { AskedBox(text: row.info.asked, scrolls: false) }
                        Text(verbatim: row.info.handedBack.isEmpty ? Format.handBackText(row.info) : row.info.handedBack)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).lineLimit(nil)
                    }
                }
                .frame(maxHeight: Self.maxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: toggle) {
                Text(verbatim: reading ? "Show less" : "Read all").foregroundStyle(.white.opacity(0.6)).contentShape(Rectangle()).hoverFill()
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        // Where the list is led on Read all: right under the box, as tall as the band that covers
        // the list's bottom edge. Laid out beside the box, so the box keeps its height.
        .overlay(alignment: .bottom) {
            if reading {
                Color.clear.frame(height: NotchGeometry.band).alignmentGuide(.bottom) { $0[.top] }
                    .id(ScrollTarget.readAllEnd(row.id)).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A thin line in the envelope's own manila: it came out of it. Nothing that glows or moves.
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(rgb(DoneEnvelope.hex("m") ?? 0).opacity(0.6), lineWidth: 1))
        // Where the envelope's line comes in: level with the header, at the border.
        .overlay(alignment: .topLeading) {
            Color.clear.frame(width: 1, height: 8 * 2 + 15).anchorPreference(key: CrewAnchors.self, value: .bounds) { [row.id: $0] }
        }
    }
}

/// A finished sub-agent under the envelope, on one line: its task and the first of what came
/// back. A click opens what came back in a box; one that handed nothing back has no click.
struct DoneLine: View {
    let row: AgentRow
    let open: () -> Void

    var body: some View {
        if row.handsBack {
            Button(action: open) { line.contentShape(Rectangle()).hoverFill() }
                .buttonStyle(.plain)
                // With the task: five of Felix's lines would sound alike by what came back alone.
                .accessibilityLabel(Text(verbatim: "\(Format.handedBack(type: row.info.type)): \(Format.doneLine(row))"))
                .accessibilityHint(Text(verbatim: "Read all"))
        } else {
            line
        }
    }

    private var line: some View {
        // verbatim: the task and what came back are transcript text.
        let text = Format.doneLine(row)
        return HStack(spacing: 8) {
            MascotView(status: row.status, kind: MascotKind(type: row.info.type), size: 14, flag: MascotFlag(status: row.status))
                // The anchor on the mascot, as on a sub-agent's row: the envelope's line ends at it.
                .anchorPreference(key: CrewAnchors.self, value: .bounds) { [row.id: $0] }
                .frame(width: 20)
                .help(Text(verbatim: row.info.type))
            Text(verbatim: text).lineLimit(1).help(Text(verbatim: text))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.6))
    }
}
