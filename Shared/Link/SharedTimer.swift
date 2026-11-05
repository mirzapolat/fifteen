import Foundation
import Observation

/// The part of the timer that linked devices share. Nothing personal: no intention, project,
/// rating, notes, settings or history. Times are on this device's clock.
struct SharedTimer: Equatable, Sendable {
    var phase: Phase
    var mode: TimerMode
    var state: RunState
    var total: TimeInterval
    /// When it ends, while running.
    var endsAt: Date?
    /// What's left, while paused.
    var pausedRemaining: TimeInterval?
    /// When this session started; tells one session from the next.
    var startedAt: Date?

    /// A running timer whose end has passed has finished, whether or not a device noticed yet.
    private func settled(at now: Date) -> RunState {
        if state == .running, let endsAt, endsAt <= now.addingTimeInterval(0.25) { return .finished }
        return state
    }

    /// The same timer, give or take clock rounding. Lets a device tell "someone changed it"
    /// from "it just ran out here too".
    func matches(_ other: SharedTimer, at now: Date) -> Bool {
        let a = settled(at: now), b = other.settled(at: now)
        guard phase == other.phase, a == b else { return false }
        if phase == .focus && mode != other.mode { return false }
        func near(_ x: Double?, _ y: Double?, _ slack: Double) -> Bool {
            switch (x, y) {
            case (nil, nil): true
            case let (x?, y?): abs(x - y) <= slack
            default: false
            }
        }
        let sameSession = near(startedAt?.timeIntervalSince1970, other.startedAt?.timeIntervalSince1970, 1.5)
        switch a {
        case .idle: return near(total, other.total, 1)
        case .running: return sameSession && near(endsAt?.timeIntervalSince1970, other.endsAt?.timeIntervalSince1970, 1)
        case .paused: return sameSession && near(pausedRemaining, other.pausedRemaining, 1)
        case .finished: return sameSession && near(total, other.total, 1.5)
        }
    }

    /// What a change looks like to the others, after their name: "paused", "added 5 min",
    /// "skipped to a short break", "started Flowtime". The relay passes it on as is (60 chars max).
    static func describe(from old: SharedTimer, to new: SharedTimer) -> String {
        let phaseChanged = old.phase != new.phase
        let newSession = phaseChanged || old.startedAt == nil
            || abs((old.startedAt?.timeIntervalSince1970 ?? 0) - (new.startedAt?.timeIntervalSince1970 ?? 0)) > 1.5
        // Mid-session (running or paused), as opposed to waiting to start or already over.
        let wasActive = old.state == .running || old.state == .paused
        let wasFlowing = old.mode == .flowtime && old.phase == .focus && wasActive
        let minutes = Int((new.total / 60).rounded())
        let added = Int(((new.total - old.total) / 60).rounded())

        // Leaving a session that hadn't ended for the next phase is a skip.
        if phaseChanged && wasActive {
            if wasFlowing { return "stopped Flowtime" }
            return new.phase == .focus ? "skipped to the next focus" : "skipped to \(named(new.phase))"
        }

        switch new.state {
        case .idle:
            if phaseChanged {
                // Moving on from a finished session, or skipping ahead before starting.
                if old.state == .finished {
                    return new.phase == .focus ? "is ready for the next focus" : "switched to \(named(new.phase))"
                }
                return new.phase == .focus ? "skipped to the next focus" : "skipped to \(named(new.phase))"
            }
            if old.state != .idle { return "reset the timer" }
            if old.mode != new.mode { return "switched to \(new.mode.title)" }
            return "set the timer to \(minutes) min"
        case .running:
            if newSession {
                if new.phase == .focus {
                    return new.mode == .flowtime ? "started Flowtime" : "started \(minutes) min of focus"
                }
                return "started \(named(new.phase))"
            }
            if old.state == .paused { return added > 0 ? "resumed and added \(added) min" : "resumed" }
            if old.state == .finished { return "added \(max(1, added)) min" }
            if added > 0 { return "added \(added) min" }
            return "changed the time"
        case .paused:
            if newSession { return "started and paused \(named(new.phase))" }
            if old.state == .paused && added > 0 { return "added \(added) min" }
            return "paused"
        case .finished:
            if wasFlowing { return "stopped Flowtime" }
            return old.phase == .focus ? "finished focus early" : "ended the break early"
        }
    }

    /// "a short break", "a long break", "focus".
    private static func named(_ phase: Phase) -> String {
        switch phase {
        case .focus: "focus"
        case .shortBreak: "a short break"
        case .longBreak: "a long break"
        }
    }
}

/// "Mira paused", shown for a few seconds under the ring when someone else changes the timer.
@Observable
@MainActor
final class LinkActivity {
    static let shared = LinkActivity()
    private(set) var message: String?
    /// Where the timer stands after the change: "Focus paused · 18:42 left".
    private(set) var detail: String?
    @ObservationIgnored private var clear: Task<Void, Never>?
    /// Mac: shows a small popup under the menu bar item when the timer isn't open (title, detail).
    @ObservationIgnored var popup: ((String, String) -> Void)?

    func show(_ text: String, detail: String? = nil) {
        message = text
        self.detail = detail
        clear?.cancel()
        clear = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self.message = nil
            self.detail = nil
        }
    }

    /// Clears it early (the Mac's strip under the bubble was clicked).
    func dismiss() {
        clear?.cancel()
        message = nil
        detail = nil
    }
}
