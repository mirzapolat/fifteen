import SwiftUI
import AppKit

/// A Reminders list beside the bubble, on the side the calendar box isn't. Tick things off,
/// add new ones with +, click one to make it your intention, ▶ to focus on it.
struct RemindersSidePanel: View {
    var side: PanelSide
    var isOpen: Bool
    var top: CGFloat

    @State private var adding = false
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        SideBox(kind: .reminders, side: side, isOpen: isOpen, top: top, symbol: "checklist",
                count: sync.status == .ready ? sync.items.count - sync.completing.count : nil) {
            VStack(alignment: .leading, spacing: 8) {
                header
                content
            }
        }
        // Closing the bubble closes the new-reminder row (what was typed is still added).
        .onChange(of: isOpen) { if !isOpen { adding = false } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            if let list = sync.list, sync.status == .ready {
                listMenu(list)
                let open = sync.items.count - sync.completing.count
                if open > 0 {
                    Text("\(open)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: open)
                }
            } else {
                Text("Reminders")
                    .font(.headline)
            }
            Spacer(minLength: 0)
            if sync.status == .ready {
                HStack(spacing: 0) {
                    if sync.list?.isWritable == true {
                        SideBoxIconButton(symbol: "plus", help: "New Reminder", size: 11) {
                            Haptics.play(.select)
                            withAnimation(.spring(duration: 0.35, bounce: 0.25)) { adding = true }
                        }
                    }
                    SideBoxIconButton(symbol: "arrow.up.forward.app", help: "Open Reminders") { sync.open() }
                }
                .padding(.trailing, -4)
            }
        }
        .frame(height: 20)
        // In line with the reminders below, so the title keeps the same distance from the timer.
        .padding(.horizontal, 8)
        .accessibilityAddTraits(.isHeader)
    }

