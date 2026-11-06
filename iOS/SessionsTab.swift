import SwiftUI
import UniformTypeIdentifiers

/// Sessions: a journal of your focus. This week at a glance on top (tap it for Insights), then
/// every session, newest first, under the day it belongs to: when, how long, what it was for, how
/// it went and what you got done. Tap one to edit it; swipe to delete. Projects at the top left,
/// search, filters, export and import at the top right.
struct SessionsTab: View {
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs
    @Environment(TimerEngine.self) private var engine
    @State private var search = ""
    @State private var projectFilter = ProjectFilter.all
    @State private var show = Show.all
    @State private var confirmDelete: Set<FocusRecord.ID> = []
    @State private var path: [Route] = []
    @Bindable private var router = AppRouter.shared
    @State private var exportFile: ExportFile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importMessage: String?

    enum Route: Hashable {
        case session(FocusRecord.ID)
        case insights
    }

    enum ProjectFilter: Hashable {
        case all, unassigned
        case project(UUID)
    }

    enum Show: String, CaseIterable, Identifiable {
        case all, notes, rated, distracted
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "All Sessions"
            case .notes: "With Notes"
            case .rated: "Rated"
            case .distracted: "With Distractions"
            }
        }
        var symbol: String {
            switch self {
            case .all: "list.bullet"
            case .notes: "text.quote"
            case .rated: "star"
            case .distracted: "exclamationmark.bubble"
            }
        }
    }

    var body: some View {
        let analytics = Analytics(records: history.records, calendar: .current, dayStartHour: prefs.dayStartsAtHour)
        let days = grouped(filtered, analytics)
        NavigationStack(path: $path) {
            Group {
                if history.records.isEmpty {
                    emptyState
                } else {
                    journal(days, analytics)
                }
            }
            .navigationTitle("Sessions")
            .toolbar { toolbar(analytics) }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .session(let id): SessionDetail(id: id)
                case .insights: MobileInsightsView()
                }
            }
        }
        .sheet(isPresented: $router.projectsShown) { ProjectsSheet() }
        // "Show Insights" from elsewhere (or `--tab insights` at launch).
        .onChange(of: router.insightsRequested, initial: true) {
            guard router.insightsRequested else { return }
            router.insightsRequested = false
            if prefs.insightsEnabled && path.last != .insights { path = [.insights] }
        }
        .onChange(of: prefs.insightsEnabled) {
            if !prefs.insightsEnabled { path.removeAll { $0 == .insights } }
        }
        // Projects switched off: no project filter left behind.
        .onChange(of: prefs.projectsActive) {
            if !prefs.projectsActive { projectFilter = .all; router.projectsShown = false }
        }
        .fileExporter(isPresented: $showExporter, document: exportFile,
                      contentType: exportFile?.contentType ?? .json,
                      defaultFilename: exportFile?.filename) { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { importBackup($0) }
        .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .confirmationDialog(confirmDelete.count == 1 ? "Delete this session?" : "Delete \(confirmDelete.count) sessions?",
                            isPresented: Binding(get: { !confirmDelete.isEmpty }, set: { if !$0 { confirmDelete = [] } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let ids = confirmDelete
                path.removeAll { if case .session(let id) = $0 { ids.contains(id) } else { false } }
                withAnimation { history.delete(ids) }
                confirmDelete = []
                Haptics.play(.select)
            }
        } message: {
            Text("It's gone from Insights too. This can't be undone.")
        }
    }

    // MARK: The journal

    private func journal(_ days: [Day], _ analytics: Analytics) -> some View {
        ScrollViewReader { proxy in
            List {
                if !isFiltering {
                    Section {
                        WeekStrip(analytics: analytics, opensInsights: prefs.insightsEnabled) {
                            path.append(.insights)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    if engine.phase == .focus && engine.isActive {
                        Section {
                            NowRow()
                                .listRowSeparator(.hidden)
                        } header: {
                            DayHeader(title: "Now", detail: nil)
                        }
                    }
                }

                if days.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Nothing here" : "No matches",
                                           systemImage: search.isEmpty ? show.symbol : "magnifyingglass",
                                           description: Text(search.isEmpty
                                                             ? "No sessions match these filters."
                                                             : "No intention, note or project with \u{201C}\(search)\u{201D}."))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                ForEach(days) { day in
                    Section {
                        ForEach(day.records) { record in
                            NavigationLink(value: Route.session(record.id)) {
                                JournalRow(record: record, project: prefs.projectsActive ? history.project(record.projectID) : nil)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = [record.id] }
                                    .tint(.red)
                            }
                            .contextMenu { menu(for: record) }
                        }
                    } header: {
                        DayHeader(title: day.title, detail: day.summary)
                    }
                    .id(day.id)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .searchable(text: $search, prompt: "Intentions, notes, projects")
            .animation(.snappy, value: projectFilter)
            .animation(.snappy, value: show)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No sessions yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Finish a focus session and it lands here: when it was, what it was for, and how it went.")
        } actions: {
            Button {
                AppRouter.shared.showTimer()
            } label: {
                Label("Start Focusing", systemImage: "play.fill")
                    .pill(prominent: true)
            }
            .buttonStyle(.plain)
            Button("Import a Backup…") { showImporter = true }
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func menu(for record: FocusRecord) -> some View {
        if prefs.projectsActive {
            Menu("Project", systemImage: "folder") {
                Picker("Project", selection: Binding(
                    get: { record.projectID },
                    set: { history.setProject($0, for: [record.id]) }
                )) {
                    Text("No Project").tag(Project.ID?.none)
                    ForEach(history.activeProjects) { project in
                        Label(project.name, systemImage: project.symbol).tag(Project.ID?.some(project.id))
                    }
                }
            }
        }
        Menu("Rating", systemImage: "star") {
            Picker("Rating", selection: Binding(
                get: { record.rating ?? 0 },
                set: { history.update(record.id, rating: $0) }
            )) {
                ForEach((1...5).reversed(), id: \.self) { value in
                    Text("\(String(repeating: "★", count: value))  \(FocusRecord.ratingWords[value])").tag(value)
                }
                Text("No Rating").tag(0)
            }
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { confirmDelete = [record.id] }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ analytics: Analytics) -> some ToolbarContent {
        if prefs.projectsActive {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.projectsShown = true } label: {
                    Label("Projects", systemImage: "folder")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Show", selection: $show.animation(.snappy)) {
                    ForEach(Show.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.inline)
                if prefs.projectsActive && !history.projects.isEmpty {
                    Picker("Project", selection: $projectFilter.animation(.snappy)) {
                        Text("All Projects").tag(ProjectFilter.all)
                        Text("No Project").tag(ProjectFilter.unassigned)
                        ForEach(history.projects) { project in
                            Label(project.name, systemImage: project.symbol).tag(ProjectFilter.project(project.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                if isFiltering && search.isEmpty {
                    Divider()
                    Button("Show Everything", systemImage: "xmark.circle") {
                        withAnimation(.snappy) {
                            show = .all
                            projectFilter = .all
                        }
                    }
                }
            } label: {
                Label("Filter", systemImage: show != .all || projectFilter != .all
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .disabled(history.records.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Export") {
                    Button("Sessions (CSV)", systemImage: "tablecells") {
                        export(Data(history.sessionsCSV.utf8), .commaSeparatedText, "Fifteen Sessions")
                    }
                    Button("Daily Summary (CSV)", systemImage: "calendar") {
                        export(Data(analytics.dailyCSV().utf8), .commaSeparatedText, "Fifteen Daily Summary")
                    }
                    Button("Full Backup (JSON)", systemImage: "archivebox") {
                        export(history.backupJSON(), .json, "Fifteen Backup")
                    }
                }
                Button("Import Backup…", systemImage: "square.and.arrow.down") { showImporter = true }
            } label: {
                Label("Export or Import", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: Data

    private var isFiltering: Bool {
        show != .all || projectFilter != .all || !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filtered: [FocusRecord] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return history.records.filter { record in
            switch projectFilter {
            case .all: break
            case .unassigned: if record.projectID != nil { return false }
            case .project(let id): if record.projectID != id { return false }
            }
            switch show {
            case .all: break
            case .notes: if (record.note ?? "").isEmpty { return false }
            case .rated: if record.rating == nil { return false }
            case .distracted: if record.distractions == 0 { return false }
            }
            guard !query.isEmpty else { return true }
            return record.intention.lowercased().contains(query)
                || (record.note ?? "").lowercased().contains(query)
                || (prefs.projectsActive && (history.project(record.projectID)?.name.lowercased().contains(query) ?? false))
        }
    }

    /// Sessions under the day they belong to (a day starts at the hour set in Insights), newest first.
    private func grouped(_ records: [FocusRecord], _ analytics: Analytics) -> [Day] {
        let byDay = Dictionary(grouping: records) { analytics.day(of: $0.end) }
        return byDay.keys.sorted(by: >).map { key in
            Day(id: key, records: byDay[key, default: []].sorted { $0.end > $1.end }, analytics: analytics)
        }
    }

    private func export(_ data: Data, _ type: UTType, _ name: String) {
        exportFile = ExportFile(data: data, contentType: type, filename: name)
        showExporter = true
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let added = try history.importBackup(try Data(contentsOf: url))
            importMessage = added.sessions == 0 && added.projects == 0
                ? "Everything in that backup is already here."
                : "Added \(added.sessions) session\(added.sessions == 1 ? "" : "s") and \(added.projects) project\(added.projects == 1 ? "" : "s")."
        } catch {
            importMessage = "That file couldn't be read as a Fifteen backup."
        }
    }
}

/// One day of sessions.
private struct Day: Identifiable {
    var id: Date
    var records: [FocusRecord]
    var analytics: Analytics

    /// "Today", "Yesterday", "Tuesday", or "Tuesday, 3 November" further back.
    var title: String {
        let calendar = analytics.calendar
        let today = analytics.day(of: .now)
        if id == today { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), id == yesterday { return "Yesterday" }
        if let week = calendar.date(byAdding: .day, value: -6, to: today), id >= week {
            return id.formatted(.dateTime.weekday(.wide))
        }
        let sameYear = calendar.isDate(id, equalTo: today, toGranularity: .year)
        return sameYear ? id.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : id.formatted(.dateTime.day().month(.wide).year())
    }

    /// "3 sessions · 1h 15m"
    var summary: String {
        let minutes = records.reduce(0) { $0 + $1.duration } / 60
        return "\(records.count) session\(records.count == 1 ? "" : "s") · \(InsightFormat.minutes(minutes))"
    }
}

// MARK: - Parts

private struct DayHeader: View {
    var title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .textCase(nil)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// This week, one bar a day, against the week's busiest day. Today is solid. With Insights on,
/// the whole card is the way in.
private struct WeekStrip: View {
    var analytics: Analytics
    var opensInsights: Bool
    var open: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        let days = weekDays
        let minutes = days.map { analytics.minutes(onDayOf: noon($0)) }
        let top = max(minutes.max() ?? 0, 30)
        let total = minutes.reduce(0, +)
        let sessions = days.reduce(0) { $0 + analytics.sessions(onDayOf: noon($1)) }
        let today = analytics.day(of: .now)

        let card = VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Text(InsightFormat.minutes(total))
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(sessions)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(sessions == 1 ? "session" : "sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let value = minutes[index]
                    let isToday = day == today
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            Capsule().fill(style.empty)
                            Capsule()
                                .fill(isToday ? style.ink : style.bar.opacity(0.75))
                                .frame(height: value == 0 ? 0 : max(6, 56 * value / top))
                        }
                        .frame(height: 56)
                        .frame(maxWidth: 22)
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(day > today ? 0.45 : 1)
                }
            }
            .accessibilityHidden(true)
            if prefs.dailyGoalMinutes > 0 || opensInsights {
                HStack(spacing: 6) {
                    if prefs.dailyGoalMinutes > 0 {
                        let todayMinutes = analytics.minutes(onDayOf: .now)
                        Text(todayMinutes >= Double(prefs.dailyGoalMinutes)
                             ? "Today's goal of \(InsightFormat.minutes(Double(prefs.dailyGoalMinutes))) is done."
                             : "\(InsightFormat.minutes(Double(prefs.dailyGoalMinutes) - todayMinutes)) to go for today's goal.")
                    }
                    Spacer(minLength: 8)
                    if opensInsights {
                        Text("Insights")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(style.card())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.snappy, value: total)

        if opensInsights {
            Button {
                Haptics.play(.select)
                open()
            } label: { card }
            .buttonStyle(PressableCardStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("This week, \(InsightFormat.minutes(total)), \(sessions) sessions")
            .accessibilityHint("Shows Insights")
        } else {
            card
                .accessibilityElement(children: .combine)
        }
    }

    /// The seven day keys of this week, in the user's order.
    private var weekDays: [Date] {
        let calendar = analytics.calendar
        let today = analytics.day(of: .now)
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// A moment safely inside the day, whatever hour the day starts at.
    private func noon(_ day: Date) -> Date {
        analytics.calendar.date(byAdding: .hour, value: 12 + analytics.dayStartHour, to: day) ?? day
    }
}

/// Shrinks a touch while pressed, so the card feels like the button it is.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// The focus session running right now, at the top of the journal. Tap it for the timer.
private struct NowRow: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(HistoryStore.self) private var history

    var body: some View {
        Button { AppRouter.shared.showTimer() } label: {
            HStack(spacing: 14) {
                ProgressRing(progress: TimerProgress.fraction(engine), lineWidth: 3)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.intention.isEmpty ? (history.project(engine.projectID)?.name ?? "Focus") : engine.intention)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(engine.state == .paused ? "Paused" : engine.isFlowtime ? "In the flow" : "In progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(TimerProgress.clock(engine))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: !engine.isFlowtime))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the timer")
    }
}

/// One session: the time it started and how long it ran on the left, what it was for, its project,
/// distractions and note in the middle, the rating on the right.
private struct JournalRow: View {
    var record: FocusRecord
    var project: Project?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.start, format: .dateTime.hour().minute())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(InsightFormat.minutes(record.duration / 60))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // Room for "12:00 PM" where clocks have AM and PM; one line either way.
            .frame(width: 68, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(record.intention.isEmpty ? .regular : .medium))
                    .foregroundStyle(record.intention.isEmpty && project == nil ? .secondary : .primary)
                    .lineLimit(2)
                if !tags.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(tags, id: \.text) { tag in
                            HStack(spacing: 3) {
                                Image(systemName: tag.symbol)
                                Text(tag.text)
                            }
                            .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let note = record.note, !note.isEmpty {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.ink(scheme).opacity(0.2)).frame(width: 2)
                        }
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 4)
            if let rating = record.rating {
                RatingDots(value: rating)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if !record.intention.isEmpty { return record.intention }
        if let project { return project.name }
        return record.mode == .flowtime ? "Flowtime" : "Focus"
    }

    private var tags: [(text: String, symbol: String)] {
        var tags: [(text: String, symbol: String)] = []
        if let project, !record.intention.isEmpty { tags.append((project.name, project.symbol)) }
        if record.mode == .flowtime && !(record.intention.isEmpty && project == nil) { tags.append(("Flowtime", "infinity")) }
        if record.endedEarly == true { tags.append(("Ended early", "checkmark.circle")) }
        if record.distractions > 0 {
            tags.append(("\(record.distractions)", "exclamationmark.bubble"))
        }
        return tags
    }
}

// MARK: - One session

/// Everything about a session, editable after the fact: what it was for, what you got done, how it
/// went and which project it counts toward. The facts (when, how long, pauses) underneath.
private struct SessionDetail: View {
    var id: FocusRecord.ID
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var intention = ""
    @State private var note = ""
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var field: Field?

    private enum Field { case intention, note }

    var body: some View {
        if let record = history.record(id) {
            form(record)
        } else {
            ContentUnavailableView("Session deleted", systemImage: "trash")
        }
    }

    private func form(_ record: FocusRecord) -> some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text(InsightFormat.minutes(record.duration / 60))
                        .font(.system(size: 48, weight: .light))
                        .monospacedDigit()
                    Text(record.end.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.headline)
                    Text("\(record.start.formatted(date: .omitted, time: .shortened)) – \(record.end.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    stars(record)
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            Section("The One Thing") {
                TextField("What was it for?", text: $intention, prompt: Text("What's the one thing?"))
                    .focused($field, equals: .intention)
                    .submitLabel(.done)
                    .onSubmit { saveIntention() }
            }

            Section("What You Got Done") {
                TextField("Note", text: $note, prompt: Text("What did you get done?"), axis: .vertical)
                    .focused($field, equals: .note)
                    .lineLimit(3...10)
                    .onChange(of: note) { if loaded { history.update(id, note: note) } }
            }

            if prefs.projectsActive {
                Section {
                    Picker("Project", selection: Binding(
                        get: { record.projectID },
                        set: { Haptics.play(.select); history.setProject($0, for: [id]) }
                    )) {
                        Text("None").tag(Project.ID?.none)
                        ForEach(history.activeProjects) { project in
                            Label(project.name, systemImage: project.symbol).tag(Project.ID?.some(project.id))
                        }
                        // An archived project this session still belongs to.
                        if let current = history.project(record.projectID), current.isArchived {
                            Label(current.name, systemImage: current.symbol).tag(Project.ID?.some(current.id))
                        }
                    }
                }
            }

            Section("Details") {
                LabeledContent("Mode", value: record.mode == .flowtime ? "Flowtime" : "Pomodoro")
                if let planned = record.plannedDuration, abs(planned - record.duration) >= 30 {
                    LabeledContent("Planned", value: InsightFormat.minutes(planned / 60))
                }
                if record.endedEarly == true {
                    LabeledContent("Ended", value: "Early")
                }
                if let paused = record.pausedTime, paused >= 30 {
                    LabeledContent("Paused for", value: InsightFormat.minutes(paused / 60))
                }
                LabeledContent("Distractions", value: record.distractions == 0 ? "None" : "\(record.distractions)")
            }

            Section {
                Button("Delete Session", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(record.end.formatted(.dateTime.day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if field != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        saveIntention()
                        field = nil
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            guard !loaded else { return }
            intention = record.intention
            note = record.note ?? ""
            loaded = true
        }
        .onChange(of: field) { old, _ in if old == .intention { saveIntention() } }
        .onDisappear { saveIntention() }
        .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Session", role: .destructive) {
                dismiss()
                // After the page has gone, so nothing is still showing it.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation { history.delete([id]) }
                }
            }
        } message: {
            Text("It's gone from Insights too. This can't be undone.")
        }
    }

    /// The same five stars the timer asks with. Tap the current one again to take it back.
    private func stars(_ record: FocusRecord) -> some View {
        let current = record.rating ?? 0
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        Haptics.play(.select)
                        withAnimation(.spring(duration: 0.35, bounce: 0.4)) {
                            history.update(id, rating: value == current ? 0 : value)
                        }
                    } label: {
                        Image(systemName: value <= current ? "star.fill" : "star")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.ink(scheme).opacity(value <= current ? 1 : 0.3))
                            .contentTransition(.symbolEffect(.replace))
                            .scaleEffect(value == current ? 1.12 : 1)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) of 5, \(FocusRecord.ratingWords[value])")
                    .accessibilityAddTraits(value == current ? .isSelected : [])
                }
            }
            Text(current == 0 ? "How did it go?" : FocusRecord.ratingWords[current])
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.snappy, value: current)
        }
    }

    private func saveIntention() {
        guard loaded, let record = history.record(id), intention != record.intention else { return }
        history.update(id, intention: intention)
    }
}
