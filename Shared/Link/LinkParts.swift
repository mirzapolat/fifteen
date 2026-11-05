import SwiftUI
import Observation

/// Whether the Link card is showing in the bubble, in place of the ring.
@Observable
@MainActor
final class LinkChrome {
    static let shared = LinkChrome()
    var isOpen = false
    /// Whether the timer is on screen: the Mac's bubble is open, or the iPhone is on the Timer tab.
    /// Then the line under the ring says what changed, and no banner is needed.
    @ObservationIgnored var timerVisible = false
    /// iPhone and iPad: Fifteen is open and in front, so a change can show in the app itself.
    @ObservationIgnored var appActive = false
    /// Showing the code entry rather than the intro.
    var joining = false
}

/// Overlapping initials, like a little huddle. Away devices are dimmed.
struct AvatarStack: View {
    var members: [LinkSession.Member]
    var myID: String?
    var size: CGFloat = 20

    var body: some View {
        let shown = Array(members.prefix(4))
        HStack(spacing: -size * 0.3) {
            ForEach(shown) { member in
                Avatar(member: member, isMe: member.id == myID, size: size)
            }
            if members.count > shown.count {
                Text("+\(members.count - shown.count)")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .padding(.leading, size * 0.4)
            }
        }
    }
}

struct Avatar: View {
    var member: LinkSession.Member
    var isMe = false
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = Color.ink(scheme)
        Text(member.initials)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(isMe ? Color.ink(scheme == .dark ? .light : .dark) : ink)
            .frame(width: size, height: size)
            .background(Circle().fill(isMe ? ink : ink.opacity(0.14)))
            .overlay(Circle().strokeBorder(ink.opacity(0.25), lineWidth: 0.5))
            .opacity(member.online == false ? 0.4 : 1)
    }
}
