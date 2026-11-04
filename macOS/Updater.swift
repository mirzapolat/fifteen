import AppKit
import Combine
import Observation
import Sparkle

/// Updates for the direct Mac download, through Sparkle (docs/SPARKLE_PLAN.md).
/// About once a day Fifteen reads the appcast attached to the newest GitHub release; when there's
/// a newer version, Sparkle shows its update window, then downloads it, checks its signature,
/// swaps the app and relaunches.
@Observable
@MainActor
final class Updater {
    static let shared = Updater()

    #if DEBUG
    private static let isDebugBuild = true
    #else
    private static let isDebugBuild = false
    #endif

    /// False while a check is already under way (the menu item and button wait).
    private(set) var canCheck = false
    /// When Fifteen last asked for updates, for Settings.
    private(set) var lastCheck: Date?

    /// The "Check for updates automatically" switch in Settings.
    var checksAutomatically = true {
        didSet {
            guard let updater, updater.automaticallyChecksForUpdates != checksAutomatically else { return }
            updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private let driverDelegate = UserDriverDelegate()
    @ObservationIgnored private var watchers: Set<AnyCancellable> = []
    private var updater: SPUUpdater? { controller?.updater }

    /// Called once at launch. Debug builds (com.mirzapolat.fifteen.dev) never check: they're
    /// ad-hoc signed and would only be offered the published release.
    func start() {
        guard !Self.isDebugBuild else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                      userDriverDelegate: driverDelegate)
        self.controller = controller
        let updater = controller.updater
        checksAutomatically = updater.automaticallyChecksForUpdates
        lastCheck = updater.lastUpdateCheckDate
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheck = value }
            .store(in: &watchers)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.lastCheck = value }
            .store(in: &watchers)
    }

    /// "Check for Updates…": always answers, even when Fifteen is up to date.
    func checkNow() {
        // A menu bar app isn't frontmost; bring it forward so Sparkle's window isn't hidden behind others.
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

/// Fifteen lives in the menu bar, with no Dock icon. Sparkle asks such apps to opt into gentle
/// reminders, so a scheduled update shows up in front instead of quietly behind other windows.
private final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if handleShowingUpdate {
            DispatchQueue.main.async { NSApp.activate() }
        }
    }
}
