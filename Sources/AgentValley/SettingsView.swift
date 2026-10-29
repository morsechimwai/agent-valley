import AppKit
import ServiceManagement
import SwiftUI

/// The pages of the settings, split the way a Mac app's settings are. One long page had grown to
/// twenty rows; four pages, until 2026-10-15, left two of them a row or two; two pages then grew
/// to fifteen rows on one. Five since 2026-10-21, each on one subject, and none of them bare: a
/// row that hangs on a switch is dimmed while it is off, not taken away.
enum SettingsTab: String, CaseIterable {
    /// What the list shows and counts, and opening at login.
    case general
    /// The sounds, and the hours they keep still.
    case sounds
    /// The key that opens the panel, and where a session leads.
    case shortcuts
    /// What is put into Claude Code by hand: the plugin that answers, and the crew in the terminal.
    case claudeCode
    /// Which app this is and what it will not do, its updates, and the way out at the end.
    case about

    /// The word on its tab.
    var label: String { self == .claudeCode ? "Claude Code" : rawValue.capitalized }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var answers: AnswerStore
    @ObservedObject var limits: PlanLimitsClient
    @ObservedObject var updates: Updates
    /// Why the shortcut does nothing although it is switched on, when that is so.
    var shortcutNote: String? = nil
    /// The displays connected now.
    var displays: [DisplayChoice] = []
    /// The page shown. Kept by the panel, which also sends the person to a row on one.
    @Binding var tab: SettingsTab
    /// Back to the agents.
    let back: () -> Void
    /// The command last copied, so its button can say so for a moment.
    @State private var copied: String?
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    /// Install is running. Its button waits, so a second press does not run it twice.
    @State private var installing = false
    /// What became of the last press of Install, while this page is up.
    @State private var installResult: PluginInstall.Result?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // The way back, in words: the gear that led here is the only other one.
                BackToAgents(action: back)
                Spacer(minLength: 0)
                PageTabs(title: "Settings pages", pages: SettingsTab.allCases, label: { $0.label }, selection: $tab,
                         note: { $0 == .about ? updates.waiting.map(Format.updateWaiting) : nil })
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            // What scrolls under it does not show through, and fades in across the room under
            // the pages rather than being cut through a line of words. Within it: unscrolled,
            // nothing of the page is under it.
            .background {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 12)
                }
            }
            // The way back and the pages stay at the top while a long page scrolls under them:
            // moved down by as far as the page has gone up. Not a pinned header of a lazy
            // stack: that is drawn after the page, and a screen reader read the pages last.
            .visualEffect { content, proxy in
                content.offset(y: max(0, -proxy.frame(in: .scrollView).minY))
            }
            .zIndex(1)
            VStack(alignment: .leading, spacing: 12) {
                switch tab {
                case .general: general
                case .sounds: sounds
                case .shortcuts: shortcuts
                case .claudeCode: claudeCode
                case .about: about
                }
            }
            .padding([.horizontal, .bottom], 14)
        }
    }

    @ViewBuilder private var general: some View {
        SettingGroup {
            SettingRow(title: "Idle sessions", caption: Format.idleCaption) {
                ChoiceBar(title: "Idle sessions", choices: IdleSessions.allCases, label: { $0.label }, selection: $settings.idleSessions)
            }
            // The panel's own two words for what has stopped: a session is idle, an agent is done.
            SettingRow(title: Format.keepTitle, caption: Format.keepCaption) {
                ChoiceBar(title: Format.keepTitle, choices: Settings.keepFinishedChoices, label: { "\($0)m" }, selection: $settings.keepFinishedMinutes)
            }
        }
        SettingGroup {
            SettingRow(title: "Plan limits", caption: Format.limitsCaption, note: limitsNote) {
                Switch(title: "Plan limits", isOn: $settings.planLimits)
            }
            SettingRow(title: "Token use", caption: Format.usageCaption) {
                Switch(title: "Token use", isOn: $settings.tokenUse)
            }
        }
        // Where the app sits on this Mac: both set once and left. The displays in a list down
        // the page, not a bar across it: their names run long.
        SettingGroup {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow(title: "Display", caption: Format.displayChoiceCaption) { EmptyView() }
                ChoiceBar(title: "Display", choices: [.automatic] + displays, label: \.name, selection: shownDisplay, vertical: true)
            }
            SettingRow(title: "Open at login", note: loginError) {
                Switch(title: "Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
            }
        }
    }

    /// A picked display that is not connected shows as Automatic, which is where the bar is.
    /// It stays stored, so the bar goes back to it when it is plugged in again.
    private var shownDisplay: Binding<DisplayChoice> {
        Binding(get: { displays.first { $0.id == settings.display } ?? .automatic },
                set: { settings.display = $0.id })
    }

    @ViewBuilder private var sounds: some View {
        SettingGroup {
            SettingRow(title: "Sounds", caption: Format.soundsCaption) {
                Switch(title: "Sounds", isOn: $settings.sounds)
            }
            SettingRow(title: "Volume") {
                VolumeSlider(title: "Volume", value: $settings.soundVolume)
            }
            .dimmed(!settings.sounds)
        }
        SettingGroup {
            SettingRow(title: "Voice") {
                ChoiceBar(title: "Voice", choices: SoundStyle.allCases, label: { $0.title }, selection: $settings.soundStyle)
            }
            SettingRow(title: "When an agent needs you") {
                Switch(title: "Sound when an agent needs you", isOn: $settings.soundNeedsYou)
            }
            SettingRow(title: "When a session finishes", caption: Format.finishedCaption) {
                Switch(title: "Sound when a session finishes", isOn: $settings.soundFinished)
            }
            SettingRow(title: "Remind again", caption: Format.remindCaption) {
                ChoiceBar(title: "Remind again", choices: Settings.remindChoices, label: { $0 == 0 ? "Off" : "\($0)m" }, selection: $settings.remindMinutes)
            }
            SettingRow(title: "When the crew leaves and comes back", caption: settings.planLimits ? nil : Format.scenesCaption) {
                Switch(title: "When the crew leaves and comes back", isOn: $settings.soundScenes)
                    .dimmed(!settings.planLimits || settings.soundStyle == .chimes)
            }
        }
        .dimmed(!settings.sounds)
        SettingGroup {
            SettingRow(title: "Quiet hours") {
                Switch(title: "Quiet hours", isOn: $settings.quietHours)
            }
            Group {
                SettingRow(title: "From") {
                    HourStepper(title: "Quiet hours from", hour: $settings.quietFrom)
                }
                SettingRow(title: "Until") {
                    HourStepper(title: "Quiet hours until", hour: $settings.quietUntil)
                }
            }
            .dimmed(!settings.quietHours)
        }
        .dimmed(!settings.sounds)
    }

    @ViewBuilder private var shortcuts: some View {
        SettingGroup {
            SettingRow(title: "Shortcut", caption: Format.shortcutCaption, note: settings.shortcut ? shortcutNote : nil) {
                Switch(title: "Keyboard shortcut", isOn: $settings.shortcut)
            }
            // More than one: another app can hold a chord already.
            SettingRow(title: "Shortcut keys") {
                ChoiceBar(title: "Shortcut keys", choices: ShortcutKey.allCases, label: { Format.shortcut($0) }, selection: $settings.shortcutKey)
            }
            .dimmed(!settings.shortcut)
        }
        .id(ScrollTarget.shortcutID)
        SettingGroup {
            SettingRow(title: "Go to the session's tab", caption: Format.tabCaption) {
                Switch(title: "Go to the session's tab", isOn: $settings.goToTab)
            }
        }
    }

    @ViewBuilder private var claudeCode: some View {
        SettingGroup {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow(title: "Answer from the notch", caption: Format.answersCaption(installed: answers.pluginInstalled)) {
                    Switch(title: "Answer from the notch", isOn: $settings.answers)
                }
                // Names go over the same socket: with Answer off there is no way in.
                SettingRow(title: "Crew names in Claude Code", caption: Format.crewNamesCaption) {
                    Switch(title: "Crew names in Claude Code", isOn: $settings.crewNames)
                }
                .disabled(!settings.answers)
                // Shown with the switch off too while the plugin is not in: the cards that wait send people here.
                if settings.answers || !answers.pluginInstalled { install }
            }
            // What was put in by hand comes out by hand, and the way out is there whether or not
            // the switch is on: switching off does not take the plugin out. After the command
            // that puts it in, and folded: it is rarely needed.
            Fold(title: Format.removePlugin) {
                commandRow(Format.uninstallCommand, spoken: "Copy the command that removes the plugin")
            }
        }
        SettingGroup {
            SettingRow(title: Format.crewTitle, caption: Format.crewWhat) { EmptyView() }
            let crewExe = Format.stablePath(Bundle.main.executableURL ?? Bundle.main.bundleURL)
            Fold(title: Format.crewSetup) {
                Text(verbatim: Format.crewSteps.run).settingCaption()
                commandRow(Format.crewCommand(executable: crewExe, "install"), spoken: "Copy the command that puts the crew in the terminal")
                Text(verbatim: Format.crewSteps.restart).settingCaption()
            }
            Fold(title: Format.removeCrew) {
                commandRow(Format.crewCommand(executable: crewExe, "uninstall"), spoken: "Copy the command that takes the crew out of the terminal")
                Text(verbatim: Format.removeCrewNote).settingCaption()
            }
        }
    }

    /// What the plugin does and how to put it in, under its switch. The person puts it in: the
    /// button runs Claude Code's own command only when pressed, and the app never writes into ~/.claude.
    @ViewBuilder private var install: some View {
        VStack(alignment: .leading, spacing: 6) {
            let command = Format.installCommand(resources: Bundle.main.resourceURL ?? Bundle.main.bundleURL, replacing: answers.pluginLost)
            // What it does before how to put it in, and each in full: none of it may end in "…".
            Text(verbatim: Format.pluginWhat).settingCaption()
            if !answers.pluginInstalled || answers.pluginLost {
                installButton(command).padding(.top, 2)
                Text(verbatim: Format.installSteps.run).settingCaption().padding(.top, 2)
                // Whole, however long the app's path is: it can be run in a terminal as it stands.
                commandRow(command, spoken: "Copy the install command")
                if answers.pluginLost {
                    // In full white, as a failure on this page is.
                    Text(verbatim: Format.pluginLostNote).settingCaption(failure: true)
                }
                Text(verbatim: Format.marketplaceNote).settingCaption()
            }
            if let installResult {
                Text(verbatim: Format.installResult(installResult)).settingCaption(failure: installResult != .installed)
            }
            Text(verbatim: Format.installSteps.restart).settingCaption()
            if let status = Format.answersStatus(answers.state, now: Date()) {
                // A failure in full white, as every other one on this page.
                Text(verbatim: status).settingCaption(failure: answers.state.isFailure).lineLimit(3)
            }
        }
    }

    /// 0.1 from Homebrew is still installed: the one command that takes it out, first on the
    /// page the panel's Fix it opens.
    @ViewBuilder private var oldCopy: some View {
        // In full white, as a failure on this page is.
        Text(verbatim: Format.oldCopyNote).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        commandRow(AppPlace.removeOldFormula, spoken: "Copy the command that takes our 0.1 out")
    }

    @ViewBuilder private var about: some View {
        if updates.oldCopyLeft { oldCopy }
        // Which app this is and what it will not do, for someone it was handed to.
        SettingGroup {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: Format.about(name: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
                                            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String))
                    .fontWeight(.semibold)
                // In full: a promise cut short is no promise.
                Text(verbatim: Format.readOnly(updates: updates.isAvailable)).settingCaption()
            }
        }
        // Only in a release: a build to work on the app has nothing to update from.
        if updates.isAvailable {
            SettingGroup {
                SettingRow(title: Format.updatesTitle, caption: Format.updatesCaption) {
                    Switch(title: Format.updatesTitle, isOn: Binding(get: { updates.checksAutomatically }, set: { updates.checksAutomatically = $0 }))
                }
                // What the green dot on the gear and this tab is for, a click from its window.
                if let version = updates.waiting {
                    Button { updates.show() } label: { quietLabel(Format.updateWaiting(version: version) + " " + Format.updateLook, symbol: "", dot: true) }
                        .buttonStyle(.plain)
                } else {
                    Button { updates.checkNow() } label: { quietLabel(Format.checkNow, symbol: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.plain)
                }
            }
            SettingGroup {
                SettingRow(title: Format.dailyCountTitle, caption: Format.dailyCountCaption) {
                    Switch(title: Format.dailyCountTitle, isOn: $settings.dailyCount)
                }
            }
        }
        SettingGroup {
            // The crew's tip jar. The browser opens it; the app itself stays offline.
            Button { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/morsechimwai")!) } label: {
                quietLabel("Sponsor the crew", symbol: "heart")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens GitHub Sponsors in your browser")
            // A new issue with the version, macOS and Mac filled in. Also only the browser: the person
            // reads it all before they send it.
            Button {
                NSWorkspace.shared.open(Format.bugReport(
                    version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                    macOS: ProcessInfo.processInfo.operatingSystemVersion, mac: Self.macModel))
            } label: {
                quietLabel("Report a bug", symbol: "ladybug")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a new GitHub issue in your browser")
            Button { NSWorkspace.shared.open(URL(string: "https://agentvalley.app/privacy/")!) } label: {
                quietLabel("Privacy", symbol: "hand.raised")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the privacy page in your browser")
            // Ours and Sparkle's, put in the bundle by build-app.sh; a build run straight from swift has none.
            if let licenses = Bundle.main.url(forResource: "Licenses", withExtension: "txt") {
                Button { NSWorkspace.shared.open(licenses) } label: { quietLabel("Licenses", symbol: "doc.text") }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the license text")
            }
        }
        // Last, quiet and out of the boxes: the rarest action, kept away from anything clicked in passing.
        Button { NSApp.terminate(nil) } label: {
            quietLabel(Format.quit(appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String), symbol: "power")
        }
        .buttonStyle(.plain)
    }

    /// A row-wide button in grey text that lights up under the pointer, its symbol before it.
    /// The symbols stand in one column, whatever their width; the words say what they do.
    /// `dot`: the green dot of an update in the symbol's place, and the words in full white.
    private func quietLabel(_ title: String, symbol: String, dot: Bool = false) -> some View {
        HStack(spacing: 8) {
            Group {
                if dot { UpdateDot() } else { Image(systemName: symbol).font(.system(size: 11)) }
            }
            .frame(width: 14).accessibilityHidden(true)
            Text(verbatim: title)
        }
            .foregroundStyle(.white.opacity(dot ? 1 : 0.6))
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(Rectangle())
            .hoverFill()
            .padding(.horizontal, -6)
    }

    /// The Mac's model, such as Mac15,6: tells which notch it has.
    private static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    /// Why the limits are missing, under their switch: the status row only has room to say that they are.
    private var limitsNote: String? {
        if case .unavailable(let reason) = limits.display { return Format.limitsReason(reason) }
        return nil
    }

    /// Runs the install command off the main thread, then turns the switch on once it is in.
    private func installButton(_ command: String) -> some View {
        Button {
            installing = true
            installResult = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let result = PluginInstall.run(command)
                DispatchQueue.main.async {
                    installing = false
                    installResult = result
                    guard result == .installed else { return }
                    settings.answers = true
                    answers.checkPlugin()
                }
            }
        } label: {
            Text(verbatim: installing ? Format.installing : Format.installButton).panelButton(filled: true)
        }
        .buttonStyle(.plain)
        .disabled(installing)
    }

    /// A command to run in a terminal, in full, with a button that copies it.
    private func commandRow(_ command: String, spoken: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: command).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 8)
            Button { copy(command) } label: {
                Text(verbatim: copied == command ? "Copied" : "Copy")
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.35)))
                    .contentShape(Rectangle())
                    .hoverFill()
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(Text(verbatim: spoken))
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = command
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == command { copied = nil } }
    }

    /// macOS owns this setting; the switch shows whatever the system ends up with.
    private func setOpenAtLogin(_ on: Bool) {
        var failure: Error?
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error
        }
        if on, failure == nil { settings.loginItemPath = Bundle.main.bundlePath }
        let status = SMAppService.mainApp.status
        loginError = LoginItem.message(wanted: on, status: status, error: failure, appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        openAtLogin = status == .enabled
    }
}

