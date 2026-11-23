import SwiftUI
import UIKit

/// Settings → Calendar on iPhone and iPad: the Mac's pane, through the Calendar app (which also has
/// any Google or Exchange account added in the Settings app). Off until you switch it on.
struct TouchCalendarSettings: View {
    @Bindable private var settings = CalendarSettings.shared
    @Environment(Preferences.self) private var prefs
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        Section {
            Toggle("Connect your calendar", isOn: $settings.enabled.animation())
                .onChange(of: settings.enabled) {
                    // Switching on is the moment to ask, if Fifteen never has.
                    if settings.enabled && !sync.apple.isConnected && !sync.apple.isDenied { sync.connect() }
                }
        } footer: {
            Text("See today's events from the top of the timer, focus on one with a tap, and keep a record of every focus session in your calendar.")
        }

        if settings.enabled {
            Section {
                AccessRow(connected: sync.apple.isConnected, denied: sync.apple.isDenied,
                          connecting: sync.status == .connecting,
                          title: sync.apple.isConnected ? "Connected to Calendar" : "Not connected",
                          problem: { if case .failed(let reason) = sync.status { reason } else { nil } }(),
                          deniedText: "Access was turned off. Allow Full Access under Settings → Fifteen → Calendars.",
                          connect: { sync.connect() })
            } footer: {
                Text("Everything in the Calendar app: iCloud, and Google or Exchange accounts added in the Settings app.")
            }

            if sync.apple.isConnected {
                Section {
                    Toggle("Show today's events on the timer", isOn: $settings.showPanel.animation())
                    if settings.showPanel {
                        Toggle("Include all-day events", isOn: $settings.showAllDay)
                        if prefs.showIntention {
                            Toggle("Offer to make an event your intention", isOn: $settings.useEventAsIntention)
                        }
                    }
                } header: {
                    Text("On the Timer")
                } footer: {
                    if settings.showPanel {
                        Text("The calendar at the top of the timer lists what's on and what's next. Tap an event to focus on it, shortened if the event ends sooner, or to join its call. If it mentions one of your projects, that project is picked too. A dot on the calendar means your next event starts before the session would end; Today offers to make it fit.")
                    }
                }
                if settings.showPanel { CalendarChecklist() }

                Section {
                    Toggle("Add finished focus sessions to a calendar", isOn: $settings.logSessions.animation())
                    if settings.logSessions {
                        LogCalendarPicker()
                        EventTitleEditor()
                        if let error = sync.logError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                        }
                    }
                } header: {
                    Text("Backwards Tracking")
                } footer: {
                    if settings.logSessions {
                        Text("When a focus session ends, it's added where it happened, titled as above, with the minutes, distractions, how it felt and what you got done in the notes. Notes and ratings you add afterwards are sent too. These events are marked free, so they don't block your time, and they're left out of Today. A separate calendar just for focus, like “Fifteen”, keeps them easy to hide.")
                    }
                }
            }
        }
    }
}

/// Settings → Reminders on iPhone and iPad.
struct TouchRemindersSettings: View {
    @Bindable private var settings = RemindersSettings.shared
    @Environment(Preferences.self) private var prefs
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        Section {
            Toggle("Show reminders on the timer", isOn: $settings.enabled.animation())
                .onChange(of: settings.enabled) {
                    if settings.enabled && !sync.isConnected && !sync.isDenied { sync.connect() }
                }
        } footer: {
            Text("Keep a Reminders list a tap away from the timer: tick things off as you go, add new ones, pick today's priorities, and turn one into your intention.")
        }

        if settings.enabled {
            Section {
                AccessRow(connected: sync.isConnected, denied: sync.isDenied, connecting: false,
                          title: sync.isConnected ? "Connected to Reminders" : "Not connected",
                          problem: { if case .failed(let reason) = sync.status { reason } else { nil } }(),
                          deniedText: "Access was turned off. Allow Full Access under Settings → Fifteen → Reminders.",
                          connect: { sync.connect() })
            }
            if sync.isConnected {
                Section {
                    Picker("List", selection: Binding(
                        get: { sync.list?.id ?? settings.listID },
                        set: { settings.listID = $0 }
                    )) {
                        if sync.lists.isEmpty { Text("No lists").tag(settings.listID) }
                        ForEach(sync.lists) { list in
                            let duplicate = sync.lists.filter { $0.title == list.title }.count > 1
                            Text(duplicate ? "\(list.title) (\(list.group))" : list.title).tag(list.id)
                        }
                    }
                    Toggle("Only show what's due today or overdue", isOn: $settings.onlyDue)
                    if prefs.showIntention {
                        Toggle("Offer to make a reminder your intention", isOn: $settings.useAsIntention)
                    }
                } header: {
                    Text("On the Timer")
                } footer: {
                    Text("Open the list from the top of the timer. Tap the circle to mark one done, and again right away to take it back. Tap a reminder to focus on it; swipe right to make it one of today's priorities, which stay on top until the day ends.")
                }
            }
        }
    }
}

// MARK: - Parts

/// Whether Fifteen may use Calendar or Reminders, with the one button that fixes it.
private struct AccessRow: View {
    var connected: Bool
    var denied: Bool
    var connecting: Bool
    var title: String
    var problem: String?
    var deniedText: String
    var connect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(connected ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(connecting ? "Connecting…" : title)
                if let detail = denied ? deniedText : problem {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if denied {
                Button("Settings") { openAppSettings() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.primary)
            } else if !connected {
                Button("Allow") { connect() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.primary)
                    .disabled(connecting)
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
                Text(duplicate ? "\(calendar.title) (\(calendar.group))" : calendar.title)
                    .tag(calendar.id)
            }
        }
        .onAppear { sync.pickDefaultLogCalendar() }
        .onChange(of: sync.calendars) { sync.pickDefaultLogCalendar() }
    }
}

/// Which calendars Today lists, by account: yours, subscribed, then the rest. All until you untick one.
private struct CalendarChecklist: View {
    @Bindable private var settings = CalendarSettings.shared
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        let calendars = sync.calendars
        Section {
            if calendars.isEmpty {
                Text("No calendars found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(calendars) { calendar in
                Toggle(isOn: binding(for: calendar.id, all: calendars)) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(uiColor: calendar.color))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(calendar.title)
                            Text(calendar.kind == .mine ? calendar.group : "\(calendar.kind.title) · \(calendar.group)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Show Events From")
                Spacer()
                if !calendars.isEmpty { Text(summary(calendars)) }
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
        LabeledContent("Title") {
            TextField("Event title", text: $settings.eventTitle, prompt: Text(EventTitleTemplate.standard))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .monospaced()
        }
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(EventTitleTemplate.tokens) { token in
                    Button {
                        Haptics.play(.select)
                        insert(token)
                    } label: {
                        Text(token.label)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds \(token.placeholder) to the title")
                }
            }
            HStack(spacing: 6) {
                Text("Preview")
                    .foregroundStyle(.secondary)
                Text(preview)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: preview)
                Spacer(minLength: 0)
                if settings.eventTitle != EventTitleTemplate.standard {
                    Button("Reset") {
                        withAnimation(.snappy) { settings.eventTitle = EventTitleTemplate.standard }
                    }
                    .buttonStyle(.borderless)
                    .transition(.opacity)
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
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
