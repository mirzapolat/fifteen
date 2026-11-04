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

/// The ring's colors: crisp black and white, or a softly glowing rainbow.
enum RingTheme: String, CaseIterable, Identifiable {
    case mono, rainbow
    var id: Self { self }
    var title: String {
        switch self {
        case .mono: "Black & White"
        case .rainbow: "Rainbow"
        }
    }
}

/// The Mac app's icon: the bold "15" or a minimal ring, each in dark or light.
enum AppIconStyle: String, CaseIterable, Identifiable {
    case fifteenDark, fifteenLight, ringDark, ringLight
    var id: Self { self }
    var title: String {
        switch self {
        case .fifteenDark: "15 Dark"
        case .fifteenLight: "15 Light"
        case .ringDark: "Ring Dark"
        case .ringLight: "Ring Light"
        }
    }
    var isDark: Bool { self == .fifteenDark || self == .ringDark }
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
    /// A Flowtime session shorter than this is still recorded, but doesn't count toward the long break.
    var flowtimeMinimumMinutes: Int { didSet { store.set(flowtimeMinimumMinutes, forKey: Key.flowtimeMinimumMinutes) } }
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
    /// Minutes of focus per day / per week to aim for (0 = off).
    var dailyGoalMinutes: Int { didSet { store.set(dailyGoalMinutes, forKey: Key.dailyGoalMinutes) } }
    var weeklyGoalMinutes: Int { didSet { store.set(weeklyGoalMinutes, forKey: Key.weeklyGoalMinutes) } }
    /// Streaks are opt-in and only ever shown in Insights.
    var streaksEnabled: Bool { didSet { store.set(streaksEnabled, forKey: Key.streaksEnabled) } }
    /// A day counts only when the daily minutes goal is met (instead of any session).
    var streakNeedsGoal: Bool { didSet { store.set(streakNeedsGoal, forKey: Key.streakNeedsGoal) } }
    /// Weekdays (1 = Sunday … 7 = Saturday) that never break a streak.
    var streakRestDays: [Int] { didSet { store.set(streakRestDays, forKey: Key.streakRestDays) } }
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

    // Notifications & feedback
    var notifications: Bool { didSet { store.set(notifications, forKey: Key.notifications) } }
    var haptics: Bool { didSet { store.set(haptics, forKey: Key.haptics) } }

    // Display — what the timer shows
    var appearance: AppearanceMode { didSet { store.set(appearance.rawValue, forKey: Key.appearance) } }
    var ringTheme: RingTheme { didSet { store.set(ringTheme.rawValue, forKey: Key.ringTheme) } }
    var showIntention: Bool { didSet { store.set(showIntention, forKey: Key.showIntention) } }
    var showCycleDots: Bool { didSet { store.set(showCycleDots, forKey: Key.showCycleDots) } }
    var showWeekChart: Bool { didSet { store.set(showWeekChart, forKey: Key.showWeekChart) } }
    /// After focus: "What did you get done?" and a 1–5 focus rating.
    var askForReflection: Bool { didSet { store.set(askForReflection, forKey: Key.askForReflection) } }
    /// A comet swirls around the ring as a session starts (Pomodoro and Flowtime).
    var startSwirl: Bool { didSet { store.set(startSwirl, forKey: Key.startSwirl) } }

