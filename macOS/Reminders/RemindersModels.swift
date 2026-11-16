import AppKit
import Observation

/// One Reminders list the box can show.
struct ReminderList: Identifiable, Hashable {
    var id: String
    var title: String
    /// Account it belongs to ("iCloud", an Exchange address).
    var group: String
    var color: NSColor
    var isWritable: Bool
}

/// One open reminder, as the box shows it.
struct ReminderItem: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var due: Date?
    /// False for a reminder due on a day without a time.
    var dueHasTime: Bool
    /// 0 none, 1 high … 9 low (EventKit's scale).
    var priority: Int
    var created: Date?

    /// Overdue: a timed one whose time has passed, or a dated one from an earlier day.
    func isOverdue(at now: Date) -> Bool {
        guard let due else { return false }
        return dueHasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }
}

/// All Reminders settings. Mac only, like the calendar's.
@Observable
@MainActor
final class RemindersSettings {
    static let shared = RemindersSettings()

    @ObservationIgnored private let store = UserDefaults.standard

    /// The master switch: the box next to the timer.
    var enabled: Bool = false { didSet { store.set(enabled, forKey: Key.enabled) } }
    /// The list shown. Empty = the list new reminders go to.
    var listID: String = "" { didSet { store.set(listID, forKey: Key.listID) } }
    var side: PanelSide = .right { didSet { store.set(side.rawValue, forKey: Key.side) } }
    /// Hovering the box's outer edge offers to tuck it away behind the bubble.
    var collapsible: Bool = true { didSet { store.set(collapsible, forKey: Key.collapsible) } }
    var collapsed: Bool = false { didSet { store.set(collapsed, forKey: Key.collapsed) } }
    /// The box's width, as you last dragged it.
    var panelWidth: CGFloat = SidePanels.defaultWidth { didSet { store.set(Double(panelWidth), forKey: Key.panelWidth) } }
    /// Only what's due today or overdue, not everything on the list.
    var onlyDue: Bool = false { didSet { store.set(onlyDue, forKey: Key.onlyDue) } }
    /// Clicking a reminder fills in the intention.
    var useAsIntention: Bool = true { didSet { store.set(useAsIntention, forKey: Key.useAsIntention) } }

    var panelVisible: Bool { enabled }

    private init() {
        store.register(defaults: [
            Key.enabled: false,
            // The calendar box defaults to the left, so this one starts on the right.
            Key.side: PanelSide.right.rawValue,
            Key.onlyDue: false,
            Key.useAsIntention: true,
            Key.panelWidth: Double(SidePanels.defaultWidth),
            // Tucking away is offered from the box's edge unless switched off.
            Key.collapsible: true,
        ])
        load()
    }

    func resetToDefaults() {
        for key in Key.all { store.removeObject(forKey: key) }
        load()
    }

    private func load() {
        enabled = store.bool(forKey: Key.enabled)
        listID = store.string(forKey: Key.listID) ?? ""
        side = PanelSide(rawValue: store.string(forKey: Key.side) ?? "") ?? .right
        onlyDue = store.bool(forKey: Key.onlyDue)
        useAsIntention = store.bool(forKey: Key.useAsIntention)
        panelWidth = CalendarSettings.width(store.double(forKey: Key.panelWidth))
        collapsible = store.bool(forKey: Key.collapsible)
        collapsed = store.bool(forKey: Key.collapsed)
    }

    private enum Key {
        static let enabled = "remindersEnabled"
        static let listID = "remindersListID"
        static let side = "remindersSide"
        static let onlyDue = "remindersOnlyDue"
        static let useAsIntention = "remindersUseAsIntention"
        static let panelWidth = "remindersPanelWidth"
        static let collapsible = "remindersCollapsible"
        static let collapsed = "remindersCollapsed"
        static let all = [enabled, listID, side, onlyDue, useAsIntention, panelWidth, collapsible, collapsed]
    }
}
