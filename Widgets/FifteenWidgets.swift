import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct FifteenWidgets: WidgetBundle {
    var body: some Widget {
        FocusLiveActivity()
    }
}

/// The session on the Lock Screen and in the Dynamic Island: which phase it is, what it's for,
/// the time, and Pause, +5 and Reset right there. Once it's over, what comes next and the button
/// that starts it. Black and white, like the app.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenView(state: context.state, done: isDone(context))
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let done = isDone(context)
            // The expanded island has little height: one line of detail, the bar, and the
            // buttons a little shorter than on the Lock Screen, so nothing gets clipped.
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Heading(state: state, done: done, compact: true)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeLeft(state: state, done: done)
                        .font(.system(size: 30, weight: .light))
                        .frame(maxWidth: 130, alignment: .trailing)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if done {
                            DoneMessage(state: state, lines: 1)
                        } else {
                            Bar(state: state)
                        }
                        Controls(state: state, done: done, height: 34)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                // The phase at a glance (or paused, or done).
                Image(systemName: done ? "checkmark" : state.isPaused ? "pause.fill" : state.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.leading, 2)
            } compactTrailing: {
                TimeLeft(state: state, done: done, compact: true)
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: 56)
            } minimal: {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                } else {
                    Ring(state: state)
                        .frame(width: 18, height: 18)
                }
            }
            .keylineTint(.white)
        }
    }

    /// Over: the app said so, or a countdown passed its end while Fifteen was asleep.
    private func isDone(_ context: ActivityViewContext<FocusActivityAttributes>) -> Bool {
        let state = context.state
        return state.finished || (context.isStale && !state.isPaused && !state.countsUp)
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    var state: FocusActivityAttributes.ContentState
    var done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Heading(state: state, done: done)
                Spacer(minLength: 8)
                TimeLeft(state: state, done: done)
                    .font(.system(size: 42, weight: .light))
                    .frame(maxWidth: 170, alignment: .trailing)
                    .padding(.top, -6)
            }
            if done {
                DoneMessage(state: state)
            } else {
                Bar(state: state)
                Caption(state: state)
            }
            Controls(state: state, done: done)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

// MARK: - Parts

/// "Focus" / "Short Break" with its symbol, and under it what it's for: the intention and
/// project, or once it's over, the headline ("Focus done").
private struct Heading: View {
    var state: FocusActivityAttributes.ContentState
    var done: Bool
    /// In the Dynamic Island: one line under the title (the intention, else the project).
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if done {
                Label(state.doneTitle ?? "Time's up", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .lineLimit(1)
            } else {
                Label(state.title, systemImage: state.isPaused ? "pause.circle.fill" : state.symbol)
                    .font(.headline)
                    .lineLimit(1)
                    .contentTransition(.symbolEffect(.replace))
                if let intention = state.intention {
                    Text(intention)
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                if let project = state.project, !(compact && state.intention != nil) {
                    Label(project, systemImage: state.projectSymbol ?? "folder")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
    }
}

/// When it ends (or that it's counting up, or paused), and who it's shared with.
private struct Caption: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if state.isPaused {
                    Text("Paused")
                } else if state.countsUp {
                    Text("Counting up since \(Text(state.start, style: .time))")
                } else {
                    Text("Ends at \(Text(state.end, style: .time))")
                }
            }
            if let others = state.others, others > 0 {
                Text("·")
                Image(systemName: "person.2.fill")
                Text(others == 1 ? "With 1 other" : "With \(others) others")
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.6))
        .lineLimit(1)
    }
}

/// "Nice work. Time for a short break."
private struct DoneMessage: View {
    var state: FocusActivityAttributes.ContentState
    var lines = 2

    var body: some View {
        Text(state.doneMessage ?? "Open Fifteen to start the next session.")
            .font(lines == 1 ? .caption : .subheadline)
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Running: Pause or Resume (solid white), then +5 and Reset as round glassy buttons.
/// Over: what's next (solid white) and 5 more minutes.
private struct Controls: View {
    var state: FocusActivityAttributes.ContentState
    var done: Bool
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: 8) {
            if done {
                Button(intent: AdvanceTimerActivityIntent()) {
                    Label(state.nextTitle ?? "Start Next", systemImage: state.nextSymbol ?? "play.fill")
                        .primaryCapsule(height)
                }
                .buttonStyle(.plain)
                Button(intent: AddTimeActivityIntent()) {
                    Label("5 More Minutes", systemImage: "plus")
                        .secondaryCapsule(height)
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: ToggleTimerActivityIntent()) {
                    Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                        .primaryCapsule(height)
                }
                .buttonStyle(.plain)
                // Flowtime has no end to push back.
                if !state.countsUp {
                    Button(intent: AddTimeActivityIntent()) {
                        Text("+5")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .roundButton(height)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add 5 minutes")
                }
                Button(intent: ResetTimerActivityIntent()) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .roundButton(height)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset")
            }
        }
    }
}

private extension View {
    func primaryCapsule(_ height: CGFloat) -> some View {
        font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .foregroundStyle(.black)
            .background(Capsule().fill(.white))
    }

    func secondaryCapsule(_ height: CGFloat) -> some View {
        font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .foregroundStyle(.white)
            .background(Capsule().fill(.white.opacity(0.18)))
    }

    func roundButton(_ height: CGFloat) -> some View {
        frame(width: 52, height: height)
            .foregroundStyle(.white)
            .background(Capsule().fill(.white.opacity(0.18)))
    }
}

/// A thin line that empties as the session runs (fills once an hour in Flowtime).
/// Drawn by the system, so it moves while the app sleeps.
private struct Bar: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        Progress(state: state)
            .progressViewStyle(.linear)
            .tint(.white)
            .accessibilityHidden(true)
    }
}

/// The system draws and animates this ring on its own, even while the app is asleep.
private struct Ring: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        Progress(state: state)
            .progressViewStyle(.circular)
            .tint(.white)
    }
}

/// What's left (or, in Flowtime, how far into the hour), still while paused, live otherwise.
private struct Progress: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        if let paused = state.pausedRemaining {
            ProgressView(value: state.countsUp
                         ? paused.truncatingRemainder(dividingBy: 3600) / 3600
                         : paused / max(1, state.total))
        } else if state.countsUp {
            ProgressView(timerInterval: state.start...state.start.addingTimeInterval(3600), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        } else {
            ProgressView(timerInterval: state.start...state.end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        }
    }
}

/// The clock: counting down, up in Flowtime, still while paused. Once over, the extra minutes
/// with "keep counting" on, or a quiet "Done".
private struct TimeLeft: View {
    var state: FocusActivityAttributes.ContentState
    var done: Bool
    var compact = false

    var body: some View {
        Group {
            if done {
                if state.keepsCounting {
                    Text("+\(Text(timerInterval: state.end...state.end.addingTimeInterval(12 * 3600), countsDown: false))")
                } else {
                    Text("Done")
                        .font(compact ? .system(size: 15, weight: .semibold) : .system(size: 28, weight: .regular))
                }
            } else if let paused = state.pausedRemaining {
                let s = Int(paused.rounded(.up))
                Text(s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                     : String(format: "%02d:%02d", s / 60, s % 60))
                    .opacity(0.7)
            } else if state.countsUp {
                Text(timerInterval: state.start...state.start.addingTimeInterval(12 * 3600), countsDown: false)
            } else {
                Text(timerInterval: state.start...state.end, countsDown: true)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}
