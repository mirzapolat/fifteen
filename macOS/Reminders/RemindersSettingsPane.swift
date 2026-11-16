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
                Text("Keep a Reminders list beside the timer: tick things off as you go, add new ones with +, star your priorities, and turn one into your intention.")
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
            Toggle("Tuck away from the box's edge", isOn: $settings.collapsible)
            Toggle("Only show what's due today or overdue", isOn: $settings.onlyDue)
            if prefs.showIntention {
                Toggle("Offer to make a reminder your intention", isOn: $settings.useAsIntention)
            }
        } header: {
            Text("Next to the Timer")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = "Click a reminder to mark it done; click again right away to take it back. 💬 on hover makes it your intention. ☆ makes it a priority: priorities stand out at the top of the box until the day ends. ▶ starts focusing on it."
        text += " Drag the box's outer edge to make it wider or narrower."
        if settings.collapsible {
            text += " Hover the outer edge and click the tab to tuck the box away behind the timer; click it again to bring it back."
        }
        if CalendarSettings.shared.panelVisible {
            text += " Your calendar sits on the other side; moving one box moves the other."
        }
        return text
    }
}

/// The list the box shows, grouped by account, with each list's colour.
struct ReminderListPicker: View {
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
            // Grouped by account only when there's more than one: an empty heading shows as a blank line.
            if names.count > 1 {
                ForEach(names, id: \.self) { group in
                    Section(group) { rows(groups[group] ?? []) }
                }
            } else {
                rows(lists)
            }
        }
    }
}

/// A small round swatch for menus, which can't draw SwiftUI shapes.
extension ReminderListPicker {
    fileprivate func rows(_ lists: [ReminderList]) -> some View {
        ForEach(lists) { list in
            Label {
                Text(list.title)
            } icon: {
                Image(nsImage: ListDot.image(list.color))
            }
            .tag(list.id)
        }
    }
}

enum ListDot {
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
