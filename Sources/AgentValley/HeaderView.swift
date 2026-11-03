import SwiftUI

/// Which limits show the time until they reset.
enum LimitResets: Hashable {
    case all, tight, critical, none

    /// The order they are tried in as room runs out, once the bars have gone.
    static let ladder: [LimitResets] = [.all, .tight, .critical, .none]

    func shows(_ limit: PlanLimit) -> Bool {
        switch self {
        case .all: return true
        case .tight: return limit.resetMatters
        // The one that has run out, or all but: "when can I work again" is the question.
        case .critical: return limit.level == .critical
        case .none: return false
        }
    }
}

/// "3 need you" in bold red, its number swelling once each time `pulse` ticks. Only the number
/// swells, from its middle: the whole phrase used to swell from its left end and ran over the
/// words beside it.
struct NeedsYouCount: View {
    let count: Int
    var pulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let words = Format.needsYou(count)
        let number = String(count)
        HStack(spacing: 0) {
            Text(verbatim: number)
                .keyframeAnimator(initialValue: CGFloat(1), trigger: pulse) { digits, scale in
                    digits.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(Motion(reduced: reduceMotion).pulse, duration: 0.12)
                        SpringKeyframe(1, duration: 0.36, spring: .bouncy(duration: 0.3, extraBounce: 0.2))
                    }
                }
            Text(verbatim: String(words.dropFirst(number.count)))
        }
        .bold()
        .foregroundStyle(MascotFlag.red)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: words))
    }
}

/// The row under the notch: how many agents are working or quiet, and how much of the plan is used.
struct StatusRow: View {
    let working: Int
    let quiet: Int
    var needsYou = 0
    let display: PlanLimitsClient.Display
    let now: Date
    /// Leads to the settings, where the limits' switch is. nil when they are already open.
    let openSettings: (() -> Void)?
    /// Scrolls the list to whoever needs the person.
    var jump: (() -> Void)? = nil
    /// Counts the times one more agent started to wait. Each one is marked on the red count
    /// here too: open, the panel hides the bar's.
    var arrivals = 0

