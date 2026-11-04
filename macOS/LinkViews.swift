import SwiftUI
import AppKit

extension View {
    /// While the Link card is open, the other controls fade and blur into the glass:
    /// they can't be used then, and the card is the one thing to look at.
    func steppedBack(_ active: Bool) -> some View {
        blur(radius: active ? 5 : 0)
            .opacity(active ? 0.3 : 1)
            .saturation(active ? 0 : 1)
            .allowsHitTesting(!active)
            .accessibilityHidden(active)
            .animation(Pill.morph, value: active)
    }
}

/// Whether the Link card is showing in the bubble, in place of the ring.
@Observable
@MainActor
final class LinkChrome {
    static let shared = LinkChrome()
    var isOpen = false
    /// Showing the code entry rather than the intro.
    var joining = false
}

/// The card's title, in the header's top-left spot (where the phase switcher sits otherwise).
struct LinkTitle: View {
    private var link: LinkSession { LinkSession.shared }
    private var chrome: LinkChrome { LinkChrome.shared }

    var body: some View {
        let title = link.isLinked ? "Your group" : (chrome.joining ? "Join a group" : "Focus together")
        Text(title)
            .font(.headline)
            .padding(.leading, 4)
            .contentTransition(.opacity)
            .animation(.snappy, value: title)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Top right of the bubble. "Link" until you're in a group, then the group's faces.
/// Click it and the ring makes way for the Link card; click again (or Esc) to go back.
struct LinkButton: View {
    private var link: LinkSession { LinkSession.shared }
    private var chrome: LinkChrome { LinkChrome.shared }

    var body: some View {
        Button {
            Haptics.play(.select)
            withAnimation(Pill.morph) { chrome.isOpen.toggle() }
        } label: {
            label
                .fixedSize()
                .pill(prominent: chrome.isOpen)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(Pill.morph, value: link.isLinked)
        .animation(Pill.morph, value: link.members)
        .help(link.isLinked ? "Your group" : "Focus together with friends")
        .accessibilityLabel(link.isLinked ? "Linked with \(link.others.count) others" : "Link devices")
    }

    @ViewBuilder
    private var label: some View {
        if link.isLinked && !chrome.isOpen {
            HStack(spacing: 6) {
                AvatarStack(members: link.members, myID: link.myID)
                if link.status != .linked {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Reconnecting…")
                }
            }
            .padding(.horizontal, -6)
            .transition(.blurReplace)
        } else {
            Label(chrome.isOpen ? "Done" : "Link",
                  systemImage: chrome.isOpen ? "checkmark" : "laptopcomputer.and.iphone")
                .contentTransition(.symbolEffect(.replace))
                .transition(.blurReplace)
        }
    }
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

/// The Link card: start a group, join one with a code, or see who's in yours.
/// It takes the ring's place, so the bubble keeps its size.
struct LinkCard: View {
    private var link: LinkSession { LinkSession.shared }
    private var chrome: LinkChrome { LinkChrome.shared }
    private var joining: Bool { chrome.joining }
    @State private var code = ""
    @State private var copied = false
    @FocusState private var focus: Field?
    @Namespace private var glass

    private enum Field { case name, code }

    var body: some View {
        GlassEffectContainer(spacing: 2) {
            Group {
                if link.isLinked {
                    linked.transition(.blurReplace)
                } else if joining {
                    join.transition(.blurReplace)
                } else {
                    intro.transition(.blurReplace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Pill.morph, value: link.isLinked)
        .animation(Pill.morph, value: joining)
        .animation(.snappy, value: link.problem)
        .onChange(of: link.isLinked) { if link.isLinked { chrome.joining = false; code = "" } }
    }

    // MARK: Not linked

    private var intro: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 34, weight: .ultraLight))
                Text("One timer for your group. Start, pause and breaks happen for everyone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            nameField
            HStack(spacing: Pill.spacing) {
                Button { link.createGroup() } label: {
                    Label(link.busy ? "Starting…" : "Start a Group", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .pill(prominent: true)
                }
                .buttonStyle(.plain)
                .disabled(link.busy)
                .glassEffectID("primary", in: glass)
                Button {
                    link.problem = nil
                    withAnimation(Pill.morph) { chrome.joining = true }
                } label: {
                    Label("Join", systemImage: "arrow.right")
                        .fixedSize()
                        .pill()
                }
                .buttonStyle(.plain)
                .disabled(link.busy)
                .glassEffectID("secondary", in: glass)
            }
            problem
        }
    }

    private var nameField: some View {
        @Bindable var link = link
        return HStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
            TextField("Your name", text: $link.deviceName, prompt: Text("Your name, e.g. John's Mac"))
                .textFieldStyle(.plain)
                .focused($focus, equals: .name)
                .onSubmit { focus = nil }
        }
        .fieldBox(focused: focus == .name)
        .help("What others in the group see")
    }

    private var join: some View {
        VStack(spacing: 12) {
            Text("Ask someone in the group for its 6-letter code.")
                .font(.caption)
                .foregroundStyle(.secondary)
            CodeField(code: $code, onSubmit: submitCode)
            nameField
            HStack(spacing: Pill.spacing) {
                Button {
                    link.problem = nil
                    withAnimation(Pill.morph) { chrome.joining = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: Pill.height)
                        .pill(square: true)
                }
                .buttonStyle(.plain)
                .help("Back")
                .glassEffectID("secondary", in: glass)
                Button(action: submitCode) {
                    Label(link.busy ? "Joining…" : "Join", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                        .pill(prominent: true)
                }
                .buttonStyle(.plain)
                .disabled(link.busy || code.count < 6)
                .glassEffectID("primary", in: glass)
            }
            problem
        }
    }

    private func submitCode() {
        guard code.count == 6, !link.busy else { return }
        link.join(code)
    }

    @ViewBuilder
    private var problem: some View {
        if let problem = link.problem {
            Text(problem)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .transition(.blurReplace)
        }
    }

    // MARK: Linked

    private var linked: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Group code")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text(spaced(link.code ?? ""))
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                Button(action: copyCode) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: Pill.height)
                        .pill(square: true)
                }
                .buttonStyle(.plain)
                .help("Copy the code")
                .accessibilityLabel("Copy the code")
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(link.members) { member in
                        memberRow(member)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)

            HStack {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                Spacer()
                Button { link.leave() } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                        .fixedSize()
                        .pill()
                }
                .buttonStyle(.plain)
                .help("Leave the group. Your timer carries on here.")
                .glassEffectID("secondary", in: glass)
            }
        }
    }

