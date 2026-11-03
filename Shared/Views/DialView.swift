import SwiftUI

/// The ring. It empties clockwise as time passes; a dot marks where "now" is.
/// While idle, drag around it like a kitchen timer to set the minutes. Tap to start or pause.
struct DialView: View {
    @Environment(TimerEngine.self) private var engine
    var lineWidth: CGFloat = 6

    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme
    @State private var dragMinutes: Int?
    @State private var hovering = false
    /// When the start swirl began; it plays once each time a session starts.
    @State private var swirlStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let swirlDuration: TimeInterval = 1.3

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: engine.state != .running)) { context in
                let date = engine.state == .running ? context.date : engine.now
                dial(size: size, fraction: fraction(at: date), date: date)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            // The ring is the Start/Pause button: it lifts a little under the pointer.
            .scaleEffect(hovering && engine.state != .finished ? 1.025 : 1)
            .animation(.spring(duration: 0.35, bounce: 0.3), value: hovering)
            .onHover { hovering = $0 }
            // After a session the ring holds the rating dots; let those take the clicks.
            .gesture(press(size: size), including: engine.state == .finished ? .subviews : .all)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: dragMinutes) { if dragMinutes != nil { Haptics.play(.select) } }
        .onChange(of: engine.state) { old, new in
            // A fresh start (not resuming from pause) sends a comet swirling around the ring.
            if new == .running && (old == .idle || old == .finished) && !reduceMotion { swirlStart = .now }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(engine.phase.title), \(clockText) \(engine.state == .paused ? "paused" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { engine.primaryAction() }
    }

    private func dial(size: CGFloat, fraction: Double, date: Date) -> some View {
        let radius = (size - lineWidth) / 2
        let rainbow = prefs.ringTheme == .rainbow
        let flowing = isFlowing
        // Flowtime focus has no fill and no dot: just the track and, once started, the current.
        let flowFocus = engine.isFlowtime && engine.phase == .focus && engine.state != .finished
        let knobHidden = flowFocus || (engine.state == .idle && dragMinutes == nil && !engine.isFlowtime)
        return ZStack {
            BreathingDisc(active: engine.phase.isBreak && engine.state == .running)
                .padding(lineWidth * 4)

            Circle()
                .inset(by: lineWidth / 2)
                .stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)

            Group {
                Group {
                    if rainbow {
                        // A soft halo under the ring, then the ring itself.
                        arc(fraction).stroke(Self.spectrum(scheme), style: stroke(lineWidth * 1.6))
                            .blur(radius: lineWidth * 1.8)
                            .opacity(scheme == .dark ? 0.9 : 0.6)
                        arc(fraction).stroke(Self.spectrum(scheme), style: stroke(lineWidth))
                    } else {
                        arc(fraction).stroke(Color.ink(scheme), style: stroke(lineWidth))
                    }
                }
                .opacity(flowFocus ? 0 : 1)

                if flowing {
                    flowCurrent(at: date)
                } else {
                    swirl(at: date)
                }

                Circle()
                    .fill(rainbow ? Self.hue(at: fraction, scheme) : Color.ink(scheme))
                    .shadow(color: rainbow ? Self.hue(at: fraction, scheme).opacity(0.8) : .clear, radius: lineWidth * 1.4)
                    .frame(width: lineWidth * 2.2, height: lineWidth * 2.2)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(360 * fraction))
                    .opacity(knobHidden ? 0 : 1)
            }
            // While running, the colors drift slowly around the ring.
            .hueRotation(.degrees(rainbow && engine.state == .running
                                  ? date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 24) * 15 : 0))

            center(size: size)
        }
        .animation(.spring(duration: 0.6, bounce: 0.2), value: engine.state)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: dragMinutes)
    }

    /// A bright comet that whips around the ring twice as a session starts, slowing and fading out.
    @ViewBuilder
    private func swirl(at date: Date) -> some View {
        if let start = swirlStart {
            let t = date.timeIntervalSince(start) / Self.swirlDuration
            if t >= 0 && t < 1 {
                let eased = 1 - pow(1 - t, 3)
                comet(color: prefs.ringTheme == .rainbow ? Self.hue(at: eased * 2, scheme) : Color.ink(scheme),
                      tail: 0.32, headAngle: 720 * eased)
                    .opacity(min(1, t / 0.12) * min(1, (1 - t) / 0.35))
            }
        }
    }

    /// A Flowtime focus session that has started: it has no end, so the ring shows a current instead.
    private var isFlowing: Bool {
        engine.isFlowtime && engine.phase == .focus && (engine.state == .running || engine.state == .paused)
    }

    private static let flowLap: TimeInterval = 7

    /// Flowtime's ring: a comet that keeps circling for as long as you're in the flow, one lap
    /// every few seconds, over the bare track (no fill, no dot — there's no end to count toward).
    /// On start it whips around twice and settles into its cruising speed (the start swirl
    /// flows straight into it, no seam). Pausing freezes and dims it.
    private func flowCurrent(at date: Date) -> some View {
        let elapsed = engine.elapsed(at: date)
        var turns = elapsed / Self.flowLap
        var fadeIn = 1.0
        if let start = swirlStart {
            let t = date.timeIntervalSince(start) / Self.swirlDuration
            if t >= 0 && t < 1 {
                // Two extra laps that ease out to nothing: speed lands exactly on the cruise speed.
                turns += 2 * (1 - pow(1 - t, 3))
                fadeIn = min(1, t / 0.12)
            }
        }
        let head = turns.truncatingRemainder(dividingBy: 1)
        return comet(color: prefs.ringTheme == .rainbow ? Self.hue(at: head, scheme) : Color.ink(scheme),
                     tail: 0.3, headAngle: 360 * head)
            .opacity(fadeIn * (engine.state == .paused ? 0.4 : 1))
    }

    /// A glowing streak along the ring whose bright head sits at `headAngle` (0 = 12 o'clock) and
    /// whose tail fades out behind it.
    private func comet(color: Color, tail: Double, headAngle: Double) -> some View {
        let shape = Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: tail)
            .stroke(AngularGradient(colors: [color.opacity(0), color], center: .center,
                                    startAngle: .zero, endAngle: .degrees(360 * tail)),
                    style: stroke(lineWidth * 1.15))
        return ZStack {
            shape.blur(radius: lineWidth * 1.5).opacity(0.8)
            shape
        }
        .rotationEffect(.degrees(-90 - 360 * tail + headAngle))
        .allowsHitTesting(false)
    }

    /// The filled part of the ring, starting at 12 o'clock.
    private func arc(_ fraction: Double) -> some Shape {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: fraction)
            .rotation(.degrees(-90))
    }

    private func stroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round)
    }

    private static let hueStops = 12

    /// The rainbow around the ring, starting and ending on the same red so there's no seam.
    /// Angles are measured from 12 o'clock, matching `arc`.
    static func spectrum(_ scheme: ColorScheme) -> AngularGradient {
        let colors = (0...hueStops).map { hue(at: Double($0) / Double(hueStops), scheme) }
        return AngularGradient(colors: colors, center: .center,
                               startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    /// The rainbow's color at a point around the ring (0 = top, 1 = all the way round).
    static func hue(at position: Double, _ scheme: ColorScheme) -> Color {
        Color(hue: position.truncatingRemainder(dividingBy: 1),
              saturation: scheme == .dark ? 0.7 : 0.8,
              brightness: scheme == .dark ? 1 : 0.92)
    }

    private func center(size: CGFloat) -> some View {
        VStack(spacing: size * 0.015) {
            // Sessions until the long break, just above the time.
            if prefs.longBreaksEnabled && prefs.showCycleDots && !showsRating {
                CycleDots()
                    .padding(.bottom, size * 0.01)
                    .transition(.blurReplace)
            }
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
                HStack(spacing: size * 0.02) {
                    if let symbol = actionSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: max(8, size * 0.04), weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Text(subtitle)
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .contentTransition(.opacity)
                }
                .font(.system(size: max(10, size * 0.05), weight: .semibold))
                .foregroundStyle(.secondary)
                .animation(.snappy, value: subtitle)
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

    /// The ring is the button, so its label says what a tap will do.
    private var actionSymbol: String? {
        guard dragMinutes == nil else { return nil }
        switch engine.state {
        case .idle, .paused: return "play.fill"
        case .running: return hovering ? "pause.fill" : nil
        case .finished: return nil
        }
    }

    private var subtitle: String {
        switch engine.state {
        case .idle: dragMinutes == nil ? "Start" : "Release to set"
        case .running: hovering ? "Pause" : (engine.isFlowtime ? "Flowtime" : engine.phase.title)
        case .paused: "Resume"
        case .finished: engine.phase == .focus ? (engine.isCountingOvertime ? "In the flow" : "Session complete") : "Break's over"
        }
    }

    /// One gesture for the whole ring: a click anywhere starts or pauses;
    /// while idle, dragging around it sets the minutes like a kitchen timer.
    private func press(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let moved = hypot(value.translation.width, value.translation.height)
                guard engine.state == .idle, !engine.isFlowtime, moved > 6 || dragMinutes != nil else { return }
                let dx = value.location.x - size / 2
                let dy = value.location.y - size / 2
                var angle = atan2(dx, -dy)
                if angle < 0 { angle += 2 * .pi }
                var minutes = Int((angle / (2 * .pi) * 60).rounded())
                if minutes == 0 { minutes = (dragMinutes ?? 0) > 30 ? 60 : 1 }
                if minutes != dragMinutes { dragMinutes = minutes }
            }
            .onEnded { value in
                if let dragMinutes {
                    engine.setIdleMinutes(dragMinutes)
                    self.dragMinutes = nil
                } else if hypot(value.translation.width, value.translation.height) < 12 {
                    engine.primaryAction()
                }
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
            .onChange(of: current) { Haptics.play(.select) }
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