enum LoginItem {
    /// macOS keeps a login item by the app's path, and Homebrew gives each version a folder of
    /// its own and deletes the one before: after an upgrade the item names an app that is gone.
    /// Opened from a new place, the app registers again, from there.
    static func follow(_ settings: Settings, to path: String = Bundle.main.bundlePath) {
        guard SMAppService.mainApp.status == .enabled, settings.loginItemPath != path else { return }
        try? SMAppService.mainApp.unregister()
        if (try? SMAppService.mainApp.register()) != nil { settings.loginItemPath = path }
    }

    /// What to say under the switch after trying to set it, or nil when it simply worked.
    static func message(wanted: Bool, status: SMAppService.Status, error: Error?, appName: String? = nil) -> String? {
        if let error {
            return "Could not \(wanted ? "enable" : "disable"): \(error.localizedDescription)"
        }
        // Registered, but switched off by hand in System Settings: macOS will not run it until allowed.
        if wanted, status == .requiresApproval {
            return "Allow \(appName ?? "this app") in System Settings > General > Login Items"
        }
        return nil
    }
}

/// The way back to the list, in words, from whatever stands in its place or over it.
struct BackToAgents: View {
    var title = "Agents"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left").font(.system(size: 9, weight: .bold))
                Text(verbatim: title)
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
            .hoverFill()
            .padding(.leading, -6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Back to " + title.lowercased()))
    }
}

