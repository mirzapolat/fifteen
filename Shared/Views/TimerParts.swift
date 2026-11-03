import SwiftUI

/// "FOCUS ●●○○" — the phase and where you are in the cycle before a long break.
struct PhaseHeader: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs

    var body: some View {
        HStack {
            PhaseSwitcher()
            Spacer()
            HeaderCounter()
        }
        .frame(height: Pill.height)
    }
}

/// The phase name doubles as a quick switch: click it to jump to Focus, Short Break or Long Break.
/// Switching stops the current session without recording it.
struct PhaseSwitcher: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs

    private var phases: [Phase] {
        Phase.allCases.filter { phase in
            switch phase {
            case .focus: true
            case .shortBreak: prefs.shortBreaksEnabled || prefs.isFlowtime
            case .longBreak: prefs.longBreaksEnabled
            }
        }
    }

    var body: some View {
        Menu {
            Picker("Session", selection: Binding(
                get: { engine.phase },
                set: { phase in Haptics.play(.select); withAnimation(Pill.morph) { engine.select(phase) } }
            )) {
                ForEach(phases) { phase in
                    Label(phase.title, systemImage: phase.symbol).tag(phase)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 5) {
                Label(engine.phase.title, systemImage: engine.phase.symbol)
                    .contentTransition(.symbolEffect(.replace))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            // Same glass pill as the controls at the bottom.
            .pill()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(phases.count < 2)
        .animation(Pill.morph, value: engine.phase)
        .help("Switch between focus and breaks")
        .accessibilityLabel("Session type: \(engine.phase.title)")
        .accessibilityHint("Choose focus, short break or long break")
    }
}

struct CycleDots: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let count = max(1, prefs.sessionsBeforeLongBreak)
        let filled = min(count, engine.completedInCycle)
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Color.ink(scheme).opacity(index < filled ? 1 : 0.18))
                    .frame(width: 6, height: 6)
                    .scaleEffect(index == filled - 1 ? 1.15 : 1)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.4), value: filled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) of \(count) sessions before a long break")
    }
}

/// Popup state that isn't a preference: whether the project and "one thing" field are revealed.
/// They stay tucked behind a button at the bottom right until you ask for them.
@Observable
@MainActor
final class TimerChrome {
    static let shared = TimerChrome()
    var detailsShown = false
}

/// "What's the one thing?" (with the project) when revealed, "What did you get done?" after a
/// session, a small suggestion during breaks. Takes no room at all when there's nothing to show.
struct IntentionField: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs
    @FocusState private var focused: Bool
    private var chrome: TimerChrome { TimerChrome.shared }

    private enum Content: Equatable { case reflection(FocusRecord.ID), tip, intention }

    private var content: Content? {
        if let id = engine.lastRecordID, engine.phase == .focus, engine.state == .finished,
           prefs.askForReflection, history.record(id) != nil {
            return .reflection(id)
        }
        if engine.phase.isBreak { return prefs.showIntention || prefs.askForReflection ? .tip : nil }
        return prefs.showIntention && chrome.detailsShown ? .intention : nil
    }

    var body: some View {
        @Bindable var engine = engine
        let content = content
        VStack(spacing: 0) {
            if let content {
                Group {
                    switch content {
                    case .reflection(let id):
                        TextField("What did you get done?", text: Binding(
                            get: { history.record(id)?.note ?? "" },
                            set: { history.update(id, note: $0) }
                        ))
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit { focused = false }
                        .fieldBox(focused: focused)
                    case .tip:
                        Text(BreakTips.tip(for: engine.sessionStart))
                            .foregroundStyle(.secondary)
                    case .intention:
                        HStack(spacing: 4) {
                            ProjectChip()
                            TextField("What's the one thing?", text: $engine.intention)
                                .textFieldStyle(.plain)
                                .focused($focused)
                                .onSubmit {
                                    focused = false
                                    if engine.state == .idle { engine.start() }
                                }
                            // Balances the chip so the text stays centred.
                            Color.clear.frame(width: 22, height: 1)
                        }
                        .padding(.horizontal, -6)
                        .fieldBox(focused: focused)
                        // Revealed on purpose, so it's ready to type into.
                        .onAppear { if engine.intention.isEmpty { focused = true } }
                    }
                }
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Pill.height, maxHeight: Pill.height)
                .padding(.bottom, 10)
                .transition(.blurReplace.combined(with: .scale(0.96, anchor: .bottom)))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: content)
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

private extension View {
    /// A quiet rounded box that brightens while you type.
    func fieldBox(focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Pill.height * 0.32, style: .continuous)
        return padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Pill.height, maxHeight: Pill.height)
            .background(shape.fill(Color.primary.opacity(focused ? 0.08 : 0.045)))
            .overlay(shape.strokeBorder(Color.primary.opacity(focused ? 0.3 : 0.1), lineWidth: 1))
            .contentShape(shape)
    }
}

extension EnvironmentValues {
    /// Changes every time the timer is presented (each time the Mac popup opens), to replay the counter hint.
    @Entry var presentationCount = 0
}

/// Top right: today's progress toward the daily goal. (The cycle dots live inside the ring.)
struct HeaderCounter: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        if prefs.showTodayProgress {
            GoalCounter()
                .frame(height: 20, alignment: .trailing)
        }
    }
}

/// "3/8 today" with a tiny bar; "3 today" when there's no daily goal.
struct GoalCounter: View {
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let count = history.todayCount(hour: prefs.dayStartsAtHour)
        let goal = prefs.dailyGoal // 0 = no goal
        let time = history.todayDuration(hour: prefs.dayStartsAtHour)
        HStack(spacing: 6) {
            if goal > 0 {
                GoalBar(value: Double(count) / Double(goal))
                    .frame(width: 26, height: 3)
                Text(count >= goal ? "\(count)/\(goal) ✓" : "\(count)/\(goal) today")
            } else {
                Text("\(count) today")
            }
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
        .animation(.snappy, value: count)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal > 0
            ? "\(count) of \(goal) sessions today, \(TimeFormat.duration(time)) focused"
            : "\(count) sessions today, \(TimeFormat.duration(time)) focused")
    }
}

struct GoalBar: View {
    var value: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.ink(scheme).opacity(0.15))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.ink(scheme))
                        .frame(width: geo.size.width * min(1, max(0, value)))
                }
        }
        .animation(.spring(duration: 0.6), value: value)
    }
}
