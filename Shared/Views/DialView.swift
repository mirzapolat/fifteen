import SwiftUI

/// The ring. It empties clockwise as time passes; a dot marks where "now" is.
/// While idle, drag around it like a kitchen timer to set the minutes. Tap to start or pause.
struct DialView: View {
    @Environment(TimerEngine.self) private var engine
    var lineWidth: CGFloat = 6

    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme
    @State private var dragMinutes: Int?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: engine.state != .running)) { context in
                let date = engine.state == .running ? context.date : engine.now
                dial(size: size, fraction: fraction(at: date))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(drag(size: size))
            .onTapGesture { engine.primaryAction() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: dragMinutes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(engine.phase.title), \(clockText) \(engine.state == .paused ? "paused" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { engine.primaryAction() }
    }

    private func dial(size: CGFloat, fraction: Double) -> some View {
        let radius = (size - lineWidth) / 2
        return ZStack {
            BreathingDisc(active: engine.phase.isBreak && engine.state == .running)
                .padding(lineWidth * 4)

            Circle()
                .inset(by: lineWidth / 2)
                .stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)

            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: fraction)
                .stroke(Color.ink(scheme), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(Color.ink(scheme))
                .frame(width: lineWidth * 2.2, height: lineWidth * 2.2)
                .offset(y: -radius)
                .rotationEffect(.degrees(360 * fraction))
                .opacity(engine.state == .idle && dragMinutes == nil && !engine.isFlowtime ? 0 : 1)

            center(size: size)
        }
        .animation(.spring(duration: 0.6, bounce: 0.2), value: engine.state)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: dragMinutes)
    }

    private func center(size: CGFloat) -> some View {
        VStack(spacing: size * 0.015) {
            Text(clockText)
                .font(.system(size: size * 0.21, weight: .light))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: engine.state != .finished && !engine.isFlowtime))
                .animation(.snappy(duration: 0.25), value: clockText)
                .phaseAnimator(engine.state == .paused ? [1.0, 0.3] : [1.0]) { text, opacity in
                    text.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 1.1) }
                .minimumScaleFactor(0.5)
            if showsRating {
                FocusRating(size: size)
                    .transition(.blurReplace)
            } else {
                Text(subtitle)
                    .font(.system(size: max(10, size * 0.05), weight: .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
        .padding(.horizontal, lineWidth * 5)
    }

    // MARK: Values

    /// After focus, ask how it went (if enabled and the session was recorded).
    private var showsRating: Bool {
        engine.state == .finished && engine.phase == .focus && prefs.askForReflection
            && engine.lastRecordID != nil && !engine.isCountingOvertime
    }

    private func fraction(at date: Date) -> Double {
        if let dragMinutes { return Double(dragMinutes) / 60 }
        // Flowtime fills the ring like a clock's minute hand, once per hour.
        if engine.isFlowtime && engine.state != .finished {
            return engine.elapsed(at: date).truncatingRemainder(dividingBy: 3600) / 3600
        }
        switch engine.state {
        case .idle: return 1
        case .finished: return 0
        case .running, .paused: return 1 - engine.progress(at: date)
        }
    }

    private var clockText: String {
        if let dragMinutes { return TimeFormat.clock(TimeInterval(dragMinutes * 60)) }
        if engine.state == .finished {
            return engine.isCountingOvertime ? "+" + TimeFormat.clock(engine.overtime) : "Done"
        }
        if engine.isFlowtime { return TimeFormat.clock(engine.elapsed) }
        return TimeFormat.clock(engine.remaining)
    }

    private var subtitle: String {
        switch engine.state {
        case .idle: dragMinutes == nil ? (engine.isFlowtime ? "Flowtime" : engine.phase.title) : "Release to set"
        case .running: engine.isFlowtime ? "Flowtime" : engine.phase.title
        case .paused: "Paused"
        case .finished: engine.phase == .focus ? (engine.isCountingOvertime ? "In the flow" : "Session complete") : "Break's over"
        }
    }

    private func drag(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard engine.state == .idle, !engine.isFlowtime else { return }
                let dx = value.location.x - size / 2
                let dy = value.location.y - size / 2
                var angle = atan2(dx, -dy)
                if angle < 0 { angle += 2 * .pi }
                var minutes = Int((angle / (2 * .pi) * 60).rounded())
                if minutes == 0 { minutes = (dragMinutes ?? 0) > 30 ? 60 : 1 }
                if minutes != dragMinutes { dragMinutes = minutes }
            }
            .onEnded { _ in
                if let dragMinutes { engine.setIdleMinutes(dragMinutes) }
                dragMinutes = nil
            }
    }
}

/// "How focused were you?" — five dots, tap one. Stored on the session that just ended.
struct FocusRating: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(HistoryStore.self) private var history
    @Environment(\.colorScheme) private var scheme
    var size: CGFloat

    var body: some View {
        let id = engine.lastRecordID
        let current = history.record(id)?.rating ?? 0
        let dot = max(7, size * 0.042)
        VStack(spacing: size * 0.025) {
            Text(current == 0 ? "How focused were you?" : FocusRecord.ratingWords[current])
                .font(.system(size: max(10, size * 0.045), weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            HStack(spacing: dot * 0.6) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        guard let id else { return }
                        withAnimation(.spring(duration: 0.35, bounce: 0.4)) { history.update(id, rating: value) }
                    } label: {
                        Circle()
                            .fill(Color.ink(scheme).opacity(value <= current ? 1 : 0.18))
                            .frame(width: dot, height: dot)
                            .scaleEffect(value == current ? 1.25 : 1)
                            .padding(dot * 0.35)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) of 5, \(FocusRecord.ratingWords[value])")
                }
            }
            .sensoryFeedback(.selection, trigger: current)
        }
    }
}

/// A soft disc that slowly grows and shrinks during breaks: breathe in as it grows, out as it shrinks.
struct BreathingDisc: View {
    var active: Bool

    var body: some View {
        ZStack {
            if active {
                Circle()
                    .fill(Color.primary.opacity(0.07))
                    .phaseAnimator([0.78, 1.0]) { disc, scale in
                        disc.scaleEffect(scale)
                    } animation: { _ in .easeInOut(duration: 4) }
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.easeInOut(duration: 1), value: active)
    }
}