/// One line that unfolds what is rarely needed, so it does not push Quit off the page.
private struct Fold<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { open.toggle() } label: {
                HStack(spacing: 8) {
                    FoldMark(open: open)
                    Text(verbatim: title)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
                .contentShape(Rectangle())
                .hoverFill()
                .padding(.horizontal, -6)
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(verbatim: open ? "Shown" : "Hidden"))
            if open { content.padding(.leading, 17) }
        }
    }
}

/// The pages of the legend: on one page the list of keys ran off the foot of the panel.
enum LegendTab: String, CaseIterable {
    /// Who a mascot is, what its dot says, and the words on its row.
    case mascots
    /// The numbers and the mascot on the bar, with the panel shut.
    case bar
    case keys

    /// The word on its tab.
    var label: String { rawValue.capitalized }
}

/// What the creatures and the bar's numbers mean, drawn as the panel draws them.
struct Legend: View {
    /// The page shown. Kept by whoever shows the legend, so that its key can open it on the keys.
    @Binding var tab: LegendTab
    /// Puts the legend away, where it stands at the head of the list. Nil on the settings page,
    /// which has its own way back.
    var back: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // As on the settings page: the way back on the left, the pages on the right.
                if let back {
                    BackToAgents(action: back)
                    Spacer(minLength: 0)
                }
                PageTabs(title: Format.legendTitle, pages: LegendTab.allCases, label: { $0.label }, selection: $tab)
            }
            switch tab {
            case .mascots: mascots
            case .bar: bar
            case .keys: keys
            }
        }
    }

    @ViewBuilder private var mascots: some View {
        caption(Format.legendCaption)
        // Standing still: only who it is is the point here.
        HStack(spacing: 12) {
            item("session", kinds: Person.leads.indices.map { .lead(LeadLook(face: $0, hair: $0, shirt: $0)) })
            item("general-purpose", kinds: [.general])
            item("Explore", kinds: [.explore])
            item("Plan", kinds: [.plan])
        }
        // Any other type of agent is the general-purpose person in one of these shirts, picked by
        // its name, always the same one.
        item("other types, each in its own colour", kinds: Person.otherShirts.indices.map { .other(shirt: $0) })
        HStack(spacing: 12) {
            item("working", status: .working)
            item("quiet", status: .quiet, flag: .quiet)
            item("needs you", flag: .needsYou)
            item("idle or done", status: .done)
        }
        // What a working one holds, named by the tool as the step line writes it. The terminal
        // in hand looks like the green screen of a job left running: both are on this page.
        HStack(spacing: 12) {
            item("thinking", status: .working, activity: .thinking)
            item("Read", status: .working, activity: .reading)
            item("Edit", status: .working, activity: .typing)
            item("Bash", status: .working, activity: .running)
            item("Grep", status: .working, activity: .searching)
            item("Agent", status: .working, activity: .calling)
        }
        // The rest a card can show, at the mascots' size. The book's two looks on a row of their own: with more it ran past the page.
        HStack(spacing: 12) {
            mark("finished, click to open") { DoneBook(size: 14 * 10 / 12).frame(width: 14) }
            mark("open, click to close") { DoneBook(open: true, size: 14 * 10 / 12).frame(width: 14) }
        }
        HStack(spacing: 12) {
            mark("what one handed back") { DocIcon().frame(width: 14) }
            mark("Monitor job") { JobEye(size: 14) }
        }
        HStack(spacing: 12) {
            mark("job left running") { JobScreen(size: 14) }
            mark("server left running") { JobServer(size: 14) }
        }
        // The lead's task list, in Claude Code's own marks.
        HStack(spacing: 12) {
            mark("task done") { TaskMark(status: "completed").opacity(0.4) }
            mark("under way") { TaskMark(status: "in_progress") }
            mark("to do") { TaskMark(status: "pending").opacity(0.6) }
        }
        caption(Format.quietCaption)
        caption(Format.timeCaption)
    }

    @ViewBuilder private var bar: some View {
        // The bar's numbers, drawn as the bar draws them: their colours say what they count.
        HStack(spacing: 12) {
            mark("needs you") { BarBadge(count: 1) }
            mark("working") { Text(verbatim: "2").bold() }
            mark("quiet") { Text(verbatim: "2").foregroundStyle(.white.opacity(0.6)) }
            // A ring as an example, two thirds used: the real one is on the bar.
            mark("5h limit") { LimitRingView(ring: LimitRing(limit: PlanLimit(usedPercent: 65, resetsAt: nil), stale: false)).accessibilityHidden(true) }
            mark("longest wait") { Text(verbatim: "12m").bold().foregroundStyle(MascotFlag.red) }
        }
        // With nobody at work, the bar shows these in the mascot's place.
        HStack(spacing: 12) {
            mark("nothing running") { Mug(size: 14) }
            mark("job left running") { JobScreen(size: 14) }
            mark("only servers running") { JobServer(size: 14) }
        }
        caption(Format.barMascotCaption)
        caption(Format.ringCaption)
        caption(Format.waitCaption)
        caption(Format.beatCaption)
        caption(Format.displayCaption)
    }

    @ViewBuilder private var keys: some View {
        // Keys in two columns: the key, then what it does. A list, not a sentence to read through.
        caption(Format.keysCaption)
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 3) {
            ForEach(Array(Format.keys.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    Text(verbatim: entry.key).frame(width: 52, alignment: .leading)
                    Text(verbatim: entry.does).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private func mark<Sample: View>(_ label: String, @ViewBuilder sample: () -> Sample) -> some View {
        HStack(spacing: 6) {
            sample()
            Text(verbatim: label).foregroundStyle(.white.opacity(0.8)).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(_ text: String, lines: Int = 3) -> some View {
        Text(verbatim: text).foregroundStyle(.white.opacity(0.6)).lineLimit(lines).fixedSize(horizontal: false, vertical: true)
    }

    private func item(_ label: String, kinds: [MascotKind] = [.general], status: AgentStatus = .needsYou, flag: MascotFlag? = nil, activity: Activity? = nil) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                MascotView(status: status, kind: kind, size: 14, flag: flag, activity: activity)
            }
            Text(verbatim: label).foregroundStyle(.white.opacity(0.8)).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// One setting: its name in bold, what it does under it, smaller and grey. At one size and
/// weight the two read as one block, and a name could not be told from its caption.
private struct SettingRow<Control: View>: View {
    let title: String
    var caption: String? = nil
    /// Something that needs the person's attention, in full white under the name.
    var note: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: title).fontWeight(.semibold)
                Spacer()
                control
            }
            // What is wrong comes first, in full white: under a caption of four lines it sat
            // below the edge of the page.
            if let note {
                Text(verbatim: note).settingCaption(failure: true).lineLimit(2)
            }
            if let caption {
                // Room for the longest caption in full: a promise about the login must not end in "…".
                Text(verbatim: caption).settingCaption().lineLimit(6)
            }
        }
    }
}

