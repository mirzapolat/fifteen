import AppKit
import CryptoKit
import Network
import Security

/// Google Calendar, signed in directly: OAuth for desktop apps (PKCE, loopback redirect to
/// 127.0.0.1), the refresh token in the keychain, the Calendar REST API for everything else.
///
/// Needs an OAuth client of type "Desktop app" from Google Cloud Console. Its ID and secret go in
/// `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` in project.yml (a desktop client's secret isn't
/// actually secret; Google still wants it for the token exchange).
@MainActor
final class GoogleCalendarProvider: CalendarProvider {
    private static let scopes = [
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
        "https://www.googleapis.com/auth/calendar.events",
    ]
    private static let api = "https://www.googleapis.com/calendar/v3"

    private let clientID = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? "")
        .trimmingCharacters(in: .whitespaces)
    private let clientSecret = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientSecret") as? String ?? "")
        .trimmingCharacters(in: .whitespaces)

    private var refreshToken: String? = Keychain.read(Keychain.refreshToken)
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private(set) var accountName: String? = UserDefaults.standard.string(forKey: "calendarGoogleAccount")
    private var signIn: LoopbackSignIn?

    /// Built with a client ID; without one Google can't be offered.
    var isConfigured: Bool { !clientID.isEmpty }
    var isConnected: Bool { refreshToken != nil }

    // MARK: Signing in

    func connect() async throws {
        guard isConfigured else { throw CalendarError.notConfigured }
        signIn?.cancel()
        let verifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString()
        let session = LoopbackSignIn()
        signIn = session
        defer { if signIn === session { signIn = nil } }

        let port = try await session.start()
        let redirect = "http://127.0.0.1:\(port)"
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            // Always hand out a refresh token, even when this Google account said yes before.
            .init(name: "prompt", value: "consent"),
        ]
        NSWorkspace.shared.open(auth.url!)

        let query = try await session.waitForRedirect()
        guard query["state"] == state else { throw CalendarError.server("Google's answer didn't match. Try again.") }
        if let error = query["error"] {
            throw error == "access_denied" ? CalendarError.signInCancelled : CalendarError.server("Google said: \(error)")
        }
        guard let code = query["code"] else { throw CalendarError.signInCancelled }

        let tokens = try await tokenRequest([
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirect,
        ])
        guard let refresh = tokens.refresh_token else {
            throw CalendarError.server("Google didn't keep you signed in. Try again.")
        }
        refreshToken = refresh
        Keychain.write(refresh, for: Keychain.refreshToken)
        accept(tokens)
        // The primary calendar's ID is the account's email address.
        if let primary = try? await calendarList().first(where: { $0.primary == true }) {
            accountName = primary.id
            UserDefaults.standard.set(primary.id, forKey: "calendarGoogleAccount")
        }
    }

    func disconnect() {
        signIn?.cancel()
        if let token = refreshToken {
            // Best effort: tell Google to forget the grant too.
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["token": token])
            URLSession.shared.dataTask(with: request).resume()
        }
        refreshToken = nil
        accessToken = nil
        accessExpiry = .distantPast
        accountName = nil
        Keychain.delete(Keychain.refreshToken)
        UserDefaults.standard.removeObject(forKey: "calendarGoogleAccount")
    }

    func cancelSignIn() { signIn?.cancel() }

    // MARK: Calendars and events

    func calendars() async throws -> [CalendarInfo] {
        try await calendarList().map { entry in
            CalendarInfo(id: entry.id, title: entry.summaryOverride ?? entry.summary ?? entry.id,
                         group: accountName ?? "Google",
                         color: NSColor(hex: entry.backgroundColor) ?? .controlAccentColor,
                         isWritable: entry.accessRole == "owner" || entry.accessRole == "writer")
        }
    }

    func events(from start: Date, to end: Date, in calendarIDs: Set<String>) async throws -> [CalendarItem] {
        let list = try await calendarList()
        let chosen = calendarIDs.isEmpty
            ? list.filter { $0.selected ?? true }
            : list.filter { calendarIDs.contains($0.id) }
        var items: [CalendarItem] = []
        for calendar in chosen {
            var components = URLComponents(string: "\(Self.api)/calendars/\(Self.path(calendar.id))/events")!
            components.queryItems = [
                .init(name: "timeMin", value: Self.iso.string(from: start)),
                .init(name: "timeMax", value: Self.iso.string(from: end)),
                .init(name: "singleEvents", value: "true"),
                .init(name: "orderBy", value: "startTime"),
                .init(name: "maxResults", value: "50"),
            ]
            let page: EventsPage = try await get(components.url!)
            let color = NSColor(hex: calendar.backgroundColor) ?? .controlAccentColor
            for event in page.items ?? [] {
                guard event.status != "cancelled",
                      event.extendedProperties?.private?[FifteenEventTag.googleKey] == nil,
                      let range = event.range else { continue }
                // Declined invitations aren't part of your day.
                if event.attendees?.contains(where: { $0.this == true && $0.responseStatus == "declined" }) == true { continue }
                items.append(CalendarItem(id: "\(calendar.id)/\(event.id)",
                                          title: event.summary?.isEmpty == false ? event.summary! : "Untitled",
                                          start: range.start, end: range.end,
                                          calendarID: calendar.id, color: color,
                                          isAllDay: range.allDay,
                                          link: event.htmlLink.flatMap(URL.init(string:))))
            }
        }
        return items
    }

    func save(_ entry: LoggedEntry, existingID: String?, in calendarID: String) async throws -> String {
        let body = EventBody(summary: entry.title, description: entry.notes,
                             start: .init(dateTime: Self.iso.string(from: entry.start)),
                             end: .init(dateTime: Self.iso.string(from: entry.end)),
                             transparency: "transparent",
                             extendedProperties: .init(private: [FifteenEventTag.googleKey: entry.recordID.uuidString]))
        let base = "\(Self.api)/calendars/\(Self.path(calendarID))/events"
        if let existingID {
            do {
                let updated: SavedEvent = try await send(URL(string: "\(base)/\(Self.path(existingID))")!, method: "PATCH", body: body)
                return updated.id
            } catch GoogleHTTPError.status(404), GoogleHTTPError.status(410) {
                // Deleted in Google Calendar: write it again.
            }
        }
        let created: SavedEvent = try await send(URL(string: base)!, method: "POST", body: body)
        return created.id
    }

    // MARK: HTTP

    private func calendarList() async throws -> [CalendarListEntry] {
        let page: CalendarListPage = try await get(URL(string: "\(Self.api)/users/me/calendarList?maxResults=250")!)
        return page.items ?? []
    }

    private func token() async throws -> String {
        if let accessToken, accessExpiry > Date().addingTimeInterval(60) { return accessToken }
        guard let refreshToken else { throw CalendarError.noAccess }
        do {
            let tokens = try await tokenRequest(["refresh_token": refreshToken, "grant_type": "refresh_token"])
            accept(tokens)
            return tokens.access_token
        } catch GoogleHTTPError.status(400), GoogleHTTPError.status(401) {
            // The grant was revoked (or the password changed): sign in again.
            disconnect()
            throw CalendarError.server("Google signed you out. Connect again in Settings.")
        }
    }

    private func accept(_ tokens: TokenResponse) {
        accessToken = tokens.access_token
        accessExpiry = Date().addingTimeInterval(TimeInterval(tokens.expires_in ?? 3600))
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var all = fields
        all["client_id"] = clientID
        if !clientSecret.isEmpty { all["client_secret"] = clientSecret }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(all)
        return try await perform(request)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func send<T: Decodable, B: Encodable>(_ url: URL, method: String, body: B) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw GoogleHTTPError.status(status) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Helpers

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Calendar IDs are email-like ("…@group.calendar.google.com", sometimes with "#").
    private static func path(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? id
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }
}

