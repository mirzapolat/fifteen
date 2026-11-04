import AppKit
import Observation

/// Website icons for the website blocker's lists, fetched from each site itself (no third-party
/// favicon service, so the list of sites never leaves the Mac except to the sites themselves),
/// and kept on disk so each one is fetched once.
@Observable
@MainActor
final class Favicons {
    static let shared = Favicons()

    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    /// The icon for `site`, or nil while it loads (or if the site has none). Starts loading on first ask.
    func icon(for site: String) -> NSImage? {
        if let image = images[site] { return image }
        if !requested.contains(site) {
            requested.insert(site)
            Task { await load(site) }
        }
        return nil
    }

    private func load(_ site: String) async {
        let file = Self.folder.appendingPathComponent(site + ".png")
        if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            images[site] = image
            return
        }
        // The big touch icon first (crisp at any size), then the classic favicon.
        for path in ["apple-touch-icon.png", "favicon.ico"] {
            guard let url = URL(string: "https://\(site)/\(path)"),
                  let image = await Self.fetch(url) else { continue }
            images[site] = image
            if let png = Self.png(image) {
                try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                try? png.write(to: file)
            }
            return
        }
    }

    private nonisolated static func fetch(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let image = NSImage(data: data), image.isValid,
              image.representations.contains(where: { $0.pixelsWide >= 16 }) else { return nil }
        return image
    }

    private static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Fifteen", isDirectory: true)
            .appendingPathComponent("Favicons", isDirectory: true)
    }
}
