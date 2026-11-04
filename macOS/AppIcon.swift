import AppKit
import SwiftUI

/// The four app icons, drawn in code so they stay crisp at every size:
/// the bold "15" or a minimal ring, each in dark or light.
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
}

/// Applies the chosen icon to the running app and to the app in Finder, the Dock and Spotlight.
@MainActor
enum AppIconChanger {
    /// On launch: only the running app's icon (nothing written to disk).
    static func applyAtLaunch(_ style: AppIconStyle) {
        NSApp.applicationIconImage = style == .fifteenDark ? nil : AppIconArt.image(style)
    }

    /// From Settings: also changes the icon Finder shows. "15 Dark" restores the built-in icon.
    static func apply(_ style: AppIconStyle) {
        applyAtLaunch(style)
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
            HStack(spacing: 8) {
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
