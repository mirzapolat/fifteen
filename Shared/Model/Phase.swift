import Foundation

/// The three kinds of session in the Pomodoro Technique.
enum Phase: String, Codable, CaseIterable, Identifiable, Sendable {
    case focus
    case shortBreak
    case longBreak

    var id: Self { self }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var symbol: String {
        switch self {
        case .focus: "circle.dashed"
        case .shortBreak: "cup.and.heat.waves"
        case .longBreak: "figure.walk"
        }
    }

    var isBreak: Bool { self != .focus }

    /// Label for the pill that moves on to this phase.
    var startTitle: String {
        switch self {
        case .focus: "Back to Focus"
        case .shortBreak: "Take a Break"
        case .longBreak: "Take a Long Break"
        }
    }
}

enum RunState: String, Codable, Sendable {
    case idle, running, paused, finished
}

enum TimerEvent {
    case started(Phase)
    case paused
    case resumed
    case finished(Phase)
    case stopped
    case tick
}

enum TimeFormat {
    /// 25:00, 4:59, 1:02:03 — always rounds up so the clock never shows 00:00 while running.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// 25m, 1h 05m — for the menu bar when seconds are hidden.
    static func short(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded(.up)))
        return minutes >= 60 ? String(format: "%dh %02dm", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    /// 1h 25m, 45m, 0m — for totals in History.
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

/// Small, concrete things to do during a break.
enum BreakTips {
    static let all = [
        "Stand up and stretch.",
        "Look at something far away for twenty seconds.",
        "Drink a glass of water.",
        "Roll your shoulders. Unclench your jaw.",
        "Close your eyes and breathe slowly.",
        "Take a short walk.",
        "Open a window. Get some air.",
        "Step away from the screen.",
    ]

    static func tip(for seed: Date?) -> String {
        guard let seed else { return all[0] }
        return all[Int(seed.timeIntervalSince1970 / 7) % all.count]
    }
}
