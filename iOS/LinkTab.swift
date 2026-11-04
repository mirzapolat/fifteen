import SwiftUI
import UIKit

/// Link on iPhone and iPad: start a group, join one with a code, or see who's in yours.
/// Same black-and-white glass as the timer, one calm column, big type for the code.
struct LinkTab: View {
    private var link: LinkSession { LinkSession.shared }
    @State private var joining = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    Group {
                        if link.isLinked {
                            LinkedPage()
                                .transition(.blurReplace)
                        } else if joining {
                            JoinPage(back: { withAnimation(Pill.morph) { joining = false } })
                                .transition(.blurReplace)
                        } else {
                            IntroPage(join: { withAnimation(Pill.morph) { joining = true } })
                                .transition(.blurReplace)
                        }
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .animation(Pill.morph, value: link.isLinked)
            .animation(.snappy, value: link.problem)
            .onChange(of: link.isLinked) { if link.isLinked { joining = false } }
        }
    }
}

// MARK: - Not linked

/// Two rings, drawn in like the onboarding one: two people, one rhythm.
private struct LinkMark: View {
    @State private var appeared = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = Color.ink(scheme)
        HStack(spacing: -34) {
            ring(ink, to: 0.78, delay: 0.1)
            ring(ink, to: 0.78, delay: 0.3)
                .rotationEffect(.degrees(180))
        }
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }

    private func ring(_ ink: Color, to end: Double, delay: Double) -> some View {
        ZStack {
            Circle().stroke(ink.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: appeared ? end : 0)
                .stroke(ink, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 96, height: 96)
        .animation(.spring(duration: 1.4, bounce: 0.2).delay(delay), value: appeared)
    }
}

