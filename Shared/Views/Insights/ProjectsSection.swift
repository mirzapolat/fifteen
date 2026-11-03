import SwiftUI
import Charts

/// Where your time goes, by project. Create, rename, re-symbol, archive and delete projects here.
struct ProjectsSection: View {
    var analytics: Analytics
    @Binding var period: Period

    @Environment(HistoryStore.self) private var history
    @Environment(\.colorScheme) private var scheme
    @State private var naming: NamingTarget?
    @State private var name = ""
    @State private var showArchived = false

    private enum NamingTarget: Identifiable {
        case new
        case rename(Project)
        var id: String {
            switch self {
            case .new: "new"
            case .rename(let p): p.id.uuidString
            }
        }
    }

    var body: some View {
        let shares = analytics.projectShares(period)
        let total = max(1, shares.reduce(0) { $0 + $1.minutes })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PeriodBar(analytics: analytics, period: $period)

                if !shares.isEmpty {
                    InsightCard(title: "Share of focus") {
                        ProjectShareView(shares: shares)
                    }
                }

                InsightCard(title: "Projects", subtitle: "Pick one from the folder button in the timer's caption box.") {
                    VStack(spacing: 0) {
                        ForEach(history.activeProjects) { project in
                            projectRow(project, share: shares.first { $0.projectID == project.id }, total: total)
                            Divider()
                        }
                        Button {
                            name = ""
                            naming = .new
                        } label: {
                            Label("New Project", systemImage: "plus")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                let archived = history.projects.filter(\.isArchived)
                if !archived.isEmpty {
                    DisclosureGroup("Archived (\(archived.count))", isExpanded: $showArchived) {
                        VStack(spacing: 0) {
                            ForEach(archived) { project in
                                projectRow(project, share: shares.first { $0.projectID == project.id }, total: total)
                                Divider()
                            }
                        }
                    }
                    .padding(16)
                    .background(InsightStyle(scheme: scheme).card())
                }
            }
            .padding(20)
        }
        .alert(alertTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button(alertButton) { commitName() }
        }
    }

    private func projectRow(_ project: Project, share: ProjectShare?, total: Double) -> some View {
        let minutes = share?.minutes ?? 0
        return HStack(spacing: 12) {
            Menu {
                ForEach(Project.symbols, id: \.self) { symbol in
                    Button { var p = project; p.symbol = symbol; history.updateProject(p) } label: {
                        Label(symbol, systemImage: symbol)
                    }
                }
            } label: {
                Image(systemName: project.symbol)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(InsightStyle(scheme: scheme).cardFill))
                    .overlay(Circle().strokeBorder(InsightStyle(scheme: scheme).cardEdge, lineWidth: 1))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change symbol")

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).foregroundStyle(project.isArchived ? .secondary : .primary)
                Text("\(share?.sessions ?? 0) session\(share?.sessions == 1 ? "" : "s") · \(Int((minutes / total * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Sparkline(buckets: analytics.series(period) { $0.projectID == project.id })
                .frame(width: 90, height: 24)
            Text(InsightFormat.minutes(minutes))
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
            Menu {
                Button("Rename…") { name = project.name; naming = .rename(project) }
                Button(project.isArchived ? "Unarchive" : "Archive") {
                    var p = project
                    p.isArchived.toggle()
                    history.updateProject(p)
                }
                Divider()
                Button("Delete", role: .destructive) { history.deleteProject(project.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("Rename…") { name = project.name; naming = .rename(project) }
            Button("Delete", role: .destructive) { history.deleteProject(project.id) }
        }
    }

    private var alertTitle: String {
        if case .rename = naming { return "Rename Project" }
        return "New Project"
    }

    private var alertButton: String {
        if case .rename = naming { return "Rename" }
        return "Create"
    }

    private func commitName() {
        switch naming {
        case .new:
            history.addProject(named: name)
        case .rename(var project):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                project.name = trimmed
                history.updateProject(project)
            }
        case nil:
            break
        }
        naming = nil
    }
}

/// A tiny bar trend for one project over the selected period.
struct Sparkline: View {
    var buckets: [Bucket]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("Date", bucket.start), y: .value("Minutes", bucket.minutes))
                .foregroundStyle(InsightStyle(scheme: scheme).bar.opacity(0.7))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}
