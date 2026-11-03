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

            // How long, and how often — side by side.
            LabeledContent("Long break") {
                HStack(spacing: 8) {
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
                    Picker("Frequency", selection: $prefs.sessionsBeforeLongBreak.animation()) {
                        Text("Off").tag(0)
                        Divider()
                        ForEach(2...12, id: \.self) { count in
                            Text("after \(count) sessions").tag(count)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        } header: {
            Text("Rhythm")
        } footer: {
            if prefs.isFlowtime {
                Text("Flowtime counts up. Work until your focus fades, press Finish, and take a break sized to the session.")
            } else {
                Text(prefs.anyBreaksEnabled
                     ? "Each break starts when the focus session before it ends."
                     : "No breaks: each session ends and waits for you to start the next one.")
            }
        }
        .onChange(of: prefs.timerMode) { TimerEngine.shared.reloadIdle() }
        .onChange(of: prefs.focusMinutes) { syncIdle(.focus) }
        .onChange(of: prefs.shortBreakMinutes) { syncIdle(.shortBreak) }
        .onChange(of: prefs.longBreakMinutes) { syncIdle(.longBreak) }
        .onChange(of: prefs.shortBreaksEnabled) { leaveDisabledBreak() }
        .onChange(of: prefs.sessionsBeforeLongBreak) { leaveDisabledBreak() }

        if !prefs.isFlowtime {
            PresetsSection()
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

        Section("Day") {
            Picker("Daily goal", selection: $prefs.dailyGoal) {
                Text("Off").tag(0)
                Divider()
                ForEach(1...24, id: \.self) { count in
                    Text("\(count) session\(count == 1 ? "" : "s")").tag(count)
                }
            }
            Picker("New day starts at", selection: $prefs.dayStartsAtHour) {
                ForEach(0..<12, id: \.self) { hour in
                    Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!, format: .dateTime.hour())
                        .tag(hour)
                }
            }
        }

        Section {
            Button("Restore Classic Rhythm") {
                withAnimation { prefs.resetTimerToDefaults() }
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

    private func syncIdle(_ phase: Phase) {
        let engine = TimerEngine.shared
        if engine.state == .idle && engine.phase == phase { engine.select(phase) }
    }

    /// If the timer is waiting on a kind of break you just turned off, go back to focus.
    private func leaveDisabledBreak() {
        let engine = TimerEngine.shared
        guard engine.state == .idle else { return }
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

        Section("Notifications") {
            Toggle("Notify when a session ends", isOn: $prefs.notifications)
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
struct PresetsSection: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            ForEach($prefs.presets) { $preset in
                HStack(spacing: 8) {
                    TextField("Name", text: $preset.name)
                        .labelsHidden()
                    Spacer(minLength: 4)
                    Picker("Focus", selection: $preset.focus) {
                        ForEach([10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Picker("Break", selection: $preset.shortBreak) {
                        Text("No break").tag(0)
                        ForEach([3, 5, 10, 15, 20], id: \.self) { Text("\($0) min break").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        prefs.apply(preset)
                        TimerEngine.shared.reloadIdle()
                    } label: {
                        Image(systemName: prefs.isCurrent(preset) ? "checkmark.circle.fill" : "circle")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .help(prefs.isCurrent(preset) ? "In use" : "Use this preset")
                    Button {
                        withAnimation { prefs.presets.removeAll { $0.id == preset.id } }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
            Button("Add Preset") {
                withAnimation {
                    prefs.presets.append(TimerPreset(name: "New Preset", focus: prefs.focusMinutes,
                                                     shortBreak: prefs.shortBreaksEnabled ? prefs.shortBreakMinutes : 0))
                }
            }
        } header: {
            Text("Presets")
        }
    }
}

/// Look and layout: theme, and which parts of the timer are shown.
struct DisplaySettingsSection: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Section("Appearance") {
            Picker("Appearance", selection: $prefs.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }

        Section("Timer") {
            Toggle("\"What's the one thing?\" field", isOn: $prefs.showIntention)
            Toggle("Cycle dots", isOn: $prefs.showCycleDots)
                .disabled(!prefs.longBreaksEnabled)
            Toggle("Today's progress", isOn: $prefs.showTodayProgress)
        }

        Section {
            Toggle("Notes and focus rating after each session", isOn: $prefs.askForReflection)
        } header: {
            Text("After a Session")
        } footer: {
            Text("Write what you got done and rate how focused you were, right on the timer. Both show up in History.")
        }

        Section("History") {
            Toggle("Weekly chart", isOn: $prefs.showWeekChart)
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
