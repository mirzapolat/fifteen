import SwiftUI

/// The row under the ring:  [length]  ·····  [reset] [history] […]
/// The ring itself starts and pauses. When a session ends, the length pill grows into a tinted
/// "Take a Break" (or "Back to Focus") so moving on is one click.
struct ControlPills: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.appActions) private var actions
    @Environment(\.colorScheme) private var scheme
    @Namespace private var glass

    var body: some View {
        // Less than the gap between pills, so each stays its own drop of glass instead of melting
        // into its neighbour; glassID still morphs pills in and out (macOS 26+).
        GlassGroup(spacing: 2) {
            // Left: this session (length, project/intention, reset) — it changes as the session does.
            // Right: the app (Insights, •••) — fixed in the corner, never shifting.
            HStack(spacing: Pill.spacing) {
                if engine.state == .finished {
                    nextPill
                        .glassID("leading", in: glass)
                } else {
                    lengthPill
                        .glassID("leading", in: glass)
                }
                if showsDetailsPill {
                    detailsPill
                        .glassID("details", in: glass)
                }
                // Reset morphs in only when there's something to reset; last in its group, away
                // from the main pill, so it isn't hit by accident.
                if engine.state != .idle {
                    resetPill
                        .glassID("reset", in: glass)
                }
                if engine.state != .finished {
                    Spacer(minLength: 0)
                }
                if prefs.insightsEnabled {
                    historyPill
                        .glassID("history", in: glass)
                }
                morePill
                    .glassID("more", in: glass)
            }
        }
        .animation(Pill.morph, value: engine.state)
        .animation(Pill.morph, value: engine.phase)
    }

    // MARK: Leading — length, or move on

    private var nextPill: some View {
        Button {
            engine.advance(autoStart: true)
        } label: {
            Label(nextTitle, systemImage: nextSymbol)
                .fixedSize()
                .frame(maxWidth: .infinity)
                .pill(prominent: true)
        }
        .buttonStyle(.plain)
        .help(nextTitle)
    }

    private var continuesFocus: Bool { engine.phase == .focus && engine.nextPhase == .focus }
    private var nextTitle: String { continuesFocus ? "Next Session" : engine.nextPhase.startTitle }
    private var nextSymbol: String { continuesFocus ? "play.fill" : engine.nextPhase.symbol }

    @ViewBuilder
    private var lengthPill: some View {
        if engine.isFlowtime && engine.isActive {
            // Flowtime has no end: this pill is how you stop when your focus fades.
            Button { engine.finishEarly() } label: {
                Label("Finish", systemImage: "checkmark").fixedSize().pill()
            }
            .buttonStyle(.plain)
            .help("End this session and take your break")
        } else {
            lengthMenu
        }
    }

    /// Idle: pick a length (or a preset, or the mode). Running: add time.
    private var lengthMenu: some View {
        Menu {
            if engine.state == .idle {
                if !engine.isFlowtime {
                    Picker("Length", selection: Binding(
                        get: { Int(engine.total / 60) },
                        set: { engine.setIdleMinutes($0) }
                    )) {
                        ForEach(lengths, id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                if !prefs.presets.isEmpty {
                    Menu("Presets") {
                        ForEach(prefs.presets) { preset in
                            Toggle(isOn: Binding(get: { prefs.isCurrent(preset) },
                                                 set: { _ in apply(preset) })) {
                                Text(presetLabel(preset))
                            }
                        }
                    }
                }
                Divider()
                // Only two modes, so one item flips between them.
                Button(prefs.isFlowtime ? "Switch to Pomodoro" : "Switch to Flowtime",
                       systemImage: prefs.isFlowtime ? "timer" : "infinity") {
                    prefs.timerMode = prefs.isFlowtime ? .pomodoro : .flowtime
                    engine.reloadIdle()
                }
            } else {
                Section("Add Time") {
                    Button("1 Minute", systemImage: "plus") { engine.extend(by: 60) }
                    Button("5 Minutes", systemImage: "plus") { engine.extend(by: 300) }
                    Button("10 Minutes", systemImage: "plus") { engine.extend(by: 600) }
                }
            }
        } label: {
            Label(lengthTitle, systemImage: lengthSymbol)
                .monospacedDigit()
                .fixedSize()
                .pill()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(engine.state == .idle ? "Length, presets and mode" : "Add time")
    }

    /// Common lengths, plus the current one if it's something else (e.g. set by dragging the ring).
    private var lengths: [Int] {
        let presets = [10, 15, 20, 25, 30, 45, 50, 60, 90]
        let current = Int(engine.total / 60)
        return presets.contains(current) ? presets : (presets + [current]).sorted()
    }

    private func presetLabel(_ preset: TimerPreset) -> String {
        preset.shortBreak == 0
            ? "\(preset.name) — \(preset.focus) min, no breaks"
            : "\(preset.name) — \(preset.focus) min focus, \(preset.shortBreak) min break"
    }

    private var lengthTitle: String {
        if engine.state != .idle { return "Time" }
        return engine.isFlowtime ? "Flow" : "\(Int(engine.total / 60)) min"
    }

    private var lengthSymbol: String {
        if engine.state != .idle { return "plus" }
        return engine.isFlowtime ? "infinity" : "timer"
    }

    private func apply(_ preset: TimerPreset) {
        prefs.apply(preset)
        engine.reloadIdle()
    }

    // MARK: Trailing — reset, history, more

    private var resetPill: some View {
        Button { engine.reset() } label: {
            Image(systemName: "arrow.counterclockwise")
                .frame(width: Pill.height)
                .pill(square: true)
        }
        .buttonStyle(.plain)
        .help("Reset this session")
        .accessibilityLabel("Reset")
    }

    /// Hidden in breaks, and after a session, when the "What did you get done?" note takes the field's place.
    private var showsDetailsPill: Bool {
        (prefs.showIntention || prefs.projectsActive) && !engine.phase.isBreak && engine.state != .finished
    }

    private var historyPill: some View {
        Button { actions.showHistory() } label: {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .frame(width: Pill.height)
                .pill(square: true)
        }
        .buttonStyle(.plain)
        .help("Insights")
        .accessibilityLabel("Insights")
    }

    /// Reveals the project and "one thing" field. Solid while it's open; the icon is filled when
    /// a project or intention is set, so you know there's something behind it.
    private var detailsPill: some View {
        let chrome = TimerChrome.shared
        let hasDetails = !engine.intention.isEmpty || engine.projectID != nil
        return Button {
            withAnimation(Pill.morph) { chrome.detailsShown.toggle() }
        } label: {
            Image(systemName: hasDetails ? "text.bubble.fill" : "text.bubble")
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Pill.height)
                .pill(prominent: chrome.detailsShown, square: true)
        }
        .buttonStyle(.plain)
        .help(chrome.detailsShown ? "Hide project and intention" : "Project and intention")
        .accessibilityLabel("Project and intention")
        .accessibilityAddTraits(chrome.detailsShown ? .isSelected : [])
    }

    /// Only what isn't already one click away elsewhere.
    private var morePill: some View {
        Menu {
            Section {
                if engine.phase == .focus && engine.isActive {
                    if !engine.isFlowtime {
                        Button("Finish Early", systemImage: "checkmark.circle") { engine.finishEarly() }
                    }
                    Button("Log a Distraction", systemImage: "exclamationmark.bubble") { engine.logDistraction() }
                }
                Button(skipTitle, systemImage: "forward.end") { engine.skip() }
            }
            Section {
                Button("Settings…", systemImage: "gearshape") { actions.showSettings() }
                if let quit = actions.quit {
                    Button("Quit Fifteen", systemImage: "power") { quit() }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: Pill.height)
                .pill(square: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private var skipTitle: String {
        if engine.phase.isBreak { return "Skip Break" }
        return engine.nextPhase.isBreak ? "Skip to Break" : "Skip Session"
    }
}
