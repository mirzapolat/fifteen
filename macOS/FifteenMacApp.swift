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
        FifteenShortcuts.updateAppShortcutParameters()
        LinkSession.shared.start()
        Updater.shared.start()

        // `open Fifteen.app --args --open` shows the bubble right away (handy after first install).
        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { status.showPanel() }
        }
        // `--settings` opens Settings; `--settings-tab 2` picks a tab (0 General, 1 Keyboard, 2 Timer, 3 Sound, 4 Display, 5 Focus, 6 About).
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
