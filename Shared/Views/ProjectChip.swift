import SwiftUI

/// A small folder button at the start of the caption box: which project this session counts toward.
struct ProjectChip: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(HistoryStore.self) private var history
    @Environment(\.appActions) private var actions

    var body: some View {
        let current = history.project(engine.projectID)
        Menu {
            Picker("Project", selection: Binding(
                get: { current?.id },
                set: { id in
                    Haptics.play(.select)
                    engine.projectID = id
                }
            )) {
                Text("No Project").tag(Project.ID?.none)
                ForEach(history.activeProjects) { project in
                    Label(project.name, systemImage: project.symbol).tag(Project.ID?.some(project.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Manage Projects…", systemImage: "folder.badge.gearshape") { actions.showInsights(.projects) }
        } label: {
            Image(systemName: current?.symbol ?? "folder")
                .font(.callout)
                .foregroundStyle(current == nil ? .tertiary : .primary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(current.map { "Project: \($0.name)" } ?? "Choose a project")
        .accessibilityLabel(current.map { "Project, \($0.name)" } ?? "Choose a project")
    }
}
