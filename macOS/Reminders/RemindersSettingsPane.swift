import SwiftUI
import AppKit

/// Settings → Reminders. Off until you switch it on; then: access, which list, and which side.
struct RemindersSettingsPane: View {
    @Bindable private var settings = RemindersSettings.shared
    @Environment(Preferences.self) private var prefs
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        Form {
            Section {
                Toggle("Show reminders next to the timer", isOn: $settings.enabled.animation())
            } footer: {
                Text("Keep a Reminders list beside the timer: tick things off as you go, add new ones with +, star today's priorities, and turn one into your intention with a click.")
            }

            if settings.enabled {
                accessSection
                // Reading the status re-checks access whenever it changes.
                if sync.status == .ready || sync.isConnected {
                    listSection
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if settings.enabled { sync.refresh() } }
    }

    // MARK: Access

    private var accessSection: some View {
        Section("Access") {
            HStack(spacing: 10) {
                Image(systemName: sync.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(sync.isConnected ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sync.isConnected ? "Connected to Reminders" : "Not connected")
                    if sync.isDenied {
                        Text("Access was turned off. Allow Fifteen under Privacy & Security → Reminders.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if case .failed(let reason) = sync.status {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if sync.isDenied {
                    Button("Open Privacy Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                    }
                } else if !sync.isConnected {
                    Button("Allow Access…") { sync.connect() }
                } else {
                    Button("Open Reminders") { sync.open() }
                }
            }
        }
    }

    // MARK: The box

    private var listSection: some View {
        Section {
            ReminderListPicker()
            Picker("Side", selection: SidePanels.sideBinding(for: .reminders)) {
                ForEach(PanelSide.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Only show what's due today or overdue", isOn: $settings.onlyDue)
            if prefs.showIntention {
                Toggle("Clicking a reminder makes it your intention", isOn: $settings.useAsIntention)
            }
        } header: {
            Text("Next to the Timer")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = "Tick the circle to mark a reminder done; tick it again right away to take it back. ☆ makes it one of today's priorities: those sit highlighted at the top until the day ends. ▶ starts focusing on it."
        if CalendarSettings.shared.panelVisible {
            text += " Your calendar sits on the other side; moving one box moves the other."
        }
        return text
    }
}

/// The list the box shows, grouped by account, with each list's colour.
private struct ReminderListPicker: View {
    @Bindable private var settings = RemindersSettings.shared
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        let lists = sync.lists
        let groups = Dictionary(grouping: lists, by: \.group)
        let names = groups.keys.sorted()
        Picker("List", selection: Binding(
            get: { sync.list?.id ?? settings.listID },
            set: { settings.listID = $0 }
        )) {
            if lists.isEmpty {
                Text("No lists").tag(settings.listID)
            }
            ForEach(names, id: \.self) { group in
                Section(names.count > 1 ? group : "") {
                    ForEach(groups[group] ?? []) { list in
                        Label {
                            Text(list.title)
                        } icon: {
                            Image(nsImage: ListDot.image(list.color))
                        }
                        .tag(list.id)
                    }
                }
            }
        }
    }
}

/// A small round swatch for menus, which can't draw SwiftUI shapes.
private enum ListDot {
    static func image(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
