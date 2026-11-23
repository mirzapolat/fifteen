import SwiftUI
import AppKit

/// The events box beside the bubble, tucked behind its left or right edge the way the Link strip
/// tucks under its bottom. What's on now, what's next, and a nudge when a session would run into
/// the next event. Click an event for what you can do with it: focus on it, make it your
/// intention, join its call, or open it in your calendar.
struct CalendarSidePanel: View {
    var side: PanelSide
    var isOpen: Bool
    var top: CGFloat

    private var sync: CalendarSync { CalendarSync.shared }

    var body: some View {
        TimelineView(.everyMinute) { context in
            SideBox(kind: .calendar, side: side, isOpen: isOpen, top: top, symbol: "calendar",
                    count: sync.status == .ready ? eventsLeftToday(now: context.date) : nil) {
                content(now: context.date)
            }
        }
    }

    /// For the collapsed strip: today's timed events still to come or under way.
    private func eventsLeftToday(now: Date) -> Int {
        sync.upcoming(at: now).filter { !$0.isAllDay && Calendar.current.isDate($0.start, inSameDayAs: now) || $0.isHappening(at: now) }.count
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(now: now)
            switch sync.status {
            case .off, .notConnected:
                SideBoxMessage(symbol: "calendar.badge.plus", text: connectText) {
                    Button("Connect") { sync.connect() }
                        .controlSize(.small)
                }
            case .connecting where sync.events.isEmpty:
                SideBoxMessage(symbol: "hourglass", text: "Waiting for \(CalendarSettings.shared.source.title)…") {
                    Button("Cancel") { sync.cancelConnecting() }
                        .controlSize(.small)
                }
            case .failed(let reason) where sync.events.isEmpty:
                SideBoxMessage(symbol: "exclamationmark.triangle", text: reason) {
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
            HStack(spacing: 0) {
                if sync.status == .ready {
                    SideBoxIconButton(symbol: "arrow.clockwise", help: "Refresh") { sync.refresh() }
                    SideBoxIconButton(symbol: "arrow.up.forward.app", help: openAppHelp) { CalendarSync.openCalendarApp() }
                }
                SideBoxCollapseButton(kind: .calendar, side: side)
            }
            .padding(.trailing, -4)
        }
        // In line with the events below, so the title keeps the same distance from the timer.
        .padding(.horizontal, 8)
        .accessibilityAddTraits(.isHeader)
    }

    private var openAppHelp: String {
        CalendarSettings.shared.source == .apple ? "Open Calendar" : "Open Google Calendar"
    }
}

extension CalendarSync {
    /// The Calendar app, or Google Calendar in the browser.
    static func openCalendarApp() {
        if CalendarSettings.shared.source == .google {
            NSWorkspace.shared.open(URL(string: "https://calendar.google.com")!)
        } else {
            openApp("com.apple.iCal")
        }
    }

    /// An event in the Calendar app (at its day) or on Google Calendar.
    static func open(_ item: CalendarItem) {
        if let link = item.link { NSWorkspace.shared.open(link) } else { openCalendarApp() }
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
                FadingScrollView {
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
            VStack(alignment: .leading, spacing: 4) {
                // Click the event for everything you can do with it (the same menu as a right-click).
                Menu {
                    actions
                } label: {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                if let meeting = item.meeting, item.end > now {
                    JoinButton(meeting: meeting, isSoon: isCurrent || item.start.timeIntervalSince(now) <= 10 * 60)
                }
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
        .help(canStart ? "Click to focus on it or open it" : "Click for more")
        .contextMenu { actions }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var actions: some View {
        if canStart {
            Button("Focus on This", systemImage: "play.fill") { sync.focus(on: item) }
            if isCurrent, minutesLeft >= 1, !prefs.isFlowtime {
                Button("Focus Until It Ends (\(minutesLeft) min)", systemImage: "timer") {
                    sync.focus(on: item, untilItEnds: true)
                }
            }
        }
        if sync.eventsBecomeIntention {
            Button("Use as Intention", systemImage: "text.bubble") {
                Haptics.play(.select)
                sync.use(item)
            }
        }
        if let meeting = item.meeting {
            Button("Join \(meeting.service)", systemImage: "video") { NSWorkspace.shared.open(meeting.url) }
        }
        Divider()
        Button(openHelp, systemImage: "calendar") { CalendarSync.open(item) }
    }

    /// Only before a session starts; while one runs, an event can still become its intention.
    private var canStart: Bool {
        !engine.isActive && item.end > now && !item.isAllDay
    }

    private var openHelp: String {
        CalendarSettings.shared.source == .apple ? "Open in Calendar" : "Open in Google Calendar"
    }

    private var minutesLeft: Int { Int(item.end.timeIntervalSince(now) / 60) }

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

/// "Join Zoom" under an event with a call link: filled in when it's on now or about to start.
private struct JoinButton: View {
    var meeting: MeetingLink
    var isSoon: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            Haptics.play(.select)
            NSWorkspace.shared.open(meeting.url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 8.5, weight: .semibold))
                Text("Join \(meeting.service)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSoon ? Color.white : Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule().fill(isSoon ? Color.accentColor.opacity(hovering ? 1 : 0.88)
                                      : Color.accentColor.opacity(hovering ? 0.22 : 0.13))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
        .animation(.snappy, value: isSoon)
        .help(meeting.url.absoluteString)
    }
}