    /// The list's name; click it to show another list.
    private func listMenu(_ list: ReminderList) -> some View {
        let groups = Dictionary(grouping: sync.lists, by: \.group)
        let names = groups.keys.sorted()
        return Menu {
            // Grouped by account only when there's more than one: an empty heading shows as a blank line.
            if names.count > 1 {
                ForEach(names, id: \.self) { group in
                    Section(group) { options(groups[group] ?? [], current: list) }
                }
            } else {
                options(sync.lists, current: list)
            }
        } label: {
            HStack(spacing: 4) {
                Text(list.title)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show another list")
    }

    private func options(_ lists: [ReminderList], current: ReminderList) -> some View {
        ForEach(lists) { option in
            Button {
                Haptics.play(.select)
                RemindersSettings.shared.listID = option.id
            } label: {
                Label {
                    Text(option.title)
                } icon: {
                    Image(nsImage: option.id == current.id
                          ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Shown") ?? ListDot.image(option.color)
                          : ListDot.image(option.color))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sync.status {
        case .off, .notConnected:
            if sync.isDenied {
                SideBoxMessage(symbol: "checklist", text: "Allow Fifteen under Privacy & Security → Reminders.") {
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                    }
                    .controlSize(.small)
                }
            } else {
                SideBoxMessage(symbol: "checklist", text: "See a Reminders list here and tick things off as you go.") {
                    Button("Connect") { sync.connect() }
                        .controlSize(.small)
                }
            }
        case .failed(let reason):
            SideBoxMessage(symbol: "exclamationmark.triangle", text: reason) {
                Button("Try Again") { sync.refresh() }
                    .controlSize(.small)
            }
        case .ready:
            if sync.list == nil {
                SideBoxMessage(symbol: "list.bullet", text: "No lists in Reminders yet.") {
                    Button("Open Reminders") { sync.open() }
                        .controlSize(.small)
                }
            } else {
                ReminderListView(adding: $adding)
            }
        }
    }
}

/// The open reminders, and the row for a new one at the bottom while adding.
private struct ReminderListView: View {
    @Binding var adding: Bool
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        let color = Color(nsColor: sync.list?.color ?? .controlAccentColor)
        let empty = sync.items.isEmpty && !adding
        ZStack(alignment: .top) {
            if empty {
                SideBoxMessage(symbol: "checkmark.circle",
                               text: RemindersSettings.shared.onlyDue ? "Nothing due today." : "All done.") {
                    if sync.list?.isWritable == true {
                        Button("Add Reminder") {
                            withAnimation(.spring(duration: 0.35, bounce: 0.25)) { adding = true }
                        }
                        .controlSize(.small)
                    }
                }
                .transition(.opacity.combined(with: .scale(0.96)))
            } else {
                ScrollViewReader { proxy in
                    FadingScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            // One list for both groups, so a starred row glides up instead of jumping.
                            ForEach(rows) { row in
                                switch row {
                                case .heading(let title, let star):
                                    SectionHeading(title: title, star: star, color: color)
                                        .transition(.opacity)
                                case .reminder(let item, let priority):
                                    ReminderRow(item: item, color: color, isPriority: priority)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity.combined(with: .offset(x: -40)).combined(with: .scale(scale: 0.96, anchor: .leading))
                                        ))
                                }
                            }
                            if adding {
                                NewReminderRow(color: color, adding: $adding)
                                    .id("new")
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .onChange(of: adding) {
                        if adding { withAnimation(.snappy) { proxy.scrollTo("new", anchor: .bottom) } }
                    }
                    .onChange(of: sync.items.count) {
                        if adding { withAnimation(.snappy) { proxy.scrollTo("new", anchor: .bottom) } }
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.4, bounce: 0.2), value: empty)
    }
}

private enum Row: Identifiable {
    case heading(String, star: Bool)
    case reminder(ReminderItem, priority: Bool)

    var id: String {
        switch self {
        case .heading(let title, _): "heading-\(title)"
        case .reminder(let item, _): item.id
        }
    }
}

extension ReminderListView {
    /// "Priorities" on top, then everything else (headed only when both are there).
    fileprivate var rows: [Row] {
        let ordered = sync.ordered
        guard !ordered.today.isEmpty else { return ordered.rest.map { .reminder($0, priority: false) } }
        var rows: [Row] = [.heading("Priorities", star: true)]
        rows += ordered.today.map { .reminder($0, priority: true) }
        if !ordered.rest.isEmpty {
            rows.append(.heading("Later", star: false))
            rows += ordered.rest.map { .reminder($0, priority: false) }
        }
        return rows
    }
}

private struct SectionHeading: View {
    var title: String
    var star: Bool
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            if star {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.top, star ? 0 : 8)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The round tick. Ticking fills it with the list's colour, draws a checkmark and lets off a
/// small burst; un-ticking just empties it again.
private struct ReminderCheck: View {
    var ticked: Bool
    var color: Color
    var dashed = false
    /// Bumped on each tick so the pop and the burst replay, but not on un-tick.
    @State private var bursts = 0

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ticked ? color : Color.secondary.opacity(0.6),
                              style: StrokeStyle(lineWidth: 1.3, dash: dashed ? [2.2, 2.2] : []))
            Circle()
                .fill(color)
                .scaleEffect(ticked ? 1 : 0.01)
                .opacity(ticked ? 1 : 0)
            CheckmarkShape()
                .trim(from: 0, to: ticked ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .padding(4)
                .animation(ticked ? .easeOut(duration: 0.22).delay(0.08) : .easeIn(duration: 0.1), value: ticked)
        }
        .frame(width: 15, height: 15)
        .keyframeAnimator(initialValue: 1.0, trigger: bursts) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.3, duration: 0.12, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
        }
        .background { if !dashed { TickBurst(color: color, trigger: bursts) } }
        .animation(.spring(duration: 0.3, bounce: 0.5), value: ticked)
        .onChange(of: ticked) { _, isTicked in
            if isTicked { bursts += 1 }
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

/// A ring and a handful of sparks that fly out from the tick and fade.
private struct TickBurst: View {
    var color: Color
    var trigger: Int
    private let sparks = 8

    var body: some View {
        if trigger > 0 {
            ZStack {
                Circle().stroke(color, lineWidth: 1.5)
                ForEach(0..<sparks, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 1.8, height: 4)
                        .offset(y: -13)
                        .rotationEffect(.degrees(Double(i) / Double(sparks) * 360))
                }
            }
            .frame(width: 15, height: 15)
            .keyframeAnimator(initialValue: BurstState(), trigger: trigger) { view, state in
                view.scaleEffect(state.scale).opacity(state.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.6, duration: 0.001)
                    CubicKeyframe(1.6, duration: 0.45)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.9, duration: 0.001)
                    LinearKeyframe(0.9, duration: 0.12)
                    CubicKeyframe(0, duration: 0.33)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    struct BurstState { var scale = 1.0; var opacity = 0.0 }
}

private struct ReminderRow: View {
    var item: ReminderItem
    var color: Color
    var isPriority = false
    @Environment(TimerEngine.self) private var engine
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    /// How far the row is swiped left to show Delete (0 when closed).
    @State private var swipe: CGFloat = 0
    @State private var swipeStart: CGFloat = 0
    /// Whether the current trackpad gesture is sideways (a swipe), up and down (a scroll), or not yet known.
    @State private var swipeAxis: Axis?
    @State private var scrollMonitor: Any?
    private var sync: RemindersSync { RemindersSync.shared }
    private var canEdit: Bool { sync.list?.isWritable == true }

    private static let revealWidth: CGFloat = 64
    private static let deleteDistance: CGFloat = 150

    var body: some View {
        let ticked = sync.completing.contains(item.id)
        let highlighted = isPriority && !ticked
        HStack(alignment: .top, spacing: 8) {
            Button {
                Haptics.play(.select)
                sync.toggle(item)
            } label: {
                ReminderCheck(ticked: ticked, color: color)
                    .padding(4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(-4)
            .padding(.top, 1)
            .help(ticked ? "Not Done" : "Mark as Done")
            .accessibilityLabel(ticked ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TextField("Reminder", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1...4)
                        .focused($focused)
                        .onSubmit(save)
                        .onExitCommand(perform: cancel)
                        .onChange(of: focused) { if !focused && editing { save() } }
                } else {
                    (priorityMarks + Text(item.title))
                        .font(.system(size: 12, weight: .medium))
                        .strikethrough(ticked, color: .secondary)
                        .foregroundStyle(ticked ? .secondary : .primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let due = dueLabel {
                    Text(due.text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(due.overdue && !ticked ? Color.red : Color.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .animation(.easeOut(duration: 0.2), value: ticked)
            Spacer(minLength: 0)
            if (hovering || isPriority) && !ticked && !editing {
                HStack(spacing: 2) {
                    PriorityStar(isOn: isPriority, color: color) {
                        Haptics.play(.select)
                        sync.togglePriority(item)
                    }
                    if hovering && sync.remindersBecomeIntention {
                        SideBoxIconButton(symbol: "text.bubble", help: "Make This Your Intention", size: 10) {
                            Haptics.play(.select)
                            sync.use(item)
                        }
                        .transition(.opacity.combined(with: .scale(0.8)))
                    }
                }
                // As tall as a line of text, so the buttons showing on hover don't make the row grow.
                .frame(height: 15)
                .transition(.opacity.combined(with: .scale(0.8)))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            if highlighted {
                // Priorities glow faintly in the list's colour.
                shape.fill(color.opacity(hovering ? 0.2 : 0.13))
                    .overlay(shape.strokeBorder(color.opacity(0.28), lineWidth: 0.75))
            } else if editing {
                shape.fill(Color.primary.opacity(0.05))
                    .overlay(shape.strokeBorder(color.opacity(0.5), lineWidth: 1))
            } else if ticked {
                // A faint wash of the list's colour while it waits to go.
                shape.fill(color.opacity(0.1))
            } else {
                shape.fill(Color.primary.opacity(hovering ? 0.05 : 0))
            }
        }
        .animation(.easeOut(duration: 0.25), value: ticked)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: highlighted)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        // Swiped left, the row slides over a Delete button that stays where the row was.
        .offset(x: swipe)
        .background(alignment: .trailing) { deleteButton }
        .onHover { inside in
            hovering = inside
            if inside { watchSwipes() } else { stopWatchingSwipes() }
        }
        .onDisappear { stopWatchingSwipes() }
        .animation(.snappy(duration: 0.18), value: hovering)
        // Clicking the row edits its text (or opens a read-only one in Reminders); only the circle
        // ticks it off. While editing, clicks belong to the text field.
        .gesture(TapGesture().onEnded {
            if swipe != 0 { return closeSwipe() }
            startEditing(ticked: ticked)
        }, including: editing ? .subviews : .all)
        .help(editing ? "" : (canEdit ? "Click to edit" : "Click to open in Reminders"))
        .contextMenu {
            if !engine.isActive { Button("Focus on This") { sync.focus(on: item) } }
            if sync.remindersBecomeIntention { Button("Use as Intention") { sync.use(item) } }
            if canEdit && !ticked { Button("Edit") { startEditing(ticked: ticked) } }
            Button(ticked ? "Not Done" : "Mark as Done") { sync.toggle(item) }
            Button(isPriority ? "Remove from Priorities" : "Make a Priority") { sync.togglePriority(item) }
            Divider()
            Button("Open in Reminders") { sync.open(item) }
            if canEdit {
                Button("Delete", role: .destructive) { delete() }
            }
        }
    }

    // MARK: Swipe to delete

    private var deleteButton: some View {
        Button(action: delete) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red)
                .overlay {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .scaleEffect(min(1, -swipe / Self.revealWidth))
                }
                .frame(width: max(0, -swipe - 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(swipe < 0 ? 1 : 0)
        .help("Delete")
        .accessibilityLabel("Delete reminder")
    }

    /// Two-finger swipes on the trackpad while the pointer is over this row. Sideways ones move the
    /// row (and are kept from the list); up-and-down ones are left alone, so the list still scrolls.
    private func watchSwipes() {
        guard scrollMonitor == nil, canEdit else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { handleScroll(event) } ? nil : event
        }
    }

    private func stopWatchingSwipes() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        swipeAxis = nil
        if swipe != 0 { closeSwipe() }
    }

    /// Returns true when the event was a swipe this row used.
    private func handleScroll(_ event: NSEvent) -> Bool {
        // Momentum after a swipe belongs to the swipe; after a scroll, to the list.
        if event.momentumPhase != [] { return swipeAxis == .horizontal }
        if event.phase == .began || event.phase == .mayBegin {
            swipeAxis = nil
            swipeStart = swipe
        }
        if swipeAxis == nil, event.phase == .changed || event.phase == .began {
            let dx = abs(event.scrollingDeltaX), dy = abs(event.scrollingDeltaY)
            if dx + dy < 1 { return false }
            swipeAxis = dx > dy * 1.5 ? .horizontal : .vertical
        }
        guard swipeAxis == .horizontal else { return false }
        switch event.phase {
        case .began, .changed:
            swipeStart += event.scrollingDeltaX
            // Free to the left, a little resistance past closed on the right.
            swipe = swipeStart < 0 ? swipeStart : swipeStart * 0.2
        case .ended, .cancelled:
            if swipe < -Self.deleteDistance {
                delete()
            } else if swipe < -Self.revealWidth / 2 {
                Haptics.play(.select)
                withAnimation(.spring(duration: 0.3, bounce: 0.15)) { swipe = -Self.revealWidth }
            } else {
                closeSwipe()
            }
        default:
            break
        }
        return true
    }

    private func closeSwipe() {
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) { swipe = 0 }
    }

    private func delete() {
        Haptics.play(.select)
        stopWatchingSwipes()
        sync.delete(item)
    }

    private func startEditing(ticked: Bool) {
        guard !ticked else { return }
        Haptics.play(.select)
        guard canEdit else { return sync.open(item) }
        draft = item.title
        withAnimation(.snappy(duration: 0.15)) { editing = true }
        DispatchQueue.main.async { focused = true }
    }

    private func save() {
        guard editing else { return }
        sync.rename(item, to: draft)
        withAnimation(.snappy(duration: 0.15)) { editing = false }
    }

    private func cancel() {
        withAnimation(.snappy(duration: 0.15)) { editing = false }
        focused = false
    }

    /// "!!" for high priority, like the Reminders app.
    private var priorityMarks: Text {
        let marks = switch item.priority {
        case 1...4: "!!! "
        case 5: "!! "
        case 6...9: "! "
        default: ""
        }
        return Text(marks).foregroundColor(color).fontWeight(.bold)
    }

    private var dueLabel: (text: String, overdue: Bool)? {
        guard let due = item.due else { return nil }
        let now = Date()
        let calendar = Calendar.current
        let time = item.dueHasTime ? " · \(due.formatted(.dateTime.hour().minute()))" : ""
        let day: String
        if calendar.isDateInToday(due) {
            day = "Today"
        } else if calendar.isDateInTomorrow(due) {
            day = "Tomorrow"
        } else if calendar.isDateInYesterday(due) {
            day = "Yesterday"
        } else if abs(due.timeIntervalSince(now)) < 6 * 86_400 {
            day = due.formatted(.dateTime.weekday(.wide))
        } else {
            day = due.formatted(.dateTime.day().month(.abbreviated))
        }
        return (day + time, item.isOverdue(at: now))
    }
}

/// ☆ on hover makes a reminder one of today's priorities; ★ stays on the ones that are.
private struct PriorityStar: View {
    var isOn: Bool
    var color: Color
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn ? color : (hovering ? Color.primary : Color.secondary))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isOn)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isOn ? "Remove from Priorities" : "Make a Priority")
        .accessibilityLabel(isOn ? "Remove from priorities" : "Make a priority")
    }
}

/// Typing a new reminder: Return adds it and starts the next, Esc or clicking away stops.
private struct NewReminderRow: View {
    var color: Color
    @Binding var adding: Bool
    @State private var text = ""
    @FocusState private var focused: Bool
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ReminderCheck(ticked: false, color: color, dashed: true)
            TextField("New Reminder", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand(perform: stop)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(focused ? 0.5 : 0.2), lineWidth: 1))
        )
        .animation(.easeInOut(duration: 0.2), value: focused)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: focused) {
            // Clicking away keeps what was typed (like the Reminders app) and closes the row.
            if !focused { stop() }
        }
    }

    private func submit() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return stop() }
        Haptics.play(.select)
        sync.add(title)
        text = ""
        focused = true
    }

    private func stop() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { sync.add(title) }
        text = ""
        guard adding else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.1)) { adding = false }
    }
}
