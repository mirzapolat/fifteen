import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

/// Native Mac preferences: toolbar tabs with icons above their labels,
/// and the window animates to each pane's height.
@MainActor
final class SettingsTabController: NSTabViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        canPropagateSelectedChildViewControllerTitle = true
        transitionOptions = [.crossfade, .allowUserInteraction]
        add("General", symbol: "gearshape", height: Self.paneHeight) { GeneralPane() }
        add("Keyboard", symbol: "keyboard", height: Self.paneHeight) { KeyboardPane() }
        add("Timer", symbol: "timer", height: Self.paneHeight) { Form { TimerSettingsSection() }.formStyle(.grouped) }
        add("Sound", symbol: "speaker.wave.2", height: Self.paneHeight) { Form { SoundSettingsSection() }.formStyle(.grouped) }
        add("Display", symbol: "circle.lefthalf.filled", height: Self.paneHeight) {
            Form { DisplaySettingsSection() }.formStyle(.grouped)
        }
        add("Focus", symbol: "eye.slash", height: Self.paneHeight) { FocusPane() }
        add("About", symbol: "info.circle", height: Self.paneHeight) { AboutView() }
    }

    /// Every tab is the same size, so switching tabs never resizes the window; longer panes scroll.
    private static let paneHeight: CGFloat = 620

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func add<Content: View>(_ title: String, symbol: String, height: CGFloat,
                                    @ViewBuilder content: () -> Content) {
        let root = content()
            .frame(width: 500, height: height)
            .toggleStyle(InkSwitchStyle())
            .environment(TimerEngine.shared)
            .environment(Preferences.shared)
            .environment(HistoryStore.shared)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }
}

private struct GeneralPane: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section("Menu Bar") {
                Picker("Show", selection: $prefs.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if prefs.menuBarDisplay != .time {
                    MenuBarIconPicker()
                }
                Toggle("Show seconds", isOn: $prefs.menuBarSeconds)
                    .disabled(prefs.menuBarDisplay == .icon)
                Toggle("Open the timer when a session ends", isOn: $prefs.openWhenDone)
            }

            Section {
                LinkNameField()
                Toggle("Notify when others change the timer", isOn: $prefs.linkNotifications)
            } header: {
                Text("Link")
            } footer: {
                Text("When someone in your group starts, pauses, resets or takes a break, a notification says who and what. Not while the timer is open, where it shows under the ring.")
            }

            Section {
                LaunchAtLoginToggle()
                Toggle("Pause focus while the Mac is locked", isOn: $prefs.pauseWhenLocked)
            } header: {
                Text("System")
            } footer: {
                Text("Fifteen picks up where you left off when you unlock. While linked with others, locking doesn't pause the group's timer.")
            }
        }
        .formStyle(.grouped)
    }
}

/// "Shown to others as": the name your group sees.
private struct LinkNameField: View {
    var body: some View {
        @Bindable var link = LinkSession.shared
        TextField("Shown to others as", text: $link.deviceName, prompt: Text(LinkSession.defaultName))
    }
}

/// Shortcuts that work from anywhere, and the clicks the menu bar item understands.
private struct KeyboardPane: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Toggle("Global keyboard shortcuts", isOn: $prefs.globalHotKeys)
                Group {
                    LabeledContent("Start or pause", value: "⌃⌥P")
                    LabeledContent("Skip to next", value: "⌃⌥S")
                    LabeledContent("Reset session", value: "⌃⌥R")
                    LabeledContent("Open Fifteen", value: "⌃⌥O")
                }
                .disabled(!prefs.globalHotKeys)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("These work in any app, without opening Fifteen.")
            }

            Section("Menu Bar") {
                LabeledContent("Open the timer", value: "Click")
                LabeledContent("Start or pause", value: "⌥-click")
                LabeledContent("Quick menu", value: "Right-click")
            }

            Section("In the Timer") {
                LabeledContent("Close", value: "Esc")
                LabeledContent("Start with your intention", value: "Return")
            }
        }
        .formStyle(.grouped)
    }
}

