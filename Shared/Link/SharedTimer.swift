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

    /// What a change looks like to the others: "paused", "added 5 min", "started a short break".
    static func describe(from old: SharedTimer, to new: SharedTimer) -> String {
        let newSession = old.phase != new.phase || old.startedAt == nil
            || abs((old.startedAt?.timeIntervalSince1970 ?? 0) - (new.startedAt?.timeIntervalSince1970 ?? 0)) > 1.5
        let started: String = switch new.phase {
        case .focus: "started focus"
        case .shortBreak: "started a short break"
        case .longBreak: "started a long break"
        }
        let added = Int(((new.total - old.total) / 60).rounded())
        switch new.state {
        case .idle:
            if old.state != .idle { return "reset the timer" }
            if old.phase != new.phase { return "switched to \(new.phase.title.lowercased())" }
            if old.mode != new.mode { return "switched to \(new.mode.title)" }
            return "set \(Int((new.total / 60).rounded())) min"
        case .running:
            if newSession { return started }
            if old.state == .paused { return "resumed" }
            if old.state == .finished { return "added \(max(1, added)) min" }
            return added > 0 ? "added \(added) min" : "changed the timer"
        case .paused:
            if newSession { return started }
            return old.state == .paused && added > 0 ? "added \(added) min" : "paused"
        case .finished:
            return "finished early"
        }
    }
}

/// "Mira paused", shown for a few seconds under the ring when someone else changes the timer.
@Observable
@MainActor
final class LinkActivity {
    static let shared = LinkActivity()
    private(set) var message: String?
    @ObservationIgnored private var clear: Task<Void, Never>?

    func show(_ text: String) {
        message = text
        clear?.cancel()
        clear = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self.message = nil
        }
    }
}
