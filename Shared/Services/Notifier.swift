import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// The words for a session that just ended, shared by the notification and the Live Activity so
/// both say the same thing.
enum SessionWords {
    static func done(phase: Phase, next: Phase, minutes: Int, intention: String) -> (title: String, message: String) {
        let what = quoted(intention)
        let length = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        switch phase {
        case .focus:
            switch next {
            case .shortBreak:
                return ("Focus done", what.map { "\(length) on \($0). Time for a short break." }
                        ?? "Nice work. Time for a short break.")
            case .longBreak:
                return ("Round complete", what.map { "\(length) on \($0) rounds it off. Time for a long break." }
                        ?? "That's a full round. Time for a long break.")
            case .focus:
                return ("Session complete", what.map { "\(length) on \($0). Start the next one when you're ready." }
                        ?? "Nice work. Start the next one when you're ready.")
            }
        case .shortBreak, .longBreak:
            return ("Break's over", what.map { "Back to \($0)?" } ?? "Ready for the next round?")
        }
    }

    /// “Write the intro”, trimmed so a long intention doesn't swamp the line.
    static func quoted(_ intention: String) -> String? {
        let text = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let short = text.count > 40 ? text.prefix(38).trimmingCharacters(in: .whitespaces) + "…" : text
        return "\u{201C}\(short)\u{201D}"
    }
}

/// Schedules one notification for the moment the current session ends,
/// with actions to move on or snooze straight from the banner.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private let requestID = "fifteen.session.end"
    private let linkRequestID = "fifteen.link.activity"
    /// Opens the timer (the Mac's bubble, the iPhone's Timer tab) when a notification is tapped.
    var openTimer: (() -> Void)?
    /// iPhone: opens the Link group when a Link notification is tapped.
    var openLink: (() -> Void)?
    private var asked = false

    /// One category per way a session can end, so the banner's button says exactly what it does.
    private enum Category: String, CaseIterable {
        /// Focus ends, a short break is next.
        case toBreak = "fifteen.end.break"
        case toLongBreak = "fifteen.end.longBreak"
        /// A break ends, focus is next.
        case toFocus = "fifteen.end.focus"
        /// Focus ends with no break in between.
        case next = "fifteen.end.next"
        /// What's next starts on its own; nothing to press.
        case automatic = "fifteen.end.auto"

        var nextTitle: String? {
            switch self {
            case .toBreak: "Take a Break"
            case .toLongBreak: "Take a Long Break"
            case .toFocus: "Back to Focus"
            case .next: "Start Next Session"
            case .automatic: nil
            }
        }
    }

    func setUp() {
        center.delegate = self
        let snooze = UNNotificationAction(identifier: "snooze", title: "5 More Minutes", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "plus"))
        let categories = Category.allCases.map { category -> UNNotificationCategory in
            var actions: [UNNotificationAction] = []
            if let title = category.nextTitle {
                actions.append(UNNotificationAction(identifier: "next", title: title, options: [],
                                                    icon: UNNotificationActionIcon(systemImageName: "play.fill")))
                actions.append(snooze)
            }
            return UNNotificationCategory(identifier: category.rawValue, actions: actions, intentIdentifiers: [])
        }
        center.setNotificationCategories(Set(categories))
        NotificationAccess.shared.refresh()
    }

    func requestAuthorizationIfNeeded() {
        guard !asked else { return }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in NotificationAccess.shared.refresh() }
        }
    }

    func sync(with engine: TimerEngine) {
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        guard Preferences.shared.notifications, engine.state == .running, !engine.isFlowtime,
              let end = engine.endDate else { return }
        requestAuthorizationIfNeeded()

        let prefs = Preferences.shared
        let next = engine.nextPhase
        let words = SessionWords.done(phase: engine.phase, next: next,
                                      minutes: Int((engine.total / 60).rounded()), intention: engine.intention)
        let content = UNMutableNotificationContent()
        content.title = words.title
        content.body = words.message

        // If what's next starts by itself, say so instead of offering a button for it.
        let startsByItself = engine.phase == .focus
            ? next.isBreak && prefs.autoStartBreaks && !prefs.keepCountingAfterEnd
            : prefs.autoStartFocus
        let category: Category
        if startsByItself {
            category = .automatic
            let minutes = prefs.minutes(for: next)
            content.body = engine.phase == .focus
                ? "Your \(minutes)-minute break starts now. \(BreakTips.tip(for: end))"
                : SessionWords.quoted(engine.intention).map { "Focus starts now: \($0)." }
                    ?? "Your next \(minutes)-minute focus starts now."
        } else {
            category = switch (engine.phase, next) {
            case (.focus, .shortBreak): .toBreak
            case (.focus, .longBreak): .toLongBreak
            case (.focus, .focus): .next
            default: .toFocus
            }
        }
        content.categoryIdentifier = category.rawValue
        content.threadIdentifier = "fifteen.session"
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        #if os(iOS)
        // The Mac plays Fifteen's own chime; the iPhone may be asleep, so the system sound stands in.
        content.sound = .default
        #endif

        let interval = max(1, end.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
    }

    /// "Mira paused" — someone in the Link group changed the timer. Each one replaces the last,
    /// so a burst of changes leaves a single, current banner rather than a stack.
    func notifyLinkActivity(title: String, body: String) {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "fifteen.link"
        content.userInfo = ["link": true]
        content.interruptionLevel = .active
        center.removeDeliveredNotifications(withIdentifiers: [linkRequestID])
        center.add(UNNotificationRequest(identifier: linkRequestID, content: content, trigger: nil))
    }

    /// Opening Fifteen clears the session banner: the timer says the same thing.
    func clearDelivered() {
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        #if os(iOS)
        // On the Timer tab the ring itself shows that the session ended (and the chime plays); a
        // banner on top would only cover it. Elsewhere in the app it's worth the banner.
        let isSession = notification.request.identifier == "fifteen.session.end"
        Task { @MainActor in
            completionHandler(isSession && LinkChrome.shared.timerVisible ? [.list] : [.banner, .list])
        }
        #else
        completionHandler([.banner, .list])
        #endif
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let isLink = response.notification.request.content.userInfo["link"] as? Bool == true
        Task { @MainActor in
            let engine = TimerEngine.shared
            engine.refresh()
            switch action {
            case "next":
                if engine.state == .finished { engine.advance(autoStart: true) }
            case "snooze":
                if engine.state != .idle { engine.extend(by: 5 * 60) }
            case UNNotificationDefaultActionIdentifier:
                if isLink, let openLink = Notifier.shared.openLink { openLink() } else { Notifier.shared.openTimer?() }
            default:
                break
            }
            completionHandler()
        }
    }
}

/// Whether Fifteen may show notifications, kept current so Settings can warn when it can't.
@MainActor @Observable
final class NotificationAccess {
    static let shared = NotificationAccess()

    private(set) var status: UNAuthorizationStatus = .notDetermined

    /// Allowed in any form (provisional and ephemeral count, too).
    var isAllowed: Bool {
        #if os(iOS)
        if status == .ephemeral { return true }
        #endif
        return status == .authorized || status == .provisional
    }

    func refresh() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus != status { status = settings.authorizationStatus }
        }
    }

    /// Asks once if never asked; refused before, so only System Settings can change it.
    func request(open: (URL) -> Void) {
        if status == .notDetermined {
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                refresh()
            }
        } else if let url = Self.settingsURL {
            open(url)
        }
    }

    static var settingsURL: URL? {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")
        #else
        URL(string: UIApplication.openNotificationSettingsURLString)
        #endif
    }
}
