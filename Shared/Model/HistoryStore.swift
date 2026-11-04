import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Focus history and projects, kept as a small versioned JSON file in Application Support.
/// Never thrown away silently: old formats are backed up before upgrading, unreadable files are set aside.
@Observable
@MainActor
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var records: [FocusRecord] = []
    private(set) var projects: [Project] = []

    @ObservationIgnored private let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fifteen", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    @ObservationIgnored private var fileURL: URL { folder.appendingPathComponent("history.json") }

    /// `--demo`: generated history for previews and screenshots. Kept in memory only, never saved.
    @ObservationIgnored private let isDemo = CommandLine.arguments.contains("--demo")

    private init() {
        if isDemo { loadDemo() } else { load() }
    }

    private func loadDemo() {
        var generator = SystemRandomNumberGenerator()
        let names = [("Thesis", "graduationcap"), ("Reading", "book"), ("Client work", "briefcase")]
        projects = names.map { Project(name: $0.0, symbol: $0.1) }
        let intentions = ["Draft chapter 3", "Literature notes", "Fix the login bug", "Plan the week", "Read 30 pages", ""]
        let calendar = Calendar.current
        for daysAgo in (0..<120).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now)) else { continue }
            let weekend = calendar.isDateInWeekend(day)
            let count = Int.random(in: weekend ? 0...2 : 1...6, using: &generator)
            var clock = calendar.date(bySettingHour: Int.random(in: 8...10, using: &generator), minute: 0, second: 0, of: day)!
            for _ in 0..<count {
                let minutes = Double([25, 25, 25, 30, 45, 50].randomElement(using: &generator)!)
                let end = clock.addingTimeInterval(minutes * 60)
                guard end < .now else { break }
                records.append(FocusRecord(start: clock, end: end, duration: minutes * 60,
                                           intention: intentions.randomElement(using: &generator)!,
                                           distractions: Int.random(in: 0...2, using: &generator),
                                           rating: Bool.random(using: &generator) ? Int.random(in: 2...5, using: &generator) : nil,
                                           projectID: projects.randomElement(using: &generator)?.id,
                                           mode: .pomodoro, plannedDuration: minutes * 60))
                clock = end.addingTimeInterval(Double(Int.random(in: 5...90, using: &generator)) * 60)
            }
        }
    }

    // MARK: Loading & saving

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let file = try? JSONDecoder.history.decode(HistoryFile.self, from: data) {
            records = file.sessions
            projects = file.projects
        } else if let legacy = try? JSONDecoder.history.decode([FocusRecord].self, from: data) {
            // Schema v1 was a bare array. Keep a copy, then upgrade in place.
            let backup = folder.appendingPathComponent("history.v1.backup.json")
            if !FileManager.default.fileExists(atPath: backup.path) { try? data.write(to: backup) }
            records = legacy
            save()
        } else {
            let aside = folder.appendingPathComponent("history.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
        }
    }

    private func save() {
        guard !isDemo else { return }
        let file = HistoryFile(schemaVersion: HistoryFile.currentVersion, sessions: records, projects: projects)
        guard let data = try? JSONEncoder.history.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Sessions

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

    func update(_ id: FocusRecord.ID, intention: String? = nil, note: String? = nil, rating: Int? = nil) {
        guard let index = records.lastIndex(where: { $0.id == id }) else { return }
        if let intention { records[index].intention = intention.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let note { records[index].note = note.isEmpty ? nil : note }
        // 0 takes a rating back.
        if let rating { records[index].rating = rating == 0 ? nil : rating }
        save()
    }

    func setProject(_ projectID: Project.ID?, for ids: Set<FocusRecord.ID>) {
        for index in records.indices where ids.contains(records[index].id) {
            records[index].projectID = projectID
        }
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

    /// Every session and project gone, including the backup copies kept beside the history file.
    func wipeEverything() {
        records = []
        projects = []
        save()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("history.") && file != fileURL {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Projects

    var activeProjects: [Project] { projects.filter { !$0.isArchived } }

    func project(_ id: Project.ID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    @discardableResult
    func addProject(named name: String) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(name: trimmed.isEmpty ? "Untitled" : trimmed,
                              symbol: Project.symbols[projects.count % Project.symbols.count])
        projects.append(project)
        save()
        return project
    }

    func updateProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        save()
    }

    /// Deletes a project; its sessions stay, unassigned.
    func deleteProject(_ id: Project.ID) {
        projects.removeAll { $0.id == id }
        for index in records.indices where records[index].projectID == id {
            records[index].projectID = nil
        }
        save()
    }

    // MARK: Today

    func todayCount(hour: Int) -> Int { today(hour: hour).count }

    func todayDuration(hour: Int) -> TimeInterval {
        today(hour: hour).reduce(0) { $0 + $1.duration }
    }

    private func today(hour: Int) -> [FocusRecord] {
        let key = Analytics.dayKey(.now, hour: hour, calendar: .current)
        return records.filter { Analytics.dayKey($0.end, hour: hour, calendar: .current) == key }
    }

    // MARK: Export & import

    var sessionsCSV: String {
        let formatter = ISO8601DateFormatter()
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["start,end,minutes,project,intention,note,rating,distractions,mode,ended_early"]
        for r in records.sorted(by: { $0.end < $1.end }) {
            lines.append([
                formatter.string(from: r.start),
                formatter.string(from: r.end),
                String(Int((r.duration / 60).rounded())),
                quoted(project(r.projectID)?.name ?? ""),
                quoted(r.intention),
                quoted(r.note ?? ""),
                r.rating.map(String.init) ?? "",
                String(r.distractions),
                r.mode?.rawValue ?? "",
                (r.endedEarly ?? false) ? "yes" : "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    func backupJSON() -> Data {
        let file = HistoryFile(schemaVersion: HistoryFile.currentVersion, sessions: records, projects: projects)
        return (try? JSONEncoder.history.encode(file)) ?? Data()
    }

    /// Merges a backup (v2, or a v1 array) by id; nothing already here is duplicated or overwritten.
    func importBackup(_ data: Data) throws -> (sessions: Int, projects: Int) {
        let incoming: HistoryFile
        if let file = try? JSONDecoder.history.decode(HistoryFile.self, from: data) {
            incoming = file
        } else {
            incoming = HistoryFile(schemaVersion: 1,
                                   sessions: try JSONDecoder.history.decode([FocusRecord].self, from: data),
                                   projects: [])
        }
        let knownProjects = Set(projects.map(\.id))
        let newProjects = incoming.projects.filter { !knownProjects.contains($0.id) }
        let knownSessions = Set(records.map(\.id))
        let newSessions = incoming.sessions.filter { !knownSessions.contains($0.id) }
        projects += newProjects
        records = (records + newSessions).sorted { $0.end < $1.end }
        save()
        return (newSessions.count, newProjects.count)
    }
}

/// A file handed to the system save panel.
struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var data: Data
    var contentType: UTType
    var filename: String

    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
        filename = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
