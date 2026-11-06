import SwiftUI

@main
struct FifteeniOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Notifier.shared.setUp()
        // Tapping a session banner brings you to the timer; a Link banner to your group.
        Notifier.shared.openTimer = { AppRouter.shared.showTimer() }
        Notifier.shared.openLink = { AppRouter.shared.showLink() }
        LiveActivityController.shared.start()
        LinkSession.shared.start()
        FifteenShortcuts.updateAppShortcutParameters()
        // `--start` starts a session right away (for screenshots of the running timer).
        if CommandLine.arguments.contains("--start") { TimerEngine.shared.start() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(TimerEngine.shared)
                .environment(Preferences.shared)
                .environment(HistoryStore.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                TimerEngine.shared.refresh()
                Notifier.shared.clearDelivered()
            }
        }
    }
}

enum AppTab: Hashable {
    case timer, sessions, settings
}

/// Which tab is showing, and whether the Link sheet is up, so any view can switch.
@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()
    var tab: AppTab = AppRouter.launchTab
    /// The Link sheet, opened from the top right of the timer.
    var linkShown = CommandLine.arguments.contains("--link")
    /// Projects, opened from the top left of Sessions (or "Manage Projects…" on the timer).
    /// `--tab sessions --projects` opens it at launch (for screenshots).
    var projectsShown = CommandLine.arguments.contains("--projects")
    /// Sessions should push Insights next time it can (`--tab insights` does this at launch).
    var insightsRequested = AppRouter.launchArgument == "insights" || AppRouter.launchArgument == "analytics"

    func showTimer() {
        tab = .timer
    }

    func showLink() {
        guard Preferences.shared.linkEnabled else { return showTimer() }
        tab = .timer
        linkShown = true
    }

    func showInsights() {
        guard Preferences.shared.insightsEnabled else { return }
        linkShown = false
        tab = .sessions
        insightsRequested = true
    }

    func showProjects() {
        guard Preferences.shared.projectsActive else { return }
        linkShown = false
        tab = .sessions
        projectsShown = true
    }

    /// `--tab timer|sessions|insights|settings` picks the first tab; insights opens on top of
    /// Sessions (`--link` opens the Link sheet).
    private static var launchArgument: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--tab"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    private static var launchTab: AppTab {
        switch launchArgument {
        case "sessions", "history", "analytics", "insights": .sessions
        case "settings": .settings
        default: .timer
        }
    }
}

/// Three tabs on a Liquid Glass bar: Timer (where the app opens), Sessions and Settings.
/// Insights opens from This Week in Sessions; Link lives on the timer itself, top right,
/// the way the Mac's bubble has it.
struct RootView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarded") private var onboarded = false
    @Bindable private var router = AppRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Timer", systemImage: "timer", value: AppTab.timer) {
                TimerTab()
            }
            Tab("Sessions", systemImage: "clock.arrow.circlepath", value: AppTab.sessions) {
                SessionsTab()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                IOSSettingsView()
            }
        }
        // While a session is on, scrolling down shrinks the bar so the running timer above it
        // gets the room; otherwise there's nothing to make room for, so the bar stays put.
        .tabBarMinimizeBehavior(engine.state == .idle ? .never : .onScrollDown)
        // Away from the Timer tab, a running session rides along just above the bar.
        .modifier(RunningTimerAccessory(enabled: router.tab != .timer && engine.state != .idle))
        // Someone in your group changed the timer while you're on another tab.
        .overlay(alignment: .top) { LinkBanner(visible: router.tab != .timer) }
        .sheet(isPresented: $router.linkShown) {
            LinkSheet()
        }
        .background { BreakCoverHost() }
        .environment(\.appActions, AppActions(
            showInsights: { section in
                switch section {
                case .projects: router.showProjects()
                case .sessions:
                    router.linkShown = false
                    router.tab = .sessions
                default: router.showInsights()
                }
            },
            showSettings: { router.tab = .settings }
        ))
        .fullScreenCover(isPresented: .constant(!onboarded)) {
            OnboardingView { onboarded = true }
        }
        .onChange(of: engine.state, initial: true) { updateIdleTimer() }
        .onChange(of: prefs.keepScreenOn) { updateIdleTimer() }
        .onChange(of: router.tab, initial: true) { updateVisibility() }
        // Link can't stay open once it's switched off.
        .onChange(of: prefs.linkEnabled, initial: true) { if !prefs.linkEnabled { router.linkShown = false } }
        .onChange(of: scenePhase, initial: true) { updateVisibility() }
        .preferredColorScheme(prefs.appearance.colorScheme)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn && engine.state == .running
    }

    /// On the Timer tab (and in the Link sheet over it), a Link change shows under the ring or on
    /// the group's card, so no banner is needed.
    private func updateVisibility() {
        let active = scenePhase == .active
        LinkChrome.shared.appActive = active
        LinkChrome.shared.timerVisible = active && router.tab == .timer
    }
}

