import AppIntents

/// Shortcuts, Siri and Spotlight actions. On the Mac these also work from the Shortcuts menu bar.
struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus"
    static let description = IntentDescription("Starts a focus session in Fifteen.")

    @Parameter(title: "Minutes", description: "Leave empty to use your usual length.")
    var minutes: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = TimerEngine.shared
        engine.startNow(.focus, minutes: minutes)
        return .result(dialog: "Focusing for \(Int(engine.total / 60)) minutes.")
    }
}

struct StartBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Break"
    static let description = IntentDescription("Starts a short or long break in Fifteen.")

    @Parameter(title: "Long Break", default: false)
    var long: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = TimerEngine.shared
        engine.startNow(long ? .longBreak : .shortBreak)
        return .result(dialog: "Break for \(Int(engine.total / 60)) minutes.")
    }
}

struct TogglePauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Timer"
    static let description = IntentDescription("Pauses the running timer, or resumes it.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let engine = TimerEngine.shared
        switch engine.state {
        case .running: engine.pause()
        case .paused: engine.resume()
        case .idle: engine.start()
        case .finished: engine.advance(autoStart: true)
        }
        return .result()
    }
}

struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Timer"
    static let description = IntentDescription("Stops the current session without recording it.")

    @MainActor
    func perform() async throws -> some IntentResult {
        TimerEngine.shared.reset()
        return .result()
    }
}

struct TimeLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Time Left"
    static let description = IntentDescription("Tells you how much time is left in the current session.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let engine = TimerEngine.shared
        engine.refresh()
        let minutes = Int((engine.remaining / 60).rounded(.up))
        let dialog: IntentDialog = switch engine.state {
        case .idle: "No session running."
        case .finished: "The session is over."
        case .paused: "\(engine.phase.title) is paused with \(minutes) minutes left."
        case .running: "\(minutes) minutes of \(engine.phase.title.lowercased()) left."
        }
        return .result(value: minutes, dialog: dialog)
    }
}

struct FifteenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(),
                    phrases: ["Start focus in \(.applicationName)", "Start a \(.applicationName) session"],
                    shortTitle: "Start Focus", systemImageName: "circle.dashed")
        AppShortcut(intent: StartBreakIntent(),
                    phrases: ["Take a break in \(.applicationName)"],
                    shortTitle: "Start Break", systemImageName: "cup.and.heat.waves")
        AppShortcut(intent: TogglePauseIntent(),
                    phrases: ["Pause \(.applicationName)", "Resume \(.applicationName)"],
                    shortTitle: "Pause or Resume", systemImageName: "playpause")
        AppShortcut(intent: StopTimerIntent(),
                    phrases: ["Stop \(.applicationName)"],
                    shortTitle: "Stop", systemImageName: "stop")
        AppShortcut(intent: TimeLeftIntent(),
                    phrases: ["How much time is left in \(.applicationName)"],
                    shortTitle: "Time Left", systemImageName: "timer")
    }
}
