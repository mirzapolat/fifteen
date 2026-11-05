import SwiftUI

/// "Cover the screen during breaks", the iPhone's version of the Mac's break curtain: while a
/// break runs, a calm dark screen with the ring and something to do, so the break actually happens.
/// One more minute and Skip are right there; "Back to the timer" closes it for this break.
struct BreakCoverHost: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(Preferences.self) private var prefs
    /// The break (by its start) whose cover you closed; it stays closed until the next one.
    @State private var closedFor: Date?

    var body: some View {
        Color.clear
            .fullScreenCover(isPresented: Binding(get: { shows }, set: { if !$0 { closedFor = engine.sessionStart } })) {
                BreakCover { closedFor = engine.sessionStart }
            }
    }

    private var shows: Bool {
        prefs.breakCurtain && engine.phase.isBreak && engine.state == .running
            && (closedFor == nil || closedFor != engine.sessionStart)
    }
}

private struct BreakCover: View {
    var close: () -> Void
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        GeometryReader { geo in
            let dial = min(geo.size.width - 96, geo.size.height * 0.42, 340)
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                DialView(lineWidth: 7)
                    .frame(width: dial, height: dial)
                Text(BreakTips.tip(for: engine.sessionStart))
                    .font(.title3.weight(.light))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 36)
                    .padding(.horizontal, 32)
                Text(nextLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer(minLength: 24)
                GlassEffectContainer(spacing: 2) {
                    HStack(spacing: Pill.spacing) {
                        Button { engine.extend(by: 60) } label: {
                            Label("1 More Minute", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                                .pill()
                        }
                        Button { engine.skip() } label: {
                            Label("Skip Break", systemImage: "forward.end")
                                .frame(maxWidth: .infinity)
                                .pill()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
                Button(action: close) {
                    Text("Back to the timer")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    /// "Then: 25 minutes of focus".
    private var nextLine: String {
        let minutes = Preferences.shared.minutes(for: .focus)
        return Preferences.shared.isFlowtime ? "Then: Flowtime" : "Then: \(minutes) minutes of focus"
    }
}
