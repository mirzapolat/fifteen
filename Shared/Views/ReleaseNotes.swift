import Foundation

// MARK: - Release notes

/// One version's notes, read from a bundled `<version>.html`. On the Mac that's `release-notes/`, the
/// same file Sparkle's update window and the GitHub release show; the iPhone and iPad have their own
/// in `release-notes/ios/`. An `<h2>` title, a `<p>` line and a `<ul>` of changes.
struct ReleaseNotes: Identifiable {
    var version: String
    var title: String
    var intro: String?
    var items: [String]
    /// The same changes with a bit more shape, for the iPhone's What's New: a bold lead-in
    /// (`<strong>`) and an SF Symbol (`<li data-symbol="calendar">`) when the file gives them.
    var entries: [Entry] = []
    var id: String { version }

    struct Entry: Hashable {
        var title: String?
        var text: String
        var symbol: String?
    }

    #if os(macOS)
    private static let folderName = "release-notes"
    #else
    private static let folderName = "ios"
    #endif

    /// Every bundled version, newest first.
    static let bundled: [ReleaseNotes] = {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent(folderName),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension == "html" }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).map {
                    parse($0, version: url.deletingPathExtension().lastPathComponent)
                }
            }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }()

    static func parse(_ html: String, version: String) -> ReleaseNotes {
        func contents(of tag: String) -> [String] {
            let pattern = try! Regex("<\(tag)(?:\\s[^>]*)?>(.*?)</\(tag)>").dotMatchesNewlines().ignoresCase()
            return html.matches(of: pattern)
                .compactMap { $0.output[1].substring.map { plainText(String($0)) } }
                .filter { !$0.isEmpty }
        }
        return ReleaseNotes(version: version,
                            title: contents(of: "h2").first ?? "Fifteen \(version)",
                            intro: contents(of: "p").first,
                            items: contents(of: "li"),
                            entries: entries(in: html))
    }

    private static func entries(in html: String) -> [Entry] {
        let item = try! Regex("<li(\\s[^>]*)?>(.*?)</li>").dotMatchesNewlines().ignoresCase()
        let symbol = try! Regex("data-symbol\\s*=\\s*\"([^\"]+)\"").ignoresCase()
        let lead = try! Regex("^\\s*<strong>(.*?)</strong>").dotMatchesNewlines().ignoresCase()
        return html.matches(of: item).compactMap { match in
            let attributes = match.output[1].substring.map(String.init) ?? ""
            var body = match.output[2].substring.map(String.init) ?? ""
            var title: String?
            if let found = body.firstMatch(of: lead) {
                title = found.output[1].substring.map { plainText(String($0)) }
                body = String(body[found.range.upperBound...])
            }
            let text = plainText(body)
            guard !text.isEmpty || title != nil else { return nil }
            let name = attributes.firstMatch(of: symbol)?.output[1].substring.map(String.init)
            return Entry(title: title, text: text, symbol: name)
        }
    }

    private static func plainText(_ html: String) -> String {
        var text = html.replacing(try! Regex("<[^>]+>"), with: "")
        for (entity, character) in ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                                    "&apos;": "'", "&rsquo;": "’", "&nbsp;": " ", "&amp;": "&"] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
