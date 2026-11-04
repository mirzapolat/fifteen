import SwiftUI

/// Facts about the app, in one place.
enum AppInfo {
    static let name = "Fifteen"
    static let tagline = "A minimalist black-and-white Pomodoro timer."
    static let developer = "Mirza Polat"
    static let releaseDate = DateComponents(calendar: .current, year: 2026, month: 11, day: 3).date ?? .now
    static let platforms = "Mac, iPhone and iPad"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var copyright: String {
        "© \(Calendar.current.component(.year, from: releaseDate)) \(developer)"
    }
}

struct AboutView: View {
    #if os(macOS)
    @Environment(Preferences.self) private var prefs
    #endif

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    #if os(macOS)
                    // The icon you picked in Display (it carries its own shadow).
                    Image(nsImage: AppIconArt.image(prefs.appIcon, size: 256))
                        .resizable()
                        .frame(width: 104, height: 104)
                    #else
                    AppMark()
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    #endif
                    Text(AppInfo.name)
                        .font(.title.weight(.semibold))
                    Text("Version \(AppInfo.version) (\(AppInfo.build))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(AppInfo.tagline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("App") {
                LabeledContent("Version", value: AppInfo.version)
                LabeledContent("Build", value: AppInfo.build)
                LabeledContent("Released") {
                    Text(AppInfo.releaseDate, format: .dateTime.day().month(.wide).year())
                }
                LabeledContent("Available on", value: AppInfo.platforms)
            }

            Section {
                LabeledContent("Developer", value: AppInfo.developer)
            } header: {
                Text("Developer")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free, with no account and no ads. Your history stays on this device; Link shares only the timer.")
                    Text(AppInfo.copyright)
                }
            }

            #if os(macOS)
            // Where Mac apps usually keep their reset buttons. (On iPhone they're in Settings.)
            ResetSection()
            #endif
        }
        .formStyle(.grouped)
    }
}

/// The Fifteen mark, drawn in SwiftUI so it matches the app icon on every platform:
/// a big, bold white "15" on black.
struct AppMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(Color.black)
                Text("15")
                    .font(.system(size: s * 0.55, weight: .black, design: .rounded))
                    .kerning(-s * 0.027)
                    .foregroundStyle(.white)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
