import SwiftUI

@main
struct FifteeniOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Notifier.shared.setUp()
        // Tapping a Link banner brings you to the timer it's about.
        Notifier.shared.openTimer = { AppRouter.shared.tab = .timer }
        LiveActivityController.shared.start()
        LinkSession.shared.start()
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
            if phase == .active { TimerEngine.shared.refresh() }
        }
    }
}

enum AppTab: Hashable {
    case link, timer, analytics, settings
}

/// Which tab is showing, so any view can switch tabs.
@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()
    var tab: AppTab = AppRouter.launchTab

    /// `--tab link|timer|analytics|settings` picks the first tab; Timer otherwise.
    private static var launchTab: AppTab {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--tab"), args.indices.contains(i + 1) else { return .timer }
        return switch args[i + 1] {
        case "link": .link
        case "analytics", "insights": .analytics
        case "settings": .settings
        default: .timer
        }
    }
}

/// Four tabs on a Liquid Glass bar: Link, Timer (where the app opens), Analytics and Settings.
struct RootView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarded") private var onboarded = false
    @Bindable private var router = AppRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            if prefs.linkEnabled {
                Tab("Link", systemImage: "person.2", value: AppTab.link) {
                    LinkTab()
                }
            }
            Tab("Timer", systemImage: "timer", value: AppTab.timer) {
                TimerTab()
            }
            if prefs.insightsEnabled {
                Tab("Analytics", systemImage: "chart.bar", value: AppTab.analytics) {
                    InsightsView(stacked: true)
                }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                IOSSettingsView()
            }
        }
        // Long Insights pages get the room back; the bar returns as you scroll up.
        .tabBarMinimizeBehavior(.onScrollDown)
        // Away from the Timer tab, a running session rides along just above the bar.
        .modifier(RunningTimerAccessory(enabled: router.tab != .timer && engine.state != .idle))
        .environment(\.appActions, AppActions(
            showInsights: { section in
                guard prefs.insightsEnabled else { return }
                InsightsRoute.shared.jump = section
                router.tab = .analytics
            },
            showSettings: { router.tab = .settings }
        ))
        .fullScreenCover(isPresented: .constant(!onboarded)) {
            OnboardingView { onboarded = true }
        }
        .onChange(of: engine.state, initial: true) { updateIdleTimer() }
        .onChange(of: prefs.keepScreenOn) { updateIdleTimer() }
        .onChange(of: router.tab, initial: true) { updateTimerVisible() }
        // A tab that's been switched off can't stay selected.
        .onChange(of: prefs.linkEnabled, initial: true) { if !prefs.linkEnabled && router.tab == .link { router.tab = .timer } }
        .onChange(of: prefs.insightsEnabled, initial: true) {
            if !prefs.insightsEnabled && router.tab == .analytics { router.tab = .timer }
        }
        .onChange(of: scenePhase) { updateTimerVisible() }
        .preferredColorScheme(prefs.appearance.colorScheme)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn && engine.state == .running
    }

    /// On the Timer tab, a Link change shows under the ring, so no banner is needed.
    private func updateTimerVisible() {
        LinkChrome.shared.timerVisible = scenePhase == .active && router.tab == .timer
    }
}

/// The timer, filling the screen. Controls float at the bottom as glass pills, above the tab bar.
struct TimerTab: View {
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height * 1.15
            if landscape {
                // Ring on the left; header, caption and controls in a column on the right.
                let dial = min(geo.size.height * 0.8, geo.size.width * 0.5, 600)
                HStack(spacing: 48) {
                    DialView(lineWidth: dial > 380 ? 9 : 7)
                        .frame(width: dial, height: dial)
                    VStack(spacing: 20) {
                        PhaseHeader()
                        Spacer(minLength: 0)
                        TouchIntentionField()
                    }
                    .frame(maxWidth: 400)
                    .padding(.vertical, 16)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // One column; header, caption and controls share its width so their edges line up.
                let column = min(geo.size.width - 32, 520)
                let dial = min(geo.size.width - 56, geo.size.height * 0.56, 560)
                VStack(spacing: 0) {
                    PhaseHeader()
                        .frame(width: column)
                        .padding(.top, 8)
                    Spacer(minLength: 16)
                    DialView(lineWidth: dial > 380 ? 9 : 7)
                        .frame(width: dial, height: dial)
                    Spacer(minLength: 16)
                    TouchIntentionField()
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

/// The header's right side on iPhone and iPad: the timer's controls (length, or Add Time and Reset).
struct TimerHeaderTrailing: View {
    var body: some View {
        TouchControlPills()
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

/// One screen, shown once.
struct OnboardingView: View {
    var done: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: appeared ? 0.78 : 0)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 140, height: 140)
            .animation(.spring(duration: 1.4, bounce: 0.2).delay(0.2), value: appeared)

            VStack(spacing: 10) {
                Text("One timer. One thing.")
                    .font(.largeTitle.weight(.semibold))
                Text("Focus for 25 minutes, then rest for 5. After four rounds, take a longer break.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                Label("Drag around the ring to set the time.", systemImage: "hand.draw")
                Label("Tap the ring to start or pause.", systemImage: "hand.tap")
                Label("Your countdown follows you to the Lock Screen.", systemImage: "lock")
                Label("Focus together with friends in Link.", systemImage: "person.2")
            }
            .font(.callout)
            Spacer()
            Button {
                Notifier.shared.requestAuthorizationIfNeeded()
                done()
            } label: {
                Text("Begin").frame(maxWidth: .infinity).pill(prominent: true)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .onAppear { appeared = true }
    }
}
