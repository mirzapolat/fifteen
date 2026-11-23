import SwiftUI

/// Which release notes to show once at launch on iPhone and iPad: every version since the one last
/// opened. A brand-new install sees the onboarding instead.
@MainActor
enum WhatsNew {
    private static let lastSeenKey = "lastSeenVersion"

    /// Works out the notes for this launch and remembers this version as seen.
    static func forThisLaunch(onboarded: Bool) -> [ReleaseNotes]? {
        let defaults = UserDefaults.standard
        let current = AppInfo.version
        defer { defaults.set(current, forKey: lastSeenKey) }
        let notes: [ReleaseNotes]
        if let lastSeen = defaults.string(forKey: lastSeenKey) {
            notes = ReleaseNotes.bundled.filter {
                isNewer($0.version, than: lastSeen) && !isNewer($0.version, than: current)
            }
        } else if onboarded {
            // Versions before this one didn't remember what was seen: someone who already went
            // through the onboarding is updating, so show what this version brings.
            notes = currentNotes
        } else {
            return nil
        }
        return notes.isEmpty ? nil : notes
    }

    /// This version's notes alone (Settings → What's New, and `--whats-new`).
    static var currentNotes: [ReleaseNotes] {
        ReleaseNotes.bundled.filter { $0.version == AppInfo.version }
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}

/// After an update: what's new, newest version first, as a sheet over the timer.
struct WhatsNewSheet: View {
    var notes: [ReleaseNotes]
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 14) {
                    AppMark()
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)
                    VStack(spacing: 4) {
                        Text("What's New")
                            .font(.largeTitle.weight(.bold))
                        Text(notes.count > 1 ? "Since you last opened Fifteen" : "In Fifteen \(notes.first?.version ?? AppInfo.version)")
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 44)
                .padding(.bottom, 32)

                VStack(alignment: .leading, spacing: 32) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        VStack(alignment: .leading, spacing: 22) {
                            if notes.count > 1 {
                                Text(note.title)
                                    .font(.title3.weight(.semibold))
                            }
                            if let intro = note.intro {
                                Text(intro)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(Array(entries(note).enumerated()), id: \.offset) { offset, entry in
                                row(entry)
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 12)
                                    .animation(.spring(duration: 0.6, bounce: 0.2)
                                        .delay(0.15 + Double(index * 4 + offset) * 0.06), value: appeared)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button {
                Haptics.play(.select)
                dismiss()
            } label: {
                Text("Continue").frame(maxWidth: .infinity).pill(prominent: true)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            // The list fades out under the button instead of running into it.
            .background {
                LinearGradient(stops: [.init(color: Color(uiColor: .systemBackground).opacity(0), location: 0),
                                       .init(color: Color(uiColor: .systemBackground), location: 0.35)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { appeared = true }
        }
    }

    private func entries(_ note: ReleaseNotes) -> [ReleaseNotes.Entry] {
        note.entries.isEmpty ? note.items.map { .init(title: nil, text: $0, symbol: nil) } : note.entries
    }

    private func row(_ entry: ReleaseNotes.Entry) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: entry.symbol ?? "sparkle")
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let title = entry.title {
                    Text(title)
                        .font(.headline)
                }
                Text(entry.text)
                    .foregroundStyle(entry.title == nil ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
