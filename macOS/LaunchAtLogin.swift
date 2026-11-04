import Foundation
import ServiceManagement

/// Fifteen opens at login by default. It's switched on once, the first time Fifteen runs from
/// Applications; after that it's the user's choice (Settings → General, or System Settings →
/// Login Items), and Fifteen never turns it back on.
enum LaunchAtLogin {
    private static let setUpKey = "launchAtLoginSetUp"

    /// Called once at launch.
    static func enableOnFirstLaunch() {
        #if !DEBUG // Fifteen Dev from Xcode shouldn't add itself to Login Items.
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: setUpKey) else { return }
        // Not yet while it runs from the disk image or Downloads: login would open that copy.
        // It's tried again on the next launch, once Fifteen has been moved to Applications.
        guard isInApplications else { return }
        defaults.set(true, forKey: setUpKey)
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        #endif
    }

    private static var isInApplications: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let folders = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        return folders.contains { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }
}
