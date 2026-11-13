import SwiftUI
import AppKit

/// Settings → Calendar. Off until you switch it on; then: where events come from, the box next to
/// the timer, and writing finished sessions back into a calendar.
struct CalendarSettingsPane: View {
    @Bindable private var settings = CalendarSettings.shared
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        Form {
            Section {
                Toggle("Connect a calendar", isOn: $settings.enabled.animation())
            } footer: {
                Text("See today's events next to the timer, turn one into your intention with a click, and keep a record of every focus session in your calendar.")
            }

            if settings.enabled {
                sourceSection
                // Reading the status here re-checks the connection whenever it changes.
                if sync.status == .ready || (sync.status != .connecting && sync.provider.isConnected) {
                    panelSection
                    loggingSection
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if settings.enabled { sync.refresh() } }
    }

    // MARK: Source

    private var sourceSection: some View {
        Section {
            Picker("Calendar", selection: $settings.source.animation()) {
                ForEach(CalendarSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            connectionRow
        } header: {
            Text("Source")
        } footer: {
            Text(settings.source == .apple
                 ? "Everything in the Calendar app: iCloud, Exchange, and Google accounts you've added under System Settings → Internet Accounts."
                 : "Signs in to Google in your browser. Fifteen reads your events and adds your sessions; it never changes or deletes anything else.")
        }
    }

    private var connectionRow: some View {
        HStack(spacing: 10) {
            Image(systemName: sync.provider.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(sync.provider.isConnected ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionTitle)
                if let detail = connectionDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            connectionButton
        }
    }

    private var connectionTitle: String {
        if sync.status == .connecting { return "Connecting…" }
        guard sync.provider.isConnected else { return "Not connected" }
        switch settings.source {
        case .apple: return "Connected to Calendar"
        case .google: return sync.google.accountName.map { "Signed in as \($0)" } ?? "Signed in to Google"
        }
    }

    private var connectionDetail: String? {
        if case .failed(let reason) = sync.status { return reason }
        switch settings.source {
        case .apple where sync.apple.isDenied:
            return "Access was turned off. Allow Fifteen under Privacy & Security → Calendars."
        case .google where !sync.google.isConfigured:
            return "This build has no Google client ID. Use Apple Calendar, or add your Google account to the Calendar app."
        case .google where sync.status == .connecting:
            return "Finish signing in in your browser."
        default:
            return nil
        }
    }

    @ViewBuilder
    private var connectionButton: some View {
        switch settings.source {
        case .apple:
            if sync.apple.isDenied {
                Button("Open Privacy Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            } else if !sync.apple.isConnected {
                Button("Allow Access…") { sync.connect() }
                    .disabled(sync.status == .connecting)
            }
        case .google:
            if sync.status == .connecting {
                Button("Cancel") { sync.cancelConnecting() }
            } else if sync.google.isConnected {
                Button("Sign Out") { sync.disconnect() }
            } else {
                Button("Sign In with Google…") { sync.connect() }
                    .disabled(!sync.google.isConfigured)
            }
        }
    }

    // MARK: The box next to the timer

    private var panelSection: some View {
        Section {
            Toggle("Show upcoming events next to the timer", isOn: $settings.showPanel.animation())
            if settings.showPanel {
                Picker("Side", selection: $settings.side) {
                    ForEach(CalendarSide.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Include all-day events", isOn: $settings.showAllDay)
                Toggle("Clicking an event makes it your intention", isOn: $settings.useEventAsIntention)
                CalendarChecklist(title: "Show Events From")
            }
        } header: {
            Text("Next to the Timer")
        } footer: {
            if settings.showPanel {
                Text("▶ next to an event starts focusing on it, shortened if the event ends sooner. If an event mentions one of your projects, that project is picked too. When a session would run into your next event, the box says so and offers to make it fit.")
            }
        }
    }

    // MARK: Backwards tracking

    private var loggingSection: some View {
        Section {
            Toggle("Add finished focus sessions to a calendar", isOn: $settings.logSessions.animation())
            if settings.logSessions {
                LogCalendarPicker()
                if let error = sync.logError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        } header: {
            Text("Backwards Tracking")
        } footer: {
            if settings.logSessions {
                Text("When a focus session ends, it's added where it happened: your intention (or project) as the title, the minutes, distractions, how it felt and what you got done in the notes. Notes and ratings you add afterwards are sent too. These events are marked free, so they don't block your time, and they don't show up in the box next to the timer. A separate calendar just for focus, like “Fifteen”, keeps them easy to hide.")
            }
        }
    }
}

/// The calendar sessions are written to: only ones Fifteen may add events to.
private struct LogCalendarPicker: View {
    @Bindable private var settings = CalendarSettings.shared
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        let writable = sync.calendars.filter(\.isWritable)
        Picker("Add to", selection: $settings.logCalendar) {
            if !writable.contains(where: { $0.id == settings.logCalendar }) {
                Text("Choose…").tag(settings.logCalendar)
            }
            ForEach(writable) { calendar in
                let duplicate = writable.filter { $0.title == calendar.title }.count > 1
                Label {
                    Text(duplicate ? "\(calendar.title) (\(calendar.group))" : calendar.title)
                } icon: {
                    Image(nsImage: CalendarDot.image(calendar.color))
                }
                .tag(calendar.id)
            }
        }
        .onAppear { sync.pickDefaultLogCalendar() }
        .onChange(of: sync.calendars) { sync.pickDefaultLogCalendar() }
    }
}

/// Which calendars show up in the box. All of them until you pick some.
private struct CalendarChecklist: View {
    var title: String
    @Bindable private var settings = CalendarSettings.shared
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        let calendars = sync.calendars
        let groups = Dictionary(grouping: calendars, by: \.group)
        let names = groups.keys.sorted()
        DisclosureGroup {
            if calendars.isEmpty {
                Text("No calendars found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(names, id: \.self) { group in
                if names.count > 1 {
                    Text(group)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                ForEach(groups[group] ?? []) { calendar in
                    Toggle(isOn: binding(for: calendar.id, all: calendars)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(nsColor: calendar.color))
                                .frame(width: 9, height: 9)
                            Text(calendar.title)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        } label: {
            LabeledContent(title) {
                Text(summary(calendars))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summary(_ calendars: [CalendarInfo]) -> String {
        let shown = settings.shownCalendars.intersection(calendars.map(\.id))
        if shown.isEmpty || shown.count == calendars.count { return "All" }
        return "\(shown.count) of \(calendars.count)"
    }

    /// Empty means all; unticking one from "all" ticks every other one.
    private func binding(for id: String, all calendars: [CalendarInfo]) -> Binding<Bool> {
        Binding {
            let shown = settings.shownCalendars.intersection(calendars.map(\.id))
            return shown.isEmpty || shown.contains(id)
        } set: { on in
            var shown = settings.shownCalendars.intersection(calendars.map(\.id))
            if shown.isEmpty { shown = Set(calendars.map(\.id)) }
            if on { shown.insert(id) } else { shown.remove(id) }
            // Everything ticked is the same as "all", which also picks up calendars added later.
            settings.shownCalendars = shown.count == calendars.count ? [] : shown
        }
    }
}

/// A small round swatch for menus, which can't draw SwiftUI shapes.
private enum CalendarDot {
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
