import AppKit
import SwiftUI
import Observation

@Observable
@MainActor
final class PanelPresentation {
    var isOpen = false
    /// Where the nub sits, in the bubble's own coordinates (points from its left edge).
    var arrowX: CGFloat = PopoverView.width / 2
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let host = NSHostingView(rootView: rootView)
        contentView = host
        setContentSize(host.fittingSize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Shows the bubble under the menu bar item with a springy "grow out of the menu bar" animation.
@MainActor
final class GlassPanelController: NSObject, NSWindowDelegate {
    private let presentation = PanelPresentation()
    private let anchor: () -> NSStatusBarButton?
    private var panel: GlassPanel?
    private var clickMonitor: Any?

    init(anchor: @escaping () -> NSStatusBarButton?) {
        self.anchor = anchor
    }

    var isShown: Bool { presentation.isOpen }

    func toggle() { isShown ? close() : open() }

    func open() {
        let panel = panel ?? makePanel()
        // Settings can show or hide parts of the bubble, so measure it fresh each time.
        if let content = panel.contentView { panel.setContentSize(content.fittingSize) }
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        anchor()?.highlight(true)
        // Ready to type an intention when there's none yet; otherwise don't select the existing text.
        let engine = TimerEngine.shared
        if !(engine.state == .idle && engine.intention.isEmpty) { panel.makeFirstResponder(nil) }
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { self.presentation.isOpen = true }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        guard presentation.isOpen else { return }
        withAnimation(.spring(duration: 0.28, bounce: 0)) { presentation.isOpen = false }
        anchor()?.highlight(false)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            if !presentation.isOpen { panel?.orderOut(nil) }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Give menus opened from the bubble a moment; close only if focus really moved elsewhere.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if let panel, !panel.isKeyWindow, NSApp.modalWindow == nil, !self.hasOpenMenu { close() }
        }
    }

    private var hasOpenMenu: Bool {
        NSApp.windows.contains { $0.isVisible && $0.level.rawValue >= NSWindow.Level.popUpMenu.rawValue && $0 !== panel }
    }

    private func makePanel() -> GlassPanel {
        let actions = AppActions(
            showHistory: { [weak self] in
                self?.close()
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
        panel.onEscape = { [weak self] in self?.close() }
        panel.delegate = self
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let button = anchor(), let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var x = buttonFrame.midX - size.width / 2
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX - GlassPanel.margin + 8), visible.maxX - size.width + GlassPanel.margin - 8)
        }
        // The nub's tip sits just under the menu bar, right below the item.
        let y = buttonFrame.minY - 3 - size.height + GlassPanel.margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        presentation.arrowX = buttonFrame.midX - (x + GlassPanel.margin)
    }
}

/// The bubble grows out of the nub's tip: scale from there, un-blur, fade in.
struct PopoverRoot: View {
    var presentation: PanelPresentation

    var body: some View {
        let tip = UnitPoint(x: presentation.arrowX / PopoverView.width, y: 0)
        PopoverView(arrowX: presentation.arrowX)
            .scaleEffect(presentation.isOpen ? 1 : 0.4, anchor: tip)
            .opacity(presentation.isOpen ? 1 : 0)
            .blur(radius: presentation.isOpen ? 0 : 12)
            .padding(GlassPanel.margin)
    }
}

struct PopoverView: View {
    static let width: CGFloat = 300
    static let arrowHeight: CGFloat = 11

    var arrowX: CGFloat
    @Environment(Preferences.self) private var prefs

    var body: some View {
        VStack(spacing: 14) {
            PhaseHeader()
            DialView(lineWidth: 5)
                .frame(width: 200, height: 200)
                .padding(.vertical, 2)
            if prefs.showIntention || prefs.askForReflection {
                IntentionField()
                    .frame(height: 20)
            }
            ControlPills()
            if prefs.showTodayProgress {
                TodayLine()
            }
        }
        .padding(16)
        .padding(.top, Self.arrowHeight)
        .frame(width: Self.width)
        .glassEffect(.regular, in: BubbleShape(arrowX: arrowX))
    }
}
