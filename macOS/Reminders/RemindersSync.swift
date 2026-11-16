import AppKit
import EventKit
import Observation
import SwiftUI

/// Ties a Reminders list to the timer: keeps its open reminders fresh for the side box, ticks
/// them off, adds new ones, and turns one into your intention.
@Observable
@MainActor
final class RemindersSync {
    static let shared = RemindersSync()

    enum Status: Equatable {
        case off
        case notConnected
        case ready
        case failed(String)
    }

    private(set) var status: Status = .off
    private(set) var lists: [ReminderList] = []
    private(set) var items: [ReminderItem] = []
    /// Ticked in the box and about to be marked done; ticking again within the moment takes it back.
    private(set) var completing: Set<String> = []

    @ObservationIgnored let settings = RemindersSettings.shared
    @ObservationIgnored private(set) var store = EKEventStore()
    @ObservationIgnored private let engine = TimerEngine.shared
    @ObservationIgnored private let prefs = Preferences.shared
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var completeTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var started = false

    var isConnected: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .denied || status == .restricted
    }

    /// The list shown: the chosen one, or where new reminders go.
    var list: ReminderList? {
        lists.first { $0.id == settings.listID }
            ?? lists.first { $0.id == store.defaultCalendarForNewReminders()?.calendarIdentifier }
            ?? lists.first
    }

    /// Clicking a reminder fills in the intention: only when that's switched on and intentions are.
    var remindersBecomeIntention: Bool { settings.useAsIntention && prefs.showIntention }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let previousReset = prefs.onFactoryReset
        prefs.onFactoryReset = { [weak self] in
            previousReset?()
            self?.settings.resetToDefaults()
        }
        observe()
        loadPriorities()
        watchSettings()
    }

    private func watchSettings() {
        withObservationTracking {
            _ = settings.enabled
            _ = settings.listID
            _ = settings.onlyDue
        } onChange: {
            Task { @MainActor in RemindersSync.shared.watchSettings() }
        }
        refresh()
    }

    func bubbleOpened() {
        guard settings.enabled else { return }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 30 { return }
        refresh()
    }

    private func observe() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { RemindersSync.shared.refresh() }
        }
    }

    // MARK: Access

    func connect() {
        Task {
            do {
                guard try await store.requestFullAccessToReminders() else {
                    status = .notConnected
                    return
                }
                // A store made before access was granted doesn't see any lists; start fresh.
                store = EKEventStore()
                observe()
                await loadAfterConnecting()
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    /// A brand-new store fills in its accounts in the background, so right after access is
    /// granted it can report no lists at all. Keep asking for a few seconds until they show up,
    /// instead of leaving an empty box until the next launch.
    private func loadAfterConnecting() async {
        refreshTask?.cancel()
        for attempt in 0..<6 {
            store.refreshSourcesIfNecessary()
            await load()
            if !lists.isEmpty || !settings.enabled { return }
            try? await Task.sleep(for: .milliseconds(250 << attempt))
        }
    }

    // MARK: Reading

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await load() }
    }

    private func load() async {
        guard settings.enabled else {
            status = .off
            items = []
            lists = []
            return
        }
        guard isConnected else {
            status = .notConnected
            items = []
            lists = []
            return
        }
        lists = store.calendars(for: .reminder)
            .map { list in
                ReminderList(id: list.calendarIdentifier, title: list.title,
                             group: list.source?.title ?? "Other",
                             color: list.color ?? .controlAccentColor,
                             isWritable: list.allowsContentModifications)
            }
            .sorted { ($0.group, $0.title) < ($1.group, $1.title) }
        guard let list, let calendar = store.calendar(withIdentifier: list.id) else {
            items = []
            status = .ready
            return
        }
        let end: Date? = settings.onlyDue
            ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
            : nil
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: [calendar])
        let fetched: [ReminderItem] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { reminder in
                    let parts = reminder.dueDateComponents
                    return ReminderItem(id: reminder.calendarItemIdentifier,
                                        title: reminder.title?.isEmpty == false ? reminder.title : "New Reminder",
                                        due: parts.flatMap { Calendar.current.date(from: $0) },
                                        dueHasTime: parts?.hour != nil,
                                        priority: reminder.priority,
                                        created: reminder.creationDate)
                }
                continuation.resume(returning: items)
            }
        }
        guard !Task.isCancelled else { return }
        // Ones being ticked off stay until they're done, so the row doesn't jump away mid-animation.
        let kept = items.filter { completing.contains($0.id) && !fetched.contains($0) }
        withAnimation(.snappy) {
            items = Self.sorted(fetched + kept)
        }
        lastRefresh = Date()
        loadPriorities()
        status = .ready
    }

    /// Dated ones first (soonest on top), then the rest in the order they were added.
    private static func sorted(_ items: [ReminderItem]) -> [ReminderItem] {
        items.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                let pa = a.priority == 0 ? 10 : a.priority, pb = b.priority == 0 ? 10 : b.priority
                if pa != pb { return pa < pb }
                return (a.created ?? .distantPast) < (b.created ?? .distantPast)
            }
        }
    }

    // MARK: Changing

    /// Ticks a reminder (marked done after a moment, so it can be taken back), or un-ticks it.
    func toggle(_ item: ReminderItem) {
        if completing.contains(item.id) {
            completeTasks[item.id]?.cancel()
            completeTasks[item.id] = nil
            completing.remove(item.id)
            return
        }
        completing.insert(item.id)
        completeTasks[item.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            self.complete(item)
        }
    }

    private func complete(_ item: ReminderItem) {
        defer {
            completeTasks[item.id] = nil
            completing.remove(item.id)
        }
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            refresh()
            return
        }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                items.removeAll { $0.id == item.id }
                priorityIDs.removeAll { $0 == item.id }
            }
            savePriorities()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Adds a reminder to the list shown, at the bottom like the Reminders app does.
    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let list, let calendar = store.calendar(withIdentifier: list.id) else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        do {
            try store.save(reminder, commit: true)
            let item = ReminderItem(id: reminder.calendarItemIdentifier, title: title, due: nil,
                                    dueHasTime: false, priority: 0, created: Date())
            withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
                items = Self.sorted(items + [item])
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Deletes a reminder from Reminders, like swiping it away there.
    func delete(_ item: ReminderItem) {
        completeTasks[item.id]?.cancel()
        completeTasks[item.id] = nil
        completing.remove(item.id)
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            refresh()
            return
        }
        do {
            try store.remove(reminder, commit: true)
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                items.removeAll { $0.id == item.id }
                priorityIDs.removeAll { $0 == item.id }
            }
            savePriorities()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Changes a reminder's text. An empty title leaves it as it was.
    func rename(_ item: ReminderItem, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != item.title,
              let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.title = title
        do {
            try store.save(reminder, commit: true)
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].title = title }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Today's priorities

    /// Reminders picked as today's priorities, in the order they were picked. Kept by Fifteen,
    /// not in Reminders, and only for the day they were picked: each morning starts clean.
    private(set) var priorityIDs: [String] = []
    @ObservationIgnored private var priorityDay = ""
    @ObservationIgnored private let prioritiesKey = "remindersTodayPriorities"

    private static var today: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// Drops yesterday's picks (and ones no longer on the list) whenever the box is looked at.
    func loadPriorities() {
        let saved = UserDefaults.standard.dictionary(forKey: prioritiesKey)
        let day = saved?["day"] as? String ?? ""
        let ids = day == Self.today ? (saved?["ids"] as? [String] ?? []) : []
        priorityDay = Self.today
        if ids != priorityIDs { priorityIDs = ids }
    }

    private func savePriorities() {
        UserDefaults.standard.set(["day": Self.today, "ids": priorityIDs], forKey: prioritiesKey)
    }

    func isPriority(_ item: ReminderItem) -> Bool { priorityIDs.contains(item.id) }

    func togglePriority(_ item: ReminderItem) {
        if priorityDay != Self.today { loadPriorities() }
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            if let index = priorityIDs.firstIndex(of: item.id) {
                priorityIDs.remove(at: index)
            } else {
                priorityIDs.append(item.id)
            }
        }
        savePriorities()
    }

    /// Today's priorities first (in the order picked), then the rest.
    var ordered: (today: [ReminderItem], rest: [ReminderItem]) {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let today = priorityIDs.compactMap { byID[$0] }
        let picked = Set(priorityIDs)
        return (today, items.filter { !picked.contains($0.id) })
    }

    // MARK: Using

    /// Fills in the intention (and a project the reminder mentions).
    func use(_ item: ReminderItem) {
        guard settings.useAsIntention else { return }
        CalendarSync.shared.useTitle(item.title)
    }

    /// Starts a regular focus session on a reminder.
    func focus(on item: ReminderItem) {
        CalendarSync.shared.useTitle(item.title)
        guard !engine.isActive else { return }
        engine.startNow(.focus)
    }

    /// The Reminders app, at the reminder when one is given.
    func open(_ item: ReminderItem? = nil) {
        if let item, let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(item.id)"),
           NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else {
            openApp("com.apple.reminders")
        }
    }
}
