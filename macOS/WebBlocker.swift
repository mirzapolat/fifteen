import AppKit
import ApplicationServices
import Observation
import os

/// Keeps distracting websites closed during focus, in Safari, Chrome (and its Chromium siblings) and Firefox.
/// - Safari and the Chromium browsers are asked for their tab URLs over Apple Events; macOS asks once
///   per browser whether Fifteen may control it.
/// - Firefox has no scripting for tabs, so its address bar is read through Accessibility.
/// A blocked tab is sent to a calm local page, a toast says why, and "Allow 5 min" lets it through.
@Observable
@MainActor
final class WebBlocker {
    static let shared = WebBlocker()

    /// Browsers that refused Apple Events (the person said no in the Automation prompt).
    private(set) var deniedBrowsers: Set<String> = []

    @ObservationIgnored private let engine = TimerEngine.shared
    @ObservationIgnored private let prefs = Preferences.shared
    @ObservationIgnored private var allowedUntil: [String: Date] = [:]
    @ObservationIgnored private var checking = false
    /// Apple Events and Accessibility calls block, sometimes for a while, so they run off the main thread.
    @ObservationIgnored private let queue = DispatchQueue(label: "com.mirzapolat.fifteen.webblocker")

    var isActive: Bool {
        prefs.blockWebsites && (prefs.siteListMode == .allow || !prefs.blockedSites.isEmpty)
            && engine.phase == .focus && engine.isActive
    }

    func start() {
        writeBlockPage()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { WebBlocker.shared.checkFrontTab() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { WebBlocker.shared.checkFrontTab() }
        }
        engine.observe { event in
            switch event {
            case .started(.focus), .resumed:
                WebBlocker.shared.sweep()
            case .finished, .stopped:
                WebBlocker.shared.allowedUntil = [:]
            default:
                break
            }
        }
    }

    // MARK: Checking

    /// Looks at the tab in front, if a browser is in front. Runs every second during focus.
    private func checkFrontTab() {
        guard isActive, !checking,
              let app = NSWorkspace.shared.frontmostApplication,
              let browser = watched(app) else { return }
        checking = true
        let pid = app.processIdentifier
        queue.async {
            let result = browser.frontURL(pid: pid)
            DispatchQueue.main.async {
                let blocker = WebBlocker.shared
                blocker.checking = false
                blocker.note(result, for: browser)
                guard case .success(let url?) = result, let site = blocker.blockedSite(for: url) else { return }
                blocker.block(url, site: site, in: browser, app: app)
            }
        }
    }

