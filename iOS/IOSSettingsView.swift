import SwiftUI

/// The Settings tab: the Mac's panes as a native list you drill into, each row with a quiet
/// summary of what's set. Start Over sits at the bottom, as on the Mac.
struct IOSSettingsView: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    page("Timer", symbol: "timer", summary: timerSummary) { TimerSettingsSection() }
                    page("Sound", symbol: "speaker.wave.2", summary: soundSummary) { SoundSettingsSection() }
                    page("Display", symbol: "circle.lefthalf.filled", summary: prefs.appearance.title) {
                        DisplaySettingsSection()
                    }
                }
                Section {
                    page("Link", symbol: "person.2", summary: LinkSession.shared.isLinked ? "In a group" : nil) {
                        LinkSettingsSection()
                    }
                    page("Lock Screen", symbol: "lock", summary: prefs.liveActivity ? "Live Activity" : "Off") {
                        LockScreenSection()
                    }
                }
                Section {
                    NavigationLink {
                        AboutView()
                            .navigationTitle("About")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("About Fifteen", systemImage: "info.circle")
                    }
                }
                ResetSection()
            }
            .navigationTitle("Settings")
        }
        .toggleStyle(InkSwitchStyle())
    }

    private func page<Content: View>(_ title: String, symbol: String, summary: String?,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        NavigationLink {
            Form { content() }
                .toggleStyle(InkSwitchStyle())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            LabeledContent {
                if let summary { Text(summary) }
            } label: {
                Label(title, systemImage: symbol)
            }
        }
    }

    private var timerSummary: String {
        if prefs.isFlowtime { return "Flowtime" }
        return prefs.shortBreaksEnabled
            ? "\(prefs.focusMinutes) / \(prefs.shortBreakMinutes) min"
            : "\(prefs.focusMinutes) min"
    }

    private var soundSummary: String {
        prefs.soundEnabled ? prefs.chime.title : "Off"
    }
}

/// Your name in the group, banners for what others do, and the group you're in.
private struct LinkSettingsSection: View {
    @Environment(Preferences.self) private var prefs
    @State private var confirmLeave = false

    var body: some View {
        @Bindable var prefs = prefs
        @Bindable var link = LinkSession.shared
        Section {
            LabeledContent("Shown to others as") {
                TextField("Name", text: $link.deviceName, prompt: Text(LinkSession.defaultName))
                    .multilineTextAlignment(.trailing)
                    .textContentType(.name)
                    .submitLabel(.done)
            }
            Toggle("Notify when others change the timer", isOn: $prefs.linkNotifications)
        } footer: {
            Text("When someone in your group starts, pauses, resets or takes a break, a notification says who and what. Not while you're on the Timer tab, where it shows under the ring.")
        }

        if let code = link.code {
            Section {
                LabeledContent("Group code") {
                    Text(code).monospaced()
                }
                Button("Leave Group", role: .destructive) { confirmLeave = true }
                    .confirmationDialog("Leave the group?", isPresented: $confirmLeave, titleVisibility: .visible) {
                        Button("Leave Group", role: .destructive) { link.leave() }
                    } message: {
                        Text("Your timer carries on here, on its own.")
                    }
            } header: {
                Text("Your Group")
            } footer: {
                Text("While linked, changing your focus length here doesn't change the group's timer until you start or reset it.")
            }
        }
    }
}

private struct LockScreenSection: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Live Activity", isOn: $prefs.liveActivity)
        } footer: {
            Text("The countdown stays on your Lock Screen and in the Dynamic Island, and ticks even while Fifteen is closed.")
        }
        Section {
            Toggle("Keep screen on while running", isOn: $prefs.keepScreenOn)
        } footer: {
            Text("Handy with the phone on a stand: the timer stays in view instead of the screen going dark.")
        }
    }
}

// MARK: - Presets

/// Named rhythms like "Study 50/10", made for touch: tap one to edit it, swipe to delete.
/// The timer's length pill lists them in this order.
struct TouchPresetsSection: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            ForEach($prefs.presets) { $preset in
                NavigationLink {
                    PresetEditor(preset: $preset)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name.isEmpty ? "Untitled" : preset.name)
                            Text(detail(preset))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if prefs.isCurrent(preset) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .accessibilityLabel("In use")
                        }
                    }
                }
            }
            .onDelete { prefs.presets.remove(atOffsets: $0) }
            .onMove { prefs.presets.move(fromOffsets: $0, toOffset: $1) }
            Button("Add Preset", systemImage: "plus") {
                withAnimation(.snappy) {
                    prefs.presets.append(TimerPreset(name: "New Preset", focus: prefs.focusMinutes,
                                                     shortBreak: prefs.shortBreaksEnabled ? prefs.shortBreakMinutes : 0))
                }
            }
        } header: {
            Text("Presets")
        } footer: {
            Text("Pick one from the timer's length pill. Swipe left on a preset to delete it.")
        }
    }

    private func detail(_ preset: TimerPreset) -> String {
        preset.shortBreak == 0 ? "\(preset.focus) min, no breaks" : "\(preset.focus) min focus, \(preset.shortBreak) min break"
    }
}

private struct PresetEditor: View {
    @Binding var preset: TimerPreset
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    private static let focusOptions = [10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90]
    private static let breakOptions = [0, 3, 5, 10, 15, 20]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $preset.name, prompt: Text("Name"))
            }
            Section {
                Picker("Focus", selection: $preset.focus) {
                    ForEach(Self.options(Self.focusOptions, including: preset.focus), id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Break", selection: $preset.shortBreak) {
                    ForEach(Self.options(Self.breakOptions, including: preset.shortBreak), id: \.self) {
                        Text($0 == 0 ? "None" : "\($0) min").tag($0)
                    }
                }
            }
            Section {
                Button(prefs.isCurrent(preset) ? "In Use" : "Use This Preset", systemImage: "checkmark.circle") {
                    prefs.apply(preset)
                    if !TimerEngine.shared.isLinked { TimerEngine.shared.reloadIdle() }
                    Haptics.play(.select)
                }
                .disabled(prefs.isCurrent(preset))
            }
            Section {
                Button("Delete Preset", systemImage: "trash", role: .destructive) {
                    let id = preset.id
                    dismiss()
                    // After the page has gone, so nothing is still editing it.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        withAnimation(.snappy) { prefs.presets.removeAll { $0.id == id } }
                    }
                }
            }
        }
        .navigationTitle(preset.name.isEmpty ? "Preset" : preset.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func options(_ base: [Int], including value: Int) -> [Int] {
        base.contains(value) ? base : (base + [value]).sorted()
    }
}
