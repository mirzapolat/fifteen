import Foundation
import UserNotifications

/// Schedules one notification for the moment the current session ends,
/// with actions to move on or snooze straight from the banner.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private let requestID = "fifteen.session.end"
    private let category = "fifteen.end"
    private var asked = false

    func setUp() {
        center.delegate = self
        let next = UNNotificationAction(identifier: "next", title: "Start Next", options: [])
        let snooze = UNNotificationAction(identifier: "snooze", title: "5 More Minutes", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [next, snooze], intentIdentifiers: [])
        ])
    }

    func requestAuthorizationIfNeeded() {
        guard !asked else { return }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
            default:
                break
            }
            completionHandler()
        }
    }
}
