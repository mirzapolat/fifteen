import AppKit
import CoreText
import SwiftUI

/// The app icons, drawn in code so they stay crisp at every size:
/// the bold "15" or a minimal ring, each in dark, light or the dial's rainbow.
enum AppIconArt {
    private static var cache: [String: NSImage] = [:]

    static func image(_ style: AppIconStyle, size: CGFloat = 1024) -> NSImage {
        let key = "\(style.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(style, in: rect)
            return true
        }
        cache[key] = image
        return image
    }

    private static func draw(_ style: AppIconStyle, in rect: NSRect) {
        let scale = rect.width / 1024
        // macOS icon grid: an 824 pt rounded square centred on a 1024 canvas.
        let body = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
        let shape = NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale)

        let dark = style.isDark
        let ink = dark ? NSColor.white : NSColor.black
        let gradient = dark
            ? NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.02, alpha: 1))
            : NSGradient(starting: NSColor(white: 1, alpha: 1), ending: NSColor(white: 0.9, alpha: 1))

        // A soft shadow under the tile, like the system icons.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 18 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
        shadow.set()
        (dark ? NSColor.black : NSColor.white).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        gradient?.draw(in: shape, angle: -90)
        // A hairline edge so the light tile doesn't melt into white backgrounds.
        (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.1)).setStroke()
        let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1.5 * scale, dy: 1.5 * scale),
                                xRadius: 184 * scale, yRadius: 184 * scale)
        edge.lineWidth = 3 * scale
        edge.stroke()

        let center = NSPoint(x: body.midX, y: body.midY)
        switch style {
        case .fifteenRainbow:
            drawRainbowFifteen(center: center, scale: scale)
        case .ringRainbow:
            drawRainbowRing(center: center, scale: scale)
        case .fifteenDark, .fifteenLight:
            let base = NSFont.systemFont(ofSize: 470 * scale, weight: .black)
            let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,
                              size: 470 * scale) ?? base
            let text = NSAttributedString(string: "15", attributes: [
                .font: font, .foregroundColor: ink, .kern: -24 * scale,
            ])
            let width = text.size().width
            // Centre the digits' cap height (not the line box). draw(at:) takes the line's bottom,
            // which sits one descender below the baseline.
            let baseline = center.y - font.capHeight / 2
            text.draw(at: NSPoint(x: center.x - width / 2 + 6 * scale, y: baseline + font.descender))
        case .ringDark, .ringLight:
            let radius = 250 * scale
            let line = 58 * scale
            ink.withAlphaComponent(0.16).setStroke()
            let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2))
            track.lineWidth = line
            track.stroke()

            let left = 0.72
            ink.setStroke()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * left, clockwise: true)
            arc.lineWidth = line
            arc.lineCapStyle = .round
            arc.stroke()

            let angle = (90 - 360 * left) * .pi / 180
            let knob = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let r = line * 0.95
            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: knob.x - r, y: knob.y - r, width: r * 2, height: r * 2)).fill()
        }
    }

    // MARK: Rainbow

    /// The dial's rainbow at a point along it (0…1), as drawn on a dark background.
    private static func hue(_ position: Double) -> NSColor {
        NSColor(DialView.hue(at: position, .dark))
    }

    /// The ring of the Rainbow dial theme: the same arc and knob, colored along its length, over a soft glow.
    private static func drawRainbowRing(center: NSPoint, scale: CGFloat) {
        let radius = 250 * scale
        let line = 58 * scale
        let left = 0.72

        NSColor.white.withAlphaComponent(0.12).setStroke()
        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                width: radius * 2, height: radius * 2))
        track.lineWidth = line
        track.stroke()

        func point(_ p: Double) -> NSPoint {
            let angle = (90 - 360 * p) * .pi / 180
            return NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        // Short overlapping segments, each its own color, read as one smooth gradient.
        func strokeArc(width: CGFloat) {
            let steps = 180
            for i in 0..<steps {
                let a = left * Double(i) / Double(steps)
                let b = left * Double(i + 1) / Double(steps)
                hue(a).setStroke()
                let segment = NSBezierPath()
                segment.appendArc(withCenter: center, radius: radius,
                                  startAngle: 90 - 360 * a, endAngle: 90 - 360 * min(left, b + 0.002), clockwise: true)
                segment.lineWidth = width
                segment.lineCapStyle = i == 0 ? .round : .butt
                segment.stroke()
            }
            let knob = point(left)
            let r = width / 2 * 1.9
            hue(left).setFill()
            NSBezierPath(ovalIn: NSRect(x: knob.x - r, y: knob.y - r, width: r * 2, height: r * 2)).fill()
        }

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = hue(0.4).withAlphaComponent(0.85)
        glow.shadowBlurRadius = 70 * scale
        glow.set()
        strokeArc(width: line)
        NSGraphicsContext.restoreGraphicsState()
        strokeArc(width: line)
    }

    /// The bold "15", filled with the rainbow running across it, with a soft glow underneath.
    private static func drawRainbowFifteen(center: NSPoint, scale: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let base = NSFont.systemFont(ofSize: 470 * scale, weight: .black)
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,
                          size: 470 * scale) ?? base
        let glyphs = textPath("15", font: font, kern: -24 * scale)
        let box = glyphs.boundingBoxOfPath
        // Same placement as the plain "15": centred on its cap height.
        var move = CGAffineTransform(translationX: center.x - box.midX + 6 * scale,
                                     y: center.y - font.capHeight / 2)
        guard let path = glyphs.copy(using: &move) else { return }
        let bounds = path.boundingBoxOfPath

        let stops = 24
        let colors = (0...stops).map { hue(Double($0) / Double(stops) * 0.5).cgColor } as CFArray
        let locations = (0...stops).map { CGFloat($0) / CGFloat(stops) }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors, locations: locations) else { return }
        let start = CGPoint(x: bounds.minX, y: bounds.maxY)
        let end = CGPoint(x: bounds.maxX, y: bounds.minY)

        // Glow: the digits in a mid-spectrum color, blurred, under the gradient fill.
        context.saveGState()
        context.setShadow(offset: .zero, blur: 70 * scale, color: hue(0.25).withAlphaComponent(0.8).cgColor)
        context.addPath(path)
        context.setFillColor(hue(0.25).cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    /// The outline of `string` set in `font`, with its baseline at y = 0.
    private static func textPath(_ string: String, font: NSFont, kern: CGFloat) -> CGPath {
        let text = NSAttributedString(string: string, attributes: [.font: font, .kern: kern])
        let line = CTLineCreateWithAttributedString(text)
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            for (glyph, position) in zip(glyphs, positions) {
                if let outline = CTFontCreatePathForGlyph(runFont, glyph, nil) {
                    path.addPath(outline, transform: CGAffineTransform(translationX: position.x, y: position.y))
                }
            }
        }
        return path
    }
}

