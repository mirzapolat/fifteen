import AppKit
import Observation

/// Ties the calendar to the timer: keeps today's events fresh for the side box, starts focus from
/// an event, and writes each finished focus session into a calendar ("backwards tracking").
@Observable
@MainActor
final class CalendarSync {
    static let shared = CalendarSync()

    enum Status: Equatable {
        /// The integration is switched off in Settings.
        case off
        /// Switched on, but no calendar access yet.
        case notConnected
        case connecting
        case ready
        case failed(String)
    }

    private(set) var status: Status = .off
    private(set) var calendars: [CalendarInfo] = []
    /// From the start of today to the end of tomorrow, sorted, without Fifteen's own sessions.
    private(set) var events: [CalendarItem] = []
    private(set) var lastRefresh: Date?
    /// The last backwards-tracking problem, shown in Settings until the next write works.
    private(set) var logError: String?

    @ObservationIgnored let settings = CalendarSettings.shared
    @ObservationIgnored let apple = AppleCalendarProvider()
    @ObservationIgnored let google = GoogleCalendarProvider()
    @ObservationIgnored private let engine = TimerEngine.shared
    @ObservationIgnored private let history = HistoryStore.shared
    @ObservationIgnored private let prefs = Preferences.shared
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    var provider: any CalendarProvider { settings.source == .apple ? apple : google }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        prefs.onFactoryReset = { [weak self] in self?.settings.resetToDefaults() }
        apple.onStoreChange = { [weak self] in
            guard self?.settings.source == .apple else { return }
            self?.refresh()
        }
        engine.observe { [weak self] event in
            if case .finished(.focus) = event, let id = self?.engine.lastRecordID {
                self?.logSession(id)
            }
        }
        watchSettings()
        watchHistory()
    }

    /// Re-reads everything when the switch, the source or the chosen calendars change.
    private func watchSettings() {
        withObservationTracking {
            _ = settings.enabled
            _ = settings.source
            _ = settings.shownCalendars
            _ = settings.showAllDay
        } onChange: {
            Task { @MainActor in CalendarSync.shared.watchSettings() }
        }
        refresh()
        syncPoller()
    }

    /// Every five minutes while switched on, so "next up" and the warnings stay right.
    private func syncPoller() {
        poller?.cancel()
        guard settings.enabled else { return }
        poller = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if Task.isCancelled { return }
                self?.refresh()
            }
        }
    }

    /// The bubble opened: fresh events if the last look is more than a minute old.
    func bubbleOpened() {
        guard settings.panelVisible else { return }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        refresh()
    }

    // MARK: Connecting

    func connect() {
        guard settings.enabled else { return }
        status = .connecting
        Task {
            do {
                try await provider.connect()
                await load()
                pickDefaultLogCalendar()
            } catch CalendarError.signInCancelled {
                status = provider.isConnected ? .ready : .notConnected
            } catch {
                status = provider.isConnected ? .ready : .failed(error.localizedDescription)
            }
        }
    }

    func cancelConnecting() {
        google.cancelSignIn()
        if status == .connecting { status = provider.isConnected ? .ready : .notConnected }
    }

    func disconnect() {
        provider.disconnect()
        calendars = []
        events = []
        status = .notConnected
    }

    /// Without a choice yet, sessions go to the calendar new events go to (Apple) or your main one (Google).
    func pickDefaultLogCalendar() {
        let writable = calendars.filter(\.isWritable)
        guard !writable.isEmpty, !writable.contains(where: { $0.id == settings.logCalendar }) else { return }
        let fallback: String? = switch settings.source {
        case .apple: apple.store.defaultCalendarForNewEvents?.calendarIdentifier
        case .google: google.accountName
        }
        settings.logCalendar = writable.first(where: { $0.id == fallback })?.id ?? writable[0].id
    }

    // MARK: Reading

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await load() }
    }

    private func load() async {
        guard settings.enabled else {
            status = .off
            events = []
            calendars = []
            return
        }
        guard provider.isConnected else {
            if status != .connecting { status = .notConnected }
            events = []
            calendars = []
            return
        }
        do {
            let source = settings.source
            let calendars = try await provider.calendars()
            let day = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 2, to: day) ?? day.addingTimeInterval(2 * 86_400)
            let items = try await provider.events(from: day, to: end, in: settings.shownCalendars)
            guard !Task.isCancelled, source == settings.source else { return }
            self.calendars = calendars
            self.events = items.sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
            lastRefresh = Date()
            status = .ready
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            status = provider.isConnected ? .failed(error.localizedDescription) : .notConnected
        }
    }

    // MARK: What the side box shows

    /// Events still to come (or under way), timed ones only unless all-day events are wanted.
    func upcoming(at now: Date) -> [CalendarItem] {
        events.filter { $0.end > now && (settings.showAllDay || !$0.isAllDay) }
    }

    /// The timed event happening right now, if any (the shortest one when several overlap).
    func current(at now: Date) -> CalendarItem? {
        events.filter { !$0.isAllDay && $0.isHappening(at: now) }
            .min { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }
    }

    /// The next timed event that hasn't started yet.
    func next(after now: Date) -> CalendarItem? {
        events.first { !$0.isAllDay && $0.start > now }
    }

    // MARK: Starting from an event

    /// Fills in the intention (and a project whose name the event mentions) from an event.
    func use(_ item: CalendarItem) {
        guard settings.useEventAsIntention else { return }
        var intention = item.title
        if prefs.projectsActive, let project = matchingProject(for: item.title) {
            engine.projectID = project.id
            // "Thesis" as an event title is the project itself, not an intention.
            if project.name.compare(item.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                intention = ""
            }
        }
        if prefs.showIntention { engine.intention = intention }
        TimerChrome.shared.detailsShown = !engine.intention.isEmpty || engine.projectID != nil
    }

    /// Starts focus for an event now: a regular session, shortened when the event ends sooner.
    func focus(on item: CalendarItem, untilItEnds: Bool = false) {
        use(item)
        guard !engine.isActive else { return }
        if prefs.isFlowtime {
            engine.startNow(.focus)
            return
        }
        let now = Date()
        let left = Int(item.end.timeIntervalSince(now) / 60)
        let minutes: Int? = if item.isHappening(at: now) && left >= 1 {
            untilItEnds ? left : min(prefs.focusMinutes, left)
        } else {
            nil
        }
        engine.startNow(.focus, minutes: minutes)
    }

    /// The longest active project name that appears in the title.
    private func matchingProject(for title: String) -> Project? {
        history.activeProjects
            .filter { !$0.name.isEmpty && title.range(of: $0.name, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .max { $0.name.count < $1.name.count }
    }

    // MARK: Backwards tracking

    private struct LoggedEvent: Codable {
        var calendarID: String
        var eventID: String
        var source: String
        var fingerprint: String
        var loggedAt: Date
    }

    @ObservationIgnored private let loggedKey = "calendarLoggedEvents"

    private var logged: [String: LoggedEvent] {
        get {
            guard let data = UserDefaults.standard.data(forKey: loggedKey) else { return [:] }
            return (try? JSONDecoder().decode([String: LoggedEvent].self, from: data)) ?? [:]
        }
        set {
            // Only recent sessions can still change (reflection, overtime); forget the rest.
            let cutoff = Date().addingTimeInterval(-3 * 86_400)
            let kept = newValue.filter { $0.value.loggedAt > cutoff }
            UserDefaults.standard.set(try? JSONEncoder().encode(kept), forKey: loggedKey)
        }
    }

    private func logSession(_ id: FocusRecord.ID) {
        guard settings.enabled, settings.logSessions, provider.isConnected,
              let record = history.record(id), record.duration >= 60 else { return }
        Task { await write(record) }
    }

    /// Notes, a rating or overtime can come in after the session ended; send those along too.
    private func watchHistory() {
        withObservationTracking {
            _ = history.records
        } onChange: {
            Task { @MainActor in
                CalendarSync.shared.scheduleUpdates()
                CalendarSync.shared.watchHistory()
            }
        }
    }

    private func scheduleUpdates() {
        guard settings.enabled, settings.logSessions, provider.isConnected else { return }
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            // Typing a note changes the record on every keystroke; wait until it settles.
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            for (key, entry) in self.logged where entry.source == self.settings.source.rawValue {
                guard let id = UUID(uuidString: key), let record = self.history.record(id),
                      self.entry(for: record).fingerprint != entry.fingerprint else { continue }
                await self.write(record)
            }
        }
    }

    private func write(_ record: FocusRecord) async {
        let entry = entry(for: record)
        let key = record.id.uuidString
        let previous = logged[key].flatMap { $0.source == settings.source.rawValue ? $0 : nil }
        // Keep editing the event where it was first written, even if the log calendar changed since.
        let calendarID = previous?.calendarID ?? settings.logCalendar
        guard !calendarID.isEmpty else {
            logError = "Choose a calendar for your sessions in Settings."
            return
        }
        do {
            let eventID = try await provider.save(entry, existingID: previous?.eventID, in: calendarID)
            var all = logged
            all[key] = LoggedEvent(calendarID: calendarID, eventID: eventID, source: settings.source.rawValue,
                                   fingerprint: entry.fingerprint, loggedAt: previous?.loggedAt ?? Date())
            logged = all
            logError = nil
        } catch {
            logError = error.localizedDescription
        }
    }

    /// What a session looks like as an event: its intention (or project) as the title, the rest in the notes.
    private func entry(for record: FocusRecord) -> LoggedEntry {
        let project = history.project(record.projectID)
        let title = !record.intention.isEmpty ? record.intention : (project?.name ?? "Focus")
        var lines: [String] = []
        var summary = "\(max(1, Int((record.duration / 60).rounded()))) min focused"
        if record.distractions > 0 {
            summary += " · \(record.distractions) distraction\(record.distractions == 1 ? "" : "s")"
        }
        if record.endedEarly == true { summary += " · ended early" }
        lines.append(summary)
        if let project, !record.intention.isEmpty { lines.append("Project: \(project.name)") }
        if let rating = record.rating, FocusRecord.ratingWords.indices.contains(rating) {
            lines.append("Felt: \(FocusRecord.ratingWords[rating])")
        }
        if let note = record.note, !note.isEmpty { lines.append("Got done: \(note)") }
        lines.append("")
        lines.append("Logged by Fifteen")
        return LoggedEntry(recordID: record.id, title: title, notes: lines.joined(separator: "\n"),
                           start: record.start, end: record.end)
    }
}