    private func memberRow(_ member: LinkSession.Member) -> some View {
        let isMe = member.id == link.myID
        return HStack(spacing: 8) {
            Avatar(member: member, isMe: isMe, size: 22)
            Text(member.name)
                .lineLimit(1)
            if isMe {
                Text("You")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isMe {
                Text(member.online == false ? "Away" : "Here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if link.status != .linked { return "Reconnecting…" }
        let others = link.others.count
        return others == 0 ? "Share the code to invite" : "\(others + 1) in sync"
    }

    private func spaced(_ code: String) -> String {
        code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code
    }

    private func copyCode() {
        guard let code = link.code else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation(.snappy) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { copied = false }
        }
    }
}

/// Six big letters. Takes typing or pasting ("kqx-mrt" works), keeps only what a code can hold,
/// and shows every letter in capitals the moment it's typed. The placeholder is six faint dots
/// in the same monospaced font, so each letter lands exactly where its dot was.
private struct CodeField: View {
    @Binding var code: String
    var onSubmit: () -> Void
    @State private var focused = false

    static let font = NSFont.monospacedSystemFont(ofSize: 26, weight: .semibold)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        CodeTextField(code: $code, focused: $focused, onSubmit: onSubmit)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay {
                // Still-empty: a dot for each letter to come.
                Text(String(repeating: "\u{00B7}", count: 6))
                    .font(Font(Self.font))
                    .foregroundStyle(.tertiary)
                    .opacity(code.isEmpty ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background(shape.fill(Color.primary.opacity(focused ? 0.08 : 0.045)))
            .overlay(shape.strokeBorder(Color.primary.opacity(focused ? 0.3 : 0.1), lineWidth: 1))
            .contentShape(shape)
    }
}

/// An AppKit field, because a SwiftUI one on the Mac doesn't redraw a changed value while you're
/// still typing in it: "kqx" stayed lowercase until you left the field.
private struct CodeTextField: NSViewRepresentable {
    @Binding var code: String
    @Binding var focused: Bool
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: code)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = CodeField.font
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Group code")
        // Ready to type into as soon as it appears.
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != code { field.stringValue = code }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CodeTextField
        init(parent: CodeTextField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            let clean = LinkSession.normalize(field.stringValue)
            if field.stringValue != clean {
                // Capitals right away; the caret stays at the end, where typing happens.
                field.stringValue = clean
                field.currentEditor()?.selectedRange = NSRange(location: (clean as NSString).length, length: 0)
            }
            parent.code = clean
        }

        func controlTextDidBeginEditing(_ note: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ note: Notification) { parent.focused = false }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}
