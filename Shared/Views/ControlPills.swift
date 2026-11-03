import SwiftUI

/// Duration · Start/Pause · "…" — three glass pills that morph into each other.
/// At the end of a session the duration pill melts away and Start grows into a tinted "Take a Break".
struct ControlPills: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.appActions) private var actions
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: Pill.spacing) {
            HStack(spacing: Pill.spacing) {
                if engine.state != .finished {
                    durationPill
                        .glassEffectID("duration", in: glass)
                }
                primaryPill
                    .glassEffectID("primary", in: glass)
                morePill
                    .glassEffectID("more", in: glass)
            }
        }
        .animation(Pill.morph, value: engine.state)
        .animation(Pill.morph, value: engine.phase)
    }

    // MARK: Primary

    private var primaryPill: some View {
        Button {
            engine.primaryAction()
        } label: {
            Label(primaryTitle, systemImage: primarySymbol)
                .contentTransition(.symbolEffect(.replace))
                .fixedSize()
                .frame(maxWidth: .infinity)
                .pill(prominent: engine.state == .finished)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: engine.state)
        .help(primaryTitle)
    }

    private var primaryTitle: String {
        switch engine.state {
        case .idle: "Start"
        case .running: "Pause"
        case .paused: "Resume"
        case .finished: continuesFocus ? "Next Session" : engine.nextPhase.startTitle
        }
    }

    private var primarySymbol: String {
        switch engine.state {
        case .idle, .paused: "play.fill"
        case .running: "pause.fill"
        case .finished: continuesFocus ? "play.fill" : engine.nextPhase.symbol
        }
    }

    /// Focus followed directly by focus (breaks turned off).
    private var continuesFocus: Bool { engine.phase == .focus && engine.nextPhase == .focus }

    private var skipTitle: String {
        if engine.phase.isBreak { return "Skip Break" }
        return engine.nextPhase.isBreak ? "Skip to Break" : "Skip Session"
    }

    // MARK: Duration

    @ViewBuilder
    private var durationPill: some View {
        if engine.isFlowtime && engine.isActive {
            // Flowtime has no end: this pill is how you stop when your focus fades.
            Button { engine.finishEarly() } label: {
                Label("Finish", systemImage: "checkmark").fixedSize().pill()
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .help("End this session and take your break")
        } else {
            durationMenu
        }
    }

    private var durationMenu: some View {
        Menu {
            if engine.state == .idle {
                if !prefs.presets.isEmpty {
                    Section("Presets") {
                        ForEach(prefs.presets) { preset in
                            Toggle(isOn: Binding(get: { prefs.isCurrent(preset) },
                                                 set: { _ in applyPreset(preset) })) {
                                Text("\(preset.name) · \(preset.focus)/\(preset.shortBreak == 0 ? "–" : "\(preset.shortBreak)")")
                            }
                        }
                    }
                }
                Section("Mode") {
                    Picker("Mode", selection: Binding(get: { prefs.timerMode },
                                                      set: { prefs.timerMode = $0; engine.reloadIdle() })) {
                        ForEach(TimerMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                if !engine.isFlowtime {
                    Section("This Session") {
                        ForEach([5, 10, 15, 20, 25, 30, 45, 50, 60, 90], id: \.self) { minutes in
                            Button("\(minutes) minutes") { engine.setIdleMinutes(minutes) }
                        }
                    }
                }
            } else {
                Section("Add Time") {
                    Button("1 Minute", systemImage: "plus") { engine.extend(by: 60) }
                    Button("5 Minutes", systemImage: "plus") { engine.extend(by: 300) }
                    Button("10 Minutes", systemImage: "plus") { engine.extend(by: 600) }
                }
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(durationTitle, systemImage: durationSymbol)
                    .monospacedDigit()
                    .fixedSize()
                Image(systemName: durationSymbol)
            }
            .pill()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .layoutPriority(1)
        .help(engine.state == .idle ? "Length, presets and mode" : "Add time")
    }

    private var durationTitle: String {
        if engine.state != .idle { return "Time" }
        return engine.isFlowtime ? "Flow" : "\(Int(engine.total / 60)) min"
    }

    private var durationSymbol: String {
        if engine.state != .idle { return "plus" }
        return engine.isFlowtime ? "infinity" : "timer"
    }

    private func applyPreset(_ preset: TimerPreset) {
        prefs.apply(preset)
        engine.reloadIdle()
    }

    // MARK: More

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
                if engine.state != .idle {
                    Button("Reset", systemImage: "arrow.counterclockwise") { engine.reset() }
                }
            }
            Section {
                Menu("Switch To", systemImage: "arrow.triangle.swap") {
                    ForEach(Phase.allCases) { phase in
                        Button(phase.title, systemImage: phase.symbol) { engine.select(phase) }
                            .disabled(phase == engine.phase && engine.state == .idle)
                    }
                }
            }
            Section {
                Button("History", systemImage: "chart.bar") { actions.showHistory() }
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
}
