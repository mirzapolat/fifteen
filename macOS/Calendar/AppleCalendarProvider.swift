import AppKit
import EventKit

/// The Calendar app's calendars through EventKit: iCloud, Exchange, CalDAV, and Google accounts
/// added under System Settings → Internet Accounts.
@MainActor
final class AppleCalendarProvider: CalendarProvider {
    private(set) var store = EKEventStore()
    /// Called when anything changes in the Calendar database (an edit there, a sync).
    var onStoreChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        observe()
    }

    var isConnected: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var accountName: String? { nil }
    /// Asked once and said no: only System Settings can change it now.
    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    func connect() async throws {
        guard !isConnected else { return }
        guard try await store.requestFullAccessToEvents() else { throw CalendarError.noAccess }
        // A store made before access was granted doesn't see any calendars; start fresh.
        store = EKEventStore()
        observe()
    }

    /// EventKit access can only be taken back in System Settings.
    func disconnect() {}

    func calendars() async throws -> [CalendarInfo] {
        guard isConnected else { throw CalendarError.noAccess }
        return store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                             group: calendar.source?.title ?? "Other",
                             color: calendar.color ?? .controlAccentColor,
                             isWritable: calendar.allowsContentModifications)
            }
            .sorted { ($0.group, $0.title) < ($1.group, $1.title) }
    }

    func events(from start: Date, to end: Date, in calendarIDs: Set<String>) async throws -> [CalendarItem] {
        guard isConnected else { throw CalendarError.noAccess }
        let all = store.calendars(for: .event)
        let chosen = calendarIDs.isEmpty ? all : all.filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        return store.events(matching: predicate)
            .filter { $0.url?.scheme != FifteenEventTag.scheme && $0.status != .canceled }
            .map { event in
                CalendarItem(id: event.eventIdentifier ?? event.calendarItemIdentifier,
                             title: event.title?.isEmpty == false ? event.title : "Untitled",
                             start: event.startDate, end: event.endDate,
                             calendarID: event.calendar.calendarIdentifier,
                             color: event.calendar.color ?? .controlAccentColor,
                             isAllDay: event.isAllDay,
                             link: Self.calendarLink(for: event))
            }
    }

    func save(_ entry: LoggedEntry, existingID: String?, in calendarID: String) async throws -> String {
        guard isConnected else { throw CalendarError.noAccess }
        guard let calendar = store.calendar(withIdentifier: calendarID) ?? store.defaultCalendarForNewEvents else {
            throw CalendarError.server("That calendar isn't there anymore. Pick another one in Settings.")
        }
        let event = existingID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        if event.calendar == nil { event.calendar = calendar }
        event.title = entry.title
        event.notes = entry.notes
        event.startDate = entry.start
        event.endDate = entry.end
        event.url = FifteenEventTag.url(for: entry.recordID)
        // A past focus block shouldn't make you look busy to anyone checking your free time later.
        event.availability = .free
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? event.calendarItemIdentifier
    }

    private func observe() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onStoreChange?() }
        }
    }

    /// Calendar.app opens to a day with `ical://`; there's no public link to one event.
    private static func calendarLink(for event: EKEvent) -> URL? {
        let seconds = Int(event.startDate.timeIntervalSinceReferenceDate)
        return URL(string: "ical://\(seconds)") ?? URL(string: "ical://")
    }
}
