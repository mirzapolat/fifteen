import SwiftUI
import AppKit

@main
struct FifteenMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Fifteen lives in the menu bar; its windows are opened by WindowRouter.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppIconChanger.applyAtLaunch(Preferences.shared.appIcon)
        Notifier.shared.setUp()
        let status = StatusItemController()
        statusController = status
        Notifier.shared.openTimer = { status.showPanel() }
        MacIntegrations.shared.start(togglePanel: { status.togglePanel() }, showPanel: { status.showPanel() })
        CalendarSync.shared.start()
        FifteenShortcuts.updateAppShortcutParameters()
        LinkSession.shared.start()
        // Before Sparkle starts: it marks the app as launched before, which tells an update from a new install.
        let greeting = Greeting.forThisLaunch()
        Updater.shared.start()
        LaunchAtLogin.enableOnFirstLaunch()

        // `open Fifteen.app --args --open` shows the bubble right away (handy after first install).
        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { status.showPanel() }
        }
        #if DEBUG
        // `--demo-link-popup` plays a few sample Link popups, to see how they look without a group.
        if CommandLine.arguments.contains("--demo-link-popup") {
            let samples = [("Mira started 25 min of focus", "Focus · 25:00 left"),
                           ("Jonas paused", "Focus paused · 18:42 left"),
                           ("Jonas joined", "3 in the group")]
            for (i, sample) in samples.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i) * 7) {
                    LinkSession.shared.simulate(sample.0, detail: sample.1)
                }
            }
        }
        #endif
        // A welcome on a new install, what's new after an update. `--welcome` and `--whats-new`
        // show them anyway, to try them out.
        let forced: Greeting? = CommandLine.arguments.contains("--welcome") ? .welcome
            : CommandLine.arguments.contains("--whats-new") ? .whatsNew(Greeting.currentNotes) : nil
        if let shown = forced ?? greeting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                switch shown {
                case .welcome:
                    WindowRouter.shared.showWelcome {
                        Notifier.shared.requestAuthorizationIfNeeded()
                        status.showPanel()
                    }
                case .whatsNew(let notes):
                    WindowRouter.shared.showWhatsNew(notes)
                }
            }
        }
        // `--settings` opens Settings; `--settings-tab 2` picks a tab (0 General, 1 Keyboard, 2 Timer, 3 Sound, 4 Display, 5 Insights, 6 Link, 7 Focus, 8 About).
        let args = CommandLine.arguments
        if args.contains("--settings") || args.contains("--settings-tab") {
            let tab = args.firstIndex(of: "--settings-tab").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WindowRouter.shared.showSettings(tab: tab) }
        }
        // `--link-create` starts a group, `--link-join KQXMRT` joins one (for trying Link out).
        if args.contains("--link-create") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { LinkSession.shared.createGroup() }
        }
        if let i = args.firstIndex(of: "--link-join"), args.indices.contains(i + 1) {
            let code = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { LinkSession.shared.join(code) }
        }
        // `--insights [overview|projects|sessions]` opens Insights (add `--demo` for sample data).
        if args.contains("--insights") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WindowRouter.shared.showHistory() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DoNotDisturb.shared.turnOffBeforeQuitting()
    }

    /// Opening Fifteen again from Finder or Spotlight shows the timer.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.showPanel()
        return false
    }
}

/// Opens History and Settings as ordinary windows, once each.
@MainActor
final class WindowRouter {
    static let shared = WindowRouter()
    private var windows: [String: NSWindow] = [:]

    func showHistory() {
        guard Preferences.shared.insightsEnabled else { return }
        show(id: "history", title: "Insights", size: NSSize(width: 980, height: 700)) {
            InsightsView()
                .frame(minWidth: 760, minHeight: 520)
        }
    }

    func showSettings(tab: Int? = nil) {
        if let window = windows["settings"] {
            if let tab, let tabs = window.contentViewController as? NSTabViewController,
               tabs.tabViewItems.indices.contains(tab) { tabs.selectedTabViewItemIndex = tab }
            bringToFront(window)
            return
        }
        let controller = SettingsTabController()
        if let tab, controller.tabViewItems.indices.contains(tab) { controller.selectedTabViewItemIndex = tab }
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        windows["settings"] = window
        bringToFront(window)
        // Don't drop the cursor into the first text field (a preset name) on open.
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }

    /// The first-launch welcome. Begin closes it and runs `begin` (which opens the timer).
    func showWelcome(begin: @escaping () -> Void) {
        showCard(id: "welcome", title: "Welcome to Fifteen") { [weak self] in
            WelcomeView {
                self?.close("welcome")
                begin()
            }
        }
    }

    /// What's new after an update.
    func showWhatsNew(_ notes: [ReleaseNotes]) {
        guard !notes.isEmpty else { return }
        showCard(id: "whatsNew", title: "What's New in Fifteen") { [weak self] in
            WhatsNewView(notes: notes) { self?.close("whatsNew") }
        }
    }

    /// Insights was switched off in Settings.
    func closeHistory() { close("history") }

    private func close(_ id: String) {
        windows[id]?.close()
        windows[id] = nil
    }

    /// A small fixed-size window with no visible title bar, sized to its content.
    private func showCard<Content: View>(id: String, title: String, @ViewBuilder content: () -> Content) {
        if let window = windows[id] {
            bringToFront(window)
            return
        }
        let host = NSHostingController(rootView: content().environment(Preferences.shared))
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        bringToFront(window)
    }

    private func show<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if let window = windows[id] {
            bringToFront(window)
            return
        }
        let root = content()
            .environment(TimerEngine.shared)
            .environment(Preferences.shared)
            .environment(HistoryStore.shared)
        let host = NSHostingController(rootView: root)
        host.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.center()
        windows[id] = window
        bringToFront(window)
    }

    /// Fifteen is a menu bar app, so a plain `activate()` is only a polite request that macOS often
    /// declines while another app is in front; the window then opened behind it. Order the window
    /// up regardless, and ask firmly to become the active app so it also takes the keyboard.
    private func bringToFront(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate()
    }
}
