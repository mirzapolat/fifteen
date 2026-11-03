import SwiftUI

/// Every session in the period: search, filter by project, sort, and edit after the fact.
struct SessionsSection: View {
    var analytics: Analytics
    @Binding var period: Period

    @Environment(HistoryStore.self) private var history
    @State private var search = ""
    @State private var projectFilter = ProjectFilter.all
    @State private var sortOrder = [KeyPathComparator(\FocusRecord.end, order: .reverse)]
    @State private var selection = Set<FocusRecord.ID>()
    @State private var confirmDelete: Set<FocusRecord.ID> = []

    enum ProjectFilter: Hashable {
        case all, unassigned
        case project(UUID)
    }

    var body: some View {
        let rows = filtered
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PeriodBar(analytics: analytics, period: $period)
                HStack(spacing: 12) {
                    Picker("Project", selection: $projectFilter) {
                        Text("All Projects").tag(ProjectFilter.all)
                        Text("Unassigned").tag(ProjectFilter.unassigned)
                        if !history.projects.isEmpty {
                            Divider()
                            ForEach(history.projects) { Text($0.name).tag(ProjectFilter.project($0.id)) }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Text("\(rows.count) session\(rows.count == 1 ? "" : "s") · \(InsightFormat.minutes(rows.reduce(0) { $0 + $1.duration } / 60))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(20)

            if rows.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No sessions" : "No matches", systemImage: "list.bullet",
                                       description: Text(search.isEmpty ? "Nothing recorded in this period." : "Try a different search."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(rows)
            }
        }
        .searchable(text: $search, prompt: "Search intentions and notes")
        .confirmationDialog("Delete \(confirmDelete.count) session\(confirmDelete.count == 1 ? "" : "s")?",
                            isPresented: Binding(get: { !confirmDelete.isEmpty }, set: { if !$0 { confirmDelete = [] } })) {
            Button("Delete", role: .destructive) {
                history.delete(confirmDelete)
                selection.subtract(confirmDelete)
                confirmDelete = []
            }
        } message: {
            Text("This can't be undone. Export a backup first if you want a copy.")
        }
    }

    private var filtered: [FocusRecord] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return analytics.records(in: period)
            .filter { record in
                switch projectFilter {
                case .all: true
                case .unassigned: record.projectID == nil
                case .project(let id): record.projectID == id
                }
            }
            .filter { record in
                query.isEmpty
                    || record.intention.lowercased().contains(query)
                    || (record.note ?? "").lowercased().contains(query)
                    || (history.project(record.projectID)?.name.lowercased().contains(query) ?? false)
            }
            .sorted(using: sortOrder)
    }

    @ViewBuilder
    private func list(_ rows: [FocusRecord]) -> some View {
        #if os(macOS)
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.end) { record in
                Text(record.end, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            .width(min: 90, ideal: 110)
            TableColumn("Time") { record in
                Text("\(record.start.formatted(date: .omitted, time: .shortened)) – \(record.end.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit()
            }
            .width(min: 100, ideal: 120)
            TableColumn("Length", value: \.duration) { record in
                Text(InsightFormat.minutes(record.duration / 60)).monospacedDigit()
            }
            .width(min: 50, ideal: 60)
            TableColumn("Project") { record in
                if let project = history.project(record.projectID) {
                    Label(project.name, systemImage: project.symbol)
                } else {
                    Text("–").foregroundStyle(.tertiary)
                }
            }
            .width(min: 80, ideal: 120)
            TableColumn("Intention", value: \.intention) { record in
                Text(record.intention.isEmpty ? "–" : record.intention)
                    .foregroundStyle(record.intention.isEmpty ? .tertiary : .primary)
            }
            TableColumn("Note") { record in
                Text(record.note ?? "").foregroundStyle(.secondary)
            }
            TableColumn("Rating") { record in
                if let rating = record.rating { RatingDots(value: rating) } else { Text("–").foregroundStyle(.tertiary) }
            }
            .width(min: 44, ideal: 50)
        }
        .contextMenu(forSelectionType: FocusRecord.ID.self) { ids in
            editMenu(ids)
        }
        .onDeleteCommand { confirmDelete = selection }
        #else
        List {
            ForEach(rows) { record in
                SessionRow(record: record, project: history.project(record.projectID))
                    .contextMenu { editMenu([record.id]) }
            }
            .onDelete { offsets in confirmDelete = Set(offsets.map { rows[$0].id }) }
        }
        .listStyle(.plain)
        #endif
    }

    @ViewBuilder
    private func editMenu(_ ids: Set<FocusRecord.ID>) -> some View {
        if !ids.isEmpty {
            Menu("Project") {
                Button("None") { history.setProject(nil, for: ids) }
                ForEach(history.activeProjects) { project in
                    Button { history.setProject(project.id, for: ids) } label: {
                        Label(project.name, systemImage: project.symbol)
                    }
                }
            }
            Menu("Focus Rating") {
                ForEach(1...5, id: \.self) { value in
                    Button("\(value) – \(FocusRecord.ratingWords[value])") {
                        for id in ids { history.update(id, rating: value) }
                    }
                }
            }
            Divider()
            Button("Delete…", role: .destructive) { confirmDelete = ids }
        }
    }
}
