import AppKit
import SwiftUI

/// First launch: a short, step-by-step setup of the things that matter most — the rhythm, how a
/// session ends, calendar and reminders, distractions, and the menu bar. Every step can be
/// skipped, and everything here is in Settings too.
struct OnboardingView: View {
    var begin: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, rhythm, sound, connect, distractions, websites, menuBar, link
    }

    @State private var step: Step = Self.firstStep
    @State private var forward = true

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 14)

            ZStack {
                page(step)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            controls
        }
        .frame(width: 520, height: 620)
        .toggleStyle(InkSwitchStyle())
    }

    /// `--onboarding-step 3` opens on a later step, to look at it (debug builds only).
    private static var firstStep: Step {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--onboarding-step"), args.indices.contains(i + 1),
           let n = Int(args[i + 1]), let step = Step(rawValue: n) { return step }
        #endif
        return .welcome
    }

    // MARK: Chrome

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(Color.primary.opacity(s.rawValue <= step.rawValue ? 0.85 : 0.15))
                    .frame(width: s == step ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.3), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private var controls: some View {
        HStack {
            if step != .welcome {
                Button("Back") { go(-1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if step != .welcome && step != .link {
                Button("Skip Setup", action: finish)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
            }
            Button {
                step == .link ? finish() : go(1)
            } label: {
                Text(nextTitle).frame(minWidth: 110).pill(prominent: true)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    private var nextTitle: String {
        switch step {
        case .welcome: "Set Up Fifteen"
        case .link: "Start Focusing"
        default: "Continue"
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        Haptics.play(.select)
        forward = delta > 0
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { step = next }
    }

    private func finish() {
        Haptics.play(.start)
        begin()
    }

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .welcome: WelcomeStep()
        case .rhythm: RhythmStep()
        case .sound: SoundStep()
        case .connect: ConnectStep()
        case .distractions: DistractionsStep()
        case .websites: WebsitesStep()
        case .menuBar: MenuBarStep()
        case .link: LinkStep()
        }
    }
}

// MARK: - Steps

/// A step's title and subtitle, with its content beneath.
private struct StepPage<Content: View>: View {
    var symbol: String
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .regular))
                    .frame(height: 38)
                Text(title)
                    .font(.title.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            content
        }
        .padding(.horizontal, 36)
    }
}

private struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: appeared ? 0.78 : 0)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 96, height: 96)
            .animation(.spring(duration: 1.4, bounce: 0.2).delay(0.2), value: appeared)

            VStack(spacing: 8) {
                Text("One timer. One thing.")
                    .font(.largeTitle.weight(.semibold))
                Text("Focus for a while, then rest. Let's set Fifteen up the way you work. It takes a minute, and you can change all of it later in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                TipRow(symbol: "menubar.rectangle", text: "Fifteen lives in the menu bar. Click it to open the timer.")
                TipRow(symbol: "cursorarrow.click", text: "Right-click it for more, or ⌥-click to start and pause.")
                TipRow(symbol: "person.2", text: "Focus together with friends in Link.")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 36)
        .onAppear { appeared = true }
    }
}

private struct RhythmStep: View {
    @Environment(Preferences.self) private var prefs

    private struct Rhythm: Identifiable {
        var id: String { name }
        var name: String
        var focus: Int
        var rest: Int
        var flowtime = false
    }

    private let rhythms = [
        Rhythm(name: "Classic", focus: 25, rest: 5),
        Rhythm(name: "Deep Work", focus: 50, rest: 10),
        Rhythm(name: "Quick", focus: 15, rest: 3),
        Rhythm(name: "Flowtime", focus: 0, rest: 0, flowtime: true),
    ]

