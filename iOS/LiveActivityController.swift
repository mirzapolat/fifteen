import ActivityKit
import Foundation
import Observation

/// Mirrors the timer onto the Lock Screen and Dynamic Island: while a session runs or is paused,
/// and once it's over, with the button that moves on. Idle, it goes away.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<FocusActivityAttributes>?
    private var lastState: FocusActivityAttributes.ContentState?
    /// Typing an intention changes the state on every key; updates wait a moment and go as one.
    private var pending: Task<Void, Never>?

    func start() {
        // Pick up the one already showing: when one of its buttons is tapped, the system launches
        // the app in the background to run it, and that activity has to stay put.
        // Any extras (from a crash, say) go.
        let existing = Activity<FocusActivityAttributes>.activities
        activity = existing.first
        for stale in existing.dropFirst() {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        observe()
    }

    private func observe() {
        withObservationTracking {
            sync()
        } onChange: {
            Task { @MainActor in LiveActivityController.shared.observe() }
        }
    }

    private func sync() {
        let engine = TimerEngine.shared
        let prefs = Preferences.shared
        // Read everything up front, so any change to it schedules the next sync.
        let state = engine.state
        let enabled = prefs.liveActivity
        let content = makeContent(engine, prefs)

        guard enabled, state != .idle, let content, ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        guard content != lastState else { return }
        let first = lastState == nil
        let timerMoved = lastState.map { $0.end != content.end || $0.isPaused != content.isPaused
            || $0.finished != content.finished || $0.phase != content.phase } ?? true
        lastState = content

        // A countdown goes stale when it ends: the widget then shows "done" by itself, even if
        // Fifteen is asleep and never gets to say so.
        let stale = !content.isPaused && !content.countsUp && !content.finished ? content.end : nil
        let update = ActivityContent(state: content, staleDate: stale,
                                     relevanceScore: content.finished ? 50 : 100)
        pending?.cancel()
        if let activity {
            pending = Task {
                // Typing settles first; the timer itself changes straight away.
                if !first && !timerMoved { try? await Task.sleep(for: .milliseconds(300)) }
                guard !Task.isCancelled else { return }
                await activity.update(update)
            }
        } else {
            activity = try? Activity.request(attributes: FocusActivityAttributes(), content: update)
        }
    }

    private func makeContent(_ engine: TimerEngine, _ prefs: Preferences) -> FocusActivityAttributes.ContentState? {
        let state = engine.state
        let total = engine.total
        let phase = engine.phase
        let countsUp = engine.isFlowtime
        let showDetails = prefs.liveActivityShowsDetails
        let intention = engine.intention.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = prefs.projectsActive ? HistoryStore.shared.project(engine.projectID) : nil
        let others = LinkSession.shared.isLinked ? LinkSession.shared.others.count : nil
        let now = Date()

        var content: FocusActivityAttributes.ContentState
        switch state {
        case .idle:
            return nil
        case .running:
            guard let endDate = engine.endDate else { return nil }
            content = .init(title: countsUp ? "Flowtime" : phase.title, symbol: phase.symbol,
                            start: endDate.addingTimeInterval(-total), end: endDate,
                            pausedRemaining: nil, total: total, countsUp: countsUp)
        case .paused:
            let left = engine.pausedRemaining ?? total
            content = .init(title: countsUp ? "Flowtime" : phase.title, symbol: phase.symbol,
                            start: now.addingTimeInterval(left - total), end: now.addingTimeInterval(left),
                            pausedRemaining: countsUp ? total - left : left, total: total, countsUp: countsUp)
        case .finished:
            // Overtime counts up from the end; otherwise the ring sits empty. Fixed dates, so the
            // state doesn't change every time it's worked out.
            let end = engine.endDate ?? engine.sessionStart?.addingTimeInterval(total) ?? now
            content = .init(title: phase.title, symbol: phase.symbol,
                            start: end.addingTimeInterval(-max(1, total)), end: end,
                            pausedRemaining: nil, total: total, countsUp: false)
            content.finished = true
        }

        content.phase = phase.rawValue
        if phase == .focus && showDetails {
            content.intention = intention.isEmpty ? nil : intention
            content.project = project?.name
            content.projectSymbol = project?.symbol
        }
        content.others = others
        content.keepsCounting = phase == .focus && prefs.keepCountingAfterEnd
            && (state != .finished || engine.isCountingOvertime)

        // What the finished state says, worked out now so the widget can show it on its own.
        let next = engine.nextPhase
        let continuesFocus = phase == .focus && next == .focus
        content.nextTitle = continuesFocus ? "Next Session" : next.startTitle
        content.nextSymbol = continuesFocus ? "play.fill" : next.symbol
        let words = SessionWords.done(phase: phase, next: next, minutes: Int((total / 60).rounded()),
                                      intention: showDetails ? intention : "")
        content.doneTitle = words.title
        content.doneMessage = words.message
        return content
    }

    private func end() {
        pending?.cancel()
        lastState = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
