import SwiftUI

/// The iPhone's caption under the ring. What shows follows Settings, with no toggle button:
/// - focus, with the intention or projects on: a glass capsule with the project and/or the intention
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
           prefs.reflectionActive, history.record(id) != nil {
            return .reflection(id)
        }
        if engine.phase.isBreak { return prefs.showIntention || prefs.reflectionActive ? .tip : nil }
        if engine.state == .finished { return nil }
        return prefs.showIntention || prefs.projectsActive ? .intention : nil
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
                // The gap to the controls below; none when there's nothing to show.
                .padding(.bottom, 12)
                .transition(.blurReplace.combined(with: .scale(0.96, anchor: .bottom)))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: content)
    }

    // MARK: Focus: project + intention

    private var intention: some View {
        @Bindable var engine = engine
        return HStack(spacing: 0) {
            if prefs.projectsActive {
                ProjectPill(showsName: !prefs.showIntention)
                    .padding(.leading, 6)
                    .frame(maxWidth: prefs.showIntention ? nil : .infinity)
            }
            if prefs.showIntention {
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
    /// Alone in the capsule (no intention): say "Choose a project" until one is picked.
    var showsName = false

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
                } else if showsName {
                    Text("Choose a project")
                        .lineLimit(1)
                        .frame(maxWidth: 110, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(current == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.ink(scheme == .dark ? .light : .dark)))
            .padding(.horizontal, current == nil && !showsName ? 0 : 12)
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


/// The row under the ring, like the Mac's:  [length or Add Time] [Reset]  ·····  [•••]
/// Idle: the length (with presets and the mode). Running or paused: Add Time and Reset, or Finish in
/// Flowtime. Finished: the button that moves on fills the row. Finishing early, logging a
/// distraction and skipping sit in •••. On a narrow screen the labels shrink to their icons.
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
                resetPill(compact: compact)
                    .glassEffectID("reset", in: glass)
            case .finished:
                nextPill(compact: compact)
                    .glassEffectID("leading", in: glass)
                resetPill(compact: true)
                    .glassEffectID("reset", in: glass)
            }
            if engine.state != .finished {
                Spacer(minLength: 0)
            }
            // During focus there's more than one thing to do; otherwise just Skip, as a button.
            // Once a session is over, the button that moves on already does that.
            if hasMore {
                morePill
                    .glassEffectID("more", in: glass)
            } else if engine.state != .finished {
                skipPill(compact: compact)
                    .glassEffectID("more", in: glass)
            }
        }
    }

    // MARK: Idle

    /// A length, a preset, or the mode.
    private var lengthMenu: some View {
        Menu {
            if !engine.isFlowtime {
                // Folded into one item ("Length · 25 minutes") so presets and the mode fit too.
                Picker(selection: Binding(
                    get: { Int(engine.total / 60) },
                    set: { Haptics.play(.select); engine.setIdleMinutes($0) }
                )) {
                    ForEach(lengths, id: \.self) { Text("\($0) minutes").tag($0) }
                } label: {
                    Label("Length", systemImage: "timer")
                    Text("\(Int(engine.total / 60)) minutes")
                }
                .pickerStyle(.menu)
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
            Divider()
            // Only two modes, so one item flips between them.
            Button(prefs.isFlowtime ? "Switch to Pomodoro" : "Switch to Flowtime",
                   systemImage: prefs.isFlowtime ? "timer" : "infinity") {
                prefs.timerMode = prefs.isFlowtime ? .pomodoro : .flowtime
                engine.reloadIdle()
            }
        } label: {
            Label(engine.isFlowtime ? "Flow" : "\(Int(engine.total / 60)) min",
                  systemImage: engine.isFlowtime ? "infinity" : "timer")
                .monospacedDigit()
                .contentTransition(.numericText(value: engine.total))
                .fixedSize()
                .pill()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(engine.isFlowtime ? "Flowtime" : "\(Int(engine.total / 60)) minutes")
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
        .accessibilityHint("Ends this session and starts your break")
    }

    private func resetPill(compact: Bool) -> some View {
        Button { engine.reset() } label: {
            if compact {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: Pill.height)
                    .pill(square: true)
            } else {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .fixedSize()
                    .pill()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset")
    }

    // MARK: Finished

    private func nextPill(compact: Bool) -> some View {
        let continuesFocus = engine.phase == .focus && engine.nextPhase == .focus
        let title = continuesFocus ? "Next Session" : engine.nextPhase.startTitle
        let symbol = continuesFocus ? "play.fill" : engine.nextPhase.symbol
        return Button {
            engine.advance(autoStart: true)
        } label: {
            Label(title, systemImage: symbol)
                .fixedSize()
                .frame(maxWidth: .infinity)
                .pill(prominent: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: More

    /// What isn't one tap away already: finishing early, a distraction, skipping ahead.
    private var morePill: some View {
        Menu {
            Section {
                if engine.phase == .focus && engine.isActive {
                    if !engine.isFlowtime {
                        Button("Finish Early", systemImage: "checkmark.circle") { engine.finishEarly() }
                    }
                    Button(engine.distractions == 0 ? "Log a Distraction" : "Log a Distraction (\(engine.distractions))",
                           systemImage: "exclamationmark.bubble") {
                        Haptics.play(.select)
                        engine.logDistraction()
                    }
                }
                Button(skipTitle, systemImage: "forward.end") { engine.skip() }
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
        .accessibilityLabel("More")
    }

    /// Focusing right now: finishing early and logging a distraction join Skip in •••.
    private var hasMore: Bool { engine.phase == .focus && engine.isActive }

    /// Labelled, so it's clear what it does: "Skip Break", or just "Skip" when the row is tight.
    private func skipPill(compact: Bool) -> some View {
        Button { engine.skip() } label: {
            Label(compact ? "Skip" : skipTitle, systemImage: "forward.end")
                .fixedSize()
                .pill()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(skipTitle)
    }

    private var skipTitle: String {
        if engine.phase.isBreak { return "Skip Break" }
        return engine.nextPhase.isBreak ? "Skip to Break" : "Skip Session"
    }
}

// MARK: - Link

/// Top right of the timer, as on the Mac: "Link" until you're in a group, then the group's faces.
/// Tap it for the Link sheet.
struct LinkHeaderButton: View {
    private var link: LinkSession { LinkSession.shared }

    var body: some View {
        Button {
            Haptics.play(.select)
            AppRouter.shared.linkShown = true
        } label: {
            label
                .fixedSize()
                .pill()
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(Pill.morph, value: link.isLinked)
        .animation(Pill.morph, value: link.members)
        .accessibilityLabel(link.isLinked
                            ? "Your group, with \(link.others.count) other\(link.others.count == 1 ? "" : "s")"
                            : "Link")
        .accessibilityHint(link.isLinked ? "Shows who's here" : "Focus together with friends")
    }

    @ViewBuilder
    private var label: some View {
        if link.isLinked {
            HStack(spacing: 6) {
                AvatarStack(members: link.members, myID: link.myID, size: 28)
                if link.status != .linked {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Reconnecting")
                }
            }
            .padding(.horizontal, -6)
            .transition(.blurReplace)
        } else {
            Label("Link", systemImage: "laptopcomputer.and.iphone")
                .transition(.blurReplace)
        }
    }
}