    /// When focus starts, every open tab of a blocked site goes away at once, quietly.
    func sweep() {
        guard isActive else { return }
        let running = NSWorkspace.shared.runningApplications.compactMap { app in watched(app).map { ($0, app) } }
        guard !running.isEmpty else { return }
        let page = blockPageURL
        let rules = self.rules
        let allowed = allowedUntil.filter { $0.value > Date() }.map(\.key)
        queue.async {
            var closed: [String] = []
            var results: [(Browser, Result<URL?, BrowserError>)] = []
            for (browser, app) in running {
                switch browser.allTabs(pid: app.processIdentifier) {
                case .success(let tabs):
                    results.append((browser, .success(nil)))
                    for tab in tabs {
                        guard let site = rules.blockedSite(for: tab.url), !allowed.contains(site) else { continue }
                        browser.navigate(tab.ref, to: page(site), pid: app.processIdentifier)
                        if !closed.contains(site) { closed.append(site) }
                    }
                case .failure(let error):
                    results.append((browser, .failure(error)))
                }
            }
            DispatchQueue.main.async {
                let blocker = WebBlocker.shared
                for (browser, result) in results { blocker.note(result, for: browser) }
                guard !closed.isEmpty else { return }
                AppBlocker.shared.toast.show(
                    icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil),
                    title: "Closed " + blocker.list(closed),
                    subtitle: "They'll be here when your session ends.",
                    allow: nil)
            }
        }
    }

    private func block(_ url: URL, site: String, in browser: Browser, app: NSRunningApplication) {
        let pid = app.processIdentifier
        let page = blockPageURL(site)
        queue.async { browser.navigate(.front, to: page, pid: pid) }
        engine.logDistraction()
        let left = engine.state == .paused ? "Focus paused"
            : engine.isFlowtime ? "In the flow" : "\(TimeFormat.short(engine.remaining)) of focus left"
        AppBlocker.shared.toast.show(
            icon: Favicons.shared.icon(for: site) ?? app.icon,
            title: "\(site) can wait",
            subtitle: "\(left) · distraction logged",
            allow: { WebBlocker.shared.allow(site, url: url, in: browser, pid: pid) })
    }

    /// Lets one site through for a few minutes, on purpose, and takes you back to where you were.
    func allow(_ site: String, url: URL, in browser: Browser, pid: pid_t, minutes: Int = 5) {
        allowedUntil[site] = Date().addingTimeInterval(TimeInterval(minutes * 60))
        AppBlocker.shared.toast.hide()
        queue.async { browser.navigate(.front, to: url, pid: pid) }
    }

    /// The browser behind `app`, if it's one Fifteen supports and you haven't switched off in Settings.
    private func watched(_ app: NSRunningApplication) -> Browser? {
        guard let browser = Browser(app), !prefs.ignoredBrowsers.contains(browser.bundleID) else { return nil }
        return browser
    }

    private func note(_ result: Result<URL?, BrowserError>, for browser: Browser) {
        switch result {
        case .failure(.notAuthorized) where browser.kind != .firefox: deniedBrowsers.insert(browser.bundleID)
        case .success: deniedBrowsers.remove(browser.bundleID)
        default: break
        }
    }

    // MARK: Matching

    private var rules: SiteRules {
        SiteRules(mode: prefs.siteListMode, blocked: prefs.blockedSites, allowed: prefs.allowedSites,
                  exact: Set(prefs.exactSites))
    }

    private func blockedSite(for url: URL) -> String? {
        guard let site = rules.blockedSite(for: url) else { return nil }
        if let until = allowedUntil[site], until > Date() { return nil }
        return site
    }

    /// The listed site `url` belongs to: "m.youtube.com" matches "youtube.com", unless that one is
    /// in `exact`, which matches only "youtube.com" itself (and "www.youtube.com").
    nonisolated static func match(_ url: URL, sites: [String], exact: Set<String> = []) -> String? {
        guard let host = webHost(url) else { return nil }
        return sites.first { host == $0 || (!exact.contains($0) && host.hasSuffix("." + $0)) }
    }

    /// The host of an http(s) page, without "www." Other schemes (file:, about:, chrome:) are never blocked.
    nonisolated static func webHost(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Turns whatever was typed ("https://www.YouTube.com/feed") into a bare domain ("youtube.com").
    nonisolated static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var host = URL(string: text)?.host, host.contains("."), !host.contains(" ") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private func list(_ names: [String]) -> String {
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

    // MARK: The page a blocked tab lands on

    private var blockPageFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Fifteen", isDirectory: true)
            .appendingPathComponent("blocked.html")
    }

    /// The block page, with the site in its fragment so it can say which one.
    private var blockPageURL: (String) -> URL {
        let file = blockPageFile
        return { site in
            var components = URLComponents(url: file, resolvingAgainstBaseURL: false)
            components?.fragment = site
            return components?.url ?? file
        }
    }

    private func writeBlockPage() {
        let file = blockPageFile
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.blockPage.write(to: file, atomically: true, encoding: .utf8)
    }

    private static let blockPage = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Not now · Fifteen</title>
    <style>
      :root { color-scheme: light dark; --bg: #f6f5f2; --fg: #1c1c1e; --dim: #8a8a8e; }
      @media (prefers-color-scheme: dark) { :root { --bg: #111112; --fg: #f2f2f4; --dim: #8e8e93; } }
      html, body { height: 100%; margin: 0; }
      body { background: var(--bg); color: var(--fg); display: grid; place-items: center; text-align: center;
             font: 17px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
      main { padding: 24px; max-width: 420px; }
      svg { width: 72px; height: 72px; margin-bottom: 28px; }
      h1 { font-size: 32px; font-weight: 600; letter-spacing: -0.02em; margin: 0 0 8px; }
      p { color: var(--dim); margin: 0; }
      b { color: var(--fg); font-weight: 500; }
    </style>
    </head>
    <body>
    <main>
      <svg viewBox="0 0 72 72" aria-hidden="true">
        <circle cx="36" cy="36" r="30" fill="none" stroke="var(--dim)" stroke-opacity=".25" stroke-width="6"/>
        <circle cx="36" cy="36" r="30" fill="none" stroke="var(--fg)" stroke-width="6" stroke-linecap="round"
                stroke-dasharray="188.5" stroke-dashoffset="70" transform="rotate(-90 36 36)"/>
      </svg>
      <h1>Not now.</h1>
      <p><b id="site">This site</b> can wait until your focus session ends.</p>
    </main>
    <script>
      const site = decodeURIComponent(location.hash.slice(1));
      if (site) document.getElementById("site").textContent = site;
    </script>
    </body>
    </html>
    """
}

/// What's blocked: the listed sites, or everything but the listed sites.
struct SiteRules {
    var mode: SiteListMode
    var blocked: [String]
    var allowed: [String]
    /// Sites that don't cover their subdomains.
    var exact: Set<String> = []

    /// The name to block `url` under (and to allow it under for 5 minutes), or nil if it may stay open.
    func blockedSite(for url: URL) -> String? {
        switch mode {
        case .block:
            return WebBlocker.match(url, sites: blocked, exact: exact)
        case .allow:
            guard let host = WebBlocker.webHost(url), WebBlocker.match(url, sites: allowed, exact: exact) == nil else { return nil }
            return host
        }
    }
}

// MARK: - Browsers

enum BrowserError: Error {
    case notAuthorized, failed
}

/// A tab to send somewhere else: the one in front, or one found by a sweep.
enum TabRef {
    case front
    case index(window: Int, tab: Int)
}

struct Tab {
    var ref: TabRef
    var url: URL
}

/// A browser Fifteen knows how to look into.
struct Browser {
    enum Kind { case safari, chromium, firefox }

    let bundleID: String
    let kind: Kind

    /// In the order Settings lists them.
    static let all: [(id: String, kind: Kind)] = [
        ("com.apple.Safari", .safari),
        ("com.apple.SafariTechnologyPreview", .safari),
        ("com.google.Chrome", .chromium),
        ("com.google.Chrome.beta", .chromium),
        ("com.google.Chrome.canary", .chromium),
        ("org.mozilla.firefox", .firefox),
        ("org.mozilla.firefoxdeveloperedition", .firefox),
        ("org.mozilla.nightly", .firefox),
        ("company.thebrowser.Browser", .chromium),
        ("com.brave.Browser", .chromium),
        ("com.microsoft.edgemac", .chromium),
        ("com.vivaldi.Vivaldi", .chromium),
    ]
    static let supported = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.kind) })

    /// The supported browsers on this Mac.
    static var installed: [(id: String, kind: Kind)] {
        all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    init?(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, let kind = Self.supported[id] else { return nil }
        bundleID = id
        self.kind = kind
    }

    /// Safari calls the tab in front "current tab"; Chrome and friends call it "active tab".
    private var frontTab: String { kind == .safari ? "current tab" : "active tab" }

    // MARK: Reading

    func frontURL(pid: pid_t) -> Result<URL?, BrowserError> {
        switch kind {
        case .firefox:
            return FirefoxAddressBar.read(pid: pid).map { $0.flatMap(Self.url) }
        case .safari, .chromium:
            return run("if (count of windows) is 0 then return \"\"\nreturn URL of \(frontTab) of front window")
                .map { Self.url($0) }
        }
    }

    func allTabs(pid: pid_t) -> Result<[Tab], BrowserError> {
        switch kind {
        case .firefox:
            // Only the tab in front is visible to Accessibility.
            return frontURL(pid: pid).map { url in url.map { [Tab(ref: .front, url: $0)] } ?? [] }
        case .safari, .chromium:
            // Inside the tell, "tab" means a browser tab, so the separators are spelled out.
            let script = """
            set out to ""
            repeat with w from 1 to count of windows
                try
                    repeat with t from 1 to count of tabs of window w
                        set out to out & w & (character id 9) & t & (character id 9) & (URL of tab t of window w) & (character id 10)
                    end repeat
                end try
            end repeat
            return out
            """
            return run(script).map { text in
                text.split(separator: "\n").compactMap { line in
                    let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
                    guard parts.count == 3, let w = Int(parts[0]), let t = Int(parts[1]),
                          let url = Self.url(parts[2]) else { return nil }
                    return Tab(ref: .index(window: w, tab: t), url: url)
                }
            }
        }
    }

    // MARK: Navigating

    func navigate(_ ref: TabRef, to url: URL, pid: pid_t) {
        switch kind {
        case .firefox:
            FirefoxAddressBar.go(to: url, pid: pid)
        case .safari, .chromium:
            let target = switch ref {
            case .front: "\(frontTab) of front window"
            case .index(let w, let t): "tab \(t) of window \(w)"
            }
            _ = run("set URL of \(target) to \"\(Self.escape(url.absoluteString))\"")
        }
    }

    // MARK: Apple Events

    /// Runs `body` inside a `tell` to this browser. Callers make sure it's running, so this never launches it.
    private func run(_ body: String) -> Result<String, BrowserError> {
        let source = """
        with timeout of 3 seconds
            tell application id "\(bundleID)"
                \(body)
            end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else { return .failure(.failed) }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            Logger(subsystem: "com.mirzapolat.fifteen", category: "WebBlocker")
                // The message can quote the page's address, so it stays private; the code is enough to diagnose.
                .error("\(bundleID, privacy: .public) script failed \(code ?? 0, privacy: .public): \(error[NSAppleScript.errorMessage] as? String ?? "", privacy: .private)")
            return .failure(code == -1743 ? .notAuthorized : .failed)
        }
        return .success(output.stringValue ?? "")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Address bars sometimes leave off the scheme ("youtube.com/watch?v=…").
    private static func url(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        return URL(string: text.contains("://") ? text : "https://" + text)
    }
}

// MARK: - Firefox

/// Firefox through Accessibility: reads its address bar, and types a new address into it.
enum FirefoxAddressBar {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// When each Firefox process was last asked to switch its accessibility tree on. Only touched on WebBlocker's queue.
    nonisolated(unsafe) private static var lastEnable: [pid_t: Date] = [:]

    /// Shows the system prompt that leads to Privacy & Security → Accessibility.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// The address shown, or nil while you're typing in it (half-typed addresses aren't visits).
    static func read(pid: pid_t) -> Result<String?, BrowserError> {
        guard isTrusted else { return .failure(.notAuthorized) }
        guard let field = addressBar(pid: pid) else { return .success(nil) }
        if bool(field, kAXFocusedAttribute) { return .success(nil) }
        return .success(string(field, kAXValueAttribute))
    }

    static func go(to url: URL, pid: pid_t) {
        guard isTrusted, let field = addressBar(pid: pid) else { return }
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, url.absoluteString as CFString)
        // Return, sent straight to Firefox so nothing else can catch it.
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: down)?.postToPid(pid)
        }
    }

    /// Firefox marks its address field with the DOM id "urlbar-input". Web content is skipped:
    /// it's big and the address bar is never inside it.
    private static func addressBar(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        if let field = search(app) { return field }
        // Firefox only builds the accessibility tree of its toolbar once it thinks an assistive app is
        // listening; until then a window shows nothing but its three buttons. Asking for
        // AXEnhancedUserInterface switches it on (the call reports "unsupported", but it works).
        // Firefox can drop the request while it starts up and restores tabs, so it's sent again
        // whenever the bar is missing, at most every 2 s; the tree takes a moment, so a later check finds it.
        if Date().timeIntervalSince(lastEnable[pid] ?? .distantPast) > 2 {
            lastEnable[pid] = Date()
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        return nil
    }

    private static func search(_ app: AXUIElement) -> AXUIElement? {
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var queue = [window as! AXUIElement]
        var visited = 0
        while !queue.isEmpty, visited < 3000 {
            let element = queue.removeFirst()
            visited += 1
            let role = string(element, kAXRoleAttribute)
            if role == "AXWebArea" { continue }
            if role == kAXTextFieldRole || role == kAXComboBoxRole,
               string(element, "AXDOMIdentifier") == "urlbar-input" {
                return element
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value as? Bool) ?? false
    }
}
