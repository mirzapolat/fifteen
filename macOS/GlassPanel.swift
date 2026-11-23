import AppKit
import SwiftUI
import Observation

@Observable
@MainActor
final class PanelPresentation {
    var isOpen = false
    /// Goes up by one each time the bubble opens; replays the top-right counter hint.
    var openCount = 0
    /// Where the nub sits, in the bubble's own coordinates (points from its left edge).
    var arrowX: CGFloat = PopoverView.width / 2
    /// The bubble's current height (with its margin), for telling clicks on it from clicks beside it.
    @ObservationIgnored var bubbleHeight: CGFloat = 0
}

/// A rounded rectangle with a soft, bubbly nub on top that points at the menu bar item.
struct BubbleShape: Shape {
    var arrowX: CGFloat
    var arrowHeight: CGFloat = PopoverView.arrowHeight
    var arrowWidth: CGFloat = 34
    var cornerRadius: CGFloat = 28

    var animatableData: CGFloat {
        get { arrowX }
        set { arrowX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + arrowHeight, width: rect.width, height: rect.height - arrowHeight)
        let r = min(cornerRadius, body.width / 2, body.height / 2)
        let half = arrowWidth / 2
        let x = min(max(arrowX, body.minX + r + half), body.maxX - r - half)
        let top = rect.minY

        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        p.addLine(to: CGPoint(x: x - half, y: body.minY))
        // Smooth shoulders and a rounded tip, so it reads as part of the glass rather than a sharp arrow.
        p.addCurve(to: CGPoint(x: x, y: top),
                   control1: CGPoint(x: x - half * 0.45, y: body.minY),
                   control2: CGPoint(x: x - half * 0.32, y: top))
        p.addCurve(to: CGPoint(x: x + half, y: body.minY),
                   control1: CGPoint(x: x + half * 0.32, y: top),
                   control2: CGPoint(x: x + half * 0.45, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        p.closeSubpath()
        return p
    }
}

/// A borderless, transparent panel that hosts the glass bubble. It can take keyboard focus
/// (for the intention field) without activating the app or stealing the menu bar.
final class GlassPanel: NSPanel {
    /// Transparent room around the bubble for its shadow and the open animation.
    static let margin: CGFloat = 20

    var onEscape: (() -> Void)?
    /// A click in the clear room around the bubble, which counts as clicking away.
    var onClickOutside: (() -> Void)?
    /// How tall the bubble is right now; the window is taller so the bubble can grow inside it.
    var bubbleHeight: () -> CGFloat = { .greatestFiniteMagnitude }

    /// Whether the bubble is meant to be up. While it isn't, the window lets every click through
    /// and won't come back on screen: AppKit can re-show it on its own (e.g. when a menu opened from
    /// the bubble finishes after the bubble closed), and an invisible window at menu bar level
    /// would otherwise swallow clicks on the menu bar and everything under it.
    var isPresented = false {
        didSet { ignoresMouseEvents = !isPresented }
    }

    init<Content: View>(rootView: Content) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        // Setting this explicitly makes the window take every click itself. Left at the default,
        // macOS passes clicks on see-through pixels (between the controls on the glass) to the
        // app underneath, and that click then closed the bubble.
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let host = NSHostingView(rootView: rootView)
        // The window keeps the size it's given on open. As the window's own content view, the
        // hosting view resized the window whenever the bubble grew, which under the menu bar made
        // AppKit loop on layout and crash. Inside a plain container it just fills it.
        host.sizingOptions = [.intrinsicContentSize] // reports its size; never sets the window's
        host.autoresizingMask = [.width, .height]
        let container = NSView()
        container.addSubview(host)
        contentView = container
        self.host = host
        setContentSize(host.fittingSize)
        host.frame = container.bounds
    }

    /// The SwiftUI bubble; measure this, not the container, for the size the bubble wants.
    private(set) var host: NSView!

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        guard place == .out || isPresented else { return }
        super.order(place, relativeTo: otherWin)
    }

    override func becomeKey() {
        guard isPresented else { orderOut(nil); return }
        super.becomeKey()
    }

    override func sendEvent(_ event: NSEvent) {
        if !isPresented, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            orderOut(nil)
            return
        }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type), let content = contentView {
            let point = content.convert(event.locationInWindow, from: nil)
            let fromTop = content.isFlipped ? point.y : content.bounds.height - point.y
            let insideX = point.x >= Self.margin && point.x <= content.bounds.width - Self.margin
            let insideY = fromTop >= Self.margin && fromTop <= min(bubbleHeight(), content.bounds.height) - Self.margin
            if !(insideX && insideY) {
                onClickOutside?()
                return
            }
        }
        super.sendEvent(event)
    }
}

