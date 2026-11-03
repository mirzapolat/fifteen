import AppKit

/// Template images for the menu bar, in several styles. All are black-on-clear so macOS tints them
/// for light and dark menu bars. Most show the share of time left; paused states are dimmed or marked.
enum MenuBarIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(style: MenuBarIconStyle = .ring, fraction: Double, state: RunState, phase: Phase) -> NSImage {
        // 120 steps is smoother than the eye can tell at this size.
        let shown = state == .idle ? (style == .ring || style == .pie ? 0.78 : 1) : fraction
        let step = Int((shown * 120).rounded())
        let key = "\(style.rawValue)-\(step)-\(state.rawValue)-\(phase.isBreak)"
        if let cached = cache[key] { return cached }

        let value = Double(step) / 120
        let image: NSImage
        switch style {
        case .ring: image = ring(value, state, phase)
        case .pie: image = pie(value, state)
        case .fifteen: image = fifteen(value, state)
        case .bar: image = bar(value, state)
        case .hourglass: image = hourglass(value, state)
        case .dot: image = dot(state, phase)
        }
        image.isTemplate = true
        image.accessibilityDescription = "Fifteen"
        cache[key] = image
        return image
    }

    // MARK: Styles

    /// A faint track, a ring of time left, and a dot at "now". Pause bars when paused.
    private static func ring(_ value: Double, _ state: RunState, _ phase: Phase) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let line: CGFloat = 1.6
            let radius = (min(rect.width, rect.height) - line) / 2 - 0.75
            let center = NSPoint(x: rect.midX, y: rect.midY)

            NSColor.black.withAlphaComponent(0.3).setStroke()
            let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2))
            track.lineWidth = line
            track.stroke()

            NSColor.black.setStroke()
            NSColor.black.setFill()
            if value > 0.004 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * value, clockwise: true)
                arc.lineWidth = line + 0.3
                arc.lineCapStyle = .round
                arc.stroke()
            }

            let angle = (90 - 360 * value) * .pi / 180
            let dot = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            NSBezierPath(ovalIn: NSRect(x: dot.x - 2.1, y: dot.y - 2.1, width: 4.2, height: 4.2)).fill()

            switch state {
            case .paused:
                pauseBars(center: center, height: 5)
            case .finished:
                NSBezierPath(ovalIn: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
            case .running where phase.isBreak:
                NSColor.black.withAlphaComponent(0.6).setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - 1.6, y: center.y - 1.6, width: 3.2, height: 3.2)).fill()
            default:
                break
            }
            return true
        }
    }

    /// A disc that empties clockwise, like a kitchen timer.
    private static func pie(_ value: Double, _ state: RunState) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.6
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let outline = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            outline.lineWidth = 1.2
            outline.stroke()

            NSColor.black.withAlphaComponent(state == .paused ? 0.45 : 1).setFill()
            if value >= 0.999 {
                NSBezierPath(ovalIn: NSRect(x: center.x - radius + 1.6, y: center.y - radius + 1.6,
                                            width: (radius - 1.6) * 2, height: (radius - 1.6) * 2)).fill()
            } else if value > 0.004 {
                let wedge = NSBezierPath()
                wedge.move(to: center)
                wedge.appendArc(withCenter: center, radius: radius - 1.6, startAngle: 90,
                                endAngle: 90 - 360 * value, clockwise: true)
                wedge.close()
                wedge.fill()
            }
            return true
        }
    }

    /// The bold "15" mark. While a session runs, a thin line under it shows the time left.
    private static func fifteen(_ value: Double, _ state: RunState) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 16), flipped: false) { rect in
            let base = NSFont.systemFont(ofSize: 11.5, weight: .black)
            let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 11.5) ?? base
            let alpha: CGFloat = state == .paused ? 0.45 : 1
            let text = NSAttributedString(string: "15", attributes: [
                .font: font, .foregroundColor: NSColor.black.withAlphaComponent(alpha), .kern: -0.6,
            ])
            let size = text.size()
            let showsBar = state == .running || state == .paused
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: showsBar ? 3.2 : 1.6))
            if showsBar {
                let width = rect.width - 3
                NSColor.black.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: NSRect(x: 1.5, y: 0.5, width: width, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: NSRect(x: 1.5, y: 0.5, width: max(1.6, width * value), height: 1.6),
                             xRadius: 0.8, yRadius: 0.8).fill()
            }
            return true
        }
    }

    /// A tiny battery-like bar that drains from the right.
    private static func bar(_ value: Double, _ state: RunState) -> NSImage {
        NSImage(size: NSSize(width: 20, height: 16), flipped: false) { rect in
            let frame = NSRect(x: 1, y: rect.midY - 3.5, width: rect.width - 2, height: 7)
            NSColor.black.withAlphaComponent(0.4).setStroke()
            let outline = NSBezierPath(roundedRect: frame, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1.2
            outline.stroke()
            let inner = frame.insetBy(dx: 1.8, dy: 1.8)
            NSColor.black.withAlphaComponent(state == .paused ? 0.45 : 1).setFill()
            if value > 0.004 {
                NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: max(inner.height, inner.width * value), height: inner.height),
                             xRadius: inner.height / 2, yRadius: inner.height / 2).fill()
            }
            return true
        }
    }

    /// The system hourglass: sand on top early in a session, at the bottom later on.
    private static func hourglass(_ value: Double, _ state: RunState) -> NSImage {
        let name: String = switch state {
        case .idle: "hourglass"
        case .finished: "hourglass.bottomhalf.filled"
        case .running, .paused: value > 0.5 ? "hourglass.tophalf.filled" : "hourglass.bottomhalf.filled"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Fifteen")?
            .withSymbolConfiguration(config) ?? NSImage()
        guard state == .paused else { return symbol }
        return NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.45)
            return true
        }
    }

    /// The most minimal: hollow when idle, solid while running, dimmed when paused, ringed when done.
    private static func dot(_ state: RunState, _ phase: Phase) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 16), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let r: CGFloat = 4
            let disc = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            switch state {
            case .idle:
                NSColor.black.setStroke()
                disc.lineWidth = 1.5
                disc.stroke()
            case .running:
                NSColor.black.withAlphaComponent(phase.isBreak ? 0.55 : 1).setFill()
                disc.fill()
            case .paused:
                NSColor.black.withAlphaComponent(0.4).setFill()
                disc.fill()
            case .finished:
                NSColor.black.setFill()
                disc.fill()
                let halo = NSBezierPath(ovalIn: NSRect(x: center.x - 6.3, y: center.y - 6.3, width: 12.6, height: 12.6))
                halo.lineWidth = 1
                halo.stroke()
            }
            return true
        }
    }

    private static func pauseBars(center: NSPoint, height: CGFloat) {
        NSBezierPath(roundedRect: NSRect(x: center.x - 2.4, y: center.y - height / 2, width: 1.6, height: height),
                     xRadius: 0.8, yRadius: 0.8).fill()
        NSBezierPath(roundedRect: NSRect(x: center.x + 0.8, y: center.y - height / 2, width: 1.6, height: height),
                     xRadius: 0.8, yRadius: 0.8).fill()
    }
}
