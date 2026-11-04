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

/// The running session on the Lock Screen and in the Dynamic Island: which phase it is, the time,
/// and Pause/Resume and Reset right there. Black and white, like the app.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseHeading(state: state)
                        .padding(.leading, 8)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeLeft(state: state)
                        .font(.system(size: 38, weight: .light))
                        .frame(maxWidth: 150, alignment: .trailing)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        Bar(state: state)
                        Controls(state: state)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                }
            } compactLeading: {
                // The phase at a glance: focus, a short break or a long one (or paused).
                Image(systemName: state.isPaused ? "pause.fill" : state.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.leading, 2)
            } compactTrailing: {
                TimeLeft(state: state)
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: 52)
            } minimal: {
                Ring(state: state)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(.white)
        }
    }
}

private extension FocusActivityAttributes.ContentState {
    var isPaused: Bool { pausedRemaining != nil }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                PhaseHeading(state: state)
                Spacer(minLength: 8)
                TimeLeft(state: state)
                    .font(.system(size: 44, weight: .light))
                    .frame(maxWidth: 170, alignment: .trailing)
            }
            Bar(state: state)
            Controls(state: state)
        }
        .padding(18)
        .foregroundStyle(.white)
    }
}

// MARK: - Parts

/// "Focus" / "Short Break" / "Long Break" with its symbol, and what's happening under it:
/// when it ends, that it's counting up, or that it's paused.
private struct PhaseHeading: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(state.title, systemImage: state.symbol)
                .font(.headline)
                .lineLimit(1)
            Group {
                if state.isPaused {
                    Text("Paused")
                } else if state.countsUp {
                    Text("Counting up")
                } else {
                    Text("Ends \(Text(state.end, style: .time))")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
        }
    }
}

/// Pause or Resume (solid white) and Reset (glassy), as two wide capsules.
private struct Controls: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: ToggleTimerActivityIntent()) {
                Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(.black)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            Button(intent: ResetTimerActivityIntent()) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
    }
}

/// A thin line that empties as the session runs (fills once an hour in Flowtime).
/// Drawn by the system, so it moves while the app sleeps.
private struct Bar: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        Group {
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
        .progressViewStyle(.linear)
        .tint(.white)
        .accessibilityHidden(true)
    }
}

/// The system draws and animates this ring on its own, even while the app is asleep.
private struct Ring: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        Group {
            if let paused = state.pausedRemaining {
                // Flowtime fills once per hour; countdowns show the share left.
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
        .progressViewStyle(.circular)
        .tint(.white)
    }
}

private struct TimeLeft: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        Group {
            if let paused = state.pausedRemaining {
                let s = Int(paused.rounded(.up))
                Text(s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                     : String(format: "%02d:%02d", s / 60, s % 60))
            } else {
                Text(timerInterval: state.start...state.end, countsDown: !state.countsUp)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}
