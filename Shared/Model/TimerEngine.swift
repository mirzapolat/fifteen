import Foundation
import Observation

/// The one timer. Date-based, so it stays correct across sleep, app suspension and relaunch.
@Observable
@MainActor
final class TimerEngine {
    static let shared = TimerEngine()

    private(set) var phase: Phase = .focus
    private(set) var state: RunState = .idle
    /// Length of the current session, including any time added.
    private(set) var total: TimeInterval
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var sessionStart: Date?
    /// Focus sessions finished since the last long break.
    private(set) var completedInCycle = 0
    private(set) var distractions = 0
    /// The focus session that just ended, for notes and a rating.
    private(set) var lastRecordID: FocusRecord.ID?
    /// Length of the last focus session; Flowtime sizes the next break from it.
    @ObservationIgnored private var lastFocusDuration: TimeInterval = 0
    /// Updated once per displayed second while something is counting.
    private(set) var now = Date()
    var intention = "" { didSet { save() } }

    @ObservationIgnored private let prefs = Preferences.shared
    @ObservationIgnored private let history = HistoryStore.shared
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var listeners: [(TimerEvent) -> Void] = []
    @ObservationIgnored private let snapshotKey = "timerSnapshot"

    private init() {
        total = Preferences.shared.isFlowtime ? Self.flowtimeCap : Preferences.shared.duration(for: .focus)
        restore()
        refresh()
    }

    // MARK: Derived values

    func remaining(at date: Date) -> TimeInterval {
        switch state {
        case .idle: total
        case .running: max(0, (endDate ?? date).timeIntervalSince(date))
        case .paused: pausedRemaining ?? total
        case .finished: 0
        }
    }

    var remaining: TimeInterval { remaining(at: now) }

    /// Flowtime counts up with no fixed end; under the hood it's a very long session.
    static let flowtimeCap: TimeInterval = 12 * 3600

    /// True when the current session counts up (Flowtime focus).
    var isFlowtime: Bool { phase == .focus && prefs.isFlowtime }

    func elapsed(at date: Date) -> TimeInterval {
        switch state {
        case .idle: 0
        case .finished: total
        case .running, .paused: max(0, total - remaining(at: date))
        }
    }

    var elapsed: TimeInterval { elapsed(at: now) }

    private func defaultTotal(for phase: Phase) -> TimeInterval {
        phase == .focus && prefs.isFlowtime ? Self.flowtimeCap : prefs.duration(for: phase)
    }

