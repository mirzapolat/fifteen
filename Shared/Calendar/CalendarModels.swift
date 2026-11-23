import Observation
import SwiftUI
#if os(macOS)
import AppKit
/// A calendar's or list's colour, as the platform draws it.
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    /// EventKit's colour for a calendar or list, or a quiet stand-in when it has none.
    static func eventKit(_ color: CGColor?) -> PlatformColor {
        #if os(macOS)
        color.flatMap(NSColor.init(cgColor:)) ?? .controlAccentColor
        #else
        color.map(UIColor.init(cgColor:)) ?? .systemGray
        #endif
    }
}

/// Which side of the timer a box sits on (Mac).
enum PanelSide: String, CaseIterable, Identifiable {
    case left, right
    var id: Self { self }
    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
    var opposite: PanelSide { self == .left ? .right : .left }
}


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

/// Whose calendar it is, which decides where it's listed: yours first, then subscribed ones, then the rest.
enum CalendarKind: Int, Comparable, CaseIterable {
    /// Your own calendars, which you can add events to.
    case mine
    /// Subscriptions and calendars others share with you.
    case subscribed
    /// Birthdays, holidays, Siri suggestions and other generated calendars.
    case other

    var title: String {
        switch self {
        case .mine: "My Calendars"
        case .subscribed: "Subscribed"
        case .other: "Other"
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// One calendar the user can show events from or log sessions to.
struct CalendarInfo: Identifiable, Hashable {
    var id: String
    var title: String
    /// Account or group it belongs to ("iCloud", "Google", an email).
    var group: String
    var color: PlatformColor
    var isWritable: Bool
    var kind: CalendarKind = .mine
}

/// One event, as the side box shows it.
struct CalendarItem: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarID: String
    var color: PlatformColor
    var isAllDay: Bool
    /// Where "Open in Calendar" goes.
    var link: URL?
    /// A video call to join (Zoom, Meet, Teams…), found in the event.
    var meeting: MeetingLink?

    func isHappening(at date: Date) -> Bool { start <= date && date < end }
}

/// A video call attached to an event, and which service it's on.
struct MeetingLink: Hashable {
    var url: URL
    var service: String

    /// Hosts of the common video-call services, and what to call them.
    private static let services: [(host: String, name: String)] = [
        ("zoom.us", "Zoom"), ("zoomgov.com", "Zoom"),
        ("meet.google.com", "Meet"),
        ("teams.microsoft.com", "Teams"), ("teams.live.com", "Teams"),
        ("webex.com", "Webex"),
        ("facetime.apple.com", "FaceTime"),
        ("whereby.com", "Whereby"),
        ("meet.jit.si", "Jitsi"),
        ("gotomeeting.com", "GoTo"), ("goto.com", "GoTo"),
        ("chime.aws", "Chime"),
        ("bluejeans.com", "BlueJeans"),
        ("around.co", "Around"),
        ("discord.gg", "Discord"),
        ("slack.com", "Slack"),
    ]

    /// Only web links are ever opened: invites come from other people, and a file or app link
    /// in one shouldn't become a button.
    static func isWebLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
    }

    /// The service if this is a call link, or nil for any other link.
    static func service(for url: URL) -> String? {
        guard isWebLink(url), let host = url.host?.lowercased() else { return nil }
        // Slack and Discord links are only calls when they say so.
        if host.hasSuffix("slack.com") && !url.path.contains("huddle") { return nil }
        return services.first { host == $0.host || host.hasSuffix("." + $0.host) }?.name
    }

    /// The first call link in any of these: an event's URL, then its location, then its notes.
    static func find(in texts: [String?]) -> MeetingLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let url = match.url, let service = service(for: url) {
                    return MeetingLink(url: url, service: service)
                }
            }
        }
        return nil
    }
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