    var body: some View {
        StepPage(symbol: "metronome", title: "Pick your rhythm",
                 subtitle: "How long do you like to focus before a break?") {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(rhythms) { rhythm in
                        ChoiceCard(selected: isSelected(rhythm)) {
                            apply(rhythm)
                        } label: {
                            card(rhythm)
                        }
                    }
                }
                summary
            }
        }
    }

    /// The name, the focus length big, and the break beneath it.
    private func card(_ rhythm: Rhythm) -> some View {
        VStack(spacing: 2) {
            Text(rhythm.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(rhythm.flowtime ? "∞" : "\(rhythm.focus)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(height: 42)
            Text(rhythm.flowtime ? "count up" : "min focus")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 6)
            Text(rhythm.flowtime ? "flexible break" : "\(rhythm.rest) min break")
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// Exactly what the choice sets up.
    private var summary: some View {
        VStack(spacing: 0) {
            row("timer", "Focus",
                prefs.isFlowtime ? "Counts up until you stop" : "\(prefs.focusMinutes) minutes")
            Divider().padding(.leading, 34)
            row("cup.and.saucer", "Break",
                prefs.isFlowtime ? "1 minute for every \(prefs.flowtimeBreakDivisor) you focused" : "\(prefs.shortBreakMinutes) minutes")
            Divider().padding(.leading, 34)
            HStack(spacing: 12) {
                Image(systemName: "sofa").frame(width: 22)
                Text("Every four rounds, a longer break")
                    .fontWeight(.semibold)
                    .foregroundStyle(prefs.longBreaksEnabled ? .primary : .secondary)
                Spacer()
                Toggle(isOn: Binding {
                    prefs.sessionsBeforeLongBreak > 0
                } set: { on in
                    withAnimation(.snappy) { prefs.sessionsBeforeLongBreak = on ? 4 : 0 }
                }) { EmptyView() }
                .accessibilityLabel("Every four rounds, a longer break")
                .fixedSize()
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            shape.fill(Color.primary.opacity(0.035))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        }
        .animation(.snappy, value: prefs.focusMinutes)
        .animation(.snappy, value: prefs.isFlowtime)
    }

    private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 22)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.vertical, 10)
    }

    private func isSelected(_ rhythm: Rhythm) -> Bool {
        if rhythm.flowtime { return prefs.isFlowtime }
        return !prefs.isFlowtime && prefs.focusMinutes == rhythm.focus && prefs.shortBreakMinutes == rhythm.rest
    }

    private func apply(_ rhythm: Rhythm) {
        Haptics.play(.select)
        withAnimation(.snappy) {
            prefs.timerMode = rhythm.flowtime ? .flowtime : .pomodoro
            if !rhythm.flowtime {
                prefs.focusMinutes = rhythm.focus
                prefs.shortBreakMinutes = rhythm.rest
                prefs.shortBreaksEnabled = true
            }
        }
        // Show the new length on the timer straight away.
        if TimerEngine.shared.state == .idle { TimerEngine.shared.reset() }
    }
}

private struct SoundStep: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        StepPage(symbol: "bell", title: "How should it sound?",
                 subtitle: "A chime when a session ends, and an optional sound to focus to. Tap one to hear it.") {
            VStack(alignment: .leading, spacing: 18) {
                section("When a session ends") {
                    ForEach(Chime.allCases) { chime in
                        ChipButton(title: chime.title, selected: prefs.chime == chime) {
                            prefs.chime = chime
                            prefs.breakChime = chime
                            if chime != .none {
                                prefs.soundEnabled = true
                                SoundEngine.shared.play(chime, volume: prefs.chimeVolume)
                            }
                        }
                    }
                }
                section("While you focus") {
                    ForEach(Ambient.allCases) { ambient in
                        ChipButton(title: ambient.title, selected: prefs.ambient == ambient) {
                            prefs.ambient = ambient
                            if ambient != .off { prefs.soundEnabled = true }
                            SoundEngine.shared.preview(ambient, volume: prefs.ambientVolume)
                        }
                    }
                }
                Toggle(isOn: $prefs.notifications) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify me when a session ends")
                        Text("Handy when the sound is off or you've stepped away.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: prefs.notifications) { _, on in
                    if on { Notifier.shared.requestAuthorizationIfNeeded() }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) { content() }
        }
    }
}

private struct ConnectStep: View {
    @Bindable private var calendar = CalendarSettings.shared
    @Bindable private var reminders = RemindersSettings.shared
    private var calendarSync: CalendarSync { CalendarSync.shared }
    private var remindersSync: RemindersSync { RemindersSync.shared }

