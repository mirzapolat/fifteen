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
        add("Insights", symbol: "chart.line.uptrend.xyaxis", height: Self.paneHeight) {
            Form { InsightsSettingsSection() }
                .formStyle(.grouped)
                .onChange(of: Preferences.shared.insightsEnabled) {
                    if !Preferences.shared.insightsEnabled { WindowRouter.shared.closeHistory() }
                }
        }
        add("Link", symbol: "person.2", height: Self.paneHeight) { LinkPane() }
        add("Calendar", symbol: "calendar", height: Self.paneHeight) { CalendarSettingsPane() }
        add("Focus", symbol: "eye.slash", height: Self.paneHeight) { FocusPane() }
        add("About", symbol: "info.circle", height: Self.paneHeight) { AboutView() }
    }

    /// Every tab is the same size, so switching tabs never resizes the window; longer panes scroll.
    private static let paneHeight: CGFloat = 620
    /// Wide enough for all ten toolbar tabs.
    private static let paneWidth: CGFloat = 680

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func add<Content: View>(_ title: String, symbol: String, height: CGFloat,
                                    @ViewBuilder content: () -> Content) {
        let root = content()
            .frame(width: Self.paneWidth, height: height)
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
            Section {
                LaunchAtLoginToggle()
                Toggle("Pause focus while the Mac is locked", isOn: $prefs.pauseWhenLocked)
            } header: {
                Text("System")
            } footer: {
                Text("Fifteen picks up where you left off when you unlock. While linked with others, locking doesn't pause the group's timer.")
            }

            UpdatesSection()
        }
        .formStyle(.grouped)
    }
}