/// Applies the chosen icon to the running app and to the app in Finder, the Dock and Spotlight.
@MainActor
enum AppIconChanger {
    /// On launch: the running app's icon, plus the Finder icon if it went missing. An update
    /// replaces the whole app bundle, which drops the custom icon stored inside it.
    static func applyAtLaunch(_ style: AppIconStyle) {
        NSApp.applicationIconImage = style == .fifteenDark ? nil : AppIconArt.image(style)
        let hasFinderIcon = FileManager.default.fileExists(atPath: Bundle.main.bundlePath + "/Icon\r")
        if style != .fifteenDark && !hasFinderIcon { writeFinderIcon(style) }
    }

    /// From Settings: also changes the icon Finder shows. "15 Dark" restores the built-in icon.
    static func apply(_ style: AppIconStyle) {
        NSApp.applicationIconImage = style == .fifteenDark ? nil : AppIconArt.image(style)
        writeFinderIcon(style)
    }

    /// A custom Finder icon on a bundle lives in an `Icon\r` file inside it.
    private static func writeFinderIcon(_ style: AppIconStyle) {
        let path = Bundle.main.bundlePath
        let image: NSImage? = style == .fifteenDark ? nil : AppIconArt.image(style)
        NSWorkspace.shared.setIcon(image, forFile: path, options: [])
        NSWorkspace.shared.noteFileSystemChanged(path)
    }
}

/// One tile per app icon; click to switch.
struct AppIconSection: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(AppIconStyle.allCases) { style in
                    let selected = prefs.appIcon == style
                    Button {
                        withAnimation(.snappy) { prefs.appIcon = style }
                        AppIconChanger.apply(style)
                    } label: {
                        VStack(spacing: 6) {
                            Image(nsImage: AppIconArt.image(style, size: 128))
                                .resizable()
                                .frame(width: 64, height: 64)
                            Text(style.title)
                                .font(.caption)
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(selected ? 0.1 : 0.03)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .help(style.title)
                    .accessibilityLabel("\(style.title) app icon")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("App Icon")
        } footer: {
            Text("Shown in Finder, Spotlight and notifications.")
        }
    }
}
