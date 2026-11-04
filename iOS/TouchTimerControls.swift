import SwiftUI

/// The iPhone's caption under the ring. What shows follows Settings, with no toggle button:
/// - focus, with "Project & intention" on: a glass capsule with the project chip and the intention
/// - after a focus session, with notes on: "What did you get done?"
/// - during a break: a small suggestion
struct TouchIntentionField: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs
    @FocusState private var focused: Bool

    private enum Content: Equatable { case reflection(FocusRecord.ID), tip, intention }

    private var content: Content? {
        if let id = engine.lastRecordID, engine.phase == .focus, engine.state == .finished,
           prefs.askForReflection, history.record(id) != nil {
            return .reflection(id)
        }
        if engine.phase.isBreak { return prefs.showIntention || prefs.askForReflection ? .tip : nil }
        if engine.state == .finished { return nil }
        return prefs.showIntention ? .intention : nil
    }

    var body: some View {
        let content = content
        VStack(spacing: 0) {
            if let content {
                Group {
                    switch content {
                    case .reflection(let id): reflection(id)
                    case .tip: tip
                    case .intention: intention
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Pill.height, maxHeight: Pill.height)
                .transition(.blurReplace.combined(with: .scale(0.96, anchor: .bottom)))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: content)
    }

    // MARK: Focus: project + intention

    private var intention: some View {
        @Bindable var engine = engine
        return HStack(spacing: 0) {
            ProjectPill()
                .padding(.leading, 6)
            TextField("What's the one thing?", text: $engine.intention)
                .focused($focused)
                .submitLabel(engine.state == .idle ? .go : .done)
                .onSubmit {
                    focused = false
                    if engine.state == .idle { engine.start() }
                }
                .padding(.leading, 10)
            if !engine.intention.isEmpty && focused {
                Button {
                    engine.intention = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
                .transition(.opacity)
            }
        }
        .padding(.trailing, 6)
        .frame(height: Pill.height)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { focused = true }
        .animation(.snappy(duration: 0.2), value: focused)
    }

    // MARK: After focus: a note

    private func reflection(_ id: FocusRecord.ID) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.line")
                .foregroundStyle(.secondary)
            TextField("What did you get done?", text: Binding(
                get: { history.record(id)?.note ?? "" },
                set: { history.update(id, note: $0) }
            ))
            .focused($focused)
            .submitLabel(.done)
            .onSubmit { focused = false }
        }
        .padding(.horizontal, 18)
        .frame(height: Pill.height)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { focused = true }
    }

    // MARK: Break: a suggestion

    private var tip: some View {
        Text(BreakTips.tip(for: engine.sessionStart))
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }
}

