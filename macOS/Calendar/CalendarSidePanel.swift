import SwiftUI
import AppKit

/// The events box beside the bubble, tucked behind its left or right edge the way the Link strip
/// tucks under its bottom. What's on now, what's next, and a nudge when a session would run into
/// the next event. Click an event to make it your intention; ▶ starts focusing on it.
struct CalendarSidePanel: View {
    /// The whole box, including the part tucked behind the bubble.
    static let width: CGFloat = 214
    static let tuck: CGFloat = 14
    /// Where it starts below the bubble's top edge (under the nub and the header), and how tall it is.
    static let topInset: CGFloat = 46
    static let height: CGFloat = 292

    /// How far the bubble sits from the window's leading edge because of the box.
    @MainActor static var leadingRoom: CGFloat {
        let settings = CalendarSettings.shared
        return settings.panelVisible && settings.side == .left ? width - tuck : 0
    }

    var side: CalendarSide
    var isOpen: Bool

    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .padding(side == .left ? .leading : .trailing, 12)
        .padding(side == .left ? .trailing : .leading, Self.tuck + 8)
        .frame(width: Self.width, height: Self.height, alignment: .top)
        .glassPanel(in: shape)
        .contentShape(shape)
        // Slides out from behind the bubble once it has opened.
        .offset(x: isOpen ? 0 : (side == .left ? Self.width : -Self.width))
        .opacity(isOpen ? 1 : 0)
        .animation(.spring(duration: 0.5, bounce: 0.2).delay(isOpen ? 0.12 : 0), value: isOpen)
        .frame(width: Self.width, height: Self.height)
        .clipped()
        .padding(.top, Self.topInset)
    }

    private var shape: UnevenRoundedRectangle {
        side == .left
            ? UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
            : UnevenRoundedRectangle(bottomTrailingRadius: 20, topTrailingRadius: 20)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(now: now)
            switch sync.status {
            case .off, .notConnected:
                message(symbol: "calendar.badge.plus", text: connectText) {
                    Button("Connect") { sync.connect() }
                        .controlSize(.small)
                }
            case .connecting where sync.events.isEmpty:
                message(symbol: "hourglass", text: "Waiting for \(CalendarSettings.shared.source.title)…") {
                    Button("Cancel") { sync.cancelConnecting() }
                        .controlSize(.small)
                }
            case .failed(let reason) where sync.events.isEmpty:
                message(symbol: "exclamationmark.triangle", text: reason) {
                    Button("Try Again") { sync.refresh() }
                        .controlSize(.small)
                }
            default:
                EventList(now: now)
            }
        }
    }

    private var connectText: String {
        CalendarSettings.shared.source == .apple
            ? "See today's events here and focus on them."
            : "Sign in to Google to see today's events here."
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.headline)
            Text(now.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if sync.status == .ready {
                Button {
                    sync.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func message<Action: View>(symbol: String, text: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Today's remaining events, then tomorrow's, and the nudge about the next one at the bottom.
private struct EventList: View {
    var now: Date
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        let upcoming = sync.upcoming(at: now)
        let calendar = Calendar.current
        let today = upcoming.filter { $0.start < now || calendar.isDate($0.start, inSameDayAs: now) }
        let tomorrow = upcoming.filter { !($0.start < now || calendar.isDate($0.start, inSameDayAs: now)) }
        let current = sync.current(at: now)

        VStack(alignment: .leading, spacing: 6) {
            if upcoming.isEmpty {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: "sun.max")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Nothing else today.\nAll yours.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 3) {
                        if today.isEmpty {
                            Text("Nothing else today")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                        }
                        ForEach(today) { item in
                            EventRow(item: item, now: now, isCurrent: item.id == current?.id)
                        }
                        if !tomorrow.isEmpty {
                            Text("Tomorrow")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, today.isEmpty ? 0 : 8)
                                .padding(.bottom, 2)
                            ForEach(Array(tomorrow.prefix(6))) { item in
                                EventRow(item: item, now: now, isCurrent: false)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            nudge
        }
        .animation(.snappy, value: sync.events)
    }

    /// When the session (about to start, or running) would end after the next event begins.
    @ViewBuilder
    private var nudge: some View {
        if let next = sync.next(after: now), let sessionEnd, next.start < sessionEnd {
            let minutes = max(0, Int(next.start.timeIntervalSince(now) / 60))
            let canFit = engine.state == .idle && minutes >= 5
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 0) {
                    Text(next.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(minutes == 0 ? "starts now" : "starts in \(minutes) min")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                if canFit {
                    Button("Fit \(minutes)m") {
                        Haptics.play(.select)
                        engine.setIdleMinutes(minutes)
                    }
                    .controlSize(.mini)
                    .help("Make this session end before \(next.title) starts")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            .accessibilityElement(children: .combine)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// When the focus session would end: the one about to start, or the one running. Flowtime has no end.
    private var sessionEnd: Date? {
        guard engine.phase == .focus else { return nil }
        switch engine.state {
        case .idle: return prefs.isFlowtime ? nil : now.addingTimeInterval(engine.total)
        case .running: return engine.isFlowtime ? nil : engine.endDate
        case .paused, .finished: return nil
        }
    }
}

private struct EventRow: View {
    var item: CalendarItem
    var now: Date
    var isCurrent: Bool
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    @State private var hovering = false
    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: item.color))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if canStart && (hovering || isCurrent) {
                Button {
                    Haptics.play(.start)
                    sync.focus(on: item)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isCurrent ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(isCurrent ? 0.9 : 0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(startHelp)
                .transition(.opacity.combined(with: .scale(0.8)))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isCurrent ? 0.09 : (hovering ? 0.05 : 0)))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .onTapGesture {
            Haptics.play(.select)
            sync.use(item)
        }
        .help(CalendarSettings.shared.useEventAsIntention ? "Click to make this your intention" : item.title)
        .contextMenu {
            if canStart {
                Button("Focus on This") { sync.focus(on: item) }
                if isCurrent, minutesLeft >= 1, !prefs.isFlowtime {
                    Button("Focus Until It Ends (\(minutesLeft) min)") { sync.focus(on: item, untilItEnds: true) }
                }
            }
            if CalendarSettings.shared.useEventAsIntention {
                Button("Use as Intention") { sync.use(item) }
            }
            if let link = item.link {
                Divider()
                Button("Open in Calendar") { NSWorkspace.shared.open(link) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Only before a session starts; while one runs, a click just changes its intention.
    private var canStart: Bool {
        !engine.isActive && item.end > now && !item.isAllDay
    }

    private var minutesLeft: Int { Int(item.end.timeIntervalSince(now) / 60) }

    private var startHelp: String {
        guard isCurrent, !prefs.isFlowtime else { return "Focus on this now" }
        return "Focus on this for \(min(prefs.focusMinutes, max(1, minutesLeft))) min"
    }

    private var timeLabel: String {
        if item.isAllDay { return "All day" }
        let time = Date.FormatStyle.dateTime.hour().minute()
        if isCurrent {
            return minutesLeft >= 60
                ? "Now · until \(item.end.formatted(time))"
                : "Now · \(max(1, minutesLeft)) min left"
        }
        let until = Int(item.start.timeIntervalSince(now) / 60)
        if until >= 0 && until < 60 { return "\(item.start.formatted(time)) · in \(max(1, until)) min" }
        return "\(item.start.formatted(time))–\(item.end.formatted(time))"
    }
}
