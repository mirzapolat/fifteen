import AppKit
import Observation

/// The menu bar item: a ring that empties as time passes, the time, or both.
/// Click opens the glass bubble. Right-click opens the same menu as the bubble's ••• button;
/// ⌥-click starts and pauses without opening anything.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine = TimerEngine.shared
    private let prefs = Preferences.shared
    private lazy var panel = GlassPanelController(anchor: { [weak self] in self?.item.button })

    override init() {
        super.init()
        item.autosaveName = "FifteenTimer"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("Fifteen timer")
        }
        render()
    }

    func togglePanel() { panel.toggle() }
    func showPanel() { if !panel.isShown { panel.open() } }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if event?.modifierFlags.contains(.option) == true {
            engine.primaryAction()
        } else {
            panel.toggle()
        }
    }

    /// The bubble's ••• menu, plus start/pause at the top since there's no ring to click here.
    private func showMenu() {
        if panel.isShown { panel.close() }
        let menu = NSMenu()
        // Items say for themselves whether they're enabled ("Check for Updates…" waits while a check runs).
        menu.autoenablesItems = false
        menu.addItem(action(primaryTitle, symbol: primarySymbol) { [engine] in engine.primaryAction() })
        if engine.state != .idle {
            menu.addItem(action("Reset", symbol: "arrow.counterclockwise") { [engine] in engine.reset() })
        }
        menu.addItem(.separator())
        if engine.phase == .focus && engine.isActive {
            if !engine.isFlowtime {
                menu.addItem(action("Finish Early", symbol: "checkmark.circle") { [engine] in engine.finishEarly() })
            }
            menu.addItem(action("Log a Distraction", symbol: "exclamationmark.bubble") { [engine] in engine.logDistraction() })
        }
        menu.addItem(action(skipTitle, symbol: "forward.end") { [engine] in engine.skip() })
        menu.addItem(.separator())
        menu.addItem(action("Insights…", symbol: "chart.bar") { WindowRouter.shared.showHistory() })
        menu.addItem(action("Settings…", symbol: "gearshape", key: ",") { WindowRouter.shared.showSettings() })
        let updates = action("Check for Updates…", symbol: "arrow.down.circle") { Updater.shared.checkNow() }
        updates.isEnabled = Updater.shared.canCheck
        menu.addItem(updates)
        menu.addItem(.separator())
        menu.addItem(action("Quit Fifteen", symbol: "power", key: "q") { NSApp.terminate(nil) })
        // Attach just for this click so the menu drops from the item like a normal menu bar menu.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private var primaryTitle: String {
        switch engine.state {
        case .idle: "Start \(engine.phase.title)"
        case .running: "Pause"
        case .paused: "Resume"
        case .finished: engine.nextPhase.startTitle
        }
    }

    private var primarySymbol: String {
        switch engine.state {
        case .running: "pause.fill"
        default: "play.fill"
        }
    }

    private var skipTitle: String {
        if engine.phase.isBreak { return "Skip Break" }
        return engine.nextPhase.isBreak ? "Skip to Break" : "Skip Session"
    }

    private func action(_ title: String, symbol: String, key: String = "", _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        item.keyEquivalent = key
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    /// Redraws whenever anything it reads changes.
    private func render() {
        withObservationTracking {
            draw()
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
    }

    private func draw() {
        guard let button = item.button else { return }
        let mode = prefs.menuBarDisplay
        let state = engine.state
        let flow = engine.isFlowtime && state != .finished
        // Flowtime counts up; everything else counts down.
        let remaining = flow ? engine.elapsed : engine.remaining
        let fraction: Double = switch state {
        case .idle: 1
        case .finished: 0
        case .running, .paused:
            flow ? engine.elapsed.truncatingRemainder(dividingBy: 3600) / 3600 : 1 - engine.progress(at: engine.now)
        }

        // In use: anything but a fresh focus session waiting to start (a break that's up next counts).
        let inUse = state != .idle || engine.phase != .focus
        let showIcon = switch mode {
        case .iconAndTime, .icon: true
        case .iconOrTime: !inUse
        case .time: false
        }
        let showTime = switch mode {
        case .iconAndTime: state != .idle
        case .iconOrTime: inUse
        case .icon: false
        case .time: true
        }

        // In a Link group, a small "two people" mark sits next to the time.
        let linked = LinkSession.shared.isLinked
        button.image = showIcon
            ? MenuBarIcon.image(style: prefs.menuBarIcon, fraction: fraction, state: state, phase: engine.phase)
            : (linked ? Self.linkMark : nil)
        let hasImage = button.image != nil

        if showTime {
            let text: String
            switch state {
            case .finished:
                text = engine.isCountingOvertime ? "+" + clock(engine.overtime) : "Done"
            default:
                text = clock(remaining)
            }
            let size = NSFont.menuBarFont(ofSize: 0).pointSize
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
            button.attributedTitle = NSAttributedString(string: hasImage ? " " + text : text,
                                                        attributes: [.font: font, .foregroundColor: NSColor.labelColor, .baselineOffset: 0.5])
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
        button.toolTip = "\(engine.phase.title) · \(TimeFormat.clock(remaining))"
    }

    private static let linkMark: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: "Linked")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }()

    private func clock(_ interval: TimeInterval) -> String {
        prefs.menuBarSeconds ? TimeFormat.clock(interval) : TimeFormat.short(interval)
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