private struct FocusPane: View {
    @Environment(Preferences.self) private var prefs
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        @Bindable var prefs = prefs
        // While a session is running or paused, nothing here can be loosened: you can add
        // restrictions, but not switch them off. Finish or reset the timer to change them.
        let locked = engine.isActive
        Form {
            if locked {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Locked while a session runs")
                            Text("You can add blocked apps, but not remove them or switch blocking off. Finish or reset the timer to change these.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                }
            }
            Section {
                Toggle("Block distracting apps while focusing", isOn: $prefs.hideDistractingApps.animation())
                    .disabled(locked && prefs.hideDistractingApps)
                if prefs.hideDistractingApps {
                    Picker("When one opens", selection: $prefs.blockAction) {
                        ForEach(BlockAction.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(locked)
                }
            } header: {
                Text("App Blocker")
            } footer: {
                Text(prefs.blockAction == .hide
                     ? "Blocked apps are hidden when focus starts and whenever you open one. A small note tells you why, with a way to allow it for 5 minutes. Each attempt is logged as a distraction."
                     : "Blocked apps are quit when focus starts and whenever you open one. Make sure your work is saved in them. A small note lets you allow one for 5 minutes.")
            }

            if prefs.hideDistractingApps {
                Section("Blocked Apps") {
                    BlockedAppsList(locked: locked)
                }
            }

            DoNotDisturbSection(locked: locked)

            Section {
                Toggle("Cover the screen during breaks", isOn: $prefs.breakCurtain)
            } header: {
                Text("Breaks")
            } footer: {
                Text("A calm full-screen veil so the break actually happens. Skip is always one click (or Esc) away.")
            }
        }
        .formStyle(.grouped)
        .animation(.snappy, value: locked)
    }
}

/// Do Not Disturb and your own shortcuts, both run when focus starts and ends.
/// Do Not Disturb gets a guided one-time setup of the two shortcuts it needs.
private struct DoNotDisturbSection: View {
    var locked = false
    @Environment(Preferences.self) private var prefs
    private var dnd: DoNotDisturb { DoNotDisturb.shared }

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Turn on Do Not Disturb while focusing", isOn: $prefs.doNotDisturb.animation())
                .onChange(of: prefs.doNotDisturb) { DoNotDisturb.shared.sync() }
                .disabled(locked && prefs.doNotDisturb)
            if prefs.doNotDisturb {
                shortcutRow(DoNotDisturb.onName, found: dnd.hasOnShortcut,
                            recipe: "Add “Set Focus”, choose Do Not Disturb, set it to Turn On.")
                shortcutRow(DoNotDisturb.offName, found: dnd.hasOffShortcut,
                            recipe: "Add “Set Focus”, choose Do Not Disturb, set it to Turn Off.")
                HStack {
                    Button("Check Again") { dnd.refresh() }
                    Spacer()
                    Button(dnd.testing ? "Testing…" : "Test for 3 Seconds") { dnd.test() }
                        .disabled(!dnd.isReady || dnd.testing)
                }
            }
            TextField("Also run when focus starts", text: $prefs.focusStartShortcut, prompt: Text("Shortcut name"))
            TextField("Also run when focus ends", text: $prefs.focusEndShortcut, prompt: Text("Shortcut name"))
        } header: {
            Text("Do Not Disturb & Shortcuts")
        } footer: {
            Text((prefs.doNotDisturb && !dnd.isReady
                  ? "macOS doesn't let apps switch Focus directly, so Fifteen runs two tiny shortcuts. Make each one once with the steps above, keeping the names exactly as shown."
                  : "Notifications are silenced while you focus and come back for your breaks, when you stop, and when Fifteen quits.")
                 + " You can also run your own shortcuts, for example to start a playlist or set your status.")
        }
        .onAppear { dnd.refresh() }
    }

    private func shortcutRow(_ name: String, found: Bool, recipe: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: found ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(found ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("“\(name)”")
                Text(found ? "Ready" : (dnd.checked ? recipe : "Checking…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !found {
                Button("Create…") { dnd.create(name) }
            }
        }
    }
}

/// One tile per menu bar icon style, each previewed mid-session exactly as it will look.
private struct MenuBarIconPicker: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon")
            HStack(spacing: 6) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    let selected = prefs.menuBarIcon == style
                    Button {
                        withAnimation(.snappy) { prefs.menuBarIcon = style }
                    } label: {
                        VStack(spacing: 6) {
                            Image(nsImage: MenuBarIcon.image(style: style, fraction: 0.62, state: .running, phase: .focus))
                                .renderingMode(.template)
                                .frame(height: 18)
                            Text(style.title)
                                .font(.caption)
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(selected ? 0.1 : 0.03)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(style.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open Fifteen at login", isOn: $enabled)
            .onChange(of: enabled) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

private struct BlockedAppsList: View {
    /// During a session apps can be added but not removed.
    var locked = false
    @Environment(Preferences.self) private var prefs

    /// Common time sinks, offered one click away if they're installed.
    private static let suggestedIDs = [
        "com.apple.MobileSMS", "com.apple.mail", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "org.telegram.desktop", "com.facebook.archon",
        "com.microsoft.teams2", "com.apple.news", "com.apple.TV", "com.apple.Music", "com.spotify.client",
        "com.valvesoftware.steam", "com.apple.FaceTime", "com.apple.Photos", "com.reddit.Reddit",
    ]

    var body: some View {
        if prefs.blockedApps.isEmpty {
            Text("No apps blocked yet.")
                .foregroundStyle(.secondary)
        }
        ForEach(prefs.blockedApps, id: \.self) { id in
            HStack {
                Image(nsImage: icon(for: id))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(name(for: id))
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                        .help("Can't be removed during a session")
                } else {
                    Button {
                        withAnimation { prefs.blockedApps.removeAll { $0 == id } }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                }
            }
        }
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggestions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { id in
                            Button {
                                withAnimation { prefs.blockedApps.append(id) }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(nsImage: icon(for: id))
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                    Text(name(for: id))
                                    Image(systemName: "plus")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    }
                }
            }
        }
        HStack {
            Menu("Add Running App") {
                ForEach(runningApps, id: \.self) { id in
                    Button(name(for: id)) { prefs.blockedApps.append(id) }
                }
            }
            .fixedSize()
            Button("Choose App…") { chooseApps() }
        }
    }

    private var suggestions: [String] {
        Self.suggestedIDs.filter { url(for: $0) != nil && !prefs.blockedApps.contains($0) }
    }

    private var runningApps: [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { $0 != Bundle.main.bundleIdentifier && !prefs.blockedApps.contains($0) }
            .sorted { name(for: $0).localizedCaseInsensitiveCompare(name(for: $1)) == .orderedAscending }
    }

    private func url(for id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    private func name(for id: String) -> String {
        guard let url = url(for: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func icon(for id: String) -> NSImage {
        guard let url = url(for: id) else { return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !prefs.blockedApps.contains(id) {
                prefs.blockedApps.append(id)
            }
        }
    }
}