/// Link: the master switch, your name in the group, and how others' changes reach you.
private struct LinkPane: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            LinkMasterToggle()
            if prefs.linkEnabled {
                Section {
                    LinkNameField()
                    Toggle("Notify when others change the timer", isOn: $prefs.linkNotifications.animation())
                    if prefs.linkNotifications {
                        Picker("Show as", selection: $prefs.linkAlertStyle.animation()) {
                            ForEach(LinkAlertStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if prefs.linkAlertStyle.showsNotification && !prefs.notifications { NotificationAccessWarning() }
                    }
                } header: {
                    Text("In a Group")
                } footer: {
                    Text("When someone in your group starts, pauses, resets or takes a break, a small popup under the menu bar, a system notification or both say who and what. Not while the timer is open, where it shows under the ring.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Automatic checks (on by default), and a way to check right now.
private struct UpdatesSection: View {
    var body: some View {
        @Bindable var updater = Updater.shared
        Section {
            Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
            LabeledContent {
                Button("Check Now") { updater.checkNow() }
                    .disabled(!updater.canCheck)
            } label: {
                Text("Version \(AppInfo.version) (\(AppInfo.build))")
                if let last = updater.lastCheck {
                    Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("About once a day Fifteen asks GitHub whether there's a newer version. Nothing else is sent.")
        }
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
                    Label("Locked while a session runs", systemImage: "lock.fill")
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
            }

            if prefs.hideDistractingApps {
                Section("Blocked Apps") {
                    BlockedAppsList(locked: locked)
                }
            }

            WebsiteBlockerSection(locked: locked)

            DoNotDisturbSection(locked: locked)

            Section {
                Toggle("Cover the screen during breaks", isOn: $prefs.breakCurtain)
            } header: {
                Text("Breaks")
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

/// What the menu bar item shows: the time, an icon, or both. Lives in Display.
struct MenuBarSettingsSection: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
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
        HStack {
            Menu("Add Running App") {
                ForEach(runningApps, id: \.self) { id in
                    Button(name(for: id)) { prefs.blockedApps.append(id) }
                }
            }
            .fixedSize()
            Button("Choose App…") { chooseApps() }
            // Common time sinks that are installed, one click away.
            if !suggestions.isEmpty {
                Menu("Suggestions") {
                    ForEach(suggestions, id: \.self) { id in
                        Button {
                            withAnimation { prefs.blockedApps.append(id) }
                        } label: {
                            Label { Text(name(for: id)) } icon: { Image(nsImage: menuIcon(for: id)) }
                        }
                    }
                }
                .fixedSize()
            }
        }
    }

    /// Menus draw an app icon at its full size; this one is shrunk to fit a menu row.
    private func menuIcon(for id: String) -> NSImage {
        let image = icon(for: id).copy() as? NSImage ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        return image
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

/// Websites kept closed during focus: a block list, or an allow list that closes everything else.
/// Also the one-time browser permissions it needs.
private struct WebsiteBlockerSection: View {
    /// During a session the rules can only get stricter: a block list can grow, an allow list can shrink.
    var locked = false
    @Environment(Preferences.self) private var prefs
    @State private var draft = ""
    @State private var firefoxTrusted = FirefoxAddressBar.isTrusted
    private var blocker: WebBlocker { WebBlocker.shared }

    private var allowMode: Bool { prefs.siteListMode == .allow }
    /// The list the current mode edits.
    private var sites: [String] { allowMode ? prefs.allowedSites : prefs.blockedSites }
    private func setSites(_ new: [String]) {
        if allowMode { prefs.allowedSites = new } else { prefs.blockedSites = new }
    }
    /// Locked block list: no removing. Locked allow list: no adding.
    private var canRemove: Bool { !locked || allowMode }
    private var canAdd: Bool { !locked || !allowMode }

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Block distracting websites while focusing", isOn: $prefs.blockWebsites.animation())
                .disabled(locked && prefs.blockWebsites)
            if prefs.blockWebsites {
                Picker("Mode", selection: $prefs.siteListMode.animation()) {
                    ForEach(SiteListMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(locked)

                if sites.isEmpty {
                    Text(allowMode ? "No websites allowed yet, so every website is blocked." : "No websites blocked yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sites, id: \.self) { site in
                    HStack {
                        Group {
                            if let icon = Favicons.shared.icon(for: site) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(site)
                        Spacer()
                        Picker("Covers", selection: scope(site)) {
                            Text("All Subdomains").tag(false)
                            Text("Exact Domain").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .disabled(locked)
                        .help(locked ? "Can't be changed during a session" : "Whether subdomains are included")
                        if canRemove {
                            Button {
                                withAnimation {
                                    setSites(sites.filter { $0 != site })
                                    prefs.exactSites.removeAll { $0 == site }
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Remove")
                        } else {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.tertiary)
                                .help("Can't be removed during a session")
                        }
                    }
                }
                if canAdd {
                    HStack {
                        TextField("Add website", text: $draft, prompt: Text("example.com"))
                            .onSubmit { add(draft) }
                        Button("Add") { add(draft) }
                            .disabled(WebBlocker.normalize(draft) == nil)
                    }
                }
            }
        } header: {
            Text("Website Blocker")
        }

        if prefs.blockWebsites {
            Section("Browsers") {
                ForEach(Browser.installed, id: \.id) { browser in
                    browserRow(browser.id, kind: browser.kind)
                }
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                firefoxTrusted = FirefoxAddressBar.isTrusted
            }
        }
    }
    private func isExact(_ site: String) -> Bool { prefs.exactSites.contains(site) }

    /// Subdomains included (false, the default) or just this domain (true).
    private func scope(_ site: String) -> Binding<Bool> {
        Binding {
            isExact(site)
        } set: { exact in
            prefs.exactSites.removeAll { $0 == site }
            if exact { prefs.exactSites.append(site) }
        }
    }

    /// What a browser still needs before Fifteen can look into it: the warning and the button that fixes it.
    private func missingPermission(_ id: String, kind: Browser.Kind) -> (text: String, button: String, action: () -> Void)? {
        if kind == .firefox && !firefoxTrusted {
            return ("Needs access", "Allow…", {
                FirefoxAddressBar.requestAccess()
                open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            })
        }
        if blocker.deniedBrowsers.contains(id) {
            return ("Needs access", "Allow…", {
                open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            })
        }
        return nil
    }

    /// One browser: watched or left alone, and what it's missing. During a session a browser can be
    /// switched on, not off.
    private func browserRow(_ id: String, kind: Browser.Kind) -> some View {
        let on = !prefs.ignoredBrowsers.contains(id)
        let missing = on ? missingPermission(id, kind: kind) : nil
        return Toggle(isOn: Binding {
            on
        } set: { watch in
            withAnimation(.snappy) {
                prefs.ignoredBrowsers.removeAll { $0 == id }
                if !watch { prefs.ignoredBrowsers.append(id) }
            }
        }) {
            HStack(spacing: 10) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 22, height: 22)
                }
                Text(browserName(id))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let missing {
                    // The warning and its fix together, in one small bubble beside the switch.
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(missing.text)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                        Button(missing.button, action: missing.action)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                    }
                    .font(.caption)
                    .fixedSize()
                    .padding(.leading, 8)
                    .padding(.trailing, 3)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.orange.opacity(0.12)))
                }
            }
        }
        .disabled(locked && on)
    }

    private func add(_ input: String) {
        guard canAdd, let site = WebBlocker.normalize(input) else { return }
        if !sites.contains(site) {
            withAnimation { setSites(sites + [site]) }
        }
        draft = ""
    }

    private func browserName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}
