import AppKit
import SwiftUI

/// An optional full-screen veil during breaks, so the break actually happens.
/// Skip is always one click away.
@MainActor
final class BreakCurtain {
    private var windows: [NSWindow] = []

    func show() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = CurtainWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: CurtainView()
                .environment(TimerEngine.shared)
                .environment(Preferences.shared)
                .environment(HistoryStore.shared))
            window.setFrame(screen.frame, display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
        }
        windows.first?.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    func hide() {
        guard !windows.isEmpty else { return }
        let closing = windows
        windows = []
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            closing.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        }
    }
}

private final class CurtainWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private struct CurtainView: View {
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial)
            Color.black.opacity(0.55)
            VStack(spacing: 32) {
                DialView(lineWidth: 6)
                    .frame(width: 300, height: 300)
                Text(BreakTips.tip(for: engine.sessionStart))
                    .font(.title2.weight(.light))
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { engine.extend(by: 60) } label: {
                            Label("1 More Minute", systemImage: "plus").pill()
                        }
                        Button { engine.skip() } label: {
                            Label("Skip Break", systemImage: "forward.end").pill()
                        }
                    }
                    .buttonStyle(.plain)
                }
                // Esc closes the veil but keeps the break going, in the menu bar popup.
                Button { MacIntegrations.shared.continueBreakInPopup() } label: {
                    HStack(spacing: 6) {
                        Text("esc")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.5)))
                        Text("Continue the break in the menu bar")
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}