/// Settings on one subject in one box, a thin line between each, as System Settings has them.
private struct SettingGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subviews: content) { row in
                row.padding(.vertical, 10)
                    .overlay(alignment: .top) { Color.white.opacity(0.08).frame(height: 1) }
            }
        }
        // The first row's line falls on the box's own edge, and is clipped with its corner.
        .padding(.top, -1)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension Text {
    /// What a setting does, under its name: a size smaller and grey, or white for a failure.
    func settingCaption(failure: Bool = false) -> some View {
        font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(failure ? 1 : 0.6))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    /// A setting that hangs on a switch that is off: there, to be read, but not to be pressed.
    func dimmed(_ off: Bool) -> some View {
        disabled(off).opacity(off ? 0.4 : 1)
    }
}

/// Plain SwiftUI buttons rather than system controls: the panel never becomes the key window,
/// and buttons are what is known to take clicks there.
private struct Switch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule().fill(isOn ? Color.white : Color.white.opacity(0.2))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    // Off, the knob is no brighter than the row's own words.
                    Circle().fill(isOn ? Color.black : Color.white.opacity(0.6)).frame(width: 16, height: 16).padding(2)
                }
                // A ring of fill around it: behind a switch that is on, a fill would not show.
                .padding(4)
                .contentShape(Rectangle())
                .hoverFill(radius: 14)
                .padding(-4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: isOn ? "On" : "Off"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// The pages of a view: words, the open one underlined. In the filled bar a setting's choices
/// sit in, the choice of idle sessions under the settings' pages read as a second row of pages.
struct PageTabs<Page: Hashable>: View {
    let title: String
    let pages: [Page]
    let label: (Page) -> String
    @Binding var selection: Page
    /// What waits on a page: a green dot after its name, and these words to a screen reader.
    var note: (Page) -> String? = { _ in nil }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pages, id: \.self) { page in
                Button { selection = page } label: {
                    Text(verbatim: label(page))
                        .foregroundStyle(page == selection ? Color.white : Color.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(page == selection ? Color.white : Color.clear).frame(height: 2).padding(.horizontal, 8)
                        }
                        // In the room after the name: the tabs keep their places as it comes and goes.
                        .overlay(alignment: .topTrailing) { if note(page) != nil { UpdateDot().padding(.top, 2).padding(.trailing, -3) } }
                        .contentShape(Rectangle())
                        .hoverFill()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == selection ? .isSelected : [])
                .accessibilityValue(Text(verbatim: note(page) ?? ""))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: title))
    }
}

