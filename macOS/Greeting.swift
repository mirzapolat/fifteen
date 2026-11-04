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

// MARK: - Release notes

/// One version's notes, read from the bundled `release-notes/<version>.html`: the same file Sparkle's
/// update window and the GitHub release show. An `<h2>` title, a `<p>` line and a `<ul>` of changes.
struct ReleaseNotes: Identifiable {
    var version: String
    var title: String
    var intro: String?
    var items: [String]
    var id: String { version }

    /// Every bundled version, newest first.
    static let bundled: [ReleaseNotes] = {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("release-notes"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension == "html" }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).map {
                    parse($0, version: url.deletingPathExtension().lastPathComponent)
                }
            }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }()

    static func parse(_ html: String, version: String) -> ReleaseNotes {
        func contents(of tag: String) -> [String] {
            let pattern = try! Regex("<\(tag)(?:\\s[^>]*)?>(.*?)</\(tag)>").dotMatchesNewlines().ignoresCase()
            return html.matches(of: pattern)
                .compactMap { $0.output[1].substring.map { plainText(String($0)) } }
                .filter { !$0.isEmpty }
        }
        return ReleaseNotes(version: version,
                            title: contents(of: "h2").first ?? "Fifteen \(version)",
                            intro: contents(of: "p").first,
                            items: contents(of: "li"))
    }

    private static func plainText(_ html: String) -> String {
        var text = html.replacing(try! Regex("<[^>]+>"), with: "")
        for (entity, character) in ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                                    "&apos;": "'", "&rsquo;": "’", "&nbsp;": " ", "&amp;": "&"] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - Views

/// First launch: what Fifteen is and where to find it, since a menu bar app has no window of its own.
struct WelcomeView: View {
    var begin: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: appeared ? 0.78 : 0)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 96, height: 96)
            .animation(.spring(duration: 1.4, bounce: 0.2).delay(0.2), value: appeared)

            VStack(spacing: 8) {
                Text("One timer. One thing.")
                    .font(.largeTitle.weight(.semibold))
                Text("Focus for 25 minutes, then rest for 5. After four rounds, take a longer break.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                row("menubar.rectangle", "Fifteen lives in the menu bar. Click its ring to open the timer.")
                row("cursorarrow.click", "Right-click it for more, or ⌥-click to start and pause.")
                row("keyboard", "From anywhere: ⌃⌥P starts and pauses, ⌃⌥O opens the timer.")
                row("person.2", "Focus together with friends in Link.")
                row("power", "Opens at login, so it's always there. Change it in Settings.")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: begin) {
                Text("Begin").frame(maxWidth: .infinity).pill(prominent: true)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(width: 440)
        .onAppear { appeared = true }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).frame(width: 22)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

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
