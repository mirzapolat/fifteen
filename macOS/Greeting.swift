import AppKit
import SwiftUI

/// What Fifteen shows once at launch: a welcome on a brand-new install, or what's new after an
/// update (the release notes of every version since the one last opened).
enum Greeting {
    case welcome
    case whatsNew([ReleaseNotes])

    private static let lastSeenKey = "lastSeenVersion"

    /// Works out the greeting for this launch and remembers this version as seen.
    /// Call it before Sparkle starts, which marks the app as launched before.
    static func forThisLaunch() -> Greeting? {
        let defaults = UserDefaults.standard
        let current = AppInfo.version
        defer { defaults.set(current, forKey: lastSeenKey) }

        let lastSeen: String
        if let seen = defaults.string(forKey: lastSeenKey) {
            lastSeen = seen
        } else if hasRunBefore {
            // Fifteen 1.0 didn't remember versions; anyone with traces of it came from 1.0.
            lastSeen = "1.0"
        } else {
            return .welcome
        }
        let notes = ReleaseNotes.bundled.filter {
            isNewer($0.version, than: lastSeen) && !isNewer($0.version, than: current)
        }
        return notes.isEmpty ? nil : .whatsNew(notes)
    }

    /// This version's notes alone, for `--whats-new`.
    static var currentNotes: [ReleaseNotes] {
        ReleaseNotes.bundled.filter { $0.version == AppInfo.version }
    }

    private static var hasRunBefore: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "SUHasLaunchedBefore") != nil // Sparkle sets it, since 1.0
            || defaults.object(forKey: "SULastCheckTime") != nil
            || defaults.object(forKey: "launchAtLoginSetUp") != nil
            || FileManager.default.fileExists(atPath: HistoryStore.folder.appendingPathComponent("history.json").path)
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}

// MARK: - Views

/// After an update: the notes of each version since the last one opened, newest first.
struct WhatsNewView: View {
    var notes: [ReleaseNotes]
    var done: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .medium))
                Text("What's New in Fifteen")
                    .font(.title.weight(.semibold))
                Text("Version \(AppInfo.version)")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 10) {
                            if notes.count > 1 {
                                Text(note.title).font(.headline)
                            }
                            if let intro = note.intro {
                                Text(intro).foregroundStyle(.secondary)
                            }
                            ForEach(note.items, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(item)
                                }
                            }
                        }
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: done) {
                Text("Continue").frame(maxWidth: .infinity).pill(prominent: true)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(width: 440)
    }
}