/// The timer, filling the screen: the phase and Link on top, the ring, then the intention and the
/// controls underneath, as glass pills. The same order as the Mac's bubble.
struct TimerTab: View {
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height * 1.15
            if landscape {
                // Ring on the left; header, caption and controls in a column on the right.
                let dial = min(geo.size.height * 0.82, geo.size.width * 0.5, 600)
                HStack(spacing: 48) {
                    DialView(lineWidth: dial > 380 ? 9 : 7)
                        .frame(width: dial, height: dial)
                    VStack(spacing: 0) {
                        PhaseHeader()
                        Spacer(minLength: 16)
                        TouchIntentionField()
                        TouchControlPills()
                    }
                    .frame(maxWidth: 400)
                    .padding(.vertical, 16)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // One column; header, caption and controls share its width so their edges line up.
                let column = min(geo.size.width - 32, 520)
                let dial = min(geo.size.width - 56, geo.size.height * 0.52, 560)
                VStack(spacing: 0) {
                    PhaseHeader()
                        .frame(width: column)
                        .padding(.top, 8)
                    Spacer(minLength: 16)
                    DialView(lineWidth: dial > 380 ? 9 : 7)
                        .frame(width: dial, height: dial)
                    Spacer(minLength: 16)
                    VStack(spacing: 0) {
                        TouchIntentionField()
                        TouchControlPills()
                    }
                    .frame(width: column)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .persistentSystemOverlays(engine.state == .running ? .hidden : .automatic)
    }
}

/// The header's right side on iPhone and iPad: Link, the way the Mac has it.
struct TimerHeaderTrailing: View {
    var body: some View {
        if Preferences.shared.linkEnabled { LinkHeaderButton() }
    }
}

// MARK: - Running timer above the tab bar

/// The session in a glass strip above the tab bar while you're on another tab.
/// iOS 26.0 can't hide an accessory, so there it stays off rather than showing an empty strip.
private struct RunningTimerAccessory: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled) { MiniTimer() }
        } else {
            content
        }
    }
}

/// Ring, phase, time left, and play/pause. Tap anywhere else to go back to the timer.
/// When the tab bar shrinks while scrolling, it squeezes down to the ring, time and button.
private struct MiniTimer: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        let inline = placement == .inline
        HStack(spacing: 12) {
            ProgressRing(progress: TimerProgress.fraction(engine), lineWidth: 3)
                .frame(width: 22, height: 22)
            if !inline {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(TimerProgress.clock(engine))
                .font(.body.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: !engine.isFlowtime))
            Button { engine.primaryAction() } label: {
                Image(systemName: actionSymbol)
                    .font(.body.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionLabel)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .onTapGesture { AppRouter.shared.tab = .timer }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Show Timer") { AppRouter.shared.tab = .timer }
    }

    private var title: String {
        switch engine.state {
        case .finished: engine.phase == .focus ? "Session complete" : "Break's over"
        case .paused: "Paused"
        default: engine.isFlowtime ? "Flowtime" : engine.phase.title
        }
    }

    /// What it's for, or who it's with.
    private var detail: String? {
        if engine.state == .finished { return engine.nextPhase.startTitle }
        if !engine.intention.isEmpty && engine.phase == .focus { return engine.intention }
        let others = LinkSession.shared.others.count
        if LinkSession.shared.isLinked && others > 0 { return "With \(others) other\(others == 1 ? "" : "s")" }
        return nil
    }

    private var actionSymbol: String {
        switch engine.state {
        case .running: "pause.fill"
        case .finished: "forward.fill"
        default: "play.fill"
        }
    }

    private var actionLabel: String {
        switch engine.state {
        case .running: "Pause"
        case .finished: engine.nextPhase.startTitle
        default: "Resume"
        }
    }
}

/// A small version of the dial: what's left of the session, in ink.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 3
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().stroke(Color.ink(scheme).opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.ink(scheme), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.linear(duration: 0.3), value: progress)
        .accessibilityHidden(true)
    }
}

/// The numbers the small rings and clocks show, the same way the big dial does.
@MainActor
enum TimerProgress {
    /// The ring empties as time passes; Flowtime fills it once an hour.
    static func fraction(_ engine: TimerEngine) -> Double {
        if engine.isFlowtime && engine.state != .idle {
            return engine.elapsed.truncatingRemainder(dividingBy: 3600) / 3600
        }
        switch engine.state {
        case .idle: return 1
        case .finished: return 0
        case .running, .paused: return 1 - engine.progress(at: engine.now)
        }
    }

    static func clock(_ engine: TimerEngine) -> String {
        if engine.state == .finished {
            return engine.isCountingOvertime ? "+" + TimeFormat.clock(engine.overtime) : "Done"
        }
        return TimeFormat.clock(engine.isFlowtime ? engine.elapsed : engine.remaining)
    }
}

// MARK: - Onboarding

/// One screen, shown once: what Fifteen is, and where everything lives.
struct OnboardingView: View {
    var done: () -> Void
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: appeared ? 0.78 : 0)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 128, height: 128)
                .animation(.spring(duration: 1.4, bounce: 0.2).delay(0.2), value: appeared)
                .padding(.top, 40)

                VStack(spacing: 10) {
                    Text("One timer. One thing.")
                        .font(.largeTitle.weight(.semibold))
                    Text("Focus for 25 minutes, then rest for 5. After four rounds, take a longer break.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 16) {
                    row("hand.draw", "Drag around the ring to set the time. Tap it to start or pause.")
                    row("lock", "The countdown follows you to the Lock Screen and the Dynamic Island.")
                    row("clock.arrow.circlepath", "Every session lands in Sessions, with what you did and how it went.")
                    row("laptopcomputer.and.iphone", "Tap Link at the top right to focus together with friends.")
                    row("bell", "Fifteen lets you know when it's time for a break, even when it's closed.")
                }
                .font(.callout)
                .frame(maxWidth: 420, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button {
                Notifier.shared.requestAuthorizationIfNeeded()
                done()
            } label: {
                Text("Begin").frame(maxWidth: .infinity).pill(prominent: true)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .onAppear { appeared = true }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .frame(width: 24)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