    /// 0 at the start of a session, 1 at the end.
    func progress(at date: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: date) / total))
    }

    var isCountingOvertime: Bool {
        state == .finished && phase == .focus && prefs.keepCountingAfterEnd && endDate != nil
    }

    var overtime: TimeInterval {
        guard isCountingOvertime, let endDate else { return 0 }
        return max(0, now.timeIntervalSince(endDate))
    }

    var isActive: Bool { state == .running || state == .paused }

    /// What comes after the current phase.
    var nextPhase: Phase {
        guard phase == .focus else { return .focus }
        let every = prefs.sessionsBeforeLongBreak
        if every > 0 && completedInCycle > 0 && completedInCycle % every == 0 { return .longBreak }
        // Flowtime always rests after a session; its break length comes from the session.
        return prefs.shortBreaksEnabled || prefs.isFlowtime ? .shortBreak : .focus
    }

    // MARK: Actions

    /// Start → Pause → Resume → (at the end) move on.
    func primaryAction() {
        switch state {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        case .finished: advance(autoStart: true)
        }
    }

    func start() {
        guard state == .idle else { return }
        now = Date()
        sessionStart = now
        endDate = now.addingTimeInterval(total)
        distractions = 0
        state = .running
        emit(.started(phase))
        changed()
    }

    func pause() {
        guard state == .running else { return }
        now = Date()
        pausedRemaining = remaining(at: now)
        endDate = nil
        state = .paused
        emit(.paused)
        changed()
    }

    func resume() {
        guard state == .paused else { return }
        now = Date()
        endDate = now.addingTimeInterval(pausedRemaining ?? total)
        pausedRemaining = nil
        state = .running
        emit(.resumed)
        changed()
    }

    /// Stops the current session without recording it and goes back to the start of the same phase.
    func reset() {
        finishOvertime()
        let wasActive = isActive
        state = .idle
        endDate = nil
        pausedRemaining = nil
        sessionStart = nil
        total = defaultTotal(for: phase)
        if wasActive { emit(.stopped) }
        changed()
    }

    /// Jumps to the next phase without recording anything.
    func skip() {
        let next = nextPhase
        if phase == .longBreak { completedInCycle = 0 }
        select(next)
    }

    /// Moves from a finished session to the next one.
    func advance(autoStart: Bool) {
        finishOvertime()
        let next = nextPhase
        let cameFromFocus = phase == .focus && state == .finished
        if phase == .longBreak { completedInCycle = 0 }
        select(next)
        // Flowtime: the break grows with the session (a fifth of it by default).
        if cameFromFocus && prefs.isFlowtime && next == .shortBreak && lastFocusDuration > 0 {
            let minutes = max(1, (lastFocusDuration / 60 / Double(max(1, prefs.flowtimeBreakDivisor))).rounded())
            total = minutes * 60
            changed()
        }
        if autoStart { start() }
    }

    /// Ends focus now and records the time actually spent. Under a minute isn't a session, so it just stops.
    func finishEarly() {
        guard phase == .focus, isActive else { return }
        now = Date()
        let spent = elapsed(at: now)
        guard spent >= 60 else { reset(); return }
        total = spent
        endDate = now
        complete()
    }

    /// Re-reads the default length after settings change, if nothing is running.
    func reloadIdle() {
        guard state == .idle else { return }
        let stillAllowed = phase == .focus
            || (phase == .shortBreak && prefs.shortBreaksEnabled)
            || (phase == .longBreak && prefs.longBreaksEnabled)
        select(stillAllowed ? phase : .focus)
    }

    func select(_ newPhase: Phase) {
        if isActive { emit(.stopped) }
        if state == .finished { finishOvertime() }
        phase = newPhase
        state = .idle
        endDate = nil
        pausedRemaining = nil
        sessionStart = nil
        total = defaultTotal(for: newPhase)
        now = Date()
        changed()
    }

    /// Starts a session of the given phase right away, from anywhere (Shortcuts, menu, hot key).
    func startNow(_ newPhase: Phase, minutes: Int? = nil) {
        select(newPhase)
        if let minutes { total = TimeInterval(max(1, minutes) * 60) }
        start()
    }

    /// Changes the length of the session that's about to start.
    func setIdleMinutes(_ minutes: Int) {
        guard state == .idle, !isFlowtime else { return }
        total = TimeInterval(min(180, max(1, minutes)) * 60)
        changed()
    }

    func extend(by seconds: TimeInterval) {
        now = Date()
        switch state {
        case .idle:
            total = min(180 * 60, total + seconds)
        case .running:
            endDate = endDate?.addingTimeInterval(seconds)
            total += seconds
        case .paused:
            pausedRemaining = (pausedRemaining ?? 0) + seconds
            total += seconds
        case .finished:
            // "Just a few more minutes": reopen the session. Undo the record so it isn't counted twice.
            if phase == .focus, let last = history.records.last, last.end == endDate {
                history.delete([last.id])
                completedInCycle = max(0, completedInCycle - 1)
            }
            total += seconds
            endDate = now.addingTimeInterval(seconds)
            state = .running
            emit(.resumed)
        }
        changed()
    }

    /// The Pomodoro Technique's interruption mark.
    func logDistraction() {
        guard phase == .focus, isActive else { return }
        distractions += 1
        save()
    }

    /// Re-checks the clock, e.g. when an iPhone app comes back to the foreground.
    func refresh() {
        now = Date()
        if state == .running, remaining(at: now) <= 0 { complete() }
        startTickerIfNeeded()
    }

    func observe(_ listener: @escaping (TimerEvent) -> Void) {
        listeners.append(listener)
    }

    // MARK: Internals

    private func complete() {
        let end = endDate ?? now
        let fresh = now.timeIntervalSince(end) < 5
        if phase == .focus {
            let start = sessionStart ?? end.addingTimeInterval(-total)
            let record = FocusRecord(start: start, end: end, duration: total,
                                     intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
                                     distractions: distractions)
            history.add(record)
            lastRecordID = record.id
            lastFocusDuration = total
            completedInCycle += 1
        }
        state = .finished
        pausedRemaining = nil
        if fresh {
            SoundEngine.shared.play(phase.isBreak ? prefs.breakChime : prefs.chime, volume: prefs.chimeVolume)
        }
        let finishedPhase = phase
        emit(.finished(finishedPhase))

        // Without a break in between, the next session waits until you start it.
        let next = nextPhase
        let auto = next.isBreak ? prefs.autoStartBreaks : (finishedPhase.isBreak && prefs.autoStartFocus)
        if auto && !isCountingOvertime {
            advance(autoStart: true)
        } else {
            changed()
        }
    }

    /// Adds overtime from "keep counting" to the session that just ended.
    private func finishOvertime() {
        guard isCountingOvertime else { return }
        now = Date()
        history.extendLast(by: overtime)
    }

    private func changed() {
        save()
        Notifier.shared.sync(with: self)
        SoundEngine.shared.syncAmbient(playing: shouldPlayAmbient)
        startTickerIfNeeded()
    }

    private var shouldPlayAmbient: Bool {
        guard state == .running else { return false }
        return phase == .focus || prefs.ambientDuringBreaks
    }

    private func emit(_ event: TimerEvent) {
        for listener in listeners { listener(event) }
    }

    private var needsTicking: Bool { state == .running || isCountingOvertime }

    private func startTickerIfNeeded() {
        guard needsTicking else {
            ticker?.cancel()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.tick() else { break }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Returns how long to wait until the displayed second changes, or nil to stop ticking.
    private func tick() -> TimeInterval? {
        now = Date()
        switch state {
        case .running:
            let left = remaining(at: now)
            if left <= 0 {
                complete()
                return needsTicking ? 0.25 : nil
            }
            if phase == .focus && prefs.ticking { SoundEngine.shared.tick() }
            emit(.tick)
            let fraction = left - left.rounded(.down)
            return (fraction < 0.01 ? 1 : fraction) + 0.005
        case .finished where isCountingOvertime:
            emit(.tick)
            let elapsed = overtime
            return 1 - (elapsed - elapsed.rounded(.down)) + 0.005
        default:
            ticker = nil
            return nil
        }
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var phase: Phase
        var state: RunState
        var total: TimeInterval
        var endDate: Date?
        var pausedRemaining: TimeInterval?
        var sessionStart: Date?
        var completedInCycle: Int
        var distractions: Int
        var intention: String
    }

    private func save() {
        let snapshot = Snapshot(phase: phase, state: state, total: total, endDate: endDate,
                                pausedRemaining: pausedRemaining, sessionStart: sessionStart,
                                completedInCycle: completedInCycle, distractions: distractions, intention: intention)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        phase = s.phase
        state = s.state
        total = s.total
        endDate = s.endDate
        pausedRemaining = s.pausedRemaining
        sessionStart = s.sessionStart
        completedInCycle = s.completedInCycle
        distractions = s.distractions
        intention = s.intention
        if state == .finished && !isCountingOvertime { endDate = nil }
    }
}