/// The project inside the intention capsule: a faint folder until one is picked, then a solid
/// ink pill with its symbol and name.
private struct ProjectPill: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(HistoryStore.self) private var history
    @Environment(\.appActions) private var actions
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let current = history.project(engine.projectID)
        let ink = Color.ink(scheme)
        Menu {
            Picker("Project", selection: Binding(
                get: { current?.id },
                set: { id in
                    Haptics.play(.select)
                    engine.projectID = id
                }
            )) {
                Text("No Project").tag(Project.ID?.none)
                ForEach(history.activeProjects) { project in
                    Label(project.name, systemImage: project.symbol).tag(Project.ID?.some(project.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Manage Projects…", systemImage: "folder.badge.gearshape") { actions.showInsights(.projects) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: current?.symbol ?? "folder")
                if let current {
                    Text(current.name)
                        .lineLimit(1)
                        .frame(maxWidth: 110, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(current == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.ink(scheme == .dark ? .light : .dark)))
            .padding(.horizontal, current == nil ? 0 : 12)
            .frame(minWidth: 32, minHeight: 32)
            .background(Capsule().fill(current == nil ? ink.opacity(0.07) : ink))
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .animation(Pill.morph, value: current?.id)
        .accessibilityLabel(current.map { "Project, \($0.name)" } ?? "Choose a project")
    }
}

/// The timer's controls, top right in the header. Idle: the length. Running or paused: Add Time
/// and Reset. Finished: move on, and Reset. Skipping, finishing early and logging a distraction
/// sit in the Add Time menu, so there's no "more" button. When the phase name beside them is long
/// or the screen narrow, Add Time and the move-on button shrink to their icons.
struct TouchControlPills: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 2) {
            ViewThatFits(in: .horizontal) {
                row(compact: false)
                row(compact: true)
            }
        }
        .animation(Pill.morph, value: engine.state)
        .animation(Pill.morph, value: engine.phase)
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: Pill.spacing) {
            switch engine.state {
            case .idle:
                lengthMenu
                    .glassEffectID("leading", in: glass)
            case .running, .paused:
                Group {
                    if engine.isFlowtime { finishPill } else { addTimeMenu(compact: compact) }
                }
                .glassEffectID("leading", in: glass)
                resetPill
                    .glassEffectID("reset", in: glass)
            case .finished:
                nextPill(compact: compact)
                    .glassEffectID("leading", in: glass)
                resetPill
                    .glassEffectID("reset", in: glass)
            }
        }
        .fixedSize()
    }

    // MARK: Idle

    /// A length, a preset, or the mode.
    private var lengthMenu: some View {
        Menu {
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
                Menu("Presets", systemImage: "list.bullet") {
                    ForEach(prefs.presets) { preset in
                        Toggle(isOn: Binding(get: { prefs.isCurrent(preset) },
                                             set: { _ in prefs.apply(preset); engine.reloadIdle() })) {
                            Text(preset.name)
                            Text(preset.shortBreak == 0 ? "\(preset.focus) min, no breaks"
                                 : "\(preset.focus) min focus, \(preset.shortBreak) min break")
                        }
                    }
                }
            }
            Picker("Mode", selection: Binding(
                get: { prefs.timerMode },
                set: { prefs.timerMode = $0; engine.reloadIdle() }
            )) {
                ForEach(TimerMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
        } label: {
            Label(engine.isFlowtime ? "Flow" : "\(Int(engine.total / 60)) min",
                  systemImage: engine.isFlowtime ? "infinity" : "timer")
                .monospacedDigit()
                .fixedSize()
                .pill()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityHint("Length, presets and mode")
    }

    /// Common lengths, plus the current one if it's something else (e.g. set by dragging the ring).
    private var lengths: [Int] {
        let common = [10, 15, 20, 25, 30, 45, 50, 60, 90]
        let current = Int(engine.total / 60)
        return common.contains(current) ? common : (common + [current]).sorted()
    }

    // MARK: Running or paused

    private func addTimeMenu(compact: Bool) -> some View {
        Menu {
            Section("Add Time") {
                Button("1 Minute", systemImage: "plus") { engine.extend(by: 60) }
                Button("5 Minutes", systemImage: "plus") { engine.extend(by: 300) }
                Button("10 Minutes", systemImage: "plus") { engine.extend(by: 600) }
            }
            sessionActions
        } label: {
            if compact {
                Image(systemName: "plus")
                    .frame(width: Pill.height)
                    .pill(square: true)
            } else {
                Label("Add Time", systemImage: "plus")
                    .fixedSize()
                    .pill()
            }
        }
        .accessibilityLabel("Add Time")
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Flowtime has no end: this is how you stop when your focus fades.
    private var finishPill: some View {
        Button { engine.finishEarly() } label: {
            Label("Finish", systemImage: "checkmark").fixedSize().pill()
        }
        .buttonStyle(.plain)
        .contextMenu { sessionActions }
        .accessibilityHint("Ends this session and starts your break")
    }

    @ViewBuilder
    private var sessionActions: some View {
        Section {
            if engine.phase == .focus {
                if !engine.isFlowtime {
                    Button("Finish Early", systemImage: "checkmark.circle") { engine.finishEarly() }
                }
                Button("Log a Distraction", systemImage: "exclamationmark.bubble") { engine.logDistraction() }
            }
            Button(skipTitle, systemImage: "forward.end") { engine.skip() }
        }
    }

    private var skipTitle: String {
        if engine.phase.isBreak { return "Skip Break" }
        return engine.nextPhase.isBreak ? "Skip to Break" : "Skip Session"
    }

    private var resetPill: some View {
        Button { engine.reset() } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .fixedSize()
                .pill()
        }
        .buttonStyle(.plain)
    }

    // MARK: Finished

    private func nextPill(compact: Bool) -> some View {
        let continuesFocus = engine.phase == .focus && engine.nextPhase == .focus
        let title = continuesFocus ? "Next Session" : engine.nextPhase.startTitle
        let symbol = continuesFocus ? "play.fill" : engine.nextPhase.symbol
        return Button {
            engine.advance(autoStart: true)
        } label: {
            if compact {
                Image(systemName: symbol)
                    .frame(width: Pill.height)
                    .pill(prominent: true, square: true)
            } else {
                Label(title, systemImage: symbol)
                    .fixedSize()
                    .pill(prominent: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
