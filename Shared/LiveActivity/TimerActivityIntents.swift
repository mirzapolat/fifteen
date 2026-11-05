#if os(iOS)
import AppIntents

// The Live Activity's buttons. They're compiled into the widget extension (which draws them) and
// the app (which runs them): as LiveActivityIntents, the system performs them in the app's
// process, starting it in the background if needed, so the timer changes and the activity follows.

/// Pause, or resume where it left off. Once the session is over, it moves on instead.
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
        case .finished: engine.advance(autoStart: true)
        case .idle: break
        }
        #endif
        return .result()
    }
}

/// Start what comes next: the break after focus, or focus after a break.
struct AdvanceTimerActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Next"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let engine = TimerEngine.shared
        // Ends the session first if it ran out while Fifteen was asleep (which may already start
        // the break, with "Start breaks automatically" on).
        engine.refresh()
        if engine.state == .finished { engine.advance(autoStart: true) }
        #endif
        return .result()
    }
}

/// A few more minutes: added to the running session, or reopening the one that just ended.
struct AddTimeActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 5 Minutes"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let engine = TimerEngine.shared
        engine.refresh()
        if engine.state != .idle { engine.extend(by: 5 * 60) }
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
        let engine = TimerEngine.shared
        engine.refresh()
        // A finished session is already saved; "reset" then just clears it off the Lock Screen
        // and leaves the next session ready to start.
        if engine.state == .finished { engine.advance(autoStart: false) } else { engine.reset() }
        #endif
        return .result()
    }
}
#endif