/// Shows the bubble under the menu bar item with a springy "grow out of the menu bar" animation.
@MainActor
final class GlassPanelController: NSObject, NSWindowDelegate {
    private let presentation = PanelPresentation()
    private let anchor: () -> NSStatusBarButton?
    private var panel: GlassPanel?
    private var clickMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?

    init(anchor: @escaping () -> NSStatusBarButton?) {
        self.anchor = anchor
    }

    var isShown: Bool { panel?.isPresented == true }

    func toggle() { isShown ? close() : open() }

    func open() {
        let panel = panel ?? makePanel()
        guard !panel.isPresented else { return }
        panel.isPresented = true
        // Settings can show or hide parts of the bubble, so measure it fresh each time.
        let engine = TimerEngine.shared
        LinkChrome.shared.isOpen = false
        LinkChrome.shared.joining = false
        // Measured fresh each time (settings can change the bubble), plus room for the
        // project/intention field to slide in without the window ever resizing.
        let size = panel.host.fittingSize
        // Room below for the project/intention field and for the Link strip to slide out.
        panel.setContentSize(NSSize(width: size.width, height: size.height + Pill.height + 10 + LinkActivityStrip.room))
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        anchor()?.highlight(true)
        LinkChrome.shared.timerVisible = true
        CalendarSync.shared.bubbleOpened()
        RemindersSync.shared.bubbleOpened()
        presentation.openCount += 1
        // Ready to type an intention when there's none yet; otherwise don't select the existing text.
        if !(engine.state == .idle && engine.intention.isEmpty) { panel.makeFirstResponder(nil) }
        DispatchQueue.main.async {
            // Closed again before this ran: stay closed.
            guard panel.isPresented else { return }
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { self.presentation.isOpen = true }
        }
        // Clicks in other apps (global monitors never see our own clicks) close the bubble.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        watchForLeaving()
    }

    func close() {
        guard let panel, panel.isPresented else { return }
        panel.isPresented = false
        withAnimation(.spring(duration: 0.28, bounce: 0)) { presentation.isOpen = false }
        LinkChrome.shared.timerVisible = false
        anchor()?.highlight(false)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            if !panel.isPresented { panel.orderOut(nil) }
        }
    }

    /// Closing only on these, never on a lost key status: clicks inside the bubble (the ring, menus,
    /// the text field) can briefly shuffle key windows, and that must not close it.
    private func watchForLeaving() {
        let openedAt = Date()
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  // macOS may hand focus back to the previous app right after opening; that's not leaving.
                  Date().timeIntervalSince(openedAt) > 0.6 else { return }
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func makePanel() -> GlassPanel {
        let actions = AppActions(
            showInsights: { [weak self] section in
                self?.close()
                if let section { InsightsRoute.shared.section = section }
                WindowRouter.shared.showHistory()
            },
            showSettings: { [weak self] in
                self?.close()
                WindowRouter.shared.showSettings()
            },
            quit: { NSApp.terminate(nil) }
        )
        let root = PopoverRoot(presentation: presentation)
            .environment(TimerEngine.shared)
            .environment(Preferences.shared)
            .environment(HistoryStore.shared)
            .environment(\.appActions, actions)
        let panel = GlassPanel(rootView: root)
        // Esc steps back out of the Link card first, then closes the bubble.
        panel.onEscape = { [weak self] in
            if LinkChrome.shared.isOpen {
                withAnimation(Pill.morph) { LinkChrome.shared.isOpen = false }
            } else {
                self?.close()
            }
        }
        panel.onClickOutside = { [weak self] in self?.close() }
        panel.delegate = self
        self.panel = panel
        panel.bubbleHeight = { [weak self] in self?.presentation.bubbleHeight ?? .greatestFiniteMagnitude }
        // Tucking a side box away or bringing it back: the window follows, keeping the bubble under its item.
        SidePanels.onResize = { [weak self] in self?.fitWidth() }
        watchSideBoxes()
        return panel
    }

    /// A box can also change size by itself, e.g. opening up once calendar access is granted.
    private func watchSideBoxes() {
        withObservationTracking {
            _ = SidePanels.extraWidth
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.fitWidth()
                self?.watchSideBoxes()
            }
        }
    }

    /// The window's width for the bubble and its side boxes, worked out directly (the SwiftUI
    /// layout catches up a frame later, and measuring it mid-drag made the window lag behind).
    private func fitWidth() {
        guard let panel, presentation.isOpen else { return }
        let width = PopoverView.width + SidePanels.extraWidth + 2 * GlassPanel.margin
        panel.setContentSize(NSSize(width: width, height: panel.frame.height))
        position(panel)
    }

    private func position(_ panel: NSPanel) {
        guard let button = anchor(), let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        // The bubble (not the whole window, which may include the side boxes) centers under the item.
        let leading = SidePanels.leadingRoom
        var x = buttonFrame.midX - PopoverView.width / 2 - leading - GlassPanel.margin
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX - GlassPanel.margin + 8), visible.maxX - size.width + GlassPanel.margin - 8)
        }
        // The nub's tip sits just under the menu bar, right below the item.
        let y = buttonFrame.minY - 3 - size.height + GlassPanel.margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        presentation.arrowX = buttonFrame.midX - (x + GlassPanel.margin + leading)
    }
}

