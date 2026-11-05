import SwiftUI
import UniformTypeIdentifiers

enum InsightsSection: String, CaseIterable, Identifiable, Hashable {
    case overview, projects, sessions
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .projects: "Projects"
        case .sessions: "Sessions"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "chart.bar"
        case .projects: "folder"
        case .sessions: "list.bullet"
        }
    }
}

/// Which Insights section is showing. Shared, so other parts of the app (like "Manage Projects…")
/// can open Insights on a specific section, even when its window is already open.
@Observable
@MainActor
final class InsightsRoute {
    static let shared = InsightsRoute()
    var section: InsightsSection = InsightsRoute.launchSection
    /// On the stacked page (iPhone and iPad): a section to scroll to, e.g. from "Manage Projects…".
    var jump: InsightsSection?

    /// `--insights calendar` etc. picks the first section (used for screenshots).
    private static var launchSection: InsightsSection {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--insights"), args.indices.contains(index + 1) else { return .overview }
        return InsightsSection(rawValue: args[index + 1]) ?? .overview
    }
}

/// Insights: where your focus goes, over days, weeks, months and years.
/// Every number comes from `Analytics`; this view only lays it out.
struct InsightsView: View {
    /// Shown when Insights is presented as a sheet.
    var onDone: (() -> Void)? = nil
    /// iPhone and iPad: Overview, Projects and Sessions one after another on a single page,
    /// under one period bar, with export and import at the end. (The Mac switches between them.)
    var stacked = false

    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs
    @Bindable private var route = InsightsRoute.shared
    @Environment(\.colorScheme) private var scheme
    @State private var period = Period(kind: .week, anchor: .now)
    @State private var exportFile: ExportFile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        let analytics = Analytics(records: history.records, calendar: .current, dayStartHour: prefs.dayStartsAtHour)
        NavigationStack {
            if stacked {
                stackedPage(analytics)
                    #if os(iOS)
                    // The period is the page's title; no bar above it.
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
            } else {
                switcherPage(analytics)
            }
        }
        .fileExporter(isPresented: $showExporter, document: exportFile,
                      contentType: exportFile?.contentType ?? .json,
                      defaultFilename: exportFile?.filename) { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    // MARK: One page (iPhone and iPad)

    private func stackedPage(_ analytics: Analytics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    StackedPeriodHeader(analytics: analytics, period: $period)
                        .padding(.bottom, 24)
                        .id(InsightsSection.overview)

                    OverviewSection(analytics: analytics, period: $period, embedded: true)

                    ProjectsSection(analytics: analytics, period: $period, embedded: true)
                        .id(InsightsSection.projects)
                        .padding(.top, 16)

                    moreLinks(analytics)
                        .padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: route.jump) { jump(proxy) }
            .onAppear { jump(proxy) }
        }
    }

    private func jump(_ proxy: ScrollViewProxy) {
        guard let section = route.jump else { return }
        route.jump = nil
        withAnimation(.snappy) { proxy.scrollTo(section, anchor: .top) }
    }

    /// Your Data, on a page of its own. (Sessions have a tab of their own.)
    private func moreLinks(_ analytics: Analytics) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                ScrollView {
                    dataCard(analytics)
                        .padding(20)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                }
                .navigationTitle("Your Data")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                #endif
            } label: {
                linkRow("Your Data", detail: "Export or import a backup", symbol: "archivebox")
            }
        }
        .buttonStyle(.plain)
        .background(InsightStyle(scheme: scheme).card())
    }

    private func linkRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    /// Export and import as plain rows, where they're easy to find and hard to hit by accident.
    private func dataCard(_ analytics: Analytics) -> some View {
        InsightCard(title: "Export & Backup", subtitle: "Your history stays on this device. Take a copy with you, or bring a backup back in.") {
            VStack(spacing: 0) {
                dataRow("Sessions", detail: "CSV", symbol: "tablecells") {
                    export(Data(history.sessionsCSV.utf8), .commaSeparatedText, "Fifteen Sessions")
                }
                Divider()
                dataRow("Daily Summary", detail: "CSV", symbol: "calendar") {
                    export(Data(analytics.dailyCSV().utf8), .commaSeparatedText, "Fifteen Daily Summary")
                }
                Divider()
                dataRow("Full Backup", detail: "JSON", symbol: "archivebox") {
                    export(history.backupJSON(), .json, "Fifteen Backup")
                }
                Divider()
                dataRow("Import Backup…", detail: nil, symbol: "square.and.arrow.down") { showImporter = true }
            }
        }
    }

    private func dataRow(_ title: String, detail: String?, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: detail == nil ? "chevron.right" : "square.and.arrow.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Switching sections (Mac)

    private func switcherPage(_ analytics: Analytics) -> some View {
        Group {
            switch route.section {
            case .overview: OverviewSection(analytics: analytics, period: $period)
            case .projects: ProjectsSection(analytics: analytics, period: $period)
            case .sessions: SessionsSection(analytics: analytics, period: $period)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Insights")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // The tabs live in the window's header, centered.
            if #available(macOS 26, iOS 26, *) {
                ToolbarItem(placement: .principal) { sectionTabs }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .principal) { sectionTabs }
            }
            ToolbarItem(placement: .primaryAction) { exportMenu(analytics) }
            if let onDone {
                ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDone) }
            }
        }
    }

    private var sectionTabs: some View {
        ViewThatFits(in: .horizontal) {
            InkSegmented(selection: $route.section, items: InsightsSection.allCases) { item in
                // Toolbars shrink labels to icons by default; keep the names visible.
                Label(item.title, systemImage: item.symbol).labelStyle(.titleAndIcon)
            }
            InkSegmented(selection: $route.section, items: InsightsSection.allCases, compact: true) { item in
                Text(item.title)
            }
        }
    }

    private func exportMenu(_ analytics: Analytics) -> some View {
        Menu {
            Section("Export") {
                Button("Sessions (CSV)") {
                    export(Data(history.sessionsCSV.utf8), .commaSeparatedText, "Fifteen Sessions")
                }
                Button("Daily Summary (CSV)") {
                    export(Data(analytics.dailyCSV().utf8), .commaSeparatedText, "Fifteen Daily Summary")
                }
                Button("Full Backup (JSON)") {
                    export(history.backupJSON(), .json, "Fifteen Backup")
                }
            }
            Button("Import Backup…") { showImporter = true }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .help("Export or import your history")
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

// MARK: - Shared building blocks

/// "November 2026   ‹ [Week|Month|Year|All] ›"
struct PeriodBar: View {
    var analytics: Analytics
    @Binding var period: Period

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                title
                Spacer(minLength: 12)
                controls
            }
            VStack(alignment: .leading, spacing: 10) {
                title
                controls
            }
        }
    }

    private var title: some View {
        Text(analytics.title(period))
            .font(.title2.weight(.semibold))
            .contentTransition(.numericText())
            .animation(.snappy, value: period)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.snappy) { period = analytics.shifted(period, by: -1) } } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(period.kind == .all)
            .help("Previous")
            InkSegmented(selection: Binding(get: { period.kind },
                                            set: { kind in withAnimation(.snappy) { period = Period(kind: kind, anchor: .now) } }),
                         items: PeriodKind.allCases, compact: true) { Text($0.title) }
            Button { withAnimation(.snappy) { period = analytics.shifted(period, by: 1) } } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(analytics.isCurrent(period))
            .help("Next")
        }
        .buttonStyle(.borderless)
    }
}

