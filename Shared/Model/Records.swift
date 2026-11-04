import Foundation

/// Plain data types for history. No app dependencies, so the analytics tests can compile them on their own.

enum TimerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Fixed-length sessions.
    case pomodoro
    /// Count up until your focus fades, then take a break proportional to the session.
    case flowtime
    var id: Self { self }
    var title: String {
        switch self {
        case .pomodoro: "Pomodoro"
        case .flowtime: "Flowtime"
        }
    }
}

/// One finished focus session.
struct FocusRecord: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var start: Date
    var end: Date
    /// Focused time, in seconds.
    var duration: TimeInterval
    var intention: String
    var distractions: Int
    /// "What did you get done?" — written after the session.
    var note: String? = nil
    /// How focused it felt, 1–5.
    var rating: Int? = nil
    // Added in schema v2; nil on older sessions.
    var projectID: UUID? = nil
    var mode: TimerMode? = nil
    /// The planned length; nil for Flowtime.
    var plannedDuration: TimeInterval? = nil
    var endedEarly: Bool? = nil
    var pausedTime: TimeInterval? = nil

    static let ratingWords = ["", "Scattered", "Distracted", "Okay", "Focused", "Deep focus"]
}

/// Where your time goes: "Thesis", "Client work", "Reading".
struct Project: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var symbol: String = "folder"
    var isArchived: Bool = false
    var created: Date = .now

    /// Offered in the project icon picker, in rows of eight: work, making, learning, life.
    static let symbols = [
        "folder", "briefcase", "doc.text", "pencil", "laptopcomputer", "terminal",
        "chevron.left.forwardslash.chevron.right", "chart.bar",
        "hammer", "wrench.and.screwdriver", "paintbrush", "camera", "film", "music.note", "mic", "puzzlepiece",
        "book", "graduationcap", "lightbulb", "brain.head.profile", "flask", "atom", "function", "globe",
        "heart", "leaf", "dumbbell", "figure.run", "house", "fork.knife", "airplane", "gamecontroller",
        "person.2", "envelope", "calendar", "cart", "star", "flag", "pawprint", "theatermasks",
    ]
}

/// The history file on disk (schema v2).
struct HistoryFile: Codable, Sendable {
    static let currentVersion = 2
    var schemaVersion: Int
    var sessions: [FocusRecord]
    var projects: [Project]
}
