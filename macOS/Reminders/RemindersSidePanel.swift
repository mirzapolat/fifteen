import SwiftUI
import AppKit

/// A Reminders list beside the bubble, on the side the calendar box isn't. Tick things off,
/// add new ones with +, click one to make it your intention, ▶ to focus on it.
struct RemindersSidePanel: View {
    var side: PanelSide
    var isOpen: Bool

    @State private var adding = false
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        SideBox(side: side, isOpen: isOpen) {
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
                Text(list.title)
                    .font(.headline)
                    .foregroundStyle(Color(nsColor: list.color))
                    .lineLimit(1)
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
        .accessibilityAddTraits(.isHeader)
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
                    ScrollView(.vertical) {
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
                                            removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading))
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
                    .scrollIndicators(.never)
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
    /// "Today" and its priorities on top, then everything else (headed only when both are there).
    fileprivate var rows: [Row] {
        let ordered = sync.ordered
        guard !ordered.today.isEmpty else { return ordered.rest.map { .reminder($0, priority: false) } }
        var rows: [Row] = [.heading("Today", star: true)]
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

/// The round tick, filling with the list's colour when ticked.
private struct ReminderCheck: View {
    var ticked: Bool
    var color: Color
    var dashed = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ticked ? color : Color.secondary.opacity(0.6),
                              style: StrokeStyle(lineWidth: 1.3, dash: dashed ? [2.2, 2.2] : []))
            Circle()
                .fill(color)
                .padding(3)
                .scaleEffect(ticked ? 1 : 0.01)
                .opacity(ticked ? 1 : 0)
        }
        .frame(width: 15, height: 15)
        .animation(.spring(duration: 0.3, bounce: 0.5), value: ticked)
    }
}

private struct ReminderRow: View {
    var item: ReminderItem
    var color: Color
    var isPriority = false
    @Environment(TimerEngine.self) private var engine
    @State private var hovering = false
    private var sync: RemindersSync { RemindersSync.shared }

    var body: some View {
        let ticked = sync.completing.contains(item.id)
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
                (priorityMarks + Text(item.title))
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(ticked, color: .secondary)
                    .foregroundStyle(ticked ? .secondary : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
            if (hovering || isPriority) && !ticked {
                HStack(spacing: 2) {
                    PriorityStar(isOn: isPriority, color: color) {
                        Haptics.play(.select)
                        sync.togglePriority(item)
                    }
                    if hovering {
                        SideBoxIconButton(symbol: "arrow.up.forward.app", help: "Open in Reminders", size: 9.5) {
                            sync.open(item)
                        }
                        .transition(.opacity.combined(with: .scale(0.8)))
                    }
                    if hovering && !engine.isActive {
                        Button {
                            Haptics.play(.start)
                            sync.focus(on: item)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.primary.opacity(0.12)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Focus on this now")
                        .transition(.opacity.combined(with: .scale(0.8)))
                    }
                }
                .transition(.opacity.combined(with: .scale(0.8)))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            if isPriority && !ticked {
                // Today's priorities glow faintly in the list's colour.
                shape.fill(color.opacity(hovering ? 0.2 : 0.13))
                    .overlay(shape.strokeBorder(color.opacity(0.28), lineWidth: 0.75))
            } else {
                shape.fill(Color.primary.opacity(hovering ? 0.05 : 0))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: isPriority)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.18), value: hovering)
        .onTapGesture {
            guard sync.remindersBecomeIntention, !ticked else { return }
            Haptics.play(.select)
            sync.use(item)
        }
        .help(sync.remindersBecomeIntention ? "Click to make this your intention" : item.title)
        .contextMenu {
            if !engine.isActive { Button("Focus on This") { sync.focus(on: item) } }
            if sync.remindersBecomeIntention { Button("Use as Intention") { sync.use(item) } }
            Button(ticked ? "Not Done" : "Mark as Done") { sync.toggle(item) }
            Button(isPriority ? "Remove from Today" : "Make a Priority for Today") { sync.togglePriority(item) }
            Divider()
            Button("Open in Reminders") { sync.open(item) }
        }
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
        .help(isOn ? "Remove from Today" : "Make a Priority for Today")
        .accessibilityLabel(isOn ? "Remove from today's priorities" : "Make a priority for today")
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
