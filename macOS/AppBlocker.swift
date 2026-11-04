import AppKit
import Observation
import SwiftUI

/// Keeps distracting apps out of the way during focus.
/// - Hides (or quits) every blocked app the moment focus starts or resumes.
/// - Catches blocked apps when they're opened or brought forward, and says so in a small glass toast.
/// - "Allow 5 min" lets one app through on purpose; it's logged as a distraction.
@MainActor
final class AppBlocker {
    static let shared = AppBlocker()

    private let engine = TimerEngine.shared
    private let prefs = Preferences.shared
    private let toast = BlockToast()
    private var allowedUntil: [String: Date] = [:]

    /// Blocking holds for the whole focus session, pauses included; apps are released only
    /// when the session finishes or is reset.
    var isActive: Bool {
        prefs.hideDistractingApps && engine.phase == .focus && engine.isActive
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { AppBlocker.shared.caught(app) }
            }
        }
        engine.observe { event in
            switch event {
            case .started(.focus), .resumed:
                AppBlocker.shared.sweep()
            case .finished, .stopped:
                AppBlocker.shared.allowedUntil = [:]
            default:
                break
            }
        }
    }

    // MARK: Blocking

    /// Clears every blocked app away at once, quietly, when focus begins.
    func sweep() {
        guard isActive else { return }
        let blocked = NSWorkspace.shared.runningApplications.filter(isBlocked)
        guard !blocked.isEmpty else { return }
        blocked.forEach(block)
        let names = blocked.compactMap(\.localizedName)
        toast.show(icon: NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil),
                   title: verbPast + " " + list(names),
                   subtitle: "They'll be here when your session ends.",
                   allowID: nil)
    }

    /// A blocked app was opened or brought forward during focus.
    private func caught(_ app: NSRunningApplication?) {
        guard isActive, let app, isBlocked(app), let id = app.bundleIdentifier else { return }
        block(app)
        engine.logDistraction()
        let name = app.localizedName ?? "That app"
        let left = engine.state == .paused ? "Focus paused"
            : engine.isFlowtime ? "In the flow" : "\(TimeFormat.short(engine.remaining)) of focus left"
        toast.show(icon: app.icon,
                   title: "\(name) can wait",
                   subtitle: "\(left) · distraction logged",
                   allowID: id)
    }

    /// Lets one app through for a few minutes, on purpose.
    func allow(_ id: String, minutes: Int = 5) {
        allowedUntil[id] = Date().addingTimeInterval(TimeInterval(minutes * 60))
        toast.hide()
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            running.unhide()
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        // When the allowance runs out, put it away again if it's still in front.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(minutes * 60 + 1))
            AppBlocker.shared.caught(NSWorkspace.shared.frontmostApplication)
        }
    }

    private func isBlocked(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              prefs.blockedApps.contains(id) else { return false }
        if let until = allowedUntil[id], until > Date() { return false }
        return true
    }

    private func block(_ app: NSRunningApplication) {
        switch prefs.blockAction {
        case .hide: app.hide()
        case .quit: app.terminate()
        }
    }

    private var verbPast: String { prefs.blockAction == .hide ? "Hid" : "Quit" }

    private func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return "distracting apps"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }
}

// MARK: - Toast

@Observable
@MainActor
final class ToastModel {
    var visible = false
    var icon: NSImage?
    var title = ""
    var subtitle = ""
    var allowID: String?
}

/// A small glass card under the menu bar that fades away after a few seconds.
@MainActor
final class BlockToast {
    private let model = ToastModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(icon: NSImage?, title: String, subtitle: String, allowID: String?) {
        model.icon = icon
        model.title = title
        model.subtitle = subtitle
        model.allowID = allowID
        let panel = panel ?? makePanel()
        if let screen = NSScreen.main {
            let size = panel.frame.size
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height + 8))
        }
        panel.orderFrontRegardless()
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { model.visible = true }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(.easeIn(duration: 0.25)) { model.visible = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if !self.model.visible { self.panel?.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSHostingView(rootView: ToastView(model: model))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        self.panel = panel
        return panel
    }
}

private struct ToastView: View {
    var model: ToastModel

    var body: some View {
        HStack(spacing: 12) {
            if let icon = model.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let id = model.allowID {
                Button { AppBlocker.shared.allow(id) } label: {
                    Text("Allow 5 min").pill()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 400, height: 58)
        .glassEffect(.regular, in: .capsule)
        .scaleEffect(model.visible ? 1 : 0.85, anchor: .top)
        .offset(y: model.visible ? 0 : -16)
        .opacity(model.visible ? 1 : 0)
        .padding(20)
    }
}
