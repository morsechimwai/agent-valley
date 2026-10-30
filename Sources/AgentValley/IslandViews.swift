import SwiftUI

/// The island's alert pill: who has just started to wait, either side of the camera, and on what
/// in the row below it. Hidden from a screen reader: the arrival already says it aloud.
struct IslandAlertView: View {
    let card: SessionCard
    let row: AgentRow
    /// The camera's width, left empty in the middle of the first row: nothing is drawn over it.
    let gap: CGFloat

    var body: some View {
        // The step as the row in the list says it: for a permission wait, the command as run.
        let line = Format.alertLine(name: card.name, step: row.step)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    // The bar's mascot for this row: dotless, as "needs you" stands beside it.
                    MascotView(status: row.status, kind: MascotKind(type: row.info.type, look: AgentStore.looks([card])[row.id] ?? LeadLook()),
                               size: 18, flag: .needsYou, dot: false)
                    Text(verbatim: "needs you").bold().foregroundStyle(MascotFlag.red).fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: gap)
                WaitBadge(row: row)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxHeight: .infinity)
            // The name in bold, the step after it grey.
            (Text(verbatim: card.name).bold() + Text(verbatim: String(line.dropFirst(card.name.count))).foregroundColor(.white.opacity(0.6)))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: IslandGeometry.alertRow)
        }
        // Clear of the pill's round corners.
        .padding(.horizontal, 14)
        .accessibilityHidden(true)
    }
}