/// A new version came in and has not been looked at yet: on the gear, the About tab and its
/// line there. Green, apart from the red of needs you, and still. Ringed in the panel's black so
/// that it stands clear of the gear it sits on.
struct UpdateDot: View {
    var body: some View {
        Circle().fill(Color.green).frame(width: 6, height: 6)
            .padding(1.5)
            .background(Circle().fill(Color.black))
            .accessibilityHidden(true)
    }
}

struct ChoiceBar<Value: Hashable>: View {
    let title: String
    let choices: [Value]
    let label: (Value) -> String
    @Binding var selection: Value
    /// One choice under the other, each as wide as the bar: for names too long to sit side by side.
    var vertical = false

    var body: some View {
        (vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))) {
            ForEach(choices, id: \.self) { choice in
                Button { selection = choice } label: {
                    Text(verbatim: label(choice))
                        .lineLimit(1)
                        .foregroundStyle(choice == selection ? Color.black : Color.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .frame(maxWidth: vertical ? .infinity : nil, alignment: .leading)
                        .frame(height: 22)
                        .background(choice == selection ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .hoverFill(darkens: choice == selection)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: title))
    }
}

/// How loud the app's sounds are: a knob dragged along a line, landing on a mark when near one.
/// A drag, not a system slider: the panel never becomes the key window. The setting, and the
/// line it sets off, change only when the knob is let go.
private struct VolumeSlider: View {
    let title: String
    @Binding var value: Double
    /// Where the knob is while it is held.
    @State private var held: Double?
    private let width: CGFloat = 150

    /// Where along the line a volume sits, from its start.
    private func x(_ volume: Double) -> CGFloat { width * volume / Sound.loudest }
    /// The volume under a point of the control, which starts the knob's half before the line.
    private func volume(at x: CGFloat) -> Double { Sound.volume(dragged: (x - 7) / width * Sound.loudest) }

    var body: some View {
        let shown = held ?? value
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: width, height: 4)
                Capsule().fill(Color.white.opacity(0.8)).frame(width: x(shown), height: 4)
                ForEach(Sound.volumeMarks, id: \.self) { mark in
                    RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.35))
                        .frame(width: 2, height: 10).offset(x: x(mark) - 1)
                }
                Circle().fill(Color.white).frame(width: 14, height: 14).offset(x: x(shown) - 7)
            }
            .frame(width: width, height: 20, alignment: .leading)
            // Room for the knob's half past either end, which takes the drag too.
            .padding(.horizontal, 7)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { held = volume(at: $0.location.x) }
                .onEnded { value = volume(at: $0.location.x); held = nil })
            Text(verbatim: Format.volume(shown)).settingCaption().monospacedDigit().frame(width: 34, alignment: .trailing)
        }
        // A slider to a screen reader, moved mark to mark: on its own it was an unknown element.
        .accessibilityRepresentation {
            Slider(value: $value, in: 0...Sound.loudest, step: 0.25) { Text(verbatim: title) }
                .accessibilityValue(Text(verbatim: Format.volume(value)))
        }
    }
}

/// An hour of the day, moved one at a time and round the clock. Buttons, as every control
/// here: the panel never becomes the key window.
private struct HourStepper: View {
    let title: String
    @Binding var hour: Int

    var body: some View {
        HStack(spacing: 2) {
            step("minus", by: -1, spoken: "Earlier")
            Text(verbatim: Format.hour(hour)).monospacedDigit().frame(minWidth: 44)
            step("plus", by: 1, spoken: "Later")
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: Format.hour(hour)))
    }

    private func step(_ symbol: String, by amount: Int, spoken: String) -> some View {
        Button { hour = Sound.hour(hour, movedBy: amount) } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 22).contentShape(Rectangle()).hoverFill()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: spoken))
    }
}
