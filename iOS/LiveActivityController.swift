import ActivityKit
import Foundation
import Observation

/// Mirrors the running timer onto the Lock Screen and Dynamic Island.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<FocusActivityAttributes>?
    private var lastState: FocusActivityAttributes.ContentState?

    func start() {
        // Pick up the one already showing: when its Pause or Reset button is tapped, the system
        // launches the app in the background to run it, and that activity has to stay put.
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
        let enabled = Preferences.shared.liveActivity
        let state = engine.state
        let total = engine.total
        let endDate = engine.endDate
        let pausedRemaining = engine.pausedRemaining
        let phase = engine.phase

        guard enabled, state == .running || state == .paused,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }

        let now = Date()
        let countsUp = engine.isFlowtime
        let title = countsUp ? "Flowtime" : phase.title
        let content: FocusActivityAttributes.ContentState
        if state == .running, let endDate {
            content = .init(title: title, symbol: phase.symbol,
                            start: endDate.addingTimeInterval(-total), end: endDate,
                            pausedRemaining: nil, total: total, countsUp: countsUp)
        } else {
            let left = pausedRemaining ?? total
            content = .init(title: title, symbol: phase.symbol,
                            start: now.addingTimeInterval(left - total), end: now.addingTimeInterval(left),
                            pausedRemaining: countsUp ? total - left : left, total: total, countsUp: countsUp)
        }
        guard content != lastState else { return }
        lastState = content

        let stale = content.pausedRemaining == nil && !countsUp ? content.end : nil
        let update = ActivityContent(state: content, staleDate: stale)
        if let activity {
            Task { await activity.update(update) }
        } else {
            activity = try? Activity.request(attributes: FocusActivityAttributes(), content: update)
        }
    }

    private func end() {
        lastState = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
