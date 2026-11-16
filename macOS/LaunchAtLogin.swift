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

    /// Whether Fifteen opens at login, or will once it runs from Applications (it's on by default).
    static var isOn: Bool {
        SMAppService.mainApp.status == .enabled || !UserDefaults.standard.bool(forKey: setUpKey)
    }

    /// The choice from onboarding. Off is remembered, so the first-launch setup never turns it back on.
    /// On registers now from Applications, or leaves it to `enableOnFirstLaunch` once Fifteen is moved there.
    static func set(_ on: Bool) {
        let defaults = UserDefaults.standard
        if on {
            #if !DEBUG
            guard isInApplications else {
                defaults.set(false, forKey: setUpKey)
                return
            }
            defaults.set(true, forKey: setUpKey)
            if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
            #else
            defaults.set(false, forKey: setUpKey)
            #endif
        } else {
            defaults.set(true, forKey: setUpKey)
            if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        }
    }

    private static var isInApplications: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let folders = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        return folders.contains { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }
}
