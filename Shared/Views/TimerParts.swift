import SwiftUI

/// "FOCUS ●●○○" — the phase and where you are in the cycle before a long break.
struct PhaseHeader: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs

    var body: some View {
        HStack {
            Label(engine.phase.title, systemImage: engine.phase.symbol)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
                .animation(Pill.morph, value: engine.phase)
            Spacer()
            if prefs.longBreaksEnabled && prefs.showCycleDots {
                CycleDots()
                    .transition(.opacity)
            }
        }
        .frame(height: 20)
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

/// "What's the one thing?" during focus, "What did you get done?" after it, a small suggestion during breaks.
struct IntentionField: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var engine = engine
        Group {
            if let id = engine.lastRecordID, engine.phase == .focus, engine.state == .finished,
               prefs.askForReflection, history.record(id) != nil {
                TextField("What did you get done?", text: Binding(
                    get: { history.record(id)?.note ?? "" },
                    set: { history.update(id, note: $0) }
                ))
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { focused = false }
                .transition(.blurReplace)
            } else if engine.phase.isBreak {
                Text(BreakTips.tip(for: engine.sessionStart))
                    .foregroundStyle(.secondary)
                    .transition(.blurReplace)
            } else if prefs.showIntention {
                TextField("What's the one thing?", text: $engine.intention)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        focused = false
                        if engine.state == .idle { engine.start() }
                    }
                    .transition(.blurReplace)
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .animation(.easeInOut(duration: 0.35), value: engine.phase.isBreak)
        .animation(.easeInOut(duration: 0.35), value: engine.state)
    }
}

/// "3 of 8 today · 1h 15m". Resets each morning at the chosen hour. No streaks.
struct TodayLine: View {
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let count = history.todayCount(hour: prefs.dayStartsAtHour)
        let time = history.todayDuration(hour: prefs.dayStartsAtHour)
        let goal = prefs.dailyGoal // 0 = no goal
        HStack(spacing: 6) {
            if goal > 0 {
                GoalBar(value: Double(count) / Double(goal))
                    .frame(width: 36, height: 3)
                Text(count >= goal ? "Goal reached · \(count) today" : "\(count) of \(goal) today")
            } else {
                Text(count == 0 ? "Nothing yet today" : "\(count) today")
            }
            if time > 0 {
                Text("·")
                Text(TimeFormat.duration(time))
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
        .animation(.snappy, value: count)
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