/// A horizontal row of capsule tabs. The selected one is a solid pill of ink (black in light mode,
/// white in dark) and its label is always the opposite ink, so it never goes white-on-white.
struct InkSegmented<Item: Hashable & Identifiable, ItemLabel: View>: View {
    @Binding var selection: Item
    var items: [Item]
    var compact = false
    /// Stretch across the available width, each item an equal share.
    var fill = false
    @ViewBuilder var label: (Item) -> ItemLabel
    @Environment(\.colorScheme) private var scheme
    @Namespace private var pill

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = item == selection
                Button {
                    withAnimation(.snappy) { selection = item }
                } label: {
                    label(item)
                        .font((compact ? Font.callout : .body).weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.ink(scheme == .dark ? .light : .dark) : Color.primary.opacity(0.7))
                        .padding(.horizontal, compact ? 10 : 14)
                        .padding(.vertical, compact ? 4 : 7)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.ink(scheme)).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(style.cardFill))
        .overlay(Capsule().strokeBorder(style.cardEdge, lineWidth: 1))
        .fixedSize(horizontal: !fill, vertical: true)
    }
}

/// The top of the one-page Analytics (iPhone and iPad): the period as the page's title with
/// back/forward beside it, and Week/Month/Year/All across the full width below.
struct StackedPeriodHeader: View {
    var analytics: Analytics
    @Binding var period: Period

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(analytics.title(period))
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: period)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                HStack(spacing: 18) {
                    Button { withAnimation(.snappy) { period = analytics.shifted(period, by: -1) } } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(period.kind == .all)
                    .accessibilityLabel("Previous")
                    Button { withAnimation(.snappy) { period = analytics.shifted(period, by: 1) } } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(analytics.isCurrent(period))
                    .accessibilityLabel("Next")
                }
                .font(.title3.weight(.semibold))
                .buttonStyle(.borderless)
            }
            InkSegmented(selection: Binding(get: { period.kind },
                                            set: { kind in withAnimation(.snappy) { period = Period(kind: kind, anchor: .now) } }),
                         items: PeriodKind.allCases, fill: true) { Text($0.title) }
        }
    }
}

