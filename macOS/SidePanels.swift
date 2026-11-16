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

    /// A box's width (including the part tucked behind the bubble) unless you've dragged it wider or narrower.
    static let defaultWidth: CGFloat = 214
    static let widthRange: ClosedRange<CGFloat> = 180...420
    static let tuck: CGFloat = 14
    static let height: CGFloat = 292

    /// Where a box starts so it's centred on the bubble's body (the part under the nub).
    static func top(forBubble height: CGFloat) -> CGFloat {
        guard height > 0 else { return 46 }
        let body = height - PopoverView.arrowHeight
        return max(PopoverView.arrowHeight, PopoverView.arrowHeight + (body - self.height) / 2).rounded()
    }
    /// Room around a box for its shadow, kept clear of the clipping that hides it behind the bubble.
    static let shadowRoom: CGFloat = 24

    /// A collapsed box: a slim strip beside the bubble with its symbol and a count.
    static let collapsedWidth: CGFloat = tuck + 34

    /// The width the box takes up now: the strip when collapsed, otherwise its own width.
    @MainActor static func width(of kind: Kind) -> CGFloat {
        isCollapsed(kind) ? collapsedWidth : fullWidth(of: kind)
    }

    /// The box's width when open, as you last dragged it.
    @MainActor static func fullWidth(of kind: Kind) -> CGFloat {
        switch kind {
        case .calendar: CalendarSettings.shared.panelWidth
        case .reminders: RemindersSettings.shared.panelWidth
        }
    }

    @MainActor static func isCollapsible(_ kind: Kind) -> Bool {
        switch kind {
        case .calendar: CalendarSettings.shared.collapsible
        case .reminders: RemindersSettings.shared.collapsible
        }
    }

    /// Collapsed for layout (the window's width). Only while collapsing is switched on in Settings.
    @MainActor static func isCollapsed(_ kind: Kind) -> Bool {
        guard isCollapsible(kind) else { return false }
        switch kind {
        case .calendar: return CalendarSettings.shared.collapsed
        case .reminders: return RemindersSettings.shared.collapsed
        }
    }

    @MainActor private static func storeCollapsed(_ collapsed: Bool, _ kind: Kind) {
        switch kind {
        case .calendar: CalendarSettings.shared.collapsed = collapsed
        case .reminders: RemindersSettings.shared.collapsed = collapsed
        }
    }

    /// Collapsing slides the box behind the bubble first and only then narrows the window;
    /// expanding widens the window first and then slides the box out. Either way the bubble
    /// never moves and nothing gets cut off mid-animation.
    @MainActor static func toggleCollapsed(_ kind: Kind) {
        let chrome = SideBoxChrome.shared
        if isCollapsed(kind) {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                storeCollapsed(false, kind)
                onResize?()
            }
            Task { @MainActor in
                withAnimation(.spring(duration: 0.45, bounce: 0.18)) { chrome.looksCollapsed[kind] = false }
            }
        } else {
            withAnimation(.spring(duration: 0.4, bounce: 0.1)) { chrome.looksCollapsed[kind] = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                guard chrome.looksCollapsed[kind] == true else { return }
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    storeCollapsed(true, kind)
                    onResize?()
                }
            }
        }
    }

    @MainActor static func setWidth(_ width: CGFloat, of kind: Kind) {
        let width = min(max(width.rounded(), widthRange.lowerBound), widthRange.upperBound)
        switch kind {
        case .calendar: CalendarSettings.shared.panelWidth = width
        case .reminders: RemindersSettings.shared.panelWidth = width
        }
        onResize?()
    }

    /// Called while a box is being resized, so the window can grow or shrink with it.
    @MainActor static var onResize: (() -> Void)?

    /// What a box adds to the window's width.
    @MainActor static func room(of kind: Kind) -> CGFloat { width(of: kind) - tuck }

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
    @MainActor static var leadingRoom: CGFloat { layout.left.map(room(of:)) ?? 0 }

    /// The window's extra width for the boxes on both sides.
    @MainActor static var extraWidth: CGFloat {
        let layout = layout
        return (layout.left.map(room(of:)) ?? 0) + (layout.right.map(room(of:)) ?? 0)
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

/// How collapsed each box looks right now, which runs a moment ahead of (collapsing) or behind
/// (expanding) the stored state that sizes the window.
@Observable
@MainActor
final class SideBoxChrome {
    static let shared = SideBoxChrome()
    var looksCollapsed: [SidePanels.Kind: Bool] = [:]

    func looksCollapsed(_ kind: SidePanels.Kind) -> Bool {
        looksCollapsed[kind] ?? SidePanels.isCollapsed(kind)
    }
}

/// The glass a side box is drawn on: rounded on the outside, tucked behind the bubble on the
/// inside, sliding out from behind it once the bubble has opened. Drag its outer edge to resize it.
struct SideBox<Content: View>: View {
    var kind: SidePanels.Kind
    var side: PanelSide
    var isOpen: Bool
    /// How far below the window's top the box starts, so it's centred on the bubble.
    var top: CGFloat
    /// Shown in the slim strip when the box is collapsed: a symbol and a count.
    var symbol: String
    var count: Int?
    @ViewBuilder var content: Content

    @State private var edgeHover = false
    @State private var tabHover = false

    var body: some View {
        let width = SidePanels.width(of: kind)
        let looksCollapsed = SidePanels.isCollapsible(kind) && SideBoxChrome.shared.looksCollapsed(kind)
        // While collapsing, the box still has its full width but slides behind the bubble so only a strip shows.
        let tucked = looksCollapsed ? max(0, width - SidePanels.collapsedWidth) : 0
        let toward: CGFloat = side == .left ? 1 : -1
        ZStack(alignment: side == .left ? .leading : .trailing) {
            content
                .padding(.top, 12)
                .padding(.bottom, 10)
                // With tucking on, the outer edge keeps room for the tab so it never covers a row.
                .padding(side == .left ? .leading : .trailing, SidePanels.isCollapsible(kind) ? 20 : 12)
                .padding(side == .left ? .trailing : .leading, SidePanels.tuck + 8)
                .frame(width: width, height: SidePanels.height, alignment: .top)
                .opacity(looksCollapsed ? 0 : 1)
                .blur(radius: looksCollapsed ? 6 : 0)
                .allowsHitTesting(!looksCollapsed)
            strip
                .frame(width: SidePanels.collapsedWidth - SidePanels.tuck, height: SidePanels.height)
                .opacity(looksCollapsed ? 1 : 0)
                .allowsHitTesting(looksCollapsed)
        }
        .frame(width: width, height: SidePanels.height, alignment: side == .left ? .leading : .trailing)
        .glassPanel(in: shape)
        .contentShape(shape)
        .overlay(alignment: side == .left ? .leading : .trailing) {
            if !looksCollapsed {
                ResizeEdge(kind: kind, side: side, hovering: $edgeHover)
            }
        }
        .overlay(alignment: side == .left ? .leading : .trailing) {
            if SidePanels.isCollapsible(kind) && (edgeHover || tabHover) {
                collapseTab(collapsed: looksCollapsed)
                    .transition(.opacity.combined(with: .scale(0.6, anchor: side == .left ? .leading : .trailing)))
            }
        }
        .animation(.snappy(duration: 0.2), value: edgeHover || tabHover)
        .offset(x: isOpen ? toward * tucked : toward * width)
        .opacity(isOpen ? 1 : 0)
        .animation(.spring(duration: 0.5, bounce: 0.2).delay(isOpen ? 0.12 : 0), value: isOpen)
        .frame(width: width, height: SidePanels.height)
        // Hidden where it slides behind the bubble, but its shadow is free on the other three sides
        // (a plain clip cut the shadow off square at the rounded corners).
        .mask {
            Rectangle()
                .padding(side == .left ? .leading : .trailing, -SidePanels.shadowRoom)
                .padding(.vertical, -SidePanels.shadowRoom)
        }
        .onHover { inside in
            // The strip itself shows the tab too, so it's easy to find again.
            if looksCollapsed { edgeHover = inside }
        }
        .padding(.top, top)
    }

    /// The slim strip a collapsed box leaves: its symbol and count. Click to open it again.
    private var strip: some View {
        Button {
            Haptics.play(.select)
            SidePanels.toggleCollapsed(kind)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show")
    }

    /// A small glass tab on the outer edge: ‹ tucks the box away, › brings it back.
    private func collapseTab(collapsed: Bool) -> some View {
        // Pointing the way the box will move: in toward the bubble, or back out.
        let inward = side == .left ? "chevron.compact.right" : "chevron.compact.left"
        let outward = side == .left ? "chevron.compact.left" : "chevron.compact.right"
        return Button {
            Haptics.play(.select)
            tabHover = false
            edgeHover = false
            SidePanels.toggleCollapsed(kind)
        } label: {
            Image(systemName: collapsed ? outward : inward)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tabHover ? .primary : .secondary)
                .frame(width: 12, height: 40)
                .background(Capsule().fill(Color.primary.opacity(tabHover ? 0.16 : 0.09)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(side == .left ? .leading : .trailing, 4)
        .onHover { tabHover = $0 }
        .help(collapsed ? "Show" : "Tuck Away")
        .accessibilityLabel(collapsed ? "Show box" : "Collapse box")
    }

    private var shape: UnevenRoundedRectangle {
        side == .left
            ? UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
            : UnevenRoundedRectangle(bottomTrailingRadius: 20, topTrailingRadius: 20)
    }
}

/// The box's outer edge: drag to make it wider or narrower (kept for next time), double-click for the usual width.
private struct ResizeEdge: View {
    var kind: SidePanels.Kind
    var side: PanelSide
    @Binding var hovering: Bool
    @State private var start: (mouse: CGFloat, width: CGFloat)?

    var body: some View {
        Color.clear
            .frame(width: 10)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 22)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else if start == nil { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        // Screen coordinates: the window itself moves while the box grows to the left.
                        let mouse = NSEvent.mouseLocation.x
                        if start == nil { start = (mouse, SidePanels.width(of: kind)) }
                        guard let start else { return }
                        let delta = (mouse - start.mouse) * (side == .left ? -1 : 1)
                        SidePanels.setWidth(start.width + delta, of: kind)
                    }
                    .onEnded { _ in
                        start = nil
                        if !hovering { NSCursor.pop() }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { SidePanels.setWidth(SidePanels.defaultWidth, of: kind) }
            }
            .help("Drag to resize · double-click for the usual width")
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

/// A vertical scroll view whose content fades into the box at an edge with more to scroll to,
/// instead of being cut off on a hard line. The fade is a mask, so nothing moves and every row
/// stays clickable; it grows with the distance left to scroll, so it eases in rather than popping.
struct FadingScrollView<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var contentFrame: CGRect = .zero
    @State private var viewport: CGFloat = 0
    private let fade: CGFloat = 22
    private static var space: String { "FadingScrollView" }

    var body: some View {
        ScrollView(.vertical) {
            content
                .background {
                    GeometryReader { geo in
                        Color.clear.onChange(of: geo.frame(in: .named(Self.space)), initial: true) { _, frame in
                            contentFrame = frame
                        }
                    }
                }
        }
        .coordinateSpace(.named(Self.space))
        .scrollIndicators(.never)
        .background {
            GeometryReader { geo in
                Color.clear.onChange(of: geo.size.height, initial: true) { _, height in viewport = height }
            }
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: topFade)
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: bottomFade)
            }
        }
    }

    /// How far the content has scrolled up past the top, up to the full fade.
    private var topFade: CGFloat { min(fade, max(0, -contentFrame.minY)) }
    /// How much is still hidden below, up to the full fade.
    private var bottomFade: CGFloat {
        guard viewport > 0 else { return 0 }
        return min(fade, max(0, contentFrame.maxY - viewport))
    }
}
