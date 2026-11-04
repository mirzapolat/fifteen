import SwiftUI

/// Liquid Glass on macOS 26 / iOS 26, and a material look-alike on older systems (the Mac app
/// runs back to macOS 14). Views use these wrappers instead of calling the glass APIs directly.
///
/// In Debug builds, launch with `-GlassFallback YES` to see the fallback on macOS 26.
enum GlassCompat {
    static var useGlass: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "GlassFallback") { return false }
        #endif
        if #available(macOS 26, iOS 26, *) { return true }
        return false
    }
}

extension View {
    /// A glass control surface (pills, buttons). On older systems: a soft tinted fill.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, iOS 26, *), GlassCompat.useGlass {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background {
                if let tint {
                    shape.fill(tint)
                } else {
                    shape.fill(Color.primary.opacity(0.08))
                        .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                }
            }
        }
    }

    @available(macOS 26, iOS 26, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// Lets glass shapes morph into each other inside a `GlassGroup`. No-op on older systems.
    @ViewBuilder
    func glassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26, iOS 26, *), GlassCompat.useGlass {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    #if os(macOS)
    /// A floating glass window body (menu bar popup, app-blocker banner) in a clear, shadowless
    /// window. On older systems: a behind-window blur with its own outline and shadow.
    @ViewBuilder
    func glassPanel<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *), GlassCompat.useGlass {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background {
                VisualEffectBlur()
                    .clipShape(shape)
                    .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            }
        }
    }
    #endif
}

/// Groups glass shapes so they blend and morph together. A plain wrapper on older systems.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, iOS 26, *), GlassCompat.useGlass {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

#if os(macOS)
/// The pre-Tahoe popover material, blurring whatever is behind the window.
private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
#endif
