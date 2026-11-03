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
    }
}
#endif
