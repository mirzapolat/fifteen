import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FifteenWidgets: WidgetBundle {
    var body: some Widget {
        FocusLiveActivity()
    }
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Ring(state: context.state)
                        .frame(width: 44, height: 44)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeLeft(state: context.state)
                        .font(.system(size: 36, weight: .light))
                        .frame(maxWidth: 140, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Label(context.state.pausedRemaining == nil ? context.state.title : "Paused",
                          systemImage: context.state.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Ring(state: context.state)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                TimeLeft(state: context.state)
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: 50)
            } minimal: {
                Ring(state: context.state)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(.white)
        }
    }
}

private struct LockScreenView: View {
    var state: FocusActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            Ring(state: state)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.headline)
                Text(state.pausedRemaining == nil ? "Fifteen" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            TimeLeft(state: state)
                .font(.system(size: 42, weight: .light))
                .frame(maxWidth: 160, alignment: .trailing)
        }
        .padding(20)
        .foregroundStyle(.white)
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
                Text(String(format: "%02d:%02d", s / 60, s % 60))
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