private enum GoogleHTTPError: Error {
    case status(Int)
}

// MARK: - Google's JSON

private struct TokenResponse: Decodable {
    var access_token: String
    var expires_in: Int?
    var refresh_token: String?
}

private struct CalendarListPage: Decodable { var items: [CalendarListEntry]? }

private struct CalendarListEntry: Decodable {
    var id: String
    var summary: String?
    var summaryOverride: String?
    var backgroundColor: String?
    var accessRole: String?
    var primary: Bool?
    var selected: Bool?
}

private struct EventsPage: Decodable { var items: [GoogleEvent]? }

private struct GoogleEvent: Decodable {
    struct When: Decodable {
        var dateTime: String?
        var date: String?
    }
    struct Attendee: Decodable {
        var this: Bool?
        var responseStatus: String?
        enum CodingKeys: String, CodingKey {
            case this = "self"
            case responseStatus
        }
    }
    struct Extended: Decodable { var `private`: [String: String]? }

    var id: String
    var status: String?
    var summary: String?
    var htmlLink: String?
    var start: When?
    var end: When?
    var attendees: [Attendee]?
    var extendedProperties: Extended?

    var range: (start: Date, end: Date, allDay: Bool)? {
        if let s = start?.dateTime.flatMap(Self.parse), let e = end?.dateTime.flatMap(Self.parse) {
            return (s, e, false)
        }
        if let s = start?.date.flatMap(Self.day.date(from:)), let e = end?.date.flatMap(Self.day.date(from:)) {
            return (s, e, true)
        }
        return nil
    }

