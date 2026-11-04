#if os(iOS)
import AppIntents

// The Live Activity's buttons. They're compiled into the widget extension (which draws them) and
// the app (which runs them): as LiveActivityIntents, the system performs them in the app's
// process, starting it in the background if needed, so the timer changes and the activity follows.

/// Pause, or resume where it left off.
struct ToggleTimerActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let engine = TimerEngine.shared
        engine.refresh()
        switch engine.state {
        case .running: engine.pause()
        case .paused: engine.resume()
        case .idle, .finished: break
        }
        #endif
        return .result()
    }
}

/// Stop the session without recording it; the activity goes away with it.
struct ResetTimerActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Reset"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        TimerEngine.shared.refresh()
        TimerEngine.shared.reset()
        #endif
        return .result()
    }
}
#endif
