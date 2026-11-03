import SwiftUI
import Charts

/// What you focused on, day by day. A record, not a scoreboard.
struct HistoryView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs
    @State private var confirmClear = false

    var body: some View {
        let hour = prefs.dayStartsAtHour
        let week = history.lastDays(7, hour: hour)
        List {
            Section {
                HStack(spacing: 0) {
                    stat(value: "\(history.todayCount(hour: hour))", label: "Today")
                    Divider()
                    stat(value: TimeFormat.duration(history.todayDuration(hour: hour)), label: "Focused Today")
                    Divider()
                    stat(value: TimeFormat.duration(week.reduce(0) { $0 + $1.minutes } * 60), label: "This Week")
                }
                .frame(height: 64)
            }

            if prefs.showWeekChart {
                Section("Last 7 Days") {
                    Chart(week) { day in
                        BarMark(x: .value("Day", day.day, unit: .day),
                                y: .value("Minutes", day.minutes),
                                width: .ratio(0.55))
                            .foregroundStyle(Color.primary.opacity(Calendar.current.isDate(day.day, inSameDayAs: week.last?.day ?? .now) ? 1 : 0.35))
                            .clipShape(.capsule)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                            AxisValueLabel { if let m = value.as(Double.self) { Text("\(Int(m))m") } }
                        }
                    }
                    .frame(height: 150)
                    .padding(.vertical, 8)
                }
            }

            let groups = history.groupedByDay(hour: hour)
            if groups.isEmpty {
                Section {
                    ContentUnavailableView("No sessions yet", systemImage: "circle.dashed",
                                           description: Text("Finished focus sessions show up here."))
                }
            }
            ForEach(groups, id: \.day) { group in
                Section {
                    ForEach(group.records) { record in
                        row(record)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { history.delete([record.id]) }
                            }
                    }
                    .onDelete { offsets in
                        history.delete(Set(offsets.map { group.records[$0].id }))
                    }
                } header: {
                    HStack {
                        Text(group.day, format: .dateTime.weekday(.wide).day().month())
                        Spacer()
                        Text(TimeFormat.duration(group.records.reduce(0) { $0 + $1.duration }))
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItemGroup {
                ShareLink(item: HistoryExport(text: history.csv), preview: SharePreview("Fifteen History.csv")) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(history.records.isEmpty)
                Button("Clear History", systemImage: "trash") { confirmClear = true }
                    .disabled(history.records.isEmpty)
            }
        }
        .confirmationDialog("Delete all sessions?", isPresented: $confirmClear) {
            Button("Delete All Sessions", role: .destructive) { history.deleteAll() }
        } message: {
            Text("This can't be undone. Export a CSV first if you want a copy.")
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.light))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ record: FocusRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.intention.isEmpty ? "Focus" : record.intention)
                    .foregroundStyle(record.intention.isEmpty ? .secondary : .primary)
                HStack(spacing: 4) {
                    Text(record.start, format: .dateTime.hour().minute())
                    Text("–")
                    Text(record.end, format: .dateTime.hour().minute())
                    if record.distractions > 0 {
                        Text("· \(record.distractions) distraction\(record.distractions == 1 ? "" : "s")")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = record.note {
                    Text(note)
                        .font(.callout)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(TimeFormat.duration(record.duration))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let rating = record.rating {
                    RatingDots(value: rating)
                        .help(FocusRecord.ratingWords[rating])
                }
            }
        }
    }
}

/// Five small dots, filled up to the rating.
struct RatingDots: View {
    var value: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(Color.ink(scheme).opacity(i <= value ? 0.85 : 0.15))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus \(value) of 5")
    }
}
