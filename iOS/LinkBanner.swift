import SwiftUI

/// "Mira paused": while you're on another tab, someone in your group changing the timer drops in
/// as a glass banner at the top for a few seconds, like the popup under the Mac's menu bar.
/// Tap it to see the group; flick it up to dismiss. (On the Timer tab the line under the ring
/// says it instead, and with Fifteen closed it's a notification.)
struct LinkBanner: View {
    var visible: Bool
    private var activity: LinkActivity { LinkActivity.shared }
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let message = visible && prefs.linkEnabled && prefs.linkNotifications ? activity.message : nil
        ZStack(alignment: .top) {
            if let message {
                Button {
                    activity.dismiss()
                    AppRouter.shared.showLink()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(message)
                                .font(.subheadline.weight(.semibold))
                                .contentTransition(.opacity)
                            if let detail = activity.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .contentTransition(.opacity)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 440)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                    if value.translation.height < -8 { activity.dismiss() }
                })
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(0.92, anchor: .top)))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows your group")
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: message)
        .onChange(of: message) { if message != nil { Haptics.play(.select) } }
    }
}
