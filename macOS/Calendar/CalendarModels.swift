import AppKit
import Observation

/// Where events come from: the Calendar app (EventKit: iCloud, Exchange, and any Google account
/// added in System Settings) or a direct sign-in to Google Calendar.
enum CalendarSource: String, CaseIterable, Identifiable {
    case apple, google
    var id: Self { self }
    var title: String {
        switch self {
        case .apple: "Apple Calendar"
        case .google: "Google Calendar"
        }
    }
}

/// Which side of the timer the events box sits on.
enum CalendarSide: String, CaseIterable, Identifiable {
    case left, right
    var id: Self { self }
    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// One calendar the user can show events from or log sessions to.
struct CalendarInfo: Identifiable, Hashable {
    var id: String
    var title: String
    /// Account or group it belongs to ("iCloud", "Google", an email).
    var group: String
    var color: NSColor
    var isWritable: Bool
}

/// One event, as the side box shows it.
struct CalendarItem: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarID: String
    var color: NSColor
    var isAllDay: Bool
    /// Where "Open in Calendar" goes.
    var link: URL?

    func isHappening(at date: Date) -> Bool { start <= date && date < end }
}

/// A finished focus session, ready to be written to a calendar.
struct LoggedEntry: Equatable {
    var recordID: UUID
    var title: String
    var notes: String
    var start: Date
    var end: Date

    /// Changes whenever anything the calendar would show changes, so edits are sent once.
    var fingerprint: String {
        "\(title)\u{1F}\(notes)\u{1F}\(Int(start.timeIntervalSince1970))\u{1F}\(Int(end.timeIntervalSince1970))"
    }
}

enum CalendarError: LocalizedError {
    case noAccess
    case notConfigured
    case signInCancelled
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noAccess: "Fifteen isn't allowed to use your calendars."
        case .notConfigured: "Google sign-in isn't set up in this build of Fifteen."
        case .signInCancelled: "Sign-in was cancelled."
        case .server(let message): message
        }
    }
}

/// One way of reading and writing calendars. Apple and Google each have one.
@MainActor
protocol CalendarProvider: AnyObject {
    var isConnected: Bool { get }
    /// Who's signed in (Google) or nil.
    var accountName: String? { get }
    func connect() async throws
    func disconnect()
    func calendars() async throws -> [CalendarInfo]
    func events(from start: Date, to end: Date, in calendarIDs: Set<String>) async throws -> [CalendarItem]
    /// Creates the event, or updates `existingID` if it's still there. Returns the event's ID.
    func save(_ entry: LoggedEntry, existingID: String?, in calendarID: String) async throws -> String
}

/// Marks the events Fifteen wrote itself, so the side box doesn't list your own sessions back to you.
enum FifteenEventTag {
    static let scheme = "fifteen"
    static func url(for recordID: UUID) -> URL { URL(string: "\(scheme)://session/\(recordID.uuidString)")! }
    static let googleKey = "fifteenSession"
}

/// All calendar settings. Mac only, kept apart from `Preferences` (which the iPhone app shares).
@Observable
@MainActor
final class CalendarSettings {
    static let shared = CalendarSettings()

    @ObservationIgnored private let store = UserDefaults.standard

    /// The master switch; everything else waits behind it.
    var enabled: Bool = false { didSet { store.set(enabled, forKey: Key.enabled) } }
    var source: CalendarSource = .apple { didSet { store.set(source.rawValue, forKey: Key.source) } }
    /// The events box next to the timer.
    var showPanel: Bool = true { didSet { store.set(showPanel, forKey: Key.showPanel) } }
    var side: CalendarSide = .left { didSet { store.set(side.rawValue, forKey: Key.side) } }
    /// Calendars shown in the box, per source. Empty = all of them.
    var shownAppleCalendars: Set<String> = [] { didSet { store.set(Array(shownAppleCalendars), forKey: Key.shownApple) } }
    var shownGoogleCalendars: Set<String> = [] { didSet { store.set(Array(shownGoogleCalendars), forKey: Key.shownGoogle) } }
    var showAllDay: Bool = false { didSet { store.set(showAllDay, forKey: Key.showAllDay) } }
    /// Backwards tracking: each finished focus session becomes an event.
    var logSessions: Bool = false { didSet { store.set(logSessions, forKey: Key.logSessions) } }
    var appleLogCalendar: String = "" { didSet { store.set(appleLogCalendar, forKey: Key.appleLog) } }
    var googleLogCalendar: String = "" { didSet { store.set(googleLogCalendar, forKey: Key.googleLog) } }
    /// Starting from an event fills in the intention and picks a project with a matching name.
    var useEventAsIntention: Bool = true { didSet { store.set(useEventAsIntention, forKey: Key.useEventAsIntention) } }

    var shownCalendars: Set<String> {
        get { source == .apple ? shownAppleCalendars : shownGoogleCalendars }
        set { if source == .apple { shownAppleCalendars = newValue } else { shownGoogleCalendars = newValue } }
    }

    var logCalendar: String {
        get { source == .apple ? appleLogCalendar : googleLogCalendar }
        set { if source == .apple { appleLogCalendar = newValue } else { googleLogCalendar = newValue } }
    }

    /// The box is drawn: the bubble is measured with it, so this decides the window's size on open.
    var panelVisible: Bool { enabled && showPanel }

    private init() {
        register()
        load()
    }

    /// Factory reset: every calendar setting back to how Fifteen ships (the switch off).
    /// A Google sign-in stays in the keychain, like Link membership; switching back on picks it up.
    func resetToDefaults() {
        for key in Key.all { store.removeObject(forKey: key) }
        load()
    }

    private func register() {
        store.register(defaults: [
            Key.enabled: false,
            Key.source: CalendarSource.apple.rawValue,
            Key.showPanel: true,
            // Menu bar items mostly sit on the right, so the box has more room on the left.
            Key.side: CalendarSide.left.rawValue,
            Key.showAllDay: false,
            Key.logSessions: false,
            Key.useEventAsIntention: true,
        ])
    }

    private func load() {
        enabled = store.bool(forKey: Key.enabled)
        source = CalendarSource(rawValue: store.string(forKey: Key.source) ?? "") ?? .apple
        showPanel = store.bool(forKey: Key.showPanel)
        side = CalendarSide(rawValue: store.string(forKey: Key.side) ?? "") ?? .left
        shownAppleCalendars = Set(store.stringArray(forKey: Key.shownApple) ?? [])
        shownGoogleCalendars = Set(store.stringArray(forKey: Key.shownGoogle) ?? [])
        showAllDay = store.bool(forKey: Key.showAllDay)
        logSessions = store.bool(forKey: Key.logSessions)
        appleLogCalendar = store.string(forKey: Key.appleLog) ?? ""
        googleLogCalendar = store.string(forKey: Key.googleLog) ?? ""
        useEventAsIntention = store.bool(forKey: Key.useEventAsIntention)
    }

    private enum Key {
        static let enabled = "calendarEnabled"
        static let source = "calendarSource"
        static let showPanel = "calendarShowPanel"
        static let side = "calendarSide"
        static let shownApple = "calendarShownApple"
        static let shownGoogle = "calendarShownGoogle"
        static let showAllDay = "calendarShowAllDay"
        static let logSessions = "calendarLogSessions"
        static let appleLog = "calendarAppleLogCalendar"
        static let googleLog = "calendarGoogleLogCalendar"
        static let useEventAsIntention = "calendarUseEventAsIntention"

        static let all = [enabled, source, showPanel, side, shownApple, shownGoogle, showAllDay,
                          logSessions, appleLog, googleLog, useEventAsIntention]
    }
}
