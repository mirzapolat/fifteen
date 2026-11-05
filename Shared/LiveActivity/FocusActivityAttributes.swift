#if os(iOS)
import ActivityKit
import Foundation

/// Shared between the iPhone app (which starts the activity) and the widget extension (which draws it).
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var symbol: String
        /// Start of the ring's sweep; `end - total` so added minutes show correctly.
        var start: Date
        var end: Date
        /// Set while paused; the Live Activity then shows a still ring and time.
        var pausedRemaining: TimeInterval?
        var total: TimeInterval
        /// Flowtime counts up from `start`; while paused, `pausedRemaining` holds the elapsed time.
        var countsUp: Bool = false

        // Added with the richer Lock Screen. Optional or defaulted, so an activity that was already
        // showing when the app updated still decodes.

        /// Focus, short break or long break (`Phase.rawValue`).
        var phase: String? = nil
        /// "What's the one thing?", unless it's switched off for the Lock Screen.
        var intention: String? = nil
        /// The project this session counts toward, and its symbol.
        var project: String? = nil
        var projectSymbol: String? = nil
        /// How many others share this timer through Link (nil when not linked).
        var others: Int? = nil
        /// The session is over (the app saw it end). Before the app notices, the widget works it
        /// out from the stale date instead.
        var finished: Bool = false
        /// "Keep counting when focus ends": once over, the time counts up from `end`.
        var keepsCounting: Bool = false
        /// What moving on means, for the finished state: "Take a Break", "Back to Focus".
        var nextTitle: String? = nil
        var nextSymbol: String? = nil
        /// The finished state's headline and line: "Focus done", "Time for a short break."
        var doneTitle: String? = nil
        var doneMessage: String? = nil
    }
}

extension FocusActivityAttributes.ContentState {
    var isPaused: Bool { pausedRemaining != nil }
    var isBreak: Bool { phase == "shortBreak" || phase == "longBreak" }
}
#endif
