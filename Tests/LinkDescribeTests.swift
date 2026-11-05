import Foundation
import Testing

/// What others read when someone in the Link group changes the timer ("Mira <action>").
struct LinkDescribeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func idle(_ phase: Phase = .focus, mode: TimerMode = .pomodoro, min: Double = 25) -> SharedTimer {
        SharedTimer(phase: phase, mode: mode, state: .idle, total: min * 60)
    }
    func running(_ phase: Phase = .focus, mode: TimerMode = .pomodoro, min: Double = 25, started: Date? = nil) -> SharedTimer {
        let start = started ?? now
        return SharedTimer(phase: phase, mode: mode, state: .running, total: min * 60,
                           endsAt: start.addingTimeInterval(min * 60), startedAt: start)
    }
    func paused(_ phase: Phase = .focus, mode: TimerMode = .pomodoro, min: Double = 25, started: Date? = nil) -> SharedTimer {
        SharedTimer(phase: phase, mode: mode, state: .paused, total: min * 60,
                    pausedRemaining: 600, startedAt: started ?? now)
    }
    func finished(_ phase: Phase = .focus, min: Double = 25) -> SharedTimer {
        SharedTimer(phase: phase, mode: .pomodoro, state: .finished, total: min * 60, startedAt: now)
    }

    func say(_ old: SharedTimer, _ new: SharedTimer) -> String { SharedTimer.describe(from: old, to: new) }

    @Test func starts() {
        #expect(say(idle(), running()) == "started 25 min of focus")
        #expect(say(idle(.shortBreak, min: 5), running(.shortBreak, min: 5)) == "started a short break")
        #expect(say(idle(mode: .flowtime), running(mode: .flowtime)) == "started Flowtime")
    }

    @Test func pausesAndResumes() {
        #expect(say(running(), paused()) == "paused")
        #expect(say(paused(), running()) == "resumed")
    }

    @Test func resets() {
        #expect(say(running(), idle()) == "reset the timer")
        #expect(say(paused(), idle()) == "reset the timer")
    }

    @Test func changesTimeAndMode() {
        #expect(say(idle(), idle(min: 40)) == "set the timer to 40 min")
        #expect(say(idle(), idle(mode: .flowtime)) == "switched to Flowtime")
        #expect(say(idle(mode: .flowtime), idle()) == "switched to Pomodoro")
    }

    @Test func addsTime() {
        #expect(say(running(), running(min: 30)) == "added 5 min")
        #expect(say(finished(), running(min: 30)) == "added 5 min")
    }

    @Test func movesOnAfterASession() {
        #expect(say(finished(), idle(.shortBreak, min: 5)) == "switched to a short break")
        #expect(say(finished(), running(.longBreak, min: 15, started: now.addingTimeInterval(60))) == "started a long break")
        #expect(say(finished(.shortBreak, min: 5), idle()) == "is ready for the next focus")
    }

    @Test func skips() {
        #expect(say(running(), idle(.shortBreak, min: 5)) == "skipped to a short break")
        #expect(say(running(), running(.shortBreak, min: 5)) == "skipped to a short break")
        #expect(say(running(.shortBreak, min: 5), idle()) == "skipped to the next focus")
        #expect(say(idle(), idle(.longBreak, min: 15)) == "skipped to a long break")
    }

    @Test func flowtimeStops() {
        let flowing = running(mode: .flowtime, min: 0)
        #expect(say(flowing, idle(.shortBreak, mode: .flowtime, min: 8)) == "stopped Flowtime")
        #expect(say(flowing, running(.shortBreak, mode: .flowtime, min: 8)) == "stopped Flowtime")
    }

    @Test func endsEarly() {
        #expect(say(running(), finished()) == "finished focus early")
        #expect(say(running(.shortBreak, min: 5), finished(.shortBreak, min: 5)) == "ended the break early")
    }
}
