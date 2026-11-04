import SwiftUI

/// A GitHub-style year of focus: one square per day, five shades of ink. Lives in Overview,
/// follows the year of the period you're looking at, and can be stepped on its own.
struct FocusCalendarCard: View {
    var analytics: Analytics
    var period: Period

    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var selectedDay: Date?

    private var thisYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        let data = analytics.heatmap(year: year)
        let yearPeriod = Period(kind: .year, anchor: analytics.calendar.date(from: DateComponents(year: year, month: 6, day: 1))!)
        let summary = analytics.summary(yearPeriod)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus calendar").font(.headline)
                    Text(yearSubtitle(summary)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .help("Previous year")
                    Text(String(year))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(year >= thisYear)
                        .help("Next year")
                }
                .buttonStyle(.borderless)
            }
            // Left-aligned when the year fits; scrollable (ending on today) when it doesn't.
            ViewThatFits(in: .horizontal) {
                Heatmap(data: data, calendar: analytics.calendar, selected: $selectedDay)
                    .padding(.vertical, 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    Heatmap(data: data, calendar: analytics.calendar, selected: $selectedDay)
                        .padding(.vertical, 2)
                }
                .defaultScrollAnchor(.trailing)
            }
            HeatLegend()
            if let day = selectedDay {
                Divider().padding(.vertical, 4)
                DayDetail(day: day, analytics: analytics)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightStyle(scheme: scheme).card())
        .animation(.snappy, value: selectedDay)
        .onChange(of: period, initial: true) {
            guard period.kind != .all else { return }
            year = min(thisYear, analytics.calendar.component(.year, from: period.anchor))
        }
    }

    private func step(_ delta: Int) {
        withAnimation(.snappy) { year += delta; selectedDay = nil }
    }

    private func yearSubtitle(_ summary: Summary) -> String {
        var parts = ["\(InsightFormat.minutes(summary.focus / 60)) focused", "\(summary.activeDays) active days"]
        if prefs.streaksEnabled {
            parts.append("all-time best streak \(analytics.streaks(prefs.streakRule).longest)")
        }
        return parts.joined(separator: " · ") + " · click a day for details"
    }
}

private struct Heatmap: View {
    var data: HeatmapData
    var calendar: Calendar
    @Binding var selected: Date?
    @Environment(\.colorScheme) private var scheme

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Month labels, placed over the week column where each month starts.
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 14)
                ForEach(data.months) { month in
                    Text(month.date, format: .dateTime.month(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .offset(x: labelWidth + CGFloat(month.column) * (cell + gap))
                }
            }
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(row % 2 == 0 && row < 6 ? weekdayLabel(row) : "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth - gap, height: cell, alignment: .leading)
                    }
                }
                ForEach(data.columns.indices, id: \.self) { column in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            if let day = data.columns[column][row] {
                                square(day)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
    }

    private func square(_ day: HeatCell) -> some View {
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: day.day) } ?? false
        let isFuture = day.day > .now
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(InsightStyle(scheme: scheme).heat(day.level))
            .opacity(isFuture ? 0.45 : 1)
            .frame(width: cell, height: cell)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.ink(scheme), lineWidth: isSelected ? 1.5 : 0)
                    .padding(-2)
            )
            .contentShape(Rectangle())
            .onTapGesture { selected = isSelected ? nil : day.day }
            .help("\(day.day.formatted(.dateTime.weekday(.wide).day().month().year())): \(day.minutes > 0 ? InsightFormat.minutes(day.minutes) : "no focus")")
            .accessibilityLabel("\(day.day.formatted(date: .complete, time: .omitted)), \(InsightFormat.minutes(day.minutes))")
    }

    private func weekdayLabel(_ row: Int) -> String {
        let weekday = (calendar.firstWeekday - 1 + row) % 7
        return calendar.veryShortWeekdaySymbols.isEmpty ? "" : calendar.shortWeekdaySymbols[weekday]
    }
}

private struct HeatLegend: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(InsightStyle(scheme: scheme).heat(level))
                    .frame(width: 11, height: 11)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The sessions of one day, inside the calendar card.
private struct DayDetail: View {
    var day: Date
    var analytics: Analytics
    @Environment(HistoryStore.self) private var history

    var body: some View {
        let sessions = analytics.records
            .filter { analytics.day(of: $0.end) == day } // `day` is already a day key from the heatmap
            .sorted { $0.end < $1.end }
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())).font(.subheadline.weight(.semibold))
                Text(sessions.isEmpty ? "No focus this day" : "\(sessions.count) session\(sessions.count == 1 ? "" : "s") · \(InsightFormat.minutes(sessions.reduce(0) { $0 + $1.duration } / 60))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(sessions) { record in
                SessionRow(record: record, project: history.project(record.projectID))
            }
        }
    }
}

/// A compact session line used by the calendar and the iPhone session list.
struct SessionRow: View {
    var record: FocusRecord
    var project: Project?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: project?.symbol ?? "circle.dashed")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.intention.isEmpty ? (project?.name ?? "Focus") : record.intention)
                HStack(spacing: 4) {
                    Text(record.start, format: .dateTime.hour().minute())
                    Text("–")
                    Text(record.end, format: .dateTime.hour().minute())
                    if let project, !record.intention.isEmpty { Text("· \(project.name)") }
                    if record.distractions > 0 { Text("· \(record.distractions) distraction\(record.distractions == 1 ? "" : "s")") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = record.note {
                    Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(InsightFormat.minutes(record.duration / 60)).monospacedDigit()
                if let rating = record.rating { RatingDots(value: rating) }
            }
        }
    }
}
