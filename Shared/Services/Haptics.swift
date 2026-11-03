#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// One place for every haptic, so they stay consistent and respect the setting.
/// iPhone: Taptic Engine. Mac: Force Touch trackpad (felt only while a finger rests on it).
@MainActor
enum Haptics {
    enum Kind {
        /// Start or resume: a firm tap.
        case start
        /// Pause or reset: a light tap.
        case pause
        /// A session ended: a success pattern.
        case finish
        /// Moving through values (dragging the ring, switching phase, rating).
        case select
    }

    static func play(_ kind: Kind) {
        guard Preferences.shared.haptics else { return }
        #if os(iOS)
        switch kind {
        case .start: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .pause: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .finish: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .select: UISelectionFeedbackGenerator().selectionChanged()
        }
        #else
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch kind {
        case .start, .finish: performer.perform(.levelChange, performanceTime: .now)
        case .pause, .select: performer.perform(.alignment, performanceTime: .now)
        }
        #endif
    }
}
