import Foundation
import Observation
import CoreTransferable
import UniformTypeIdentifiers

/// One finished focus session.
struct FocusRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    var duration: TimeInterval
    var intention: String
    var distractions: Int
    /// "What did you get done?" — written after the session.
    var note: String? = nil
    /// How focused it felt, 1–5.
    var rating: Int? = nil

    static let ratingWords = ["", "Scattered", "Distracted", "Okay", "Focused", "Deep focus"]
}

struct DayTotal: Identifiable {
    var day: Date
    var minutes: Double
    var sessions: Int
    var id: Date { day }
}

/// Focus history, kept as a small JSON file in Application Support. Never thrown away silently.
@Observable
@MainActor
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var records: [FocusRecord] = []

    @ObservationIgnored private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fifteen", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }()

    private init() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            records = try JSONDecoder.history.decode([FocusRecord].self, from: data)
        } catch {
            // Keep the unreadable file instead of overwriting it on the next save.
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    func add(_ record: FocusRecord) {
        records.append(record)
        save()
    }

    /// Adds overtime to the most recent session.
    func extendLast(by seconds: TimeInterval) {
        guard seconds > 0, !records.isEmpty else { return }
        records[records.count - 1].duration += seconds
        records[records.count - 1].end = records[records.count - 1].end.addingTimeInterval(seconds)
        save()
    }

    func record(_ id: FocusRecord.ID?) -> FocusRecord? {
        guard let id else { return nil }
        return records.last { $0.id == id }
    }

    func update(_ id: FocusRecord.ID, note: String? = nil, rating: Int? = nil) {
        guard let index = records.lastIndex(where: { $0.id == id }) else { return }
        if let note { records[index].note = note.isEmpty ? nil : note }
        if let rating { records[index].rating = rating }
        save()
    }

    func delete(_ ids: Set<FocusRecord.ID>) {
        records.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteAll() {
        records = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder.history.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Queries

    /// The "day" starts at a chosen hour, so a late-night session still counts as yesterday.
    func dayStart(for date: Date, hour: Int) -> Date {
        let shifted = date.addingTimeInterval(TimeInterval(-hour * 3600))
        return Calendar.current.startOfDay(for: shifted).addingTimeInterval(TimeInterval(hour * 3600))
    }

    func records(onDayOf date: Date, hour: Int) -> [FocusRecord] {
        let start = dayStart(for: date, hour: hour)
        let end = start.addingTimeInterval(86_400)
        return records.filter { $0.end >= start && $0.end < end }
    }

    func todayCount(hour: Int) -> Int { records(onDayOf: .now, hour: hour).count }

    func todayDuration(hour: Int) -> TimeInterval {
        records(onDayOf: .now, hour: hour).reduce(0) { $0 + $1.duration }
    }

    func lastDays(_ count: Int, hour: Int) -> [DayTotal] {
        let today = dayStart(for: .now, hour: hour)
        return (0..<count).reversed().map { offset in
            let day = today.addingTimeInterval(TimeInterval(-offset * 86_400))
            let items = records(onDayOf: day, hour: hour)
            return DayTotal(day: day, minutes: items.reduce(0) { $0 + $1.duration } / 60, sessions: items.count)
        }
    }

    var totalDuration: TimeInterval { records.reduce(0) { $0 + $1.duration } }

    /// Sessions grouped by day, newest first.
    func groupedByDay(hour: Int) -> [(day: Date, records: [FocusRecord])] {
        let groups = Dictionary(grouping: records) { dayStart(for: $0.end, hour: hour) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.end > $1.end }) }
    }

    var csv: String {
        let formatter = ISO8601DateFormatter()
        func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["start,end,minutes,intention,distractions,note,rating"]
        for r in records {
            lines.append("\(formatter.string(from: r.start)),\(formatter.string(from: r.end)),\(Int((r.duration / 60).rounded())),\(quoted(r.intention)),\(r.distractions),\(quoted(r.note ?? "")),\(r.rating.map(String.init) ?? "")")
        }
        return lines.joined(separator: "\n")
    }
}

struct HistoryExport: Transferable {
    var text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName("Fifteen History.csv")
    }
}

private extension JSONEncoder {
    static let history: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let history: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
