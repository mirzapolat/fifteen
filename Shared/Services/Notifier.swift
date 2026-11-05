import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Schedules one notification for the moment the current session ends,
/// with actions to move on or snooze straight from the banner.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private let requestID = "fifteen.session.end"
    private let linkRequestID = "fifteen.link.activity"
    /// Opens the timer (the Mac's bubble) when a Link notification is clicked.
    var openTimer: (() -> Void)?
    private let category = "fifteen.end"
    private var asked = false

    func setUp() {
        center.delegate = self
        let next = UNNotificationAction(identifier: "next", title: "Start Next", options: [])
        let snooze = UNNotificationAction(identifier: "snooze", title: "5 More Minutes", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [next, snooze], intentIdentifiers: [])
        ])
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

        let content = UNMutableNotificationContent()
        let next = engine.nextPhase
        switch engine.phase {
        case .focus:
            content.title = "Focus done"
            content.body = switch next {
            case .longBreak: "Nice work. Time for a long break."
            case .shortBreak: "Nice work. Time for a short break."
            case .focus: "Nice work. Start the next session when you're ready."
            }
        case .shortBreak, .longBreak:
            content.title = "Break's over"
            content.body = engine.intention.isEmpty ? "Ready for the next round?" : "Back to: \(engine.intention)"
        }
        content.categoryIdentifier = category
        content.interruptionLevel = .timeSensitive
        #if os(iOS)
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
        center.removeDeliveredNotifications(withIdentifiers: [linkRequestID])
        center.add(UNNotificationRequest(identifier: linkRequestID, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        Task { @MainActor in
            let engine = TimerEngine.shared
            engine.refresh()
            switch action {
            case "next":
                if engine.state == .finished { engine.advance(autoStart: true) }
            case "snooze":
                engine.extend(by: 5 * 60)
            case UNNotificationDefaultActionIdentifier:
                Notifier.shared.openTimer?()
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