    var body: some View {
        HStack(spacing: 0) {
            // Whoever needs the person leads: it is the one thing here to act on, and a click
            // on it goes there.
            if needsYou > 0 {
                Button { jump?() } label: {
                    NeedsYouCount(count: needsYou, pulse: arrivals)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .contentShape(Rectangle())
                        .hoverFill()
                        .padding(.horizontal, -6)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(Format.jumpHelp)
                .accessibilityHint(Text(verbatim: Format.jumpHelp))
            }
            HStack(spacing: 0) {
                // "0 working" only when it is all there is to say, and then not as a headline.
                let alone = needsYou == 0 && quiet == 0
                if working > 0 || alone {
                    if needsYou > 0 { Text(verbatim: " · ").foregroundStyle(.white.opacity(0.6)) }
                    Text(verbatim: Format.working(working)).fontWeight(needsYou > 0 || working == 0 ? .regular : .bold)
                        .foregroundStyle(.white.opacity(working == 0 ? 0.6 : 1))
                }
                if quiet > 0 {
                    Text(verbatim: (needsYou > 0 || working > 0 ? " · " : "") + "\(quiet) quiet").foregroundStyle(.white.opacity(0.6))
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Format.summary(working: working, quiet: quiet)))
            .accessibilityHint(Text(verbatim: Format.countsHelp))
            .help(Text(verbatim: Format.countsHelp))
            // Wide enough that a full line gives up a reset time before the counts and the
            // limits run together.
            Spacer(minLength: 24)
            if let notice = Format.limitsNotice(display), openSettings == nil {
                Text(verbatim: notice).foregroundStyle(.white.opacity(0.6))
            } else if let notice = Format.limitsNotice(display), let openSettings {
                // The switch and what it reads are in the settings, so that is where this leads,
                // and the gear says so.
                Button(action: openSettings) {
                    HStack(spacing: 4) {
                        Text(verbatim: notice)
                        Image(systemName: "gearshape").font(.system(size: 9))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .hoverFill()
                    // The whole height of the row takes the click.
                    .frame(height: NotchGeometry.statusRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open settings")
            } else if case .loading = display {
                Text(verbatim: Format.limitsLoading).foregroundStyle(.white.opacity(0.6))
            } else if case .payPerUse(let use) = display {
                // Where a plan's name and its bars go: how it pays, and today's spend.
                HStack(spacing: 12) {
                    PlanBadge(name: use.via)
                    HStack(spacing: 6) {
                        Text(verbatim: "Today").foregroundStyle(.white.opacity(0.6))
                        Text(verbatim: Format.spentToday(use.spentToday)).fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
                .help(Format.payPerUseHelp(use))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: Format.payPerUseHelp(use)))
            } else if case .limits(let limits, let asOf) = display {
                HStack(spacing: 10) {
                    // Numbers from before a refresh that failed say how old they are. Dimming
                    // them made them hard to read and said nothing.
                    if let asOf {
                        Text(verbatim: Format.limitsAge(asOf: asOf, now: now)).foregroundStyle(.white.opacity(0.6)).fixedSize()
                            .help(Format.limitsAgeHelp)
                        // A rule after it: "1m old 5h" read as one run.
                        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 12)
                    }
                    // With every value at its longest the bars no longer fit beside the summary. The numbers do.
                    // Then, with all three counts on the left, the reset times go too: first those of
                    // limits with room to spare, and only at the last that of one near its end.
                    ViewThatFits(in: .horizontal) {
                        meters(limits, rings: true, badge: true)
                        // The plan's name goes first: it is the one thing here that never changes.
                        meters(limits, rings: true)
                        ForEach(LimitResets.ladder, id: \.self) { resets in
                            meters(limits, rings: false, resets: resets)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: NotchGeometry.statusRowHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
        }
    }

    private func meters(_ limits: PlanLimits, rings: Bool, resets: LimitResets = .all, badge: Bool = false) -> some View {
        HStack(spacing: 0) {
            if badge, let plan = limits.plan {
                PlanBadge(name: plan).padding(.trailing, 12)
            }
            if let limit = limits.fiveHour {
                LimitMeter(name: "5h", spoken: Format.limitHelp(spoken: "5-hour limit", percent: limit.percentLabel, reset: limit.resetLabel(now: now)),
                           limit: limit, ring: rings, reset: resets.shows(limit) ? limit.resetLabel(now: now) : nil)
            }
            // A rule between the two windows: the gap alone read as one run of numbers.
            if limits.fiveHour != nil, limits.week != nil {
                Rectangle().fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 12)
                    .padding(.horizontal, 12)
            }
            if let limit = limits.week {
                LimitMeter(name: "7d", spoken: Format.limitHelp(spoken: "Weekly limit", percent: limit.percentLabel, reset: limit.resetLabel(now: now)),
                           limit: limit, ring: rings, reset: resets.shows(limit) ? limit.resetLabel(now: now) : nil)
            }
        }
    }
}

/// The plan's name on a pill in Claude's orange: the fill faint, the letters a lighter orange, as the
/// terminal draws it.
struct PlanBadge: View {
    let name: String

    static func colour(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    var body: some View {
        Text(verbatim: name)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Self.colour(CrewFont.Badge.ink))
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(Capsule().fill(Self.colour(CrewFont.Badge.orange).opacity(CrewFont.Badge.fillOpacity)))
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(name) plan"))
    }
}

/// How much of the 5-hour limit (or the weekly one) is used, on the shut bar: a ring, since a wing of the bar has
/// no room for a number and its name. Yellow near the end as the number in the panel is, and
/// never red. Dim when the number is an old one: here there is no room to say its age.
struct LimitRingView: View {
    let ring: LimitRing
    static let size: CGFloat = 16
    private static let line: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().inset(by: Self.line / 2).stroke(Color.white.opacity(0.2), lineWidth: Self.line)
            Circle().inset(by: Self.line / 2).trim(from: 0, to: ring.limit.fraction)
                .stroke(LimitMeter.color(ring.limit.level), style: StrokeStyle(lineWidth: Self.line, lineCap: .round))
                // From the top, clockwise, as a clock fills.
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Self.size, height: Self.size)
        .opacity(ring.stale ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Format.ringLabel(ring)))
    }
}

/// One plan limit: its name, a ring, the percent used and, when known, the time until it resets.
/// Both windows show that time: the weekly one resets on a day people rarely remember.
struct LimitMeter: View {
    let name: String
    /// The whole of it in words, with the time until it resets even when the row has dropped that:
    /// read out, and shown to the pointer.
    let spoken: String
    let limit: PlanLimit
    let ring: Bool
    let reset: String?

    /// A limit near its end has its number in an outlined chip. Outlined: filled, it was the
    /// loudest mark on a panel about agents. Not red: red is for "needs you" alone.
    static func isChip(_ level: PlanLimit.Level) -> Bool { level == .critical }

    static func color(_ level: PlanLimit.Level) -> Color {
        // Yellow, not amber: amber sat next to the sonnet mascot's orange and read as the same thing.
        level == .normal ? .white : Color(red: 0.98, green: 0.82, blue: 0.25)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: name).foregroundStyle(.white.opacity(0.6))
            if ring {
                // As the terminal draws it: filled from the top, clockwise. White at every level:
                // the number carries the warning. Yellow as well made the limits the loudest
                // thing on a panel about agents.
                ZStack {
                    Circle().inset(by: 1.5).stroke(Color.white.opacity(0.2), lineWidth: 3)
                    Circle().inset(by: 1.5).trim(from: 0, to: limit.fraction)
                        .stroke(Color.white, lineWidth: 3)
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 13, height: 13)
            }
            // The percentage is the number to read; the time until reset sits back, marked by its icon
            // so two numbers side by side are not mistaken for one reading.
            let chip = Self.isChip(limit.level)
            Text(verbatim: limit.percentLabel).fontWeight(.semibold)
                .foregroundStyle(Self.color(limit.level))
                .padding(.horizontal, chip ? 4 : 0)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Self.color(limit.level).opacity(chip ? 1 : 0)))
            if let reset {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 8, weight: .semibold))
                    Text(verbatim: reset)
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 2)
            }
        }
        // The whole meter answers the pointer, gaps included.
        .contentShape(Rectangle())
        .help(spoken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }
}
