import AppKit
import Observation

/// Link: devices in a group share one timer. Whoever changes it (start, pause, resume, reset, skip,
/// minutes, a break) changes it for everyone. Ratings, notes, projects, intentions, settings and
/// history stay on each device.
///
/// How it stays in step: after each change this device sends the timer's new state, saying which
/// revision it was based on. The relay keeps the first update for each revision and sends it to
/// everyone; a device that was a moment too late gets the winner instead and takes it on.
@Observable
@MainActor
final class LinkSession {
    static let shared = LinkSession()

    enum Status: Equatable {
        /// Not in a group.
        case off
        /// Reaching the relay (first time, or after sleep or a dropped connection).
        case connecting
        /// In a group and connected.
        case linked
    }

    struct Member: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var online: Bool?
        var initials: String {
            let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
            let letters = words.prefix(2).compactMap(\.first)
            return letters.isEmpty ? "?" : String(letters).uppercased()
        }
    }

    private(set) var status: Status = .off
    /// The group's code, once in a group. Lasts as long as the group does.
    private(set) var code: String? {
        didSet { engine.isLinked = code != nil }
    }
    private(set) var members: [Member] = []
    private(set) var myID: String?
    /// A problem to show in the Link card ("No group with that code").
    var problem: String?
    /// Busy creating or joining (the buttons show progress).
    private(set) var busy = false

    var deviceName: String {
        didSet {
            defaults.set(deviceName, forKey: Key.name)
            if status == .linked { send(["type": "rename", "name": cleanName]) }
        }
    }

    var isLinked: Bool { code != nil }
    var others: [Member] { members.filter { $0.id != myID } }

    // MARK: Private state

    @ObservationIgnored private let engine = TimerEngine.shared
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var connectionID = 0
    @ObservationIgnored private var welcomed = false
    @ObservationIgnored private var token: String? {
        didSet { defaults.set(token, forKey: Key.token) }
    }
    /// The group's timer as last confirmed by the relay, and its revision.
    @ObservationIgnored private var group: SharedTimer?
    @ObservationIgnored private var revision = 0
    /// One update on its way at a time; later changes wait and go as one.
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var checkScheduled = false
    /// Server clock minus this device's clock.
    @ObservationIgnored private var offset: TimeInterval = 0
    @ObservationIgnored private var bestRoundTrip: TimeInterval = .infinity
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored private var retryDelay: TimeInterval = 1
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    private enum Pending { case create, join(String) }

    private enum Key {
        static let name = "linkDeviceName"
        static let token = "linkToken"
        static let code = "linkCode"
        static let ticket = "linkTicket"
        static let server = "linkServerURL"
    }

    /// The public relay (server/link, deployed to the VPS).
    static let defaultServer = URL(string: "wss://fifteen.mirzapolat.com")!

    /// Where the relay lives. For a local relay while developing:
    /// `defaults write com.mirzapolat.fifteen linkServerURL ws://localhost:8787`
    /// (and `defaults delete com.mirzapolat.fifteen linkServerURL` to go back).
    private var serverURL: URL {
        defaults.string(forKey: Key.server).flatMap(URL.init(string:)) ?? Self.defaultServer
    }

    private var cleanName: String {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Self.defaultName : name
    }

    static var defaultName: String {
        Host.current().localizedName ?? "My Mac"
    }

    private init() {
        deviceName = UserDefaults.standard.string(forKey: Key.name) ?? Self.defaultName
        token = UserDefaults.standard.string(forKey: Key.token)
        code = UserDefaults.standard.string(forKey: Key.code)
        if code != nil { status = .connecting }
    }

    // MARK: Public

    /// Called once at launch: picks the group back up if this Mac was in one.
    func start() {
        engine.onChange = { [weak self] in self?.scheduleCheck() }
        engine.isLinked = isLinked
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LinkSession.shared.reconnectIfNeeded(now: true) }
        }
        if token != nil { connect() } else if code != nil { forgetGroup() }
    }

    func createGroup() {
        problem = nil
        busy = true
        pending = .create
        welcomed ? runPending() : connect()
    }

    func join(_ rawCode: String) {
        let letters = Self.normalize(rawCode)
        guard letters.count == 6 else {
            problem = "A code has 6 letters."
            return
        }
        problem = nil
        busy = true
        pending = .join(letters)
        welcomed ? runPending() : connect()
    }

    /// Leaves the group. This Mac's timer carries on from where it is, on its own.
    func leave() {
        send(["type": "leave"])
        forgetGroup()
        // Give the goodbye a moment to go out before closing.
        let id = connectionID
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if let self, self.connectionID == id, !self.isLinked, self.pending == nil { self.disconnect() }
        }
    }

    /// The person, not the computer, for the line under the ring:
    /// "Mira's MacBook Pro" → "Mira", "MacBook Air von Mirza" → "Mirza",
    /// "iMac de Lucía" → "Lucía". Anything else stays as it is.
    static func shortName(_ name: String) -> String {
        for mark in ["'s ", "’s "] {
            if let range = name.range(of: mark) { return String(name[..<range.lowerBound]) }
        }
        // How macOS names a Mac in other languages: "<model> von|de|di|van <name>".
        let words = name.split(separator: " ")
        if let i = words.lastIndex(where: { ["von", "de", "di", "da", "van", "du", "of"].contains($0.lowercased()) }),
           i > 0, i < words.count - 1 {
            return words[(i + 1)...].joined(separator: " ")
        }
        return name
    }

    /// Letters only, uppercase, without the look-alikes I and O.
    static func normalize(_ text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && $0.isLetter && $0 != "I" && $0 != "O" }.prefix(6))
    }

    // MARK: Connection

    private func connect() {
        retryTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        connectionID += 1
        welcomed = false
        inFlight = false
        bestRoundTrip = .infinity
        if isLinked { status = .connecting }
        let task = URLSession.shared.webSocketTask(with: serverURL)
        socket = task
        task.resume()
        receive(on: task, id: connectionID)
        var hello: [String: Any] = ["type": "hello", "protocol": 1, "name": cleanName]
        if let token { hello["token"] = token }
        send(hello)
    }

    private func disconnect() {
        retryTask?.cancel()
        connectionID += 1
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        welcomed = false
    }

    private func reconnectIfNeeded(now: Bool = false) {
        guard isLinked || pending != nil else { return }
        retryTask?.cancel()
        let delay = now ? 0.5 : retryDelay
        retryDelay = min(30, retryDelay * 2)
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func receive(on task: URLSessionWebSocketTask, id: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, id == self.connectionID else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(on: task, id: id)
                case .failure:
                    self.connectionLost()
                }
            }
        }
    }

    private func connectionLost() {
        socket = nil
        welcomed = false
        inFlight = false
        if isLinked {
            status = .connecting
            reconnectIfNeeded()
        } else if pending != nil {
            pending = nil
            busy = false
            problem = "Can't reach Link right now. Check your connection and try again."
        }
    }

    private func send(_ message: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    // MARK: Messages

    private struct Incoming: Decodable {
        var type: String
        var serverTime: Double?
        var t: Double?
        var code: String?
        var ticket: String?
        var memberId: String?
        var token: String?
        var revision: Int?
        var timer: WireTimer?
        var members: [Member]?
        var by: Member?
        var action: String?
        var rejected: Bool?
    }

    /// The timer on the wire: Unix seconds on the relay's clock.
    private struct WireTimer: Codable {
        var phase: Phase
        var mode: TimerMode
        var state: RunState
        var total: Double
        var endsAt: Double?
        var pausedRemaining: Double?
        var startedAt: Double?
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(Incoming.self, from: data) else { return }
        switch message.type {
        case "welcome":
            welcomed = true
            retryDelay = 1
            if let serverTime = message.serverTime { offset = serverTime - Date().timeIntervalSince1970 }
            syncClock()
            // With a token the relay puts us straight back in the group; otherwise do what was asked.
            if token == nil { runPending() }

        case "pong":
            if let sent = message.t, let serverTime = message.serverTime {
                let received = Date().timeIntervalSince1970
                let roundTrip = received - sent
                if roundTrip < bestRoundTrip {
                    bestRoundTrip = roundTrip
                    offset = serverTime - (sent + received) / 2
                }
            }

        case "joined":
            guard let code = message.code, let timer = message.timer else { return }
            let created: Bool
            if case .create = pending { created = true } else { created = false }
            self.code = code
            defaults.set(code, forKey: Key.code)
            if let ticket = message.ticket { defaults.set(ticket, forKey: Key.ticket) }
            myID = message.memberId
            token = message.token ?? token
            members = message.members ?? members
            busy = false
            problem = nil
            pending = nil
            status = .linked
            // A new group starts from this Mac's timer; joining (or coming back) takes the group's.
            accept(timer, revision: message.revision ?? 1, adopt: !created)

        case "state":
            guard let timer = message.timer else { return }
            let rejected = message.rejected == true
            let mine = !rejected && message.by?.id == myID
            if rejected || mine { inFlight = false }
            accept(timer, revision: message.revision ?? revision, adopt: !mine)
            if !mine, !rejected, let by = message.by, let action = message.action, !action.isEmpty {
                let line = "\(Self.shortName(by.name)) \(action)"
                LinkActivity.shared.show(line)
                notify(line)
            }

        case "members":
            members = message.members ?? members

        case "error":
            switch message.code {
            case "noSuchCode": fail("No group with that code. Check the letters with your friend.")
            case "full": fail("That group is full (8 devices).")
            case "rateLimited": fail("Too many tries. Wait a few minutes, then try again.")
            case "protocol": fail("Update Fifteen to link with this group.")
            case "groupGone":
                // The relay forgot the group (it restarted, or everyone was away for a long time).
                // Bring it back under the same code, from this Mac's timer.
                token = nil
                if let code {
                    pending = .create
                    var create: [String: Any] = ["type": "create", "timer": wire(engine.shared), "preferredCode": code]
                    if let ticket = defaults.string(forKey: Key.ticket) { create["ticket"] = ticket }
                    send(create)
                } else {
                    forgetGroup()
                }
            default:
                break
            }

        default:
            break
        }
    }

    /// A banner for someone else's change, unless it's switched off or the bubble is open
    /// (the line under the ring already says it there).
    private func notify(_ line: String) {
        guard Preferences.shared.linkNotifications, !LinkChrome.shared.bubbleShown else { return }
        Notifier.shared.notifyLinkActivity(title: line, body: Self.where(engine))
    }

    /// Where the timer stands now: "Focus · 23:10 left", "Short break paused · 4:12 left".
    private static func `where`(_ engine: TimerEngine) -> String {
        let phase = engine.phase.title
        switch engine.state {
        case .idle:
            return "\(phase) · \(TimeFormat.clock(engine.remaining)) ready to start"
        case .running:
            return engine.isFlowtime ? "\(phase) · \(TimeFormat.clock(engine.elapsed)) so far"
                : "\(phase) · \(TimeFormat.clock(engine.remaining)) left"
        case .paused:
            return "\(phase) paused · \(TimeFormat.clock(engine.remaining)) left"
        case .finished:
            return engine.phase == .focus ? "Session complete" : "Break's over"
        }
    }

    private func fail(_ text: String) {
        problem = text
        busy = false
        pending = nil
        if !isLinked { disconnect() }
    }

    private func runPending() {
        switch pending {
        case .create: send(["type": "create", "timer": wire(engine.shared)])
        case .join(let code): send(["type": "join", "code": code])
        case nil: break
        }
    }

    private func syncClock() {
        // A few pings; the quickest round trip gives the best estimate of the relay's clock.
        for i in 0..<4 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150 * i))
                self?.send(["type": "ping", "t": Date().timeIntervalSince1970])
            }
        }
    }

    private func forgetGroup() {
        code = nil
        myID = nil
        members = []
        token = nil
        group = nil
        revision = 0
        inFlight = false
        pending = nil
        busy = false
        status = .off
        defaults.removeObject(forKey: Key.code)
        defaults.removeObject(forKey: Key.ticket)
    }

    // MARK: Keeping in step

    private func accept(_ wire: WireTimer, revision: Int, adopt: Bool) {
        let timer = local(wire)
        group = timer
        self.revision = revision
        if adopt { engine.adopt(timer) }
        scheduleCheck()
    }

    /// The engine changes in small steps (moving on is "pick the phase", then "start"), so wait
    /// for the end of this turn and send only where it landed.
    private func scheduleCheck() {
        guard !checkScheduled else { return }
        checkScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.checkScheduled = false
            self?.sendIfChanged()
        }
    }

    private func sendIfChanged() {
        guard status == .linked, welcomed, !inFlight, let group else { return }
        let mine = engine.shared
        guard !mine.matches(group, at: Date()) else { return }
        inFlight = true
        send([
            "type": "update",
            "timer": wire(mine),
            "basedOn": revision,
            "action": SharedTimer.describe(from: group, to: mine),
        ])
    }

    private func local(_ w: WireTimer) -> SharedTimer {
        SharedTimer(phase: w.phase, mode: w.mode, state: w.state, total: w.total,
                    endsAt: w.endsAt.map { Date(timeIntervalSince1970: $0 - offset) },
                    pausedRemaining: w.pausedRemaining,
                    startedAt: w.startedAt.map { Date(timeIntervalSince1970: $0 - offset) })
    }

    private func wire(_ t: SharedTimer) -> [String: Any] {
        var out: [String: Any] = [
            "phase": t.phase.rawValue, "mode": t.mode.rawValue, "state": t.state.rawValue, "total": t.total,
        ]
        out["endsAt"] = t.endsAt.map { $0.timeIntervalSince1970 + offset } ?? NSNull()
        out["pausedRemaining"] = t.pausedRemaining ?? NSNull()
        out["startedAt"] = t.startedAt.map { $0.timeIntervalSince1970 + offset } ?? NSNull()
        return out
    }
}