/// The bubble grows out of the nub's tip: scale from there, un-blur, fade in.
/// With the calendar or reminders on, their boxes hang off the left and right sides, tucked behind the bubble.
struct PopoverRoot: View {
    var presentation: PanelPresentation
    /// The bubble's own height (without the Link strip), so the side boxes can centre on it.
    @State private var bubbleHeight: CGFloat = 0

    var body: some View {
        let layout = SidePanels.layout
        let leading = SidePanels.leadingRoom
        let totalWidth = PopoverView.width + SidePanels.extraWidth
        let tip = UnitPoint(x: (leading + presentation.arrowX) / totalWidth, y: 0)
        HStack(alignment: .top, spacing: -SidePanels.tuck) {
            if let kind = layout.left {
                sideBox(kind, on: .left)
            }
            VStack(spacing: 0) {
                PopoverView(arrowX: presentation.arrowX)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bubbleHeight = $0 }
                    .zIndex(1)
                LinkActivityStrip()
            }
            .zIndex(1)
            if let kind = layout.right {
                sideBox(kind, on: .right)
            }
        }
            .scaleEffect(presentation.isOpen ? 1 : 0.4, anchor: tip)
            .opacity(presentation.isOpen ? 1 : 0)
            .blur(radius: presentation.isOpen ? 0 : 12)
            .padding(GlassPanel.margin)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { presentation.bubbleHeight = $0 }
            // Pinned to the top: the bubble hangs from the menu bar and grows downward.
            .frame(maxHeight: .infinity, alignment: .top)
            .environment(\.presentationCount, presentation.openCount)
    }

    @ViewBuilder
    private func sideBox(_ kind: SidePanels.Kind, on side: PanelSide) -> some View {
        let top = SidePanels.top(forBubble: bubbleHeight)
        switch kind {
        case .calendar: CalendarSidePanel(side: side, isOpen: presentation.isOpen, top: top)
        case .reminders: RemindersSidePanel(side: side, isOpen: presentation.isOpen, top: top)
        }
    }
}

struct PopoverView: View {
    static let width: CGFloat = 300
    static let arrowHeight: CGFloat = 11
    /// Space between the ring and the header above it, and the controls below it.
    static let ringGap: CGFloat = 20

    var arrowX: CGFloat
    @Environment(Preferences.self) private var prefs

    var body: some View {
        // The ring sits with equal air above and below; the field and controls stack tightly under it.
        VStack(spacing: 0) {
            PhaseHeader()
                .padding(.bottom, Self.ringGap)
            // The Link card covers everything under the header (ring, field and controls), so its
            // buttons sit on the bubble's bottom edge like the controls do. What it covers keeps its
            // room, so the bubble never changes size; the card's title moves up into the header.
            let linkOpen = LinkChrome.shared.isOpen
            VStack(spacing: 0) {
                ZStack {
                    if !linkOpen {
                        DialView(lineWidth: 5)
                            .frame(width: 204, height: 204)
                            .transition(.blurReplace.combined(with: .scale(0.94)))
                    }
                }
                .frame(height: 204)
                .padding(.bottom, Self.ringGap)
                VStack(spacing: 0) {
                    IntentionField()
                    ControlPills()
                }
                .steppedAway(linkOpen)
            }
            .overlay {
                if linkOpen {
                    LinkCard()
                        .transition(.blurReplace.combined(with: .scale(0.96, anchor: .top)))
                }
            }
        }
        .padding(16)
        .padding(.top, Self.arrowHeight)
        .frame(width: Self.width)
        .glassPanel(in: BubbleShape(arrowX: arrowX))
        .contentShape(BubbleShape(arrowX: arrowX))
    }
}