    private static func parse(_ string: String) -> Date? {
        plain.date(from: string) ?? fractional.date(from: string)
    }
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    /// All-day events are plain dates, in your own time zone.
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

private struct EventBody: Encodable {
    struct When: Encodable { var dateTime: String }
    struct Extended: Encodable { var `private`: [String: String] }
    var summary: String
    var description: String
    var start: When
    var end: When
    var transparency: String
    var extendedProperties: Extended
}

private struct SavedEvent: Decodable { var id: String }

// MARK: - The loopback redirect

/// A tiny one-shot web server on 127.0.0.1 that catches Google's redirect after sign-in.
@MainActor
private final class LoopbackSignIn {
    private var listener: NWListener?
    private var portContinuation: CheckedContinuation<UInt16, Error>?
    private var redirectContinuation: CheckedContinuation<[String: String], Error>?
    private var pendingQuery: [String: String]?
    private var timeout: Task<Void, Never>?

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            portContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
        }
    }

    /// Waits for the browser to come back, for up to five minutes.
    func waitForRedirect() async throws -> [String: String] {
        if let pendingQuery { return pendingQuery }
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(300))
            if !Task.isCancelled { self?.finish(.failure(CalendarError.signInCancelled)) }
        }
        return try await withCheckedThrowingContinuation { redirectContinuation = $0 }
    }

    func cancel() {
        finish(.failure(CalendarError.signInCancelled))
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                portContinuation?.resume(returning: port)
                portContinuation = nil
            }
        case .failed(let error):
            finish(.failure(error))
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Task { @MainActor in self?.handle(request, on: connection) }
        }
    }

    private func handle(_ request: String, on connection: NWConnection) {
        // "GET /?code=…&state=… HTTP/1.1"
        let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let items = URLComponents(string: "http://127.0.0.1\(target)")?.queryItems ?? []
        var query: [String: String] = [:]
        for item in items { query[item.name] = item.value ?? "" }
        // Browsers also ask for /favicon.ico; only the redirect carries a state.
        guard query["state"] != nil else {
            respond(on: connection, status: "404 Not Found", body: "")
            return
        }
        let ok = query["code"] != nil
        let page = """
        <!doctype html><html><head><meta charset="utf-8"><title>Fifteen</title>
        <style>body{font:16px -apple-system,system-ui;display:grid;place-items:center;height:90vh;color:#222}
        @media(prefers-color-scheme:dark){body{background:#111;color:#eee}}</style></head>
        <body><div style="text-align:center"><h2>\(ok ? "Connected to Fifteen" : "Not connected")</h2>
        <p>\(ok ? "You can close this tab and go back to Fifteen." : "You can close this tab and try again from Fifteen's settings.")</p></div></body></html>
        """
        respond(on: connection, status: "200 OK", body: page)
        finish(.success(query))
    }

    private func respond(on connection: NWConnection, status: String, body: String) {
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(_ result: Result<[String: String], Error>) {
        timeout?.cancel()
        timeout = nil
        if let redirectContinuation {
            redirectContinuation.resume(with: result)
            self.redirectContinuation = nil
        } else if case .success(let query) = result {
            pendingQuery = query
        }
        if case .failure(let error) = result, let portContinuation {
            portContinuation.resume(throwing: error)
            self.portContinuation = nil
        }
        // Done after a short beat, so the browser gets its "you can close this tab" page.
        let listener = listener
        self.listener = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { listener?.cancel() }
    }
}

// MARK: - Keychain

private enum Keychain {
    static let refreshToken = "google-refresh-token"
    private static var service: String { (Bundle.main.bundleIdentifier ?? "com.mirzapolat.fifteen") + ".calendar" }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for account: String) {
        delete(account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Small extensions

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension NSColor {
    /// "#9fe1e7" → a color.
    convenience init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