/// All calendar settings, kept apart from `Preferences`. The iPhone and iPad use Apple Calendar
/// only; the side box's place and width matter only on the Mac.
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
    var side: PanelSide = .left { didSet { store.set(side.rawValue, forKey: Key.side) } }
    /// Tucked away behind the bubble with the button in its header.
    var collapsed: Bool = false { didSet { store.set(collapsed, forKey: Key.collapsed) } }
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
    /// What logged sessions are called, with {placeholders} (see `EventTitleTemplate`).
    var eventTitle: String = EventTitleTemplate.standard { didSet { store.set(eventTitle, forKey: Key.eventTitle) } }
    /// A heads-up from the menu bar a few minutes before each timed event, even mid-session.
    var alertsEnabled: Bool = false { didSet { store.set(alertsEnabled, forKey: Key.alertsEnabled) } }
    var alertMinutes: Int = 5 { didSet { store.set(alertMinutes, forKey: Key.alertMinutes) } }

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
            Key.side: PanelSide.left.rawValue,
            Key.showAllDay: false,
            Key.logSessions: false,
            Key.useEventAsIntention: true,
            Key.eventTitle: EventTitleTemplate.standard,
            Key.alertsEnabled: false,
            Key.alertMinutes: 5,
        ])
    }

    private func load() {
        enabled = store.bool(forKey: Key.enabled)
        #if os(macOS)
        source = CalendarSource(rawValue: store.string(forKey: Key.source) ?? "") ?? .apple
        #else
        source = .apple
        #endif
        showPanel = store.bool(forKey: Key.showPanel)
        side = PanelSide(rawValue: store.string(forKey: Key.side) ?? "") ?? .left
        shownAppleCalendars = Set(store.stringArray(forKey: Key.shownApple) ?? [])
        shownGoogleCalendars = Set(store.stringArray(forKey: Key.shownGoogle) ?? [])
        showAllDay = store.bool(forKey: Key.showAllDay)
        logSessions = store.bool(forKey: Key.logSessions)
        appleLogCalendar = store.string(forKey: Key.appleLog) ?? ""
        googleLogCalendar = store.string(forKey: Key.googleLog) ?? ""
        useEventAsIntention = store.bool(forKey: Key.useEventAsIntention)
        eventTitle = store.string(forKey: Key.eventTitle) ?? EventTitleTemplate.standard
        collapsed = store.bool(forKey: Key.collapsed)
        alertsEnabled = store.bool(forKey: Key.alertsEnabled)
        alertMinutes = min(max(store.integer(forKey: Key.alertMinutes), 1), 120)
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
        static let eventTitle = "calendarEventTitle"
        static let collapsed = "calendarCollapsed"
        static let alertsEnabled = "calendarAlertsEnabled"
        static let alertMinutes = "calendarAlertMinutes"

        static let all = [enabled, source, showPanel, side, shownApple, shownGoogle, showAllDay,
                          logSessions, appleLog, googleLog, useEventAsIntention, eventTitle, collapsed,
                          alertsEnabled, alertMinutes]
    }
}

/// Turns a title like "{project}: {intention} ({minutes} min)" into an event title. Placeholders
/// with nothing to fill in vanish along with the separators and brackets around them.
enum EventTitleTemplate {
    static let standard = "{title}"

    struct Token: Identifiable {
        var key: String
        var label: String
        var id: String { key }
        var placeholder: String { "{\(key)}" }
    }

    static let tokens: [Token] = [
        Token(key: "title", label: "Intention or project"),
        Token(key: "intention", label: "Intention"),
        Token(key: "project", label: "Project"),
        Token(key: "minutes", label: "Minutes"),
        Token(key: "felt", label: "How it felt"),
        Token(key: "distractions", label: "Distractions"),
    ]

    struct Values {
        var intention: String
        var project: String
        var minutes: Int
        var felt: String
        var distractions: Int
    }

    static func render(_ template: String, _ values: Values) -> String {
        let title = !values.intention.isEmpty ? values.intention : (!values.project.isEmpty ? values.project : "Focus")
        let filled: [String: String] = [
            "title": title,
            "intention": values.intention,
            "project": values.project,
            "minutes": "\(values.minutes)",
            "felt": values.felt,
            "distractions": values.distractions > 0 ? "\(values.distractions)" : "",
        ]
        var text = template
        for (key, value) in filled {
            text = text.replacingOccurrences(of: "{\(key)}", with: value, options: .caseInsensitive)
        }
        // Brackets left empty, runs of separators, and separators at either end go.
        text = text.replacingOccurrences(of: #"\(\s*\)|\[\s*\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*([·•|–—/-])(?:\s*[·•|–—/-])+\s*"#, with: " $1 ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*([:,])(?:\s*[:,·•|–—/-])+"#, with: "$1", options: .regularExpression)
        let edges = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "·•|–—/-:,"))
        text = text.trimmingCharacters(in: edges)
        return text.isEmpty ? title : text
    }
}
