import SwiftUI
import AppKit

/// Settings → Calendar. Off until you switch it on; then: where events come from, the box next to
/// the timer, and writing finished sessions back into a calendar.
struct CalendarSettingsPane: View {
    @Bindable private var settings = CalendarSettings.shared
    @Environment(Preferences.self) private var prefs
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
                    if settings.showPanel { CalendarChecklist() }
                    alertsSection
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
                Picker("Side", selection: SidePanels.sideBinding(for: .calendar)) {
                    ForEach(PanelSide.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Include all-day events", isOn: $settings.showAllDay)
                if prefs.showIntention {
                    Toggle("Clicking an event makes it your intention", isOn: $settings.useEventAsIntention)
                }
            }
        } header: {
            Text("Next to the Timer")
        } footer: {
            if settings.showPanel {
                Text(panelFooter)
            }
        }
    }

    private var panelFooter: String {
        var text = "▶ next to an event starts focusing on it, shortened if the event ends sooner. If an event mentions one of your projects, that project is picked too. When a session would run into your next event, the box says so and offers to make it fit."
        if RemindersSettings.shared.enabled {
            text += " Your reminders sit on the other side; moving one box moves the other."
        }
        return text
    }

    // MARK: Heads-up

    private var alertsSection: some View {
        Section {
            Toggle("Remind me before events start", isOn: $settings.alertsEnabled.animation())
            if settings.alertsEnabled {
                Stepper(value: $settings.alertMinutes, in: 1...120) {
                    LabeledContent("Remind me") {
                        Text("\(settings.alertMinutes) \(settings.alertMinutes == 1 ? "minute" : "minutes") before")
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Heads-Up")
        } footer: {
            if settings.alertsEnabled {
                Text("A note drops from the menu bar before each timed event in the calendars shown, even in the middle of a focus session. Click it to open the timer.")
            }
        }
    }

    // MARK: Backwards tracking

    private var loggingSection: some View {
        Section {
            Toggle("Add finished focus sessions to a calendar", isOn: $settings.logSessions.animation())
            if settings.logSessions {
                LogCalendarPicker()
                EventTitleEditor()
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
                Text("When a focus session ends, it's added where it happened, titled as above, with the minutes, distractions, how it felt and what you got done in the notes. Notes and ratings you add afterwards are sent too. These events are marked free, so they don't block your time, and they don't show up in the box next to the timer. A separate calendar just for focus, like “Fifteen”, keeps them easy to hide.")
            }
        }
    }
}

/// The calendar sessions are written to: only ones Fifteen may add events to.
private struct LogCalendarPicker: View {
    @Bindable private var settings = CalendarSettings.shared
    @Environment(Preferences.self) private var prefs
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

/// Which calendars show up in the box, as their own sections: yours, subscribed, then the rest.
/// All of them until you untick one.
private struct CalendarChecklist: View {
    @Bindable private var settings = CalendarSettings.shared
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        let calendars = sync.calendars
        let kinds = CalendarKind.allCases.filter { kind in calendars.contains { $0.kind == kind } }
        if calendars.isEmpty {
            Section("Show Events From") {
                Text("No calendars found.")
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(kinds, id: \.self) { kind in
            let inKind = calendars.filter { $0.kind == kind }
            // The account only when this section mixes several.
            let showAccount = Set(inKind.map(\.group)).count > 1
            Section {
                ForEach(inKind) { calendar in
                    Toggle(isOn: binding(for: calendar.id, all: calendars)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(nsColor: calendar.color))
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                            if showAccount {
                                Text(calendar.group)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                if kind == kinds.first {
                    HStack {
                        Text("Show Events From · \(kind.title)")
                        Spacer()
                        Text(summary(calendars))
                            .foregroundStyle(.secondary)
                            .fontWeight(.regular)
                    }
                } else {
                    Text(kind.title)
                }
            }
        }
    }

    private func summary(_ calendars: [CalendarInfo]) -> String {
        let shown = settings.shownCalendars.intersection(calendars.map(\.id))
        if shown.isEmpty || shown.count == calendars.count { return "All shown" }
        return "\(shown.count) of \(calendars.count) shown"
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

/// What logged sessions are called: a title with {placeholders}, chips to drop them in, and a preview.
private struct EventTitleEditor: View {
    @Bindable private var settings = CalendarSettings.shared
    @Environment(TimerEngine.self) private var engine
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs

    var body: some View {
        TextField("Event title", text: $settings.eventTitle, prompt: Text(EventTitleTemplate.standard))
            .monospaced()
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(EventTitleTemplate.tokens) { token in
                    Button {
                        insert(token)
                    } label: {
                        Text(token.placeholder)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(token.label)
                }
            }
            HStack(spacing: 6) {
                Text("Preview")
                    .foregroundStyle(.secondary)
                Text(preview)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: preview)
                Spacer(minLength: 0)
                if settings.eventTitle != EventTitleTemplate.standard {
                    Button("Reset") {
                        withAnimation(.snappy) { settings.eventTitle = EventTitleTemplate.standard }
                    }
                    .buttonStyle(.link)
                    .transition(.opacity)
                }
            }
            .font(.callout)
        }
        .animation(.snappy, value: settings.eventTitle == EventTitleTemplate.standard)
    }

    private func insert(_ token: EventTitleTemplate.Token) {
        var title = settings.eventTitle
        if !title.isEmpty && !title.hasSuffix(" ") { title += " " }
        settings.eventTitle = title + token.placeholder
    }

    /// The current intention and project when there are some, otherwise made-up ones.
    private var preview: String {
        let project = history.project(engine.projectID)?.name ?? history.activeProjects.first?.name ?? "Thesis"
        let felt = FocusRecord.ratingWords.indices.contains(4) ? FocusRecord.ratingWords[4] : ""
        return EventTitleTemplate.render(settings.eventTitle, .init(
            intention: engine.intention.isEmpty ? "Write the introduction" : engine.intention,
            project: prefs.projectsActive ? project : "",
            minutes: prefs.focusMinutes, felt: felt, distractions: 1))
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
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