    // Mac
    var menuBarDisplay: MenuBarDisplay { didSet { store.set(menuBarDisplay.rawValue, forKey: Key.menuBarDisplay) } }
    var menuBarSeconds: Bool { didSet { store.set(menuBarSeconds, forKey: Key.menuBarSeconds) } }
    var menuBarIcon: MenuBarIconStyle { didSet { store.set(menuBarIcon.rawValue, forKey: Key.menuBarIcon) } }
    var appIcon: AppIconStyle { didSet { store.set(appIcon.rawValue, forKey: Key.appIcon) } }
    /// Mac: open the timer bubble when a session ends.
    var openWhenDone: Bool { didSet { store.set(openWhenDone, forKey: Key.openWhenDone) } }
    /// Mac, Link: a notification when someone else in the group changes the timer.
    var linkNotifications: Bool { didSet { store.set(linkNotifications, forKey: Key.linkNotifications) } }
    var globalHotKeys: Bool { didSet { store.set(globalHotKeys, forKey: Key.globalHotKeys) } }
    var hideDistractingApps: Bool { didSet { store.set(hideDistractingApps, forKey: Key.hideDistractingApps) } }
    var blockedApps: [String] { didSet { store.set(blockedApps, forKey: Key.blockedApps) } }
    var blockAction: BlockAction { didSet { store.set(blockAction.rawValue, forKey: Key.blockAction) } }
    var breakCurtain: Bool { didSet { store.set(breakCurtain, forKey: Key.breakCurtain) } }
    /// Mac: switch on Do Not Disturb during focus (via two shortcuts).
    var doNotDisturb: Bool { didSet { store.set(doNotDisturb, forKey: Key.doNotDisturb) } }
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
            Key.flowtimeMinimumMinutes: 1,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.ringTheme: RingTheme.mono.rawValue,
            Key.showIntention: true,
            Key.showCycleDots: true,
            Key.startSwirl: true,
            Key.showWeekChart: true,
            Key.askForReflection: true,
            Key.shortBreaksEnabled: true,
            Key.sessionsBeforeLongBreak: 4,
            Key.soundEnabled: true,
            Key.blockAction: BlockAction.hide.rawValue,
            Key.dailyGoal: 8,
            Key.dailyGoalMinutes: 0,
            Key.weeklyGoalMinutes: 0,
            Key.streaksEnabled: true,
            Key.streakNeedsGoal: false,
            Key.streakRestDays: [Int](),
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
            Key.haptics: true,
            Key.menuBarDisplay: MenuBarDisplay.time.rawValue,
            Key.menuBarSeconds: true,
            Key.menuBarIcon: MenuBarIconStyle.ring.rawValue,
            Key.appIcon: AppIconStyle.fifteenDark.rawValue,
            Key.openWhenDone: true,
            Key.linkNotifications: true,
            Key.globalHotKeys: true,
            Key.hideDistractingApps: false,
            Key.blockedApps: [String](),
            Key.breakCurtain: false,
            Key.doNotDisturb: false,
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
        flowtimeMinimumMinutes = store.integer(forKey: Key.flowtimeMinimumMinutes)
        presets = store.data(forKey: Key.presets).flatMap { try? JSONDecoder().decode([TimerPreset].self, from: $0) }
            ?? TimerPreset.defaults
        appearance = AppearanceMode(rawValue: store.string(forKey: Key.appearance) ?? "") ?? .system
        ringTheme = RingTheme(rawValue: store.string(forKey: Key.ringTheme) ?? "") ?? .mono
        showIntention = store.bool(forKey: Key.showIntention)
        showCycleDots = store.bool(forKey: Key.showCycleDots)
        startSwirl = store.bool(forKey: Key.startSwirl)
        showWeekChart = store.bool(forKey: Key.showWeekChart)
        askForReflection = store.bool(forKey: Key.askForReflection)
        shortBreaksEnabled = store.bool(forKey: Key.shortBreaksEnabled)
        sessionsBeforeLongBreak = store.integer(forKey: Key.sessionsBeforeLongBreak)
        soundEnabled = store.bool(forKey: Key.soundEnabled)
        blockAction = BlockAction(rawValue: store.string(forKey: Key.blockAction) ?? "") ?? .hide
        dailyGoal = store.integer(forKey: Key.dailyGoal)
        dailyGoalMinutes = store.integer(forKey: Key.dailyGoalMinutes)
        weeklyGoalMinutes = store.integer(forKey: Key.weeklyGoalMinutes)
        streaksEnabled = store.bool(forKey: Key.streaksEnabled)
        streakNeedsGoal = store.bool(forKey: Key.streakNeedsGoal)
        streakRestDays = (store.array(forKey: Key.streakRestDays) as? [Int]) ?? []
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
        haptics = store.bool(forKey: Key.haptics)
        menuBarDisplay = MenuBarDisplay(rawValue: store.string(forKey: Key.menuBarDisplay) ?? "") ?? .time
        menuBarSeconds = store.bool(forKey: Key.menuBarSeconds)
        menuBarIcon = MenuBarIconStyle(rawValue: store.string(forKey: Key.menuBarIcon) ?? "") ?? .ring
        appIcon = AppIconStyle(rawValue: store.string(forKey: Key.appIcon) ?? "") ?? .fifteenDark
        openWhenDone = store.bool(forKey: Key.openWhenDone)
        linkNotifications = store.bool(forKey: Key.linkNotifications)
        globalHotKeys = store.bool(forKey: Key.globalHotKeys)
        hideDistractingApps = store.bool(forKey: Key.hideDistractingApps)
        blockedApps = store.stringArray(forKey: Key.blockedApps) ?? []
        breakCurtain = store.bool(forKey: Key.breakCurtain)
        doNotDisturb = store.bool(forKey: Key.doNotDisturb)
        pauseWhenLocked = store.bool(forKey: Key.pauseWhenLocked)
        focusStartShortcut = store.string(forKey: Key.focusStartShortcut) ?? ""
        focusEndShortcut = store.string(forKey: Key.focusEndShortcut) ?? ""
        liveActivity = store.bool(forKey: Key.liveActivity)
        keepScreenOn = store.bool(forKey: Key.keepScreenOn)
    }

    /// Every setting back to how Fifteen ships. History, projects and Link membership are untouched.
    func resetToFactoryDefaults() {
        for key in Self.allKeys { store.removeObject(forKey: key) }
        // Read everything back; with the stored values gone, these are the registered defaults.
        focusMinutes = store.integer(forKey: Key.focusMinutes)
        shortBreakMinutes = store.integer(forKey: Key.shortBreakMinutes)
        longBreakMinutes = store.integer(forKey: Key.longBreakMinutes)
        timerMode = TimerMode(rawValue: store.string(forKey: Key.timerMode) ?? "") ?? .pomodoro
        flowtimeBreakDivisor = store.integer(forKey: Key.flowtimeBreakDivisor)
        flowtimeMinimumMinutes = store.integer(forKey: Key.flowtimeMinimumMinutes)
        presets = store.data(forKey: Key.presets).flatMap { try? JSONDecoder().decode([TimerPreset].self, from: $0) }
            ?? TimerPreset.defaults
        appearance = AppearanceMode(rawValue: store.string(forKey: Key.appearance) ?? "") ?? .system
        ringTheme = RingTheme(rawValue: store.string(forKey: Key.ringTheme) ?? "") ?? .mono
        showIntention = store.bool(forKey: Key.showIntention)
        showCycleDots = store.bool(forKey: Key.showCycleDots)
        startSwirl = store.bool(forKey: Key.startSwirl)
        showWeekChart = store.bool(forKey: Key.showWeekChart)
        askForReflection = store.bool(forKey: Key.askForReflection)
        shortBreaksEnabled = store.bool(forKey: Key.shortBreaksEnabled)
        sessionsBeforeLongBreak = store.integer(forKey: Key.sessionsBeforeLongBreak)
        soundEnabled = store.bool(forKey: Key.soundEnabled)
        blockAction = BlockAction(rawValue: store.string(forKey: Key.blockAction) ?? "") ?? .hide
        dailyGoal = store.integer(forKey: Key.dailyGoal)
        dailyGoalMinutes = store.integer(forKey: Key.dailyGoalMinutes)
        weeklyGoalMinutes = store.integer(forKey: Key.weeklyGoalMinutes)
        streaksEnabled = store.bool(forKey: Key.streaksEnabled)
        streakNeedsGoal = store.bool(forKey: Key.streakNeedsGoal)
        streakRestDays = (store.array(forKey: Key.streakRestDays) as? [Int]) ?? []
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
        haptics = store.bool(forKey: Key.haptics)
        menuBarDisplay = MenuBarDisplay(rawValue: store.string(forKey: Key.menuBarDisplay) ?? "") ?? .time
        menuBarSeconds = store.bool(forKey: Key.menuBarSeconds)
        menuBarIcon = MenuBarIconStyle(rawValue: store.string(forKey: Key.menuBarIcon) ?? "") ?? .ring
        appIcon = AppIconStyle(rawValue: store.string(forKey: Key.appIcon) ?? "") ?? .fifteenDark
        openWhenDone = store.bool(forKey: Key.openWhenDone)
        linkNotifications = store.bool(forKey: Key.linkNotifications)
        globalHotKeys = store.bool(forKey: Key.globalHotKeys)
        hideDistractingApps = store.bool(forKey: Key.hideDistractingApps)
        blockedApps = store.stringArray(forKey: Key.blockedApps) ?? []
        breakCurtain = store.bool(forKey: Key.breakCurtain)
        doNotDisturb = store.bool(forKey: Key.doNotDisturb)
        pauseWhenLocked = store.bool(forKey: Key.pauseWhenLocked)
        focusStartShortcut = store.string(forKey: Key.focusStartShortcut) ?? ""
        focusEndShortcut = store.string(forKey: Key.focusEndShortcut) ?? ""
        liveActivity = store.bool(forKey: Key.liveActivity)
        keepScreenOn = store.bool(forKey: Key.keepScreenOn)
    }

    private static let allKeys = [
        Key.focusMinutes,
        Key.shortBreakMinutes,
        Key.longBreakMinutes,
        Key.sessionsBeforeLongBreak,
        Key.shortBreaksEnabled,
        Key.timerMode,
        Key.flowtimeBreakDivisor,
        Key.flowtimeMinimumMinutes,
        Key.presets,
        Key.appearance,
        Key.ringTheme,
        Key.showIntention,
        Key.showCycleDots,
        Key.startSwirl,
        Key.showWeekChart,
        Key.askForReflection,
        Key.soundEnabled,
        Key.blockAction,
        Key.dailyGoal,
        Key.dailyGoalMinutes,
        Key.weeklyGoalMinutes,
        Key.streaksEnabled,
        Key.streakNeedsGoal,
        Key.streakRestDays,
        Key.autoStartBreaks,
        Key.autoStartFocus,
        Key.keepCountingAfterEnd,
        Key.dayStartsAtHour,
        Key.chime,
        Key.breakChime,
        Key.chimeVolume,
        Key.ticking,
        Key.ambient,
        Key.ambientVolume,
        Key.ambientDuringBreaks,
        Key.notifications,
        Key.haptics,
        Key.menuBarDisplay,
        Key.menuBarSeconds,
        Key.menuBarIcon,
        Key.appIcon,
        Key.openWhenDone,
        Key.linkNotifications,
        Key.globalHotKeys,
        Key.hideDistractingApps,
        Key.blockedApps,
        Key.breakCurtain,
        Key.doNotDisturb,
        Key.pauseWhenLocked,
        Key.focusStartShortcut,
        Key.focusEndShortcut,
        Key.liveActivity,
        Key.keepScreenOn,
    ]

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
        static let flowtimeMinimumMinutes = "flowtimeMinimumMinutes"
        static let presets = "presets"
        static let appearance = "appearance"
        static let ringTheme = "ringTheme"
        static let showIntention = "showIntention"
        static let showCycleDots = "showCycleDots"
        static let startSwirl = "startSwirl"
        static let showWeekChart = "showWeekChart"
        static let askForReflection = "askForReflection"
        static let soundEnabled = "soundEnabled"
        static let blockAction = "blockAction"
        static let dailyGoal = "dailyGoal"
        static let dailyGoalMinutes = "dailyGoalMinutes"
        static let weeklyGoalMinutes = "weeklyGoalMinutes"
        static let streaksEnabled = "streaksEnabled"
        static let streakNeedsGoal = "streakNeedsGoal"
        static let streakRestDays = "streakRestDays"
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
        static let haptics = "haptics"
        static let menuBarDisplay = "menuBarDisplay"
        static let menuBarSeconds = "menuBarSeconds"
        static let menuBarIcon = "menuBarIcon"
        static let appIcon = "appIcon"
        static let openWhenDone = "openWhenDone"
        static let linkNotifications = "linkNotifications"
        static let globalHotKeys = "globalHotKeys"
        static let hideDistractingApps = "hideDistractingApps"
        static let blockedApps = "blockedApps"
        static let breakCurtain = "breakCurtain"
        static let doNotDisturb = "doNotDisturb"
        static let pauseWhenLocked = "pauseWhenLocked"
        static let focusStartShortcut = "focusStartShortcut"
        static let focusEndShortcut = "focusEndShortcut"
        static let liveActivity = "liveActivity"
        static let keepScreenOn = "keepScreenOn"
    }
}


extension Preferences {
    /// The streak rule from settings.
    var streakRule: StreakRule {
        StreakRule(minimumMinutes: streakNeedsGoal ? Double(dailyGoalMinutes) : 0, restWeekdays: Set(streakRestDays))
    }
}
