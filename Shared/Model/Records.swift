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

    static let symbols = [
        "folder", "book", "pencil", "doc.text", "laptopcomputer", "hammer", "paintbrush", "graduationcap",
        "briefcase", "music.note", "dumbbell", "leaf", "lightbulb", "chart.bar", "globe", "heart",
    ]
}

/// The history file on disk (schema v2).
struct HistoryFile: Codable, Sendable {
    static let currentVersion = 2
    var schemaVersion: Int
    var sessions: [FocusRecord]
    var projects: [Project]
}
