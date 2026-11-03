import Foundation
import Observation

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case iconAndTime, icon, time
    var id: Self { self }
    var title: String {
        switch self {
        case .iconAndTime: "Icon and Time"
        case .icon: "Icon Only"
        case .time: "Time Only"
        }
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case ring, pie, fifteen, bar, hourglass, dot
    var id: Self { self }
    var title: String {
        switch self {
        case .ring: "Ring"
        case .pie: "Pie"
        case .fifteen: "15"
        case .bar: "Bar"
        case .hourglass: "Hourglass"
        case .dot: "Dot"
        }
    }
}

enum Chime: String, CaseIterable, Identifiable {
    case bell, bowl, wood, none
    var id: Self { self }
    var title: String {
        switch self {
        case .bell: "Bell"
        case .bowl: "Singing Bowl"
        case .wood: "Wood Block"
        case .none: "None"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum TimerMode: String, CaseIterable, Identifiable {
    /// Fixed-length sessions.
    case pomodoro
    /// Count up until your focus fades, then take a break proportional to the session.
    case flowtime
    var id: Self { self }
    var title: String {
        switch self {
        case .pomodoro: "Pomodoro"
        case .flowtime: "Flowtime"
        }
    }
}

/// A named rhythm, e.g. "Study" = 50 min focus + 10 min breaks.
struct TimerPreset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var focus: Int
    /// 0 means no short breaks.
    var shortBreak: Int

    static let defaults = [
        TimerPreset(name: "Work", focus: 25, shortBreak: 5),
        TimerPreset(name: "Study", focus: 50, shortBreak: 10),
        TimerPreset(name: "Reading", focus: 30, shortBreak: 5),
    ]
}

enum BlockAction: String, CaseIterable, Identifiable {
    case hide, quit
    var id: Self { self }
    var title: String {
        switch self {
        case .hide: "Hide It"
        case .quit: "Quit It"
        }
    }
}

enum Ambient: String, CaseIterable, Identifiable {
    case off, white, pink, brown
    var id: Self { self }
    var title: String {
        switch self {
        case .off: "Off"
        case .white: "White Noise"
        case .pink: "Rain"
        case .brown: "Deep Rumble"
        }
    }
}

/// All user settings, stored in UserDefaults. Every property writes through on change.
@Observable
@MainActor
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored private let store = UserDefaults.standard

    // Timer
    var timerMode: TimerMode { didSet { store.set(timerMode.rawValue, forKey: Key.timerMode) } }
    var isFlowtime: Bool { timerMode == .flowtime }
    /// Flowtime break = focus time ÷ this.
    var flowtimeBreakDivisor: Int { didSet { store.set(flowtimeBreakDivisor, forKey: Key.flowtimeBreakDivisor) } }
    var presets: [TimerPreset] { didSet { store.set(try? JSONEncoder().encode(presets), forKey: Key.presets) } }
    var focusMinutes: Int { didSet { store.set(focusMinutes, forKey: Key.focusMinutes) } }
    var shortBreakMinutes: Int { didSet { store.set(shortBreakMinutes, forKey: Key.shortBreakMinutes) } }
    var longBreakMinutes: Int { didSet { store.set(longBreakMinutes, forKey: Key.longBreakMinutes) } }
    var shortBreaksEnabled: Bool { didSet { store.set(shortBreaksEnabled, forKey: Key.shortBreaksEnabled) } }
    /// 0 means long breaks are off.
    var sessionsBeforeLongBreak: Int { didSet { store.set(sessionsBeforeLongBreak, forKey: Key.sessionsBeforeLongBreak) } }
    var longBreaksEnabled: Bool { sessionsBeforeLongBreak > 0 }
    var anyBreaksEnabled: Bool { shortBreaksEnabled || longBreaksEnabled }
    var dailyGoal: Int { didSet { store.set(dailyGoal, forKey: Key.dailyGoal) } }
    var autoStartBreaks: Bool { didSet { store.set(autoStartBreaks, forKey: Key.autoStartBreaks) } }
    var autoStartFocus: Bool { didSet { store.set(autoStartFocus, forKey: Key.autoStartFocus) } }
    var keepCountingAfterEnd: Bool { didSet { store.set(keepCountingAfterEnd, forKey: Key.keepCountingAfterEnd) } }
    var dayStartsAtHour: Int { didSet { store.set(dayStartsAtHour, forKey: Key.dayStartsAtHour) } }

    // Sound
    var soundEnabled: Bool { didSet { store.set(soundEnabled, forKey: Key.soundEnabled) } }
    /// Played when a focus session ends.
    var chime: Chime { didSet { store.set(chime.rawValue, forKey: Key.chime) } }
    /// Played when a break ends.
    var breakChime: Chime { didSet { store.set(breakChime.rawValue, forKey: Key.breakChime) } }
    var chimeVolume: Double { didSet { store.set(chimeVolume, forKey: Key.chimeVolume) } }
    var ticking: Bool { didSet { store.set(ticking, forKey: Key.ticking) } }
    var ambient: Ambient { didSet { store.set(ambient.rawValue, forKey: Key.ambient) } }
    var ambientVolume: Double { didSet { store.set(ambientVolume, forKey: Key.ambientVolume) } }
    var ambientDuringBreaks: Bool { didSet { store.set(ambientDuringBreaks, forKey: Key.ambientDuringBreaks) } }

    // Notifications
    var notifications: Bool { didSet { store.set(notifications, forKey: Key.notifications) } }

    // Display — what the timer shows
    var appearance: AppearanceMode { didSet { store.set(appearance.rawValue, forKey: Key.appearance) } }
    var showIntention: Bool { didSet { store.set(showIntention, forKey: Key.showIntention) } }
    var showCycleDots: Bool { didSet { store.set(showCycleDots, forKey: Key.showCycleDots) } }
    var showTodayProgress: Bool { didSet { store.set(showTodayProgress, forKey: Key.showTodayProgress) } }
    var showWeekChart: Bool { didSet { store.set(showWeekChart, forKey: Key.showWeekChart) } }
    /// After focus: "What did you get done?" and a 1–5 focus rating.
    var askForReflection: Bool { didSet { store.set(askForReflection, forKey: Key.askForReflection) } }

    // Mac
    var menuBarDisplay: MenuBarDisplay { didSet { store.set(menuBarDisplay.rawValue, forKey: Key.menuBarDisplay) } }
    var menuBarSeconds: Bool { didSet { store.set(menuBarSeconds, forKey: Key.menuBarSeconds) } }
    var menuBarIcon: MenuBarIconStyle { didSet { store.set(menuBarIcon.rawValue, forKey: Key.menuBarIcon) } }
    var globalHotKeys: Bool { didSet { store.set(globalHotKeys, forKey: Key.globalHotKeys) } }
    var hideDistractingApps: Bool { didSet { store.set(hideDistractingApps, forKey: Key.hideDistractingApps) } }
    var blockedApps: [String] { didSet { store.set(blockedApps, forKey: Key.blockedApps) } }
    var blockAction: BlockAction { didSet { store.set(blockAction.rawValue, forKey: Key.blockAction) } }
    var breakCurtain: Bool { didSet { store.set(breakCurtain, forKey: Key.breakCurtain) } }
    var pauseWhenLocked: Bool { didSet { store.set(pauseWhenLocked, forKey: Key.pauseWhenLocked) } }
    var focusStartShortcut: String { didSet { store.set(focusStartShortcut, forKey: Key.focusStartShortcut) } }
    var focusEndShortcut: String { didSet { store.set(focusEndShortcut, forKey: Key.focusEndShortcut) } }

    // iPhone & iPad
    var liveActivity: Bool { didSet { store.set(liveActivity, forKey: Key.liveActivity) } }
    var keepScreenOn: Bool { didSet { store.set(keepScreenOn, forKey: Key.keepScreenOn) } }

    private init() {
        store.register(defaults: [
            Key.focusMinutes: 25,
            Key.shortBreakMinutes: 5,
            Key.longBreakMinutes: 15,
            Key.timerMode: TimerMode.pomodoro.rawValue,
            Key.flowtimeBreakDivisor: 5,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.showIntention: true,
            Key.showCycleDots: true,
            Key.showTodayProgress: true,
            Key.showWeekChart: true,
            Key.askForReflection: true,
            Key.shortBreaksEnabled: true,
            Key.sessionsBeforeLongBreak: 4,
            Key.soundEnabled: true,
            Key.blockAction: BlockAction.hide.rawValue,
            Key.dailyGoal: 8,
            Key.autoStartBreaks: false,
            Key.autoStartFocus: false,
            Key.keepCountingAfterEnd: false,
            Key.dayStartsAtHour: 4,
            Key.chime: Chime.bell.rawValue,
            Key.breakChime: Chime.bowl.rawValue,
            Key.chimeVolume: 0.7,
            Key.ticking: false,
            Key.ambient: Ambient.off.rawValue,
            Key.ambientVolume: 0.4,
            Key.ambientDuringBreaks: false,
            Key.notifications: true,
            Key.menuBarDisplay: MenuBarDisplay.iconAndTime.rawValue,
            Key.menuBarSeconds: true,
            Key.menuBarIcon: MenuBarIconStyle.ring.rawValue,
            Key.globalHotKeys: true,
            Key.hideDistractingApps: false,
            Key.blockedApps: [String](),
            Key.breakCurtain: false,
            Key.pauseWhenLocked: true,
            Key.focusStartShortcut: "",
            Key.focusEndShortcut: "",
            Key.liveActivity: true,
            Key.keepScreenOn: false,
        ])
        focusMinutes = store.integer(forKey: Key.focusMinutes)
        shortBreakMinutes = store.integer(forKey: Key.shortBreakMinutes)
        longBreakMinutes = store.integer(forKey: Key.longBreakMinutes)
        timerMode = TimerMode(rawValue: store.string(forKey: Key.timerMode) ?? "") ?? .pomodoro
        flowtimeBreakDivisor = store.integer(forKey: Key.flowtimeBreakDivisor)
        presets = store.data(forKey: Key.presets).flatMap { try? JSONDecoder().decode([TimerPreset].self, from: $0) }
            ?? TimerPreset.defaults
        appearance = AppearanceMode(rawValue: store.string(forKey: Key.appearance) ?? "") ?? .system
        showIntention = store.bool(forKey: Key.showIntention)
        showCycleDots = store.bool(forKey: Key.showCycleDots)
        showTodayProgress = store.bool(forKey: Key.showTodayProgress)
        showWeekChart = store.bool(forKey: Key.showWeekChart)
        askForReflection = store.bool(forKey: Key.askForReflection)
        shortBreaksEnabled = store.bool(forKey: Key.shortBreaksEnabled)
        sessionsBeforeLongBreak = store.integer(forKey: Key.sessionsBeforeLongBreak)
        soundEnabled = store.bool(forKey: Key.soundEnabled)
        blockAction = BlockAction(rawValue: store.string(forKey: Key.blockAction) ?? "") ?? .hide
        dailyGoal = store.integer(forKey: Key.dailyGoal)
        autoStartBreaks = store.bool(forKey: Key.autoStartBreaks)
        autoStartFocus = store.bool(forKey: Key.autoStartFocus)
        keepCountingAfterEnd = store.bool(forKey: Key.keepCountingAfterEnd)
        dayStartsAtHour = store.integer(forKey: Key.dayStartsAtHour)
        chime = Chime(rawValue: store.string(forKey: Key.chime) ?? "") ?? .bell
        breakChime = Chime(rawValue: store.string(forKey: Key.breakChime) ?? "") ?? .bowl
        chimeVolume = store.double(forKey: Key.chimeVolume)
        ticking = store.bool(forKey: Key.ticking)
        ambient = Ambient(rawValue: store.string(forKey: Key.ambient) ?? "") ?? .off
        ambientVolume = store.double(forKey: Key.ambientVolume)
        ambientDuringBreaks = store.bool(forKey: Key.ambientDuringBreaks)
        notifications = store.bool(forKey: Key.notifications)
        menuBarDisplay = MenuBarDisplay(rawValue: store.string(forKey: Key.menuBarDisplay) ?? "") ?? .iconAndTime
        menuBarSeconds = store.bool(forKey: Key.menuBarSeconds)
        menuBarIcon = MenuBarIconStyle(rawValue: store.string(forKey: Key.menuBarIcon) ?? "") ?? .ring
        globalHotKeys = store.bool(forKey: Key.globalHotKeys)
        hideDistractingApps = store.bool(forKey: Key.hideDistractingApps)
        blockedApps = store.stringArray(forKey: Key.blockedApps) ?? []
        breakCurtain = store.bool(forKey: Key.breakCurtain)
        pauseWhenLocked = store.bool(forKey: Key.pauseWhenLocked)
        focusStartShortcut = store.string(forKey: Key.focusStartShortcut) ?? ""
        focusEndShortcut = store.string(forKey: Key.focusEndShortcut) ?? ""
        liveActivity = store.bool(forKey: Key.liveActivity)
        keepScreenOn = store.bool(forKey: Key.keepScreenOn)
    }

    func minutes(for phase: Phase) -> Int {
        switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    func duration(for phase: Phase) -> TimeInterval { TimeInterval(minutes(for: phase) * 60) }

    func apply(_ preset: TimerPreset) {
        timerMode = .pomodoro
        focusMinutes = preset.focus
        if preset.shortBreak > 0 {
            shortBreakMinutes = preset.shortBreak
            shortBreaksEnabled = true
        } else {
            shortBreaksEnabled = false
        }
    }

    func isCurrent(_ preset: TimerPreset) -> Bool {
        guard timerMode == .pomodoro, focusMinutes == preset.focus else { return false }
        return preset.shortBreak == 0 ? !shortBreaksEnabled : (shortBreaksEnabled && shortBreakMinutes == preset.shortBreak)
    }

    /// Restores the timer section to the classic 25 / 5 / 15 × 4 rhythm.
    func resetTimerToDefaults() {
        timerMode = .pomodoro
        focusMinutes = 25
        shortBreakMinutes = 5
        longBreakMinutes = 15
        shortBreaksEnabled = true
        sessionsBeforeLongBreak = 4
        dailyGoal = 8
        autoStartBreaks = false
        autoStartFocus = false
        keepCountingAfterEnd = false
        dayStartsAtHour = 4
    }

    private enum Key {
        static let focusMinutes = "focusMinutes"
        static let shortBreakMinutes = "shortBreakMinutes"
        static let longBreakMinutes = "longBreakMinutes"
        static let sessionsBeforeLongBreak = "sessionsBeforeLongBreak"
        static let shortBreaksEnabled = "shortBreaksEnabled"
        static let timerMode = "timerMode"
        static let flowtimeBreakDivisor = "flowtimeBreakDivisor"
        static let presets = "presets"
        static let appearance = "appearance"
        static let showIntention = "showIntention"
        static let showCycleDots = "showCycleDots"
        static let showTodayProgress = "showTodayProgress"
        static let showWeekChart = "showWeekChart"
        static let askForReflection = "askForReflection"
        static let soundEnabled = "soundEnabled"
        static let blockAction = "blockAction"
        static let dailyGoal = "dailyGoal"
        static let autoStartBreaks = "autoStartBreaks"
        static let autoStartFocus = "autoStartFocus"
        static let keepCountingAfterEnd = "keepCountingAfterEnd"
        static let dayStartsAtHour = "dayStartsAtHour"
        static let chime = "chime"
        static let breakChime = "breakChime"
        static let chimeVolume = "chimeVolume"
        static let ticking = "ticking"
        static let ambient = "ambient"
        static let ambientVolume = "ambientVolume"
        static let ambientDuringBreaks = "ambientDuringBreaks"
        static let notifications = "notifications"
        static let menuBarDisplay = "menuBarDisplay"
        static let menuBarSeconds = "menuBarSeconds"
        static let menuBarIcon = "menuBarIcon"
        static let globalHotKeys = "globalHotKeys"
        static let hideDistractingApps = "hideDistractingApps"
        static let blockedApps = "blockedApps"
        static let breakCurtain = "breakCurtain"
        static let pauseWhenLocked = "pauseWhenLocked"
        static let focusStartShortcut = "focusStartShortcut"
        static let focusEndShortcut = "focusEndShortcut"
        static let liveActivity = "liveActivity"
        static let keepScreenOn = "keepScreenOn"
    }
}
