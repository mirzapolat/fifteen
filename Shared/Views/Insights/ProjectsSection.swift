import SwiftUI
import Charts

/// Where your time goes, by project. Create, rename, re-symbol, archive and delete projects here.
struct ProjectsSection: View {
    var analytics: Analytics
    @Binding var period: Period
    /// Stacked with the other sections on one page: no scroll view or period bar of its own.
    var embedded = false

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
        Group {
            if embedded {
                content
            } else {
                ScrollView { content.padding(20) }
            }
        }
        .alert(alertTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button(alertButton) { commitName() }
        }
    }

    private var projectsHint: String {
        #if os(macOS)
        "Pick one from the folder button in the timer's caption box."
        #else
        "Pick one from the folder in the timer's intention field."
        #endif
    }

    @ViewBuilder
    private var content: some View {
        let shares = analytics.projectShares(period)
        let total = max(1, shares.reduce(0) { $0 + $1.minutes })
        VStack(alignment: .leading, spacing: 16) {
            if !embedded {
                PeriodBar(analytics: analytics, period: $period)
            }

            if !shares.isEmpty {
                InsightCard(title: "Share of focus") {
                    ProjectShareView(shares: shares)
                }
            }

            InsightCard(title: "Projects", subtitle: projectsHint) {
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
    }

    private func projectRow(_ project: Project, share: ProjectShare?, total: Double) -> some View {
        let minutes = share?.minutes ?? 0
        return HStack(spacing: 12) {
            ProjectSymbolButton(project: project)

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

/// The project's icon; click it to choose another from a grid.
private struct ProjectSymbolButton: View {
    var project: Project
    @Environment(HistoryStore.self) private var history
    @Environment(\.colorScheme) private var scheme
    @State private var picking = false

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        Button { picking.toggle() } label: {
            Image(systemName: project.symbol)
                .frame(width: 30, height: 30)
                .background(Circle().fill(style.cardFill))
                .overlay(Circle().strokeBorder(picking ? Color.ink(scheme).opacity(0.6) : style.cardEdge, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Change icon")
        .accessibilityLabel("Icon for \(project.name)")
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            SymbolGrid(selection: project.symbol) { symbol in
                var p = project
                p.symbol = symbol
                history.updateProject(p)
                picking = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// A grid of project icons with the current one highlighted.
struct SymbolGrid: View {
    var selection: String
    var choose: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovered: String?

    private static let cell: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: 6), count: 8), spacing: 6) {
                ForEach(Project.symbols, id: \.self) { symbol in
                    let selected = symbol == selection
                    Button { choose(symbol) } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(selected ? (scheme == .dark ? Color.black : Color.white) : Color.primary)
                            .frame(width: Self.cell, height: Self.cell)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.ink(scheme)
                                          : Color.primary.opacity(hovered == symbol ? 0.1 : 0.04))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { hovered = symbol } else if hovered == symbol { hovered = nil }
                    }
                    .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(14)
    }
}
