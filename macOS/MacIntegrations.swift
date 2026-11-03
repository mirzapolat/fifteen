import AppKit
import Carbon.HIToolbox
import Observation

/// Everything the Mac does around the timer: hot keys, hiding distracting apps,
/// pausing on lock, the break curtain, and running your Shortcuts.
@MainActor
final class MacIntegrations {
    static let shared = MacIntegrations()

    private let engine = TimerEngine.shared
    private let prefs = Preferences.shared
    private let curtain = BreakCurtain()
    private var togglePanel: () -> Void = {}
    private var showPanel: () -> Void = {}
    private var hotKeysOn: Bool?
    private var pausedByLock = false
    /// The break (by its start time) whose curtain you closed with Esc; it carries on in the popup.
    private var curtainDismissedFor: Date?

    func start(togglePanel: @escaping () -> Void, showPanel: @escaping () -> Void) {
        self.togglePanel = togglePanel
        self.showPanel = showPanel
        engine.observe { [weak self] event in self?.handle(event) }
        sync()

        AppBlocker.shared.start()
        DoNotDisturb.shared.start()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MacIntegrations.shared.screenLocked() }
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MacIntegrations.shared.screenLocked() }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MacIntegrations.shared.screenUnlocked() }
        }
    }

    // MARK: Reacting to state

    private func sync() {
        withObservationTracking {
            syncHotKeys(prefs.globalHotKeys)
            let showCurtain = prefs.breakCurtain && engine.phase.isBreak && engine.state == .running
                && (curtainDismissedFor == nil || curtainDismissedFor != engine.sessionStart)
            showCurtain ? curtain.show() : curtain.hide()
            NSApp.appearance = switch prefs.appearance {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        } onChange: {
            Task { @MainActor in MacIntegrations.shared.sync() }
        }
    }

    private func handle(_ event: TimerEvent) {
        switch event {
        case .started(.focus):
            runShortcut(prefs.focusStartShortcut)
        case .finished(.focus):
            runShortcut(prefs.focusEndShortcut)
        case .stopped where engine.phase == .focus:
            runShortcut(prefs.focusEndShortcut)
        default:
            break
        }
    }

    /// Esc on the break curtain: close it, keep the break running, and show it in the popup.
    func continueBreakInPopup() {
        curtainDismissedFor = engine.sessionStart
        curtain.hide()
        showPanel()
    }

    // MARK: Hot keys — ⌃⌥P start/pause, ⌃⌥O open the bubble, ⌃⌥R reset, ⌃⌥S skip

    private func syncHotKeys(_ on: Bool) {
        guard on != hotKeysOn else { return }
        hotKeysOn = on
        HotKeys.shared.unregisterAll()
        guard on else { return }
        let mods = controlKey | optionKey
        HotKeys.shared.register(keyCode: kVK_ANSI_P, modifiers: mods) { TimerEngine.shared.primaryAction() }
        HotKeys.shared.register(keyCode: kVK_ANSI_O, modifiers: mods) { [weak self] in self?.togglePanel() }
        HotKeys.shared.register(keyCode: kVK_ANSI_R, modifiers: mods) { TimerEngine.shared.reset() }
        HotKeys.shared.register(keyCode: kVK_ANSI_S, modifiers: mods) { TimerEngine.shared.skip() }
    }

    // MARK: Lock & sleep — pause focus while you're away, pick up where you left off

    private func screenLocked() {
        guard prefs.pauseWhenLocked, engine.phase == .focus, engine.state == .running else { return }
        engine.pause()
        pausedByLock = true
    }

    private func screenUnlocked() {
        defer { pausedByLock = false }
        guard pausedByLock, engine.state == .paused else { return }
        engine.resume()
    }

    // MARK: Shortcuts automation

    private func runShortcut(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        try? process.run()
    }
}