/// One palette for Insights, tuned separately for light and dark so contrast holds in both.
/// Still black and white: only the strength of the ink changes.
struct InsightStyle {
    var scheme: ColorScheme
    private var dark: Bool { scheme == .dark }

    var ink: Color { .ink(scheme) }
    /// Cards lift off the window: a light wash plus a hairline edge in dark mode.
    var cardFill: Color { dark ? Color.white.opacity(0.075) : Color.black.opacity(0.035) }
    var cardEdge: Color { dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06) }
    var grid: Color { ink.opacity(dark ? 0.16 : 0.08) }
    var bar: Color { ink.opacity(dark ? 0.9 : 0.82) }
    var barDim: Color { ink.opacity(dark ? 0.38 : 0.24) }
    var line: Color { ink.opacity(dark ? 0.75 : 0.6) }
    var empty: Color { ink.opacity(dark ? 0.12 : 0.07) }

    func heat(_ level: Int) -> Color {
        level == 0 ? empty : ink.opacity((dark ? [0, 0.32, 0.52, 0.74, 1] : [0, 0.25, 0.45, 0.7, 1])[level])
    }

    func card(_ radius: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(cardFill)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(cardEdge, lineWidth: 1))
    }
}

/// A quiet rounded panel with a title.
struct InsightCard<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightStyle(scheme: scheme).card())
    }
}

/// One number, a label, and an optional comparison or detail line.
struct StatTile: View {
    var title: String
    var value: String
    var detail: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightStyle(scheme: scheme).card(14))
    }
}

/// A small progress ring for goals.
struct GoalRing: View {
    var progress: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().stroke(Color.ink(scheme).opacity(0.12), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.ink(scheme), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(duration: 0.6), value: progress)
    }
}

/// Five small stars, filled up to the rating (the same stars the timer asks with).
struct RatingDots: View {
    var value: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color.ink(scheme).opacity(i <= value ? 0.85 : 0.15))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus \(value) of 5")
    }
}

/// Grayscale shades for projects, in order of size. Black and white only; the share bar and legend agree.
enum Shade {
    static let levels: [Double] = [1, 0.7, 0.5, 0.34, 0.22, 0.13]
    static func opacity(_ index: Int) -> Double { levels[min(index, levels.count - 1)] }
}

enum InsightFormat {
    /// 0m, 45m, 1h 20m, 12h
    static func minutes(_ minutes: Double) -> String { TimeFormat.duration(minutes * 60) }

    /// Axis labels: 30m, 1h, 1.5h
    static func axis(_ minutes: Double) -> String {
        if minutes < 60 { return "\(Int(minutes))m" }
        let hours = minutes / 60
        return hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }

    /// "+18% vs last week", or nil when there's nothing to compare.
    static func change(_ now: Double, _ before: Double?, _ kind: PeriodKind) -> String? {
        guard let before, before > 0, kind != .all else { return nil }
        let percent = Int(((now - before) / before * 100).rounded())
        let label = switch kind {
        case .week: "last week"
        case .month: "last month"
        case .year: "last year"
        case .all: ""
        }
        return percent == 0 ? "Same as \(label)" : "\(percent > 0 ? "+" : "")\(percent)% vs \(label)"
    }
}
