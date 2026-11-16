import SwiftUI

/// Which side of the timer a box sits on.
enum PanelSide: String, CaseIterable, Identifiable {
    case left, right
    var id: Self { self }
    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
    var opposite: PanelSide { self == .left ? .right : .left }
}

/// The boxes that can hang off the bubble's sides: today's events and a reminders list.
/// One per side; when both are on, each keeps its own side and they swap when you move one.
enum SidePanels {
    enum Kind { case calendar, reminders }

    /// The whole box, including the part tucked behind the bubble.
    static let width: CGFloat = 214
    static let tuck: CGFloat = 14
    /// Where it starts below the bubble's top edge (under the nub and the header), and how tall it is.
    static let topInset: CGFloat = 46
    static let height: CGFloat = 292
    /// What one box adds to the window's width.
    static var room: CGFloat { width - tuck }

    /// What sits on each side right now. The calendar keeps its side; reminders take theirs,
    /// or the other one if the calendar is already there.
    @MainActor static var layout: (left: Kind?, right: Kind?) {
        let calendar = CalendarSettings.shared
        let reminders = RemindersSettings.shared
        var left: Kind?
        var right: Kind?
        if calendar.panelVisible {
            if calendar.side == .left { left = .calendar } else { right = .calendar }
        }
        if reminders.panelVisible {
            let wanted = reminders.side
            if wanted == .left ? left == nil : right == nil {
                if wanted == .left { left = .reminders } else { right = .reminders }
            } else if wanted == .left {
                right = .reminders
            } else {
                left = .reminders
            }
        }
        return (left, right)
    }

    /// Where a box actually is (it can differ from its setting while both wanted the same side).
    @MainActor static func side(of kind: Kind) -> PanelSide? {
        let layout = layout
        if layout.left == kind { return .left }
        if layout.right == kind { return .right }
        return nil
    }

    /// Moves a box to a side; the other box, if it's on, moves across to make room.
    @MainActor static func place(_ kind: Kind, on side: PanelSide) {
        let calendar = CalendarSettings.shared
        let reminders = RemindersSettings.shared
        switch kind {
        case .calendar:
            calendar.side = side
            if reminders.panelVisible { reminders.side = side.opposite }
        case .reminders:
            reminders.side = side
            if calendar.panelVisible { calendar.side = side.opposite }
        }
    }

    /// How far the bubble sits from the window's leading edge because of a box on the left.
    @MainActor static var leadingRoom: CGFloat { layout.left == nil ? 0 : room }

    /// The window's extra width for the boxes on both sides.
    @MainActor static var extraWidth: CGFloat {
        let layout = layout
        return (layout.left == nil ? 0 : room) + (layout.right == nil ? 0 : room)
    }
}

extension SidePanels {
    /// A binding for a Side picker in Settings: shows where the box really is, moving it swaps.
    @MainActor static func sideBinding(for kind: Kind) -> Binding<PanelSide> {
        Binding {
            side(of: kind) ?? (kind == .calendar ? CalendarSettings.shared.side : RemindersSettings.shared.side)
        } set: { side in
            withAnimation(.snappy) { place(kind, on: side) }
        }
    }
}

/// The glass a side box is drawn on: rounded on the outside, tucked behind the bubble on the
/// inside, sliding out from behind it once the bubble has opened.
struct SideBox<Content: View>: View {
    var side: PanelSide
    var isOpen: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.top, 12)
            .padding(.bottom, 10)
            .padding(side == .left ? .leading : .trailing, 12)
            .padding(side == .left ? .trailing : .leading, SidePanels.tuck + 8)
            .frame(width: SidePanels.width, height: SidePanels.height, alignment: .top)
            .glassPanel(in: shape)
            .contentShape(shape)
            .offset(x: isOpen ? 0 : (side == .left ? SidePanels.width : -SidePanels.width))
            .opacity(isOpen ? 1 : 0)
            .animation(.spring(duration: 0.5, bounce: 0.2).delay(isOpen ? 0.12 : 0), value: isOpen)
            .frame(width: SidePanels.width, height: SidePanels.height)
            .clipped()
            .padding(.top, SidePanels.topInset)
    }

    private var shape: UnevenRoundedRectangle {
        side == .left
            ? UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
            : UnevenRoundedRectangle(bottomTrailingRadius: 20, topTrailingRadius: 20)
    }
}

/// A small round icon button for a box's header and rows.
struct SideBoxIconButton: View {
    var symbol: String
    var help: String
    var size: CGFloat = 10
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A centred symbol, a line of text and a button, for a box with nothing to list yet.
struct SideBoxMessage<Action: View>: View {
    var symbol: String
    var text: String
    @ViewBuilder var action: Action

    var body: some View {
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
            action
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Opens an app by bundle ID, if it's installed.
@MainActor
func openApp(_ bundleID: String) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
}
