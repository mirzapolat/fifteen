import SwiftUI
import UIKit

/// Today, on iPhone and iPad: the Mac's two boxes beside the bubble, as one sheet from the top of
/// the timer. Your events (what's on, what's next, and a nudge when a session would run into the
/// next one) and a Reminders list to tick off. Tap an event or a reminder to focus on it.
struct TodaySheet: View {
    enum Page: Hashable { case calendar, reminders }

    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = TodayChrome.calendarOn ? .calendar : .reminders

    var body: some View {
        let both = TodayChrome.calendarOn && TodayChrome.remindersOn
        NavigationStack {
            Group {
                switch current {
                case .calendar: CalendarPage(close: { dismiss() })
                case .reminders: RemindersPage(close: { dismiss() })
                }
            }
            .navigationTitle(both ? "" : (current == .calendar ? "Today" : RemindersSync.shared.list?.title ?? "Reminders"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if both {
                    ToolbarItem(placement: .principal) {
                        Picker("Show", selection: $page.animation(.snappy)) {
                            Text("Calendar").tag(Page.calendar)
                            Text("Reminders").tag(Page.reminders)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(current == .calendar ? "Open Calendar" : "Open Reminders",
                           systemImage: "arrow.up.forward.app") {
                        if current == .calendar { CalendarSync.openCalendarApp() } else { RemindersSync.shared.open() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            CalendarSync.shared.appBecameActive()
            RemindersSync.shared.appBecameActive()
        }
    }

    /// The page asked for, or the one that's still switched on.
    private var current: Page {
        switch page {
        case .calendar: TodayChrome.calendarOn ? .calendar : .reminders
        case .reminders: TodayChrome.remindersOn ? .reminders : .calendar
        }
    }
}

/// Whether Today has anything to show.
@MainActor
enum TodayChrome {
    static var calendarOn: Bool { CalendarSettings.shared.panelVisible }
    static var remindersOn: Bool { RemindersSettings.shared.enabled }
    static var isOn: Bool { calendarOn || remindersOn }
}

extension CalendarSync {
    /// The Calendar app, today.
    static func openCalendarApp() {
        if let url = URL(string: "calshow:\(Int(Date().timeIntervalSinceReferenceDate))") { UIApplication.shared.open(url) }
    }

    /// An event's day in the Calendar app.
    static func open(_ item: CalendarItem) {
        if let link = item.link { UIApplication.shared.open(link) } else { openCalendarApp() }
    }

    /// When the focus session would end: the one about to start, or the one running. Flowtime has no end.
    func sessionEnd(_ engine: TimerEngine, now: Date) -> Date? {
        guard engine.phase == .focus else { return nil }
        switch engine.state {
        case .idle: return Preferences.shared.isFlowtime ? nil : now.addingTimeInterval(engine.total)
        case .running: return engine.isFlowtime ? nil : engine.endDate
        case .paused, .finished: return nil
        }
    }

    /// The next event, when the session would still be going as it starts.
    func clash(_ engine: TimerEngine, now: Date) -> CalendarItem? {
        guard CalendarSettings.shared.panelVisible, let next = next(after: now),
              let end = sessionEnd(engine, now: now), next.start < end else { return nil }
        return next
    }
}

/// Top right of the timer, left of Link: today's events and reminders. A dot says the next event
/// comes before the session would end.
struct TodayHeaderButton: View {
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        TimelineView(.everyMinute) { context in
            let clash = CalendarSync.shared.clash(engine, now: context.date)
            Button {
                Haptics.play(.select)
                AppRouter.shared.todayShown = true
            } label: {
                Image(systemName: TodayChrome.calendarOn ? "calendar" : "checklist")
                    .frame(width: Pill.height)
                    .pill(square: true)
                    .overlay(alignment: .topTrailing) {
                        if clash != nil {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                                .offset(x: 1, y: -1)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            .buttonStyle(.plain)
            .animation(.snappy, value: clash?.id)
            .accessibilityLabel("Today")
            .accessibilityValue(clash.map { "\($0.title) starts before this session would end" } ?? "")
            .accessibilityHint(TodayChrome.calendarOn ? "Your events and reminders" : "Your reminders")
        }
    }
}

// MARK: - Calendar

private struct CalendarPage: View {
    var close: () -> Void
    @Environment(TimerEngine.self) private var engine
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            List {
                switch sync.status {
                case .off, .notConnected:
                    message("calendar.badge.plus", "See today's events here and focus on them.") {
                        if sync.apple.isDenied {
                            Button("Open Settings") { openSettings() }
                        } else {
                            Button("Allow Access") { sync.connect() }
                        }
                    }
                case .connecting where sync.events.isEmpty:
                    message("hourglass", "Waiting for Calendar…") { EmptyView() }
                case .failed(let reason) where sync.events.isEmpty:
                    message("exclamationmark.triangle", reason) {
                        Button("Try Again") { sync.refresh() }
                    }
                default:
                    events(now: now)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { sync.refresh() }
            .animation(.snappy, value: sync.events)
        }
    }

    @ViewBuilder
    private func events(now: Date) -> some View {
        let upcoming = sync.upcoming(at: now)
        let calendar = Calendar.current
        let isToday: (CalendarItem) -> Bool = { $0.start < now || calendar.isDate($0.start, inSameDayAs: now) }
        let today = upcoming.filter(isToday)
        let tomorrow = upcoming.filter { !isToday($0) }
        let current = sync.current(at: now)

        if let next = sync.clash(engine, now: now) {
            Section { Nudge(next: next, now: now) }
        }
        Section {
            if today.isEmpty {
                Label("Nothing else today. All yours.", systemImage: "sun.max")
                    .foregroundStyle(.secondary)
            }
            ForEach(today) { item in
                EventRow(item: item, now: now, isCurrent: item.id == current?.id, close: close)
            }
        } header: {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        }
        if !tomorrow.isEmpty {
            Section("Tomorrow") {
                ForEach(Array(tomorrow.prefix(8))) { item in
                    EventRow(item: item, now: now, isCurrent: false, close: close)
                }
            }
        }
    }

    private func message<Actions: View>(_ symbol: String, _ text: String,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        ContentUnavailableView {
            Label("Calendar", systemImage: symbol)
        } description: {
            Text(text)
        } actions: {
            actions()
        }
        .listRowBackground(Color.clear)
    }
}

/// "Team sync starts in 12 min": the session would run into it. Before a session, it can be made to fit.
private struct Nudge: View {
    var next: CalendarItem
    var now: Date
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        let minutes = max(0, Int(next.start.timeIntervalSince(now) / 60))
        let canFit = engine.state == .idle && minutes >= 5
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(next.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(minutes == 0 ? "Starts now, before this session would end"
                     : "Starts in \(minutes) min, before this session would end")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if canFit {
                Button("Fit \(minutes) min") {
                    Haptics.play(.select)
                    engine.setIdleMinutes(minutes)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.primary)
                .accessibilityHint("Makes this session end before \(next.title) starts")
            }
        }
        .listRowBackground(Color.orange.opacity(0.12))
    }
}

/// One event. Tap for what you can do with it: focus on it, make it your intention, join its call.
private struct EventRow: View {
    var item: CalendarItem
    var now: Date
    var isCurrent: Bool
    var close: () -> Void
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        Menu {
            if canStart {
                Button("Focus on This", systemImage: "play.fill") {
                    sync.focus(on: item)
                    close()
                }
                if isCurrent, minutesLeft >= 1, !prefs.isFlowtime {
                    Button("Focus Until It Ends (\(minutesLeft) min)", systemImage: "timer") {
                        sync.focus(on: item, untilItEnds: true)
                        close()
                    }
                }
            }
            if sync.eventsBecomeIntention {
                Button("Use as Intention", systemImage: "text.bubble") {
                    Haptics.play(.select)
                    sync.use(item)
                    close()
                }
            }
            if let meeting = item.meeting {
                Button("Join \(meeting.service)", systemImage: "video") { UIApplication.shared.open(meeting.url) }
            }
            Divider()
            Button("Open in Calendar", systemImage: "calendar") { CalendarSync.open(item) }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(uiColor: item.color))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        // The row's divider starts under the title, not under the Join button.
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(timeLabel)
                        .font(.subheadline)
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let meeting = item.meeting, item.end > now {
                    JoinButton(meeting: meeting, soon: isCurrent || item.start.timeIntervalSince(now) <= 10 * 60)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? Color.primary.opacity(0.06) : nil)
        .accessibilityHint("Focus on it, or open it in Calendar")
    }

    /// Only before a session starts; while one runs, an event can still become its intention.
    private var canStart: Bool { !engine.isActive && item.end > now && !item.isAllDay }

    private var minutesLeft: Int { Int(item.end.timeIntervalSince(now) / 60) }

    private var timeLabel: String {
        if item.isAllDay { return "All day" }
        let time = Date.FormatStyle.dateTime.hour().minute()
        if isCurrent {
            return minutesLeft >= 60
                ? "Now · until \(item.end.formatted(time))"
                : "Now · \(max(1, minutesLeft)) min left"
        }
        let until = Int(item.start.timeIntervalSince(now) / 60)
        if until >= 0 && until < 60 { return "\(item.start.formatted(time)) · in \(max(1, until)) min" }
        return "\(item.start.formatted(time))–\(item.end.formatted(time))"
    }
}

/// "Join" beside an event with a call link: solid ink when it's on now or about to start.
private struct JoinButton: View {
    var meeting: MeetingLink
    var soon: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = Color.ink(scheme)
        Button {
            Haptics.play(.select)
            UIApplication.shared.open(meeting.url)
        } label: {
            Label("Join", systemImage: "video.fill")
                .font(.footnote.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(soon ? Color.ink(scheme == .dark ? .light : .dark) : ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(soon ? ink : ink.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Join \(meeting.service)")
    }
}

// MARK: - Reminders

private struct RemindersPage: View {
    var close: () -> Void
    @State private var newTitle = ""
    @FocusState private var adding: Bool
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        List {
            switch sync.status {
            case .off, .notConnected:
                ContentUnavailableView {
                    Label("Reminders", systemImage: "checklist")
                } description: {
                    Text("Tick things off and add new ones while you focus.")
                } actions: {
                    if sync.isDenied {
                        Button("Open Settings") { openSettings() }
                    } else {
                        Button("Allow Access") { sync.connect() }
                    }
                }
                .listRowBackground(Color.clear)
            case .failed(let reason) where sync.items.isEmpty:
                ContentUnavailableView("Reminders", systemImage: "exclamationmark.triangle", description: Text(reason))
                    .listRowBackground(Color.clear)
            default:
                let ordered = sync.ordered
                if !ordered.today.isEmpty {
                    Section("Today's Priorities") {
                        ForEach(ordered.today) { ReminderRow(item: $0, close: close) }
                    }
                }
                Section {
                    ForEach(ordered.rest) { ReminderRow(item: $0, close: close) }
                    if sync.list?.isWritable != false {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                                .frame(width: 30)
                            TextField("New Reminder", text: $newTitle)
                                .focused($adding)
                                .submitLabel(.done)
                                .onSubmit(add)
                        }
                    }
                } header: {
                    if !ordered.today.isEmpty { Text(sync.list?.title ?? "Reminders") }
                } footer: {
                    if sync.items.isEmpty {
                        Text("Nothing left to do on this list.")
                    } else {
                        Text("Tap the circle to tick one off; tap it again right away to take it back. Swipe right to make it one of today's priorities.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { sync.refresh() }
        .scrollDismissesKeyboard(.interactively)
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { adding = false; return }
        Haptics.play(.select)
        sync.add(title)
        newTitle = ""
        // Stay in the field for the next one, like the Reminders app.
        adding = true
    }
}

private struct ReminderRow: View {
    var item: ReminderItem
    var close: () -> Void
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        let done = sync.completing.contains(item.id)
        let priority = sync.isPriority(item)
        HStack(spacing: 12) {
            Button {
                Haptics.play(.select)
                withAnimation(.snappy) { sync.toggle(item) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Color.ink(scheme) : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Done, tap to undo" : "Mark as done")

            Menu {
                if !engine.isActive {
                    Button("Focus on This", systemImage: "play.fill") {
                        sync.focus(on: item)
                        close()
                    }
                }
                if prefs.showIntention && (sync.remindersBecomeIntention || engine.isActive) {
                    Button("Use as Intention", systemImage: "text.bubble") {
                        Haptics.play(.select)
                        CalendarSync.shared.useTitle(item.title)
                        close()
                    }
                }
                Button(priority ? "Not a Priority Today" : "Make a Priority Today",
                       systemImage: priority ? "star.slash" : "star") { sync.togglePriority(item) }
                Divider()
                Button("Open in Reminders", systemImage: "arrow.up.forward.app") { sync.open(item) }
                Button("Delete", systemImage: "trash", role: .destructive) { sync.delete(item) }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                            .foregroundStyle(done ? .secondary : .primary)
                            .strikethrough(done)
                            .lineLimit(3)
                        if let due = dueLabel {
                            Text(due)
                                .font(.caption)
                                .foregroundStyle(item.isOverdue(at: .now) ? Color.red : Color.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if priority {
                        Image(systemName: "star.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Priority")
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .leading) {
            Button(priority ? "Unstar" : "Priority", systemImage: priority ? "star.slash" : "star.fill") {
                sync.togglePriority(item)
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { sync.delete(item) }
        }
    }

    private var dueLabel: String? {
        guard let due = item.due else { return nil }
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(due) { day = "Today" }
        else if calendar.isDateInTomorrow(due) { day = "Tomorrow" }
        else if calendar.isDateInYesterday(due) { day = "Yesterday" }
        else { day = due.formatted(.dateTime.day().month(.abbreviated)) }
        return item.dueHasTime ? "\(day), \(due.formatted(date: .omitted, time: .shortened))" : day
    }
}

@MainActor
func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

@MainActor
private func openSettings() { openAppSettings() }
