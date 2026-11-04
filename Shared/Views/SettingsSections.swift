import SwiftUI

/// Form sections shared by the Mac and iPhone/iPad settings.
struct TimerSettingsSection: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Picker("Mode", selection: $prefs.timerMode.animation()) {
                ForEach(TimerMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if prefs.isFlowtime {
                Picker("Break", selection: $prefs.flowtimeBreakDivisor) {
                    Text("A third of focus time").tag(3)
                    Text("A quarter of focus time").tag(4)
                    Text("A fifth of focus time").tag(5)
                    Text("A sixth of focus time").tag(6)
                }
                Picker("Counts toward long break after", selection: $prefs.flowtimeMinimumMinutes) {
                    ForEach(Self.options([1, 5, 10, 15, 20, 25, 30, 45], including: prefs.flowtimeMinimumMinutes), id: \.self) {
                        Text("\($0) min").tag($0)
                    }
                }
                .disabled(!prefs.longBreaksEnabled)
            } else {
                ValueStepper("Focus", value: $prefs.focusMinutes, in: 1...180, unit: "min")

                // Off, or how long — one menu.
                Picker("Short break", selection: shortBreak.animation()) {
                    Text("Off").tag(0)
                    Divider()
                    ForEach(Self.options([1, 2, 3, 4, 5, 7, 10, 15, 20], including: prefs.shortBreakMinutes), id: \.self) {
                        Text("\($0) min").tag($0)
                    }
                }
            }

            // How often, then how long — side by side, or under the label on a narrow screen.
            ViewThatFits(in: .horizontal) {
                LabeledContent("Long break") { longBreakMenus }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Long break")
                    longBreakMenus
                }
            }
        } header: {
            Text("Rhythm")
        } footer: {
            if TimerEngine.shared.isLinked {
                Text("You're in a Link group: these are your own lengths. They're used when you start or reset the timer, and the group's timer stays as it is until then.")
            } else if prefs.isFlowtime {
                Text("Flowtime counts up. Work until your focus fades, press Finish, and take a break sized to the session. Shorter sessions are still saved, but don't count toward the long break.")
            } else {
                Text(prefs.anyBreaksEnabled
                     ? "Each break starts when the focus session before it ends."
                     : "No breaks: each session ends and waits for you to start the next one.")
            }
        }
        .onChange(of: prefs.timerMode) { if !TimerEngine.shared.isLinked { TimerEngine.shared.reloadIdle() } }
        .onChange(of: prefs.focusMinutes) { syncIdle(.focus) }
        .onChange(of: prefs.shortBreakMinutes) { syncIdle(.shortBreak) }
        .onChange(of: prefs.longBreakMinutes) { syncIdle(.longBreak) }
        .onChange(of: prefs.shortBreaksEnabled) { leaveDisabledBreak() }
        .onChange(of: prefs.sessionsBeforeLongBreak) { leaveDisabledBreak() }

        if !prefs.isFlowtime {
            #if os(iOS)
            TouchPresetsSection()
            #else
            PresetsSection()
            #endif
        }

        Section {
            Toggle("Start breaks automatically", isOn: $prefs.autoStartBreaks)
                .disabled(!prefs.anyBreaksEnabled)
            Toggle("Start focus automatically after a break", isOn: $prefs.autoStartFocus)
                .disabled(!prefs.anyBreaksEnabled)
            Toggle("Keep counting when focus ends", isOn: $prefs.keepCountingAfterEnd)
        } header: {
            Text("Flow")
        } footer: {
            Text("When you're in the flow, the timer counts the extra minutes instead of stopping you. They're added to the session when you move on.")
        }

        Section {
            Picker("Daily session goal", selection: $prefs.dailyGoal) {
                Text("Off").tag(0)
                Divider()
                ForEach(1...24, id: \.self) { count in
                    Text("\(count) session\(count == 1 ? "" : "s")").tag(count)
                }
            }
            Picker("Daily focus goal", selection: $prefs.dailyGoalMinutes) {
                Text("Off").tag(0)
                Divider()
                ForEach([30, 60, 90, 120, 180, 240, 300, 360], id: \.self) { Text(TimeFormat.duration(TimeInterval($0 * 60))).tag($0) }
            }
            Picker("Weekly focus goal", selection: $prefs.weeklyGoalMinutes) {
                Text("Off").tag(0)
                Divider()
                ForEach([5, 10, 15, 20, 25, 30, 40], id: \.self) { Text("\($0)h").tag($0 * 60) }
            }
            Picker("New day starts at", selection: $prefs.dayStartsAtHour) {
                ForEach(0..<12, id: \.self) { hour in
                    Text(hour == 0 ? "Midnight" : "\(hour) AM").tag(hour)
                }
            }
        } header: {
            Text("Day")
        } footer: {
            Text("Goals appear in Insights as progress rings in Overview; the daily focus goal is also a line on the per-day chart. A daily focus goal can also be what keeps a streak going.")
        }

        Section {
            Button("Restore Classic Rhythm") {
                withAnimation { prefs.resetTimerToDefaults() }
            }
        }
    }

    /// How often, then how long.
    private var longBreakMenus: some View {
        @Bindable var prefs = prefs
        return HStack(spacing: 8) {
            Picker("Frequency", selection: $prefs.sessionsBeforeLongBreak.animation()) {
                Text("Off").tag(0)
                Divider()
                ForEach(2...12, id: \.self) { count in
                    Text("after \(count) sessions").tag(count)
                }
            }
            .labelsHidden()
            .fixedSize()
            if prefs.longBreaksEnabled {
                Picker("Length", selection: $prefs.longBreakMinutes) {
                    ForEach(Self.options([5, 10, 15, 20, 25, 30, 45, 60], including: prefs.longBreakMinutes), id: \.self) {
                        Text("\($0) min").tag($0)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .transition(.opacity)
            }
        }
    }

    /// Short break minutes, with 0 meaning short breaks are off.
    private var shortBreak: Binding<Int> {
        Binding {
            prefs.shortBreaksEnabled ? prefs.shortBreakMinutes : 0
        } set: { minutes in
            if minutes == 0 {
                prefs.shortBreaksEnabled = false
            } else {
                prefs.shortBreakMinutes = minutes
                prefs.shortBreaksEnabled = true
            }
        }
    }

    /// The preset list, plus the current value if it was set to something else.
    private static func options(_ presets: [Int], including current: Int) -> [Int] {
        current > 0 && !presets.contains(current) ? (presets + [current]).sorted() : presets
    }

    /// Settings follow onto an idle timer, except a Link group's, which is everyone's.
    private func syncIdle(_ phase: Phase) {
        let engine = TimerEngine.shared
        guard !engine.isLinked else { return }
        if engine.state == .idle && engine.phase == phase { engine.select(phase) }
    }

    /// If the timer is waiting on a kind of break you just turned off, go back to focus.
    private func leaveDisabledBreak() {
        let engine = TimerEngine.shared
        guard engine.state == .idle, !engine.isLinked else { return }
        if (engine.phase == .shortBreak && !prefs.shortBreaksEnabled)
            || (engine.phase == .longBreak && !prefs.longBreaksEnabled) {
            engine.select(.focus)
        }
    }
}

struct SoundSettingsSection: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Play sounds", isOn: $prefs.soundEnabled.animation())
        } footer: {
            if !prefs.soundEnabled {
                Text("Fifteen stays silent: no chime, no ticking, no background sound.")
            }
        }
        .onChange(of: prefs.soundEnabled) { syncAmbient() }

        if prefs.soundEnabled {
            Section("End of Session") {
                LabeledContent("When focus ends") {
                    HStack(spacing: 8) {
                        Picker("When focus ends", selection: $prefs.chime) {
                            ForEach(Chime.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        PreviewButton { SoundEngine.shared.play(prefs.chime, volume: prefs.chimeVolume) }
                            .disabled(prefs.chime == .none)
                    }
                }
                if prefs.anyBreaksEnabled {
                    LabeledContent("When a break ends") {
                        HStack(spacing: 8) {
                            Picker("When a break ends", selection: $prefs.breakChime) {
                                ForEach(Chime.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            PreviewButton { SoundEngine.shared.play(prefs.breakChime, volume: prefs.chimeVolume) }
                                .disabled(prefs.breakChime == .none)
                        }
                    }
                }
                if prefs.chime != .none || prefs.breakChime != .none {
                    Slider(value: $prefs.chimeVolume, in: 0.1...1) {
                        Text("Volume")
                    } onEditingChanged: { editing in
                        if !editing { SoundEngine.shared.play(prefs.chime, volume: prefs.chimeVolume) }
                    }
                }
            }

            Section {
                LabeledContent("Ticking clock") {
                    HStack(spacing: 8) {
                        Toggle("Ticking clock", isOn: $prefs.ticking)
                            .labelsHidden()
                        PreviewButton { SoundEngine.shared.previewTicks() }
                    }
                }
                LabeledContent("Background sound") {
                    HStack(spacing: 8) {
                        Picker("Background sound", selection: $prefs.ambient) {
                            ForEach(Ambient.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        PreviewButton { previewAmbient() }
                            .disabled(prefs.ambient == .off)
                    }
                }
                .onChange(of: prefs.ambient) { syncAmbient() }
                if prefs.ambient != .off {
                    Slider(value: $prefs.ambientVolume, in: 0.05...1) {
                        Text("Volume")
                    } onEditingChanged: { editing in
                        if !editing { previewAmbient() }
                    }
                    Toggle("Also during breaks", isOn: $prefs.ambientDuringBreaks)
                }
            } header: {
                Text("While Focusing")
            } footer: {
                Text("Steady noise masks chatter and helps you settle in. It plays only while the timer runs.")
            }
        }

        Section {
            Toggle("Notify when a session ends", isOn: $prefs.notifications)
            Toggle("Haptic feedback", isOn: $prefs.haptics)
        } header: {
            Text("Notifications & Haptics")
        } footer: {
            #if os(macOS)
            Text("Haptics are felt on a Force Touch trackpad while your finger rests on it.")
            #else
            Text("A firm tap when you start, a light one when you pause, and a buzz when a session ends.")
            #endif
        }
    }

    private var playingNow: Bool {
        let engine = TimerEngine.shared
        return engine.state == .running && (engine.phase == .focus || prefs.ambientDuringBreaks)
    }

    private func syncAmbient() {
        SoundEngine.shared.syncAmbient(playing: playingNow)
    }

    private func previewAmbient() {
        if playingNow {
            syncAmbient()
        } else {
            SoundEngine.shared.preview(prefs.ambient, volume: prefs.ambientVolume)
        }
    }
}

private struct PreviewButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .help("Preview")
        .accessibilityLabel("Preview")
    }
}

/// Named rhythms like "Study 50/10". Pick one from the timer's length pill; edit them here.
/// A simple table: one row per preset, ordered with up/down arrows.
struct PresetsSection: View {
    @Environment(Preferences.self) private var prefs

    private static let focusOptions = [10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90]
    private static let breakOptions = [0, 3, 5, 10, 15, 20]
    private static let orderWidth: CGFloat = 44
    private static let focusWidth: CGFloat = 92
    private static let breakWidth: CGFloat = 104
    private static let actionsWidth: CGFloat = 52
    /// Room the menu's ⌃⌄ takes at the right of each picker.
    private static let chevronWidth: CGFloat = 30

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            if !prefs.presets.isEmpty {
                headerRow
            }
            ForEach($prefs.presets) { $preset in
                let index = prefs.presets.firstIndex(where: { $0.id == preset.id }) ?? 0
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        arrow("chevron.up", help: "Move up", disabled: index == 0) { move(index, by: -1) }
                        arrow("chevron.down", help: "Move down", disabled: index == prefs.presets.count - 1) { move(index, by: 1) }
                    }
                    .frame(width: Self.orderWidth, alignment: .leading)

                    TextField("Name", text: $preset.name, prompt: Text("Name"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Focus", selection: $preset.focus) {
                        ForEach(Self.options(Self.focusOptions, including: preset.focus), id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: Self.focusWidth)

                    Picker("Break", selection: $preset.shortBreak) {
                        ForEach(Self.options(Self.breakOptions, including: preset.shortBreak), id: \.self) {
                            Text($0 == 0 ? "None" : "\($0) min").tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: Self.breakWidth)

                    HStack(spacing: 6) {
                        Button {
                            prefs.apply(preset)
                            if !TimerEngine.shared.isLinked { TimerEngine.shared.reloadIdle() }
                        } label: {
                            Image(systemName: prefs.isCurrent(preset) ? "checkmark.circle.fill" : "circle")
                        }
                        .help(prefs.isCurrent(preset) ? "In use" : "Use this preset")
                        .accessibilityLabel(prefs.isCurrent(preset) ? "In use" : "Use this preset")
                        Button {
                            withAnimation(.snappy) { prefs.presets.removeAll { $0.id == preset.id } }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .help("Delete")
                        .accessibilityLabel("Delete \(preset.name)")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: Self.actionsWidth, alignment: .trailing)
                }
            }
            Button("Add Preset", systemImage: "plus") {
                withAnimation(.snappy) {
                    prefs.presets.append(TimerPreset(name: "New Preset", focus: prefs.focusMinutes,
                                                     shortBreak: prefs.shortBreaksEnabled ? prefs.shortBreakMinutes : 0))
                }
            }
        } header: {
            Text("Presets")
        } footer: {
            Text("The timer's length menu lists presets in this order.")
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: Self.orderWidth, height: 1)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            // Right-aligned over the values, which sit just left of each menu's chevrons.
            Text("Focus").padding(.trailing, Self.chevronWidth).frame(width: Self.focusWidth, alignment: .trailing)
            Text("Break").padding(.trailing, Self.chevronWidth).frame(width: Self.breakWidth, alignment: .trailing)
            Color.clear.frame(width: Self.actionsWidth, height: 1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func arrow(_ symbol: String, help: String, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard prefs.presets.indices.contains(index), prefs.presets.indices.contains(target) else { return }
        withAnimation(.snappy) { prefs.presets.swapAt(index, target) }
    }

    /// The standard choices, plus the preset's own value if it's something else.
    private static func options(_ base: [Int], including value: Int) -> [Int] {
        base.contains(value) ? base : (base + [value]).sorted()
    }
}

/// Look and layout: theme, and which parts of the timer are shown.
struct DisplaySettingsSection: View {
    @Environment(Preferences.self) private var prefs

    /// Weekdays in the user's order (Monday first in most of Europe).
    static var weekdayOrder: [Int] {
        (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        @Bindable var prefs = prefs
        Section("Appearance") {
            Picker("Appearance", selection: $prefs.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Theme", selection: $prefs.ringTheme.animation()) {
                ForEach(RingTheme.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }

        #if os(macOS)
        AppIconSection()
        #endif

        Section("Timer") {
            Toggle("Project & intention", isOn: $prefs.showIntention)
            Toggle("Cycle dots", isOn: $prefs.showCycleDots)
                .disabled(!prefs.longBreaksEnabled)
            Toggle("Swirl when a session starts", isOn: $prefs.startSwirl)
        }

        Section {
            Toggle("Notes and focus rating after each session", isOn: $prefs.askForReflection)
        } header: {
            Text("After a Session")
        } footer: {
            Text("Write what you got done and rate how it went, right on the timer. Both show up in Insights.")
        }

        Section {
            Toggle("Show streaks", isOn: $prefs.streaksEnabled.animation())
            if prefs.streaksEnabled {
                Picker("A day counts when", selection: $prefs.streakNeedsGoal) {
                    Text("There's at least one session").tag(false)
                    Text("The daily focus goal is met").tag(true)
                }
                .disabled(prefs.dailyGoalMinutes == 0)
                // Days beside the label when they fit, under it on a phone.
                ViewThatFits(in: .horizontal) {
                    LabeledContent("Rest days") { restDays }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rest days")
                        restDays
                    }
                }
            }
        } header: {
            Text("Insights")
        } footer: {
            Text("Streaks only ever appear in Insights. Rest days never break one.")
        }
    }

    private var restDays: some View {
        HStack(spacing: 4) {
            ForEach(Self.weekdayOrder, id: \.self) { weekday in
                let on = prefs.streakRestDays.contains(weekday)
                Button(Calendar.current.veryShortWeekdaySymbols[weekday - 1]) {
                    if on { prefs.streakRestDays.removeAll { $0 == weekday } } else { prefs.streakRestDays.append(weekday) }
                }
                .buttonStyle(.bordered)
                .tint(on ? .primary : .secondary)
                .fontWeight(on ? .bold : .regular)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// "Focus ............ 25 min [−|+]" — label on the left, value and stepper together on the right.
private struct ValueStepper: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var unit: String

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, unit: String) {
        self.title = title
        _value = value
        self.range = range
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(value) \(unit)")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.snappy, value: value)
                Stepper(title, value: $value, in: range)
                    .labelsHidden()
            }
        }
    }
}

/// A switch in the app's black-and-white ink. The stock switch fills with the accent color, which is
/// white in dark mode, so its white knob vanished. Here the knob is always the opposite ink of the
/// track: black on a white track in dark mode, white on a black track in light mode.
struct InkSwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        let ink = Color.ink(scheme)
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? ink : ink.opacity(dark ? 0.2 : 0.12))
                .overlay(Capsule().strokeBorder(ink.opacity(configuration.isOn ? 0 : 0.12), lineWidth: 1))
                .frame(width: Self.size.width, height: Self.size.height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Color.ink(dark ? .light : .dark) : (dark ? Color(white: 0.82) : .white))
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        .padding(2)
                }
                .animation(.snappy(duration: 0.2), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { configuration.isOn.toggle() }
    }

    #if os(macOS)
    private static let size = CGSize(width: 32, height: 18)
    #else
    private static let size = CGSize(width: 51, height: 31)
    #endif
}

/// Two ways to start over, each asked twice: settings back to factory defaults, and all history gone.
struct ResetSection: View {
    @Environment(Preferences.self) private var prefs
    @Environment(HistoryStore.self) private var history
    @Environment(TimerEngine.self) private var engine
    @State private var confirmSettings = false
    @State private var confirmHistory = false

    var body: some View {
        Section {
            LabeledContent {
                Button("Reset Settings…", role: .destructive) { confirmSettings = true }
                    // Mid-session it would also switch off the app blocker, which is locked then.
                    .disabled(engine.isActive)
            } label: {
                Text("Restore factory settings")
                if engine.isActive {
                    Text("Finish or reset the timer first.")
                }
            }
            .confirmationDialog("Reset all settings?", isPresented: $confirmSettings) {
                Button("Reset Settings", role: .destructive) { resetSettings() }
            } message: {
                Text("Every setting goes back to how Fifteen comes: timer lengths, presets, sounds, display, menu bar, app blocker and the rest. Your history and projects stay.")
            }

            LabeledContent {
                Button("Delete History…", role: .destructive) { confirmHistory = true }
                    .disabled(history.records.isEmpty && history.projects.isEmpty)
            } label: {
                Text("Delete all history")
                Text(historySummary)
            }
            .confirmationDialog("Delete all history?", isPresented: $confirmHistory) {
                Button("Delete Everything", role: .destructive) { wipeHistory() }
            } message: {
                Text("All sessions, notes, ratings and projects are deleted from this device, and Insights starts empty. This can't be undone. To keep a copy, export a backup from Insights first.")
            }
        } header: {
            Text("Start Over")
        }
    }

    private var historySummary: String {
        let sessions = history.records.count, projects = history.projects.count
        if sessions == 0 && projects == 0 { return "Nothing recorded yet." }
        return "\(sessions) session\(sessions == 1 ? "" : "s"), \(projects) project\(projects == 1 ? "" : "s")"
    }

    private func resetSettings() {
        withAnimation { prefs.resetToFactoryDefaults() }
        if !engine.isLinked { engine.reloadIdle() }
        #if os(macOS)
        AppIconChanger.apply(prefs.appIcon)
        DoNotDisturb.shared.sync()
        #endif
    }

    private func wipeHistory() {
        withAnimation { history.wipeEverything() }
        engine.forgetHistory()
        Haptics.play(.select)
    }
}

