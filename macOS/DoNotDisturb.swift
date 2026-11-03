import AppKit
import Observation

/// Silences notifications while you focus.
///
/// macOS has no public API for apps to switch Focus, so Fifteen runs two small shortcuts the user
/// makes once in the Shortcuts app ("Set Focus → Do Not Disturb → On / Off"). Do Not Disturb comes on
/// when focus starts or resumes, and goes off for breaks, when a session stops, and when Fifteen quits.
@Observable
@MainActor
final class DoNotDisturb {
    static let shared = DoNotDisturb()

    static let onName = "Fifteen DND On"
    static let offName = "Fifteen DND Off"

    private(set) var hasOnShortcut = false
    private(set) var hasOffShortcut = false
    private(set) var checked = false
    private(set) var testing = false
    var isReady: Bool { hasOnShortcut && hasOffShortcut }

    @ObservationIgnored private let engine = TimerEngine.shared
    @ObservationIgnored private let prefs = Preferences.shared
    /// Whether Fifteen currently has Do Not Disturb switched on.
    @ObservationIgnored private var active = false

    func start() {
        engine.observe { event in
            let dnd = DoNotDisturb.shared
            switch event {
            case .started(let phase): dnd.setActive(phase == .focus)
            case .resumed: dnd.setActive(TimerEngine.shared.phase == .focus)
            case .finished, .stopped: dnd.setActive(false)
            case .paused, .tick: break // Stay quiet through a pause.
            }
        }
        refresh()
    }

    /// Brings Do Not Disturb in line with the setting and the timer, e.g. right after the toggle changes.
    func sync() {
        setActive(prefs.doNotDisturb && engine.phase == .focus && engine.isActive)
    }

    /// Called when Fifteen quits, so Do Not Disturb is never left on by accident.
    func turnOffBeforeQuitting() {
        guard active else { return }
        active = false
        let process = Self.shortcutsProcess(["run", Self.offName])
        try? process.run()
        // Give it a moment; Shortcuts usually finishes well within this.
        let deadline = Date().addingTimeInterval(2.5)
        while process.isRunning && Date() < deadline { usleep(50_000) }
    }

    private func setActive(_ on: Bool) {
        if on && !prefs.doNotDisturb { return }
        guard on != active else { return }
        active = on
        run(on ? Self.onName : Self.offName)
    }

    // MARK: Setup helpers for Settings

    /// Looks up which of the two shortcuts exist.
    func refresh() {
        Task.detached {
            let names = Self.installedShortcuts()
            await MainActor.run {
                let dnd = DoNotDisturb.shared
                dnd.hasOnShortcut = names.contains(Self.onName)
                dnd.hasOffShortcut = names.contains(Self.offName)
                dnd.checked = true
            }
        }
    }

    /// Starts a new, correctly named shortcut in the Shortcuts app.
    func create(_ name: String) {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        if let url = URL(string: "shortcuts://create-shortcut?name=\(encoded)"), NSWorkspace.shared.open(url) { return }
        openShortcutsApp()
    }

    func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Turns Do Not Disturb on for three seconds, then off again.
    func test() {
        guard isReady, !testing else { return }
        testing = true
        run(Self.onName)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            // Don't switch it off under a focus session that started meanwhile.
            if !self.active { self.run(Self.offName) }
            self.testing = false
        }
    }

    // MARK: Shortcuts CLI

    private func run(_ name: String) {
        try? Self.shortcutsProcess(["run", name]).run()
    }

    private nonisolated static func shortcutsProcess(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    private nonisolated static func installedShortcuts() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return Set(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
    }
}
