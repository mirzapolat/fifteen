import AppKit
import SwiftUI
import Observation

/// What the Link popup says, and whether it's showing.
@Observable
@MainActor
final class LinkToastModel {
    var shown = false
    var title = ""
    var detail = ""
    /// Where the nub sits, in the popup's own coordinates.
    var arrowX: CGFloat = LinkToastView.width / 2
}

/// "Mira paused": a small glass popup that hangs from the menu bar item for a few seconds when
/// someone in the Link group changes the timer while the bubble is closed. Clicking it opens the timer.
@MainActor
final class LinkToastController {
    private let anchor: () -> NSStatusBarButton?
    private let model = LinkToastModel()
    private var panel: NSPanel?
    private var host: NSHostingView<AnyView>?
    private var hideTask: Task<Void, Never>?
    private var hovering = false
    var onClick: (() -> Void)?

    private nonisolated static let visibleFor: Duration = .seconds(5)

    init(anchor: @escaping () -> NSStatusBarButton?) {
        self.anchor = anchor
    }

    func show(title: String, detail: String) {
        let panel = panel ?? makePanel()
        let wasShown = model.shown
        model.title = title
        model.detail = detail
        if let host {
            let size = host.fittingSize
            panel.setContentSize(size)
            host.frame = NSRect(origin: .zero, size: size)
        }
        position(panel)
        panel.orderFrontRegardless()
        if !wasShown {
            DispatchQueue.main.async {
                withAnimation(.spring(duration: 0.45, bounce: 0.3)) { self.model.shown = true }
            }
        }
        scheduleHide()
    }

    func dismiss() {
        hideTask?.cancel()
        guard model.shown else { return }
        withAnimation(.spring(duration: 0.28, bounce: 0)) { model.shown = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            if !model.shown { panel?.orderOut(nil) }
        }
    }

    private func scheduleHide(after delay: Duration = visibleFor) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, !hovering else { return }
            dismiss()
        }
    }

    private func makePanel() -> NSPanel {
        let root = LinkToastRoot(model: model, onTap: { [weak self] in
            self?.dismiss()
            self?.onClick?()
        }, onHover: { [weak self] inside in
            guard let self else { return }
            hovering = inside
            // Stays while the pointer rests on it, then lingers a moment after.
            if inside { hideTask?.cancel() } else { scheduleHide(after: .seconds(2)) }
        })
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSHostingView(rootView: AnyView(root))
        host.sizingOptions = [.intrinsicContentSize]
        let container = NSView()
        container.addSubview(host)
        panel.contentView = container
        self.host = host
        self.panel = panel
        return panel
    }

    /// Centered under the menu bar item, kept on screen; the nub points at the item.
    private func position(_ panel: NSPanel) {
        guard let button = anchor(), let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let margin = LinkToastView.margin
        var x = buttonFrame.midX - size.width / 2
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX - margin + 8), visible.maxX - size.width + margin - 8)
        }
        let y = buttonFrame.minY - 3 - size.height + margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        model.arrowX = buttonFrame.midX - (x + margin)
    }
}

/// Drops out of the menu bar like the timer bubble: grows from the nub's tip and un-blurs.
private struct LinkToastRoot: View {
    var model: LinkToastModel
    var onTap: () -> Void
    var onHover: (Bool) -> Void

    var body: some View {
        let tip = UnitPoint(x: model.arrowX / LinkToastView.width, y: 0)
        LinkToastView(title: model.title, detail: model.detail, arrowX: model.arrowX)
            .scaleEffect(model.shown ? 1 : 0.5, anchor: tip)
            .opacity(model.shown ? 1 : 0)
            .blur(radius: model.shown ? 0 : 8)
            .onTapGesture(perform: onTap)
            .onHover(perform: onHover)
            .padding(LinkToastView.margin)
    }
}

struct LinkToastView: View {
    static let width: CGFloat = 250
    /// Clear room around the popup for its shadow and the drop-in animation.
    static let margin: CGFloat = 16

    var title: String
    var detail: String
    var arrowX: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy, value: title)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .padding(.top, PopoverView.arrowHeight)
        .frame(width: Self.width)
        .glassPanel(in: BubbleShape(arrowX: arrowX, arrowHeight: PopoverView.arrowHeight, arrowWidth: 26, cornerRadius: 18))
        .contentShape(BubbleShape(arrowX: arrowX))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the timer")
    }
}