private struct IntroPage: View {
    var join: () -> Void
    private var link: LinkSession { LinkSession.shared }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            LinkMark()
                .padding(.bottom, 32)
            Text("Focus together")
                .font(.largeTitle.weight(.semibold))
            Text("One timer for your group. When anyone starts, pauses or takes a break, it happens for everyone.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Spacer(minLength: 40)

            VStack(spacing: Pill.spacing) {
                LinkNameField()
                    .padding(.bottom, 6)
                GlassEffectContainer(spacing: 2) {
                    VStack(spacing: Pill.spacing) {
                        Button { link.createGroup() } label: {
                            Label(link.busy ? "Starting…" : "Start a Group", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                                .pill(prominent: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(link.busy)
                        Button {
                            link.problem = nil
                            join()
                        } label: {
                            Label("Join with a Code", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                                .pill()
                        }
                        .buttonStyle(.plain)
                        .disabled(link.busy)
                    }
                }
                LinkProblem()
                Text("Only the timer is shared. Intentions, notes, ratings and projects stay on this device.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .padding(.bottom, 20)
        }
    }
}

private struct JoinPage: View {
    var back: () -> Void
    private var link: LinkSession { LinkSession.shared }
    @State private var code = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            Text("Join a group")
                .font(.largeTitle.weight(.semibold))
            Text("Ask someone in the group for its 6-letter code.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            CodeBoxes(code: $code, onComplete: submit)
                .padding(.top, 32)
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in
                    code = LinkSession.normalize(text)
                    submit()
                }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .tint(Color(uiColor: .label))
            .padding(.top, 16)
            Spacer(minLength: 40)

            VStack(spacing: Pill.spacing) {
                LinkNameField()
                    .padding(.bottom, 6)
                GlassEffectContainer(spacing: 2) {
                    HStack(spacing: Pill.spacing) {
                        Button {
                            link.problem = nil
                            back()
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: Pill.height)
                                .pill(square: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                        Button(action: submit) {
                            Label(link.busy ? "Joining…" : "Join", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                                .pill(prominent: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(link.busy || code.count < 6)
                    }
                }
                LinkProblem()
            }
            .padding(.bottom, 20)
        }
    }

    private func submit() {
        guard code.count == 6, !link.busy else { return }
        link.join(code)
    }
}

/// Six letter boxes over an invisible text field. Typing or pasting fills them in capitals
/// ("kqx-mrt" works too); the sixth letter joins straight away.
private struct CodeBoxes: View {
    @Binding var code: String
    var onComplete: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .focused($focused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.join)
                .onSubmit(onComplete)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Group code")
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    box(index)
                        // A little more air between the two halves: KQX MRT.
                        .padding(.leading, index == 3 ? 8 : 0)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 64)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: code) { old, new in
            let clean = LinkSession.normalize(new)
            if clean != new { code = clean }
            if clean.count == 6 && old.count < 6 { onComplete() }
        }
        .onAppear { focused = true }
    }

    private func box(_ index: Int) -> some View {
        let letters = Array(code)
        let letter = index < letters.count ? String(letters[index]) : ""
        let current = focused && index == min(letters.count, 5)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let ink = Color.ink(scheme)
        return Text(letter.isEmpty ? "\u{00B7}" : letter)
            .font(.system(size: 28, weight: .semibold, design: .monospaced))
            .foregroundStyle(letter.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .contentTransition(.opacity)
            .frame(maxWidth: 52, maxHeight: .infinity)
            .background(shape.fill(ink.opacity(current ? 0.08 : 0.045)))
            .overlay(shape.strokeBorder(ink.opacity(current ? 0.55 : 0.1), lineWidth: current ? 1.5 : 1))
            .animation(.snappy(duration: 0.2), value: current)
            .animation(.snappy(duration: 0.2), value: letter)
    }
}

/// "Your name": what others in the group see.
private struct LinkNameField: View {
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var link = LinkSession.shared
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
            TextField("Your name", text: $link.deviceName, prompt: Text("Your name"))
                .textContentType(.name)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { focused = false }
        }
        .fieldBox(focused: focused)
        .accessibilityHint("What others in the group see")
    }
}

private struct LinkProblem: View {
    var body: some View {
        if let problem = LinkSession.shared.problem {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .transition(.blurReplace)
        }
    }
}

// MARK: - Linked

/// The code on top with Invite, Copy and Leave right under it, then the shared timer, then
/// who's here: an open list of faces, no boxes.
private struct LinkedPage: View {
    private var link: LinkSession { LinkSession.shared }
    @State private var copied = false
    @State private var confirmLeave = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(link.status == .linked ? "Group code" : "Group code · reconnecting…")
                    .modifier(SmallCaps())
                    .contentTransition(.opacity)
                Text(spaced(link.code ?? ""))
                    .font(.system(size: 46, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel("Code \((link.code ?? "").map(String.init).joined(separator: " "))")
            }
            .padding(.top, 28)

            GlassEffectContainer(spacing: 2) {
                // All three labelled when they fit; on a narrow phone, Leave shrinks to its icon.
                ViewThatFits(in: .horizontal) {
                    actions(compactLeave: false)
                    actions(compactLeave: true)
                }
            }
            .padding(.top, 18)
            .confirmationDialog("Leave the group?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave Group", role: .destructive) { link.leave() }
            } message: {
                Text("Your timer carries on here, on its own. You can join again with the same code.")
            }

            SharedTimerCard()
                .padding(.top, 36)

            VStack(alignment: .leading, spacing: 18) {
                Text("In this group · \(link.members.count)")
                    .modifier(SmallCaps())
                ForEach(link.members) { member in
                    memberRow(member)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 36)
            .padding(.bottom, 24)
            .animation(.snappy, value: link.members)

            Spacer(minLength: 0)
        }
    }

    private func actions(compactLeave: Bool) -> some View {
        HStack(spacing: Pill.spacing) {
            ShareLink(item: inviteText) {
                Label("Invite", systemImage: "square.and.arrow.up")
                    .fixedSize()
                    .pill(prominent: true)
            }
            .buttonStyle(.plain)
            Button(action: copyCode) {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .fixedSize()
                    .pill()
            }
            .buttonStyle(.plain)
            Button { confirmLeave = true } label: {
                if compactLeave {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .frame(width: Pill.height)
                        .pill(square: true)
                } else {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                        .fixedSize()
                        .pill()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave Group")
        }
        .fixedSize()
    }

    /// A face with a presence dot, the name, and a quiet line under it.
    private func memberRow(_ member: LinkSession.Member) -> some View {
        let isMe = member.id == link.myID
        let away = member.online == false
        let ink = Color.ink(scheme)
        return HStack(spacing: 14) {
            Avatar(member: member, isMe: isMe, size: 44)
                .overlay(alignment: .bottomTrailing) {
                    if !isMe {
                        Circle()
                            .fill(away ? Color(uiColor: .systemBackground) : ink)
                            .overlay(Circle().strokeBorder(ink.opacity(away ? 0.35 : 0), lineWidth: 1.5))
                            .frame(width: 13, height: 13)
                            .padding(2)
                            .background(Circle().fill(Color(uiColor: .systemBackground)))
                            .offset(x: 2, y: 2)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(isMe ? "You" : (away ? "Away" : "Here"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .opacity(away ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private var inviteText: String {
        "Focus with me on Fifteen. Join my group with the code \(spaced(link.code ?? ""))."
    }

    private func spaced(_ code: String) -> String {
        code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code
    }

    private func copyCode() {
        guard let code = link.code else { return }
        UIPasteboard.general.string = code
        Haptics.play(.select)
        withAnimation(.snappy) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { copied = false }
        }
    }
}

/// Small uppercase label: "GROUP CODE", "IN THIS GROUP · 3".
private struct SmallCaps: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

/// The group's timer at a glance; tap it to go to the Timer tab.
/// Says who changed it last for a few seconds ("Mira paused").
private struct SharedTimerCard: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { AppRouter.shared.tab = .timer } label: {
            HStack(spacing: 14) {
                ProgressRing(progress: TimerProgress.fraction(engine), lineWidth: 4)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: engine.phase.symbol)
                            .font(.caption.weight(.semibold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.isFlowtime ? "Flowtime" : engine.phase.title)
                        .font(.headline)
                    Text(LinkActivity.shared.message ?? stateLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(TimerProgress.clock(engine))
                    .font(.title2.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: !engine.isFlowtime))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(InsightStyle(scheme: scheme).card())
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: LinkActivity.shared.message)
        .accessibilityHint("Shows the timer")
    }

    private var stateLine: String {
        switch engine.state {
        case .idle: "Ready for whoever starts"
        case .running: engine.isFlowtime ? "Counting up together" : "Running for everyone"
        case .paused: "Paused for everyone"
        case .finished: engine.phase == .focus ? "Session complete" : "Break's over"
        }
    }
}
