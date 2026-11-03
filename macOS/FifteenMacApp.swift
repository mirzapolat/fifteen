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
        Notifier.shared.setUp()
        let status = StatusItemController()
        statusController = status
        MacIntegrations.shared.start(togglePanel: { status.togglePanel() }, showPanel: { status.showPanel() })
        FifteenShortcuts.updateAppShortcutParameters()

        // `open Fifteen.app --args --open` shows the bubble right away (handy after first install).
        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { status.showPanel() }
        }
        // `--settings` opens Settings; `--settings-tab 2` picks a tab (0 General … 3 Focus).
        let args = CommandLine.arguments
        if args.contains("--settings") || args.contains("--settings-tab") {
            let tab = args.firstIndex(of: "--settings-tab").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WindowRouter.shared.showSettings(tab: tab) }
        }
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
        show(id: "history", title: "History", size: NSSize(width: 440, height: 620)) {
            NavigationStack { HistoryView() }
        }
    }

    func showSettings(tab: Int? = nil) {
        NSApp.activate()
        if let window = windows["settings"] {
            if let tab, let tabs = window.contentViewController as? NSTabViewController,
               tabs.tabViewItems.indices.contains(tab) { tabs.selectedTabViewItemIndex = tab }
            window.makeKeyAndOrderFront(nil)
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
        window.makeKeyAndOrderFront(nil)
        // Don't drop the cursor into the first text field (a preset name) on open.
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }

    private func show<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        NSApp.activate()
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
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
        window.makeKeyAndOrderFront(nil)
    }
}