    var body: some View {
        StepPage(symbol: "calendar.badge.clock", title: "Bring in your day",
                 subtitle: "See what's coming up next to the timer, tick off reminders as you go, and turn either into your intention.") {
            VStack(spacing: 12) {
                ConnectCard(symbol: "calendar", title: "Calendar",
                            detail: calendarDetail, state: calendarState) {
                    calendar.enabled = true
                    calendar.source = .apple
                    calendarSync.connect()
                }
                if calendarState == .idle {
                    Button("Use Google Calendar instead…") {
                        calendar.enabled = true
                        calendar.source = .google
                        calendarSync.connect()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                ConnectCard(symbol: "checklist", title: "Reminders",
                            detail: "A Reminders list beside the timer. Star your priorities.",
                            state: remindersState) {
                    reminders.enabled = true
                    remindersSync.connect()
                }
                if remindersState == .connected {
                    HStack {
                        Text("Show list").foregroundStyle(.secondary)
                        Spacer()
                        ReminderListPicker()
                            .labelsHidden()
                            .fixedSize()
                    }
                    .padding(.horizontal, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.snappy, value: remindersState)
        }
    }

    private var calendarDetail: String {
        calendarState == .connected
            ? "Connected to \(calendar.source.title)."
            : "Today's events beside the timer, and every session logged."
    }

    private var calendarState: ConnectCard.State {
        guard calendar.enabled else { return .idle }
        if calendarSync.status == .connecting { return .connecting }
        return calendarSync.provider.isConnected ? .connected : .idle
    }

    private var remindersState: ConnectCard.State {
        reminders.enabled && remindersSync.isConnected ? .connected : .idle
    }
}

private struct DistractionsStep: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        StepPage(symbol: "eye.slash", title: "Keep distractions away",
                 subtitle: "Fifteen can hide the apps that pull you out of focus, and bring them back when the break starts.") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Block distracting apps while focusing", isOn: $prefs.hideDistractingApps.animation())
                    .padding(.horizontal, 4)
                if prefs.hideDistractingApps {
                    VStack(alignment: .leading, spacing: 8) {
                        if suggestions.isEmpty && prefs.blockedApps.isEmpty {
                            Text("Choose the apps to block.").font(.caption).foregroundStyle(.secondary)
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(suggestions + prefs.blockedApps.filter { !suggestions.contains($0) }, id: \.self) { id in
                                AppChip(id: id, selected: prefs.blockedApps.contains(id)) {
                                    withAnimation(.snappy) {
                                        if prefs.blockedApps.contains(id) {
                                            prefs.blockedApps.removeAll { $0 == id }
                                        } else {
                                            prefs.blockedApps.append(id)
                                        }
                                    }
                                }
                            }
                            Button("Other App…", action: chooseApps)
                                .buttonStyle(.plain)
                                .font(.callout)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(Capsule().strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Toggle(isOn: $prefs.breakCurtain) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cover the screen during breaks")
                        Text("A gentle nudge to actually look away.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// The common time sinks that are installed.
    private var suggestions: [String] {
        BlockedAppsList.suggestedIDs.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Block"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !prefs.blockedApps.contains(id) {
                prefs.blockedApps.append(id)
            }
        }
    }
}

private struct WebsitesStep: View {
    @Environment(Preferences.self) private var prefs
    @State private var draft = ""

    /// Common time sinks, one click away.
    private static let suggested = [
        "youtube.com", "x.com", "reddit.com", "instagram.com",
        "facebook.com", "tiktok.com", "netflix.com", "news.ycombinator.com",
    ]

    var body: some View {
        @Bindable var prefs = prefs
        StepPage(symbol: "globe", title: "Block distracting websites",
                 subtitle: "While you focus, Fifteen closes the sites you pick in Safari, Chrome and other browsers. They're back when the break starts.") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Block distracting websites while focusing", isOn: $prefs.blockWebsites.animation())
                    .padding(.horizontal, 4)
                if prefs.blockWebsites {
                    VStack(alignment: .leading, spacing: 12) {
                        FlowLayout(spacing: 8) {
                            ForEach(Self.suggested + prefs.blockedSites.filter { !Self.suggested.contains($0) }, id: \.self) { site in
                                SiteChip(site: site, selected: prefs.blockedSites.contains(site)) {
                                    withAnimation(.snappy) {
                                        if prefs.blockedSites.contains(site) {
                                            prefs.blockedSites.removeAll { $0 == site }
                                        } else {
                                            prefs.blockedSites.append(site)
                                        }
                                    }
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus").foregroundStyle(.secondary)
                                TextField("Add website", text: $draft, prompt: Text("Add another, e.g. example.com"))
                                    .textFieldStyle(.plain)
                                    .onSubmit(add)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                            Button("Add", action: add)
                                .disabled(WebBlocker.normalize(draft) == nil)
                        }
                        BrowserSetup()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func add() {
        guard let site = WebBlocker.normalize(draft) else { return }
        Haptics.play(.select)
        withAnimation(.snappy) {
            if !prefs.blockedSites.contains(site) { prefs.blockedSites.append(site) }
        }
        draft = ""
    }
}

private struct MenuBarStep: View {
    @Environment(Preferences.self) private var prefs
    @State private var openAtLogin = LaunchAtLogin.isOn

    var body: some View {
        @Bindable var prefs = prefs
        StepPage(symbol: "menubar.arrow.up.rectangle", title: "Make it yours",
                 subtitle: "Choose what Fifteen shows in the menu bar, and pick its icon. Look up: it changes as you pick.") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Menu bar").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Menu bar", selection: $prefs.menuBarDisplay) {
                        ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("App icon").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(AppIconStyle.allCases) { style in
                            IconTile(style: style, selected: prefs.appIcon == style) {
                                withAnimation(.snappy) {
                                    prefs.appIcon = style
                                    // A rainbow icon brings the rainbow ring with it.
                                    prefs.ringTheme = style.isRainbow ? .rainbow : .mono
                                }
                                AppIconChanger.apply(style)
                            }
                        }
                    }
                }
                Toggle("Open Fifteen at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in LaunchAtLogin.set(on) }
                    .padding(.horizontal, 4)
                TipRow(symbol: "keyboard", text: "From anywhere: ⌃⌥P starts and pauses, ⌃⌥O opens the timer.")
                    .font(.callout)
                    .padding(.top, 4)
            }
        }
    }
}

/// Link, and an invitation to bring friends along.
private struct LinkStep: View {
    static let website = AppInfo.website
    @State private var copied = false

    var body: some View {
        @Bindable var link = LinkSession.shared
        StepPage(symbol: "person.2", title: "Focus together",
                 subtitle: "With Link, a group shares one timer: start, pause and breaks happen for everyone, wherever they are.") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    TipRow(symbol: "plus.circle", text: "Start a group from the timer's Link button.")
                    TipRow(symbol: "number", text: "Friends join with its 6-letter code.")
                    TipRow(symbol: "timer", text: "Then you all focus, and rest, at the same time.")
                }
                .font(.callout)

                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                    TextField("Your name", text: $link.deviceName, prompt: Text("Your name, as your group sees it"))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Invite your friends").font(.headline)
                    Text("They'll need Fifteen too. Send them the link:")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text("getfifteen.de")
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: copy) {
                            Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                                .pill()
                        }
                        .buttonStyle(.plain)
                        ShareLink(item: Self.website, message: Text("Let's focus together with Fifteen")) {
                            Image(systemName: "square.and.arrow.up").pill(square: true)
                        }
                        .buttonStyle(.plain)
                        .help("Share…")
                    }
                }
                .padding(14)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                    shape.fill(Color.primary.opacity(0.035))
                        .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                }
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.website.absoluteString, forType: .string)
        Haptics.play(.select)
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { copied = false }
        }
    }
}

// MARK: - Parts

private struct TipRow: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).frame(width: 22)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A card that's one of several choices; the chosen one is outlined.
private struct ChoiceCard<Label: View>: View {
    var selected: Bool
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .padding(14)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                    shape.fill(Color.primary.opacity(selected ? 0.09 : (hovering ? 0.06 : 0.035)))
                        .overlay(shape.strokeBorder(Color.primary.opacity(selected ? 0.8 : 0.1), lineWidth: selected ? 1.5 : 1))
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .scaleEffect(selected ? 1 : 0.985)
        .animation(.snappy(duration: 0.2), value: selected)
        .animation(.snappy(duration: 0.15), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ChipButton: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.select)
            action()
        } label: {
            Text(title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .background(Capsule().fill(Color.primary.opacity(selected ? 0.9 : 0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One of the app icons; the chosen one is outlined.
private struct IconTile: View {
    var style: AppIconStyle
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            Haptics.play(.select)
            action()
        } label: {
            Image(nsImage: AppIconArt.image(style, size: 128))
                .resizable()
                .frame(width: 52, height: 52)
                .padding(5)
                .frame(maxWidth: .infinity)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                    shape.fill(Color.primary.opacity(selected ? 0.1 : (hovering ? 0.06 : 0.03)))
                        .overlay(shape.strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
                }
                .scaleEffect(selected ? 1.04 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: selected)
        .animation(.snappy(duration: 0.15), value: hovering)
        .help(style.title)
        .accessibilityLabel("\(style.title) app icon")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Each installed browser, and a button that asks macOS to let Fifteen see its tabs.
private struct BrowserSetup: View {
    @State private var access: [String: BrowserAccess] = [:]
    @State private var asking: Set<String> = []
    private let browsers = Browser.installed

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Let Fifteen see which site is open, once per browser:")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(browsers, id: \.id) { browser in
                    chip(browser.id, kind: browser.kind)
                }
            }
        }
        .task { await refreshLoop() }
    }

    private func chip(_ id: String, kind: Browser.Kind) -> some View {
        let state = access[id] ?? .notAsked
        return HStack(spacing: 6) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(name(id)).font(.callout).lineLimit(1)
            if asking.contains(id) {
                ProgressView().controlSize(.mini)
            } else {
                switch state {
                case .granted:
                    Image(systemName: "checkmark.circle.fill")
                        .help("Ready")
                        .transition(.scale.combined(with: .opacity))
                case .denied:
                    Button("Open Settings") { openPrivacy(kind) }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                        .help("You said no earlier. Switch Fifteen on for this browser in Privacy & Security.")
                case .notAsked, .notRunning:
                    Button("Allow") { ask(id, kind: kind) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background {
            Capsule().fill(Color.primary.opacity(state == .granted ? 0.12 : 0.05))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(state == .granted ? 0.5 : 0), lineWidth: 1))
        }
        .animation(.snappy, value: state)
    }

    /// Re-checks every couple of seconds while the step is open, so answers given in System Settings show up.
    private func refreshLoop() async {
        while !Task.isCancelled {
            for browser in browsers where !asking.contains(browser.id) {
                let id = browser.id, kind = browser.kind
                let state = await Task.detached { BrowserAccess.status(id, kind: kind, ask: false) }.value
                // A browser that isn't running can't be checked; keep what we knew.
                if state != .notRunning || access[id] == nil { access[id] = state }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Shows the macOS prompt. Apple Events can only ask a running app, so a closed browser is
    /// opened in the background first.
    private func ask(_ id: String, kind: Browser.Kind) {
        Haptics.play(.select)
        if kind == .firefox {
            _ = BrowserAccess.status(id, kind: kind, ask: true)
            openPrivacy(kind)
            return
        }
        asking.insert(id)
        Task {
            if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.hides = true
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
                try? await Task.sleep(for: .seconds(1.5))
            }
            let state = await Task.detached { BrowserAccess.status(id, kind: kind, ask: true) }.value
            access[id] = state
            asking.remove(id)
        }
    }

    private func openPrivacy(_ kind: Browser.Kind) {
        let pane = kind == .firefox ? "Privacy_Accessibility" : "Privacy_Automation"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func name(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// A website, with its icon once it's loaded; ticked when it's blocked.
private struct SiteChip: View {
    var site: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.select)
            action()
        } label: {
            HStack(spacing: 6) {
                Group {
                    if let icon = Favicons.shared.icon(for: site) {
                        Image(nsImage: icon).resizable().interpolation(.high)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 16, height: 16)
                Text(site).font(.callout).lineLimit(1)
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .frame(height: 30)
            .background {
                Capsule().fill(Color.primary.opacity(selected ? 0.12 : 0.05))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0.5 : 0), lineWidth: 1))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(site)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An installed app, shown with its icon; ticked when it's blocked.
private struct AppChip: View {
    var id: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.select)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                Text(name).font(.callout).lineLimit(1)
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(height: 30)
            .background {
                Capsule().fill(Color.primary.opacity(selected ? 0.12 : 0.05))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0.5 : 0), lineWidth: 1))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    private var name: String {
        guard let url else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private var icon: NSImage {
        guard let url else { return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Calendar or Reminders: what it adds, and a button to connect it.
private struct ConnectCard: View {
    enum State { case idle, connecting, connected }

    var symbol: String
    var title: String
    var detail: String
    var state: State
    var connect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch state {
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .transition(.scale(0.8).combined(with: .opacity))
            case .connecting:
                ProgressView().controlSize(.small)
            case .idle:
                Button {
                    Haptics.play(.select)
                    connect()
                } label: {
                    Text("Connect").pill()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            shape.fill(Color.primary.opacity(0.035))
                .overlay(shape.strokeBorder(Color.primary.opacity(state == .connected ? 0.5 : 0.1), lineWidth: 1))
        }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: state)
    }
}
