import AppKit
import Observation

/// The menu bar item: a ring that empties as time passes, the time, or both.
/// Click opens the glass bubble. Right-click (or ⌥-click) starts and pauses without opening it.
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
    func showPanel() { panel.open() }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true {
            engine.primaryAction()
        } else {
            panel.toggle()
        }
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

        let showIcon = mode != .time
        let showTime = mode == .time || (mode == .iconAndTime && state != .idle)

        button.image = showIcon
            ? MenuBarIcon.image(style: prefs.menuBarIcon, fraction: fraction, state: state, phase: engine.phase)
            : nil

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
            let color: NSColor = state == .paused ? .secondaryLabelColor : .labelColor
            button.attributedTitle = NSAttributedString(string: showIcon ? " " + text : text,
                                                        attributes: [.font: font, .foregroundColor: color, .baselineOffset: 0.5])
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
        button.toolTip = "\(engine.phase.title) · \(TimeFormat.clock(remaining))"
    }

    private func clock(_ interval: TimeInterval) -> String {
        prefs.menuBarSeconds ? TimeFormat.clock(interval) : TimeFormat.short(interval)
    }
}
