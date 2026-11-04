import SwiftUI
import Charts

/// Layout, top to bottom:
/// 1. Hero — the period's focus time, how it compares, the supporting numbers, and the main chart.
/// 2. Calendar — the whole year at a glance, one square per day.
/// 3. Patterns — when in the day, which days of the week.
/// 4. Progress & where it went — goals and streak beside the project split; focus quality if rated.
struct OverviewSection: View {
    var analytics: Analytics
    @Binding var period: Period

    @Environment(Preferences.self) private var prefs
    @Environment(HistoryStore.self) private var history
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let summary = analytics.summary(period)
        let previous = analytics.previousSummary(period)
        let style = InsightStyle(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PeriodBar(analytics: analytics, period: $period)

                hero(summary, previous: previous, style: style)

                FocusCalendarCard(analytics: analytics, period: period)

                // Goals are about today and this week, so they show even when the period
                // you're looking at is empty (that's when "0 of 8" matters most).
                if hasProgress && summary.sessions == 0 {
                    InsightCard(title: "Progress") { progress }
                }

                if summary.sessions > 0 {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)],
                              alignment: .leading, spacing: 16) {
                        InsightCard(title: "When you focus", subtitle: peakHourText) {
                            HourChart(hours: analytics.hourOfDay(period))
                        }
                        InsightCard(title: "Best days", subtitle: bestDayText) {
                            WeekdayChart(days: analytics.weekdays(period))
                        }
                        if hasProgress {
                            InsightCard(title: "Progress") { progress }
                        }
                        let shares = analytics.projectShares(period)
                        if !history.projects.isEmpty && !shares.isEmpty {
                            InsightCard(title: "Projects", subtitle: "Where your focus went") {
                                ProjectShareView(shares: shares)
                            }
                        }
                        let ratings = analytics.series(period).filter { $0.rating != nil }
                        if !ratings.isEmpty {
                            InsightCard(title: "Focus quality", subtitle: "Average rating, 1 scattered – 5 deep focus") {
                                RatingChart(buckets: ratings, unit: analytics.bucketUnit(period))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: Hero

    private func hero(_ summary: Summary, previous: Summary?, style: InsightStyle) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    headline(summary, previous: previous)
                    Spacer(minLength: 12)
                    metrics(summary, divided: true)
                }
                VStack(alignment: .leading, spacing: 18) {
                    headline(summary, previous: previous)
                    metrics(summary, divided: false)
                }
            }
            if summary.sessions == 0 {
                ContentUnavailableView("No focus sessions here yet", systemImage: "circle.dashed",
                                       description: Text("Finished sessions show up here. Try another period, or start one."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chartSubtitle).font(.caption).foregroundStyle(.secondary)
                    FocusTimeChart(series: analytics.series(period),
                                   average: analytics.rollingAverage(period),
                                   unit: analytics.bucketUnit(period),
                                   goal: analytics.bucketUnit(period) == .day && prefs.dailyGoalMinutes > 0
                                       ? Double(prefs.dailyGoalMinutes) : nil,
                                   calendar: analytics.calendar)
                }
            }
        }
        .padding(20)
        .background(style.card(20))
    }

    private func headline(_ summary: Summary, previous: Summary?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Focus time")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(InsightFormat.minutes(summary.focus / 60))
                .font(.system(size: 42, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let change = InsightFormat.change(summary.focus, previous?.focus, period.kind) {
                Text(change)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.14 : 0.07)))
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func metrics(_ summary: Summary, divided: Bool) -> some View {
        let items: [(String, String)] = [
            ("Sessions", "\(summary.sessions)"),
            ("Average", InsightFormat.minutes(summary.average / 60)),
            ("Active days", period.kind == .all ? "\(summary.activeDays)" : "\(summary.activeDays)/\(daysIn(period))"),
            ("Rating", summary.averageRating.map { String(format: "%.1f", $0) } ?? "–"),
            ("Distractions", String(format: "%.1f/h", summary.distractionsPerHour)),
        ]
        if divided {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider().frame(height: 40).padding(.horizontal, 14) }
                    metric(item.0, item.1)
                }
            }
            .fixedSize()
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in metric(item.0, item.1) }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Progress

    private var hasProgress: Bool {
        prefs.dailyGoal > 0 || prefs.dailyGoalMinutes > 0 || prefs.weeklyGoalMinutes > 0 || prefs.streaksEnabled
    }

    private var progress: some View {
        let streaks = prefs.streaksEnabled ? analytics.streaks(prefs.streakRule) : nil
        return VStack(alignment: .leading, spacing: 16) {
            // Wraps onto a second row when the card is narrow.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16, alignment: .leading)],
                      alignment: .leading, spacing: 14) {
                if prefs.dailyGoal > 0 {
                    let count = analytics.sessions(onDayOf: .now)
                    goalRing("Sessions today", progress: Double(count) / Double(prefs.dailyGoal),
                             value: "\(count)", detail: "of \(prefs.dailyGoal)")
                }
                if prefs.dailyGoalMinutes > 0 {
                    let value = analytics.minutes(onDayOf: .now)
                    goalRing("Today", progress: value / Double(prefs.dailyGoalMinutes),
                             value: InsightFormat.minutes(value),
                             detail: "of \(InsightFormat.minutes(Double(prefs.dailyGoalMinutes)))")
                }
                if prefs.weeklyGoalMinutes > 0 {
                    let value = analytics.minutes(inWeekOf: .now)
                    goalRing("This week", progress: value / Double(prefs.weeklyGoalMinutes),
                             value: InsightFormat.minutes(value),
                             detail: "of \(InsightFormat.minutes(Double(prefs.weeklyGoalMinutes)))")
                }
            }
            if let streaks {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(streaks.current)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text("day streak").foregroundStyle(.secondary)
                    Spacer()
                    Text("Best \(streaks.longest)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func goalRing(_ title: String, progress: Double, value: String, detail: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                GoalRing(progress: progress)
                Text("\(min(999, Int((progress * 100).rounded())))%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(value).font(.headline).monospacedDigit()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Text

    private func daysIn(_ period: Period) -> Int {
        let range = analytics.interval(period)
        return analytics.calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 0
    }

    private var chartSubtitle: String {
        analytics.bucketUnit(period) == .day ? "Per day · dashed line: 7-day average" : "Per month"
    }

    private var peakHourText: String? {
        let hours = analytics.hourOfDay(period)
        guard let peak = hours.indices.max(by: { hours[$0] < hours[$1] }), hours[peak] > 0 else { return nil }
        return "Most focused around \(peak):00"
    }

    private var bestDayText: String? {
        let days = analytics.weekdays(period)
        guard let best = days.max(by: { $0.minutes < $1.minutes }), best.minutes > 0 else { return nil }
        return "\(analytics.calendar.weekdaySymbols[best.weekday - 1])s are your strongest"
    }
}

// MARK: - Charts

/// Charts plot hours so the axis lands on round values (1h, 2h…); labels convert back.
private func hourAxis(_ style: InsightStyle) -> some AxisContent {
    AxisMarks { value in
        AxisGridLine().foregroundStyle(style.grid)
        AxisValueLabel { if let hours = value.as(Double.self) { Text(InsightFormat.axis(hours * 60)) } }
    }
}

struct FocusTimeChart: View {
    var series: [Bucket]
    var average: [Bucket]
    var unit: Calendar.Component
    var goal: Double?
    var calendar: Calendar

    @State private var selected: Date?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        let highlighted = selected.flatMap { date in
            series.first { calendar.isDate($0.start, equalTo: date, toGranularity: unit) }
        }
        Chart {
            ForEach(series) { bucket in
                BarMark(x: .value("Date", bucket.start, unit: unit),
                        y: .value("Hours", bucket.minutes / 60))
                    .foregroundStyle(highlighted == nil || highlighted?.id == bucket.id ? style.bar : style.barDim)
                    .cornerRadius(4)
            }
            ForEach(average) { bucket in
                LineMark(x: .value("Date", bucket.start, unit: unit),
                         y: .value("Average", bucket.minutes / 60))
                    .foregroundStyle(style.line)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .interpolationMethod(.catmullRom)
            }
            if let goal {
                RuleMark(y: .value("Goal", goal / 60))
                    .foregroundStyle(style.line)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal \(InsightFormat.minutes(goal))").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let highlighted {
                RuleMark(x: .value("Selected", highlighted.start, unit: unit))
                    .foregroundStyle(style.grid)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(highlighted.start, format: unit == .day ? .dateTime.weekday(.abbreviated).day().month() : .dateTime.month(.wide).year())
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(InsightFormat.minutes(highlighted.minutes)).font(.caption.weight(.semibold)).monospacedDigit()
                            Text("\(highlighted.sessions) session\(highlighted.sessions == 1 ? "" : "s")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(style.card(8))
                        .background(RoundedRectangle(cornerRadius: 8).fill(.background))
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis { hourAxis(style) }
        .chartXAxis {
            if unit == .day && series.count <= 7 {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            } else if unit == .day {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine().foregroundStyle(style.grid)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            } else {
                AxisMarks(values: .stride(by: .month, count: series.count > 18 ? 3 : 1)) { _ in
                    AxisValueLabel(format: series.count > 18 ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.month(.narrow), centered: true)
                }
            }
        }
        .frame(height: 220)
    }
}

struct HourChart: View {
    var hours: [Double]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        let peak = hours.max() ?? 0
        Chart {
            // Hours as categories, so every bar gets a real width.
            ForEach(0..<24, id: \.self) { hour in
                BarMark(x: .value("Hour", String(hour)), y: .value("Hours", hours[hour] / 60), width: .ratio(0.7))
                    .foregroundStyle(hours[hour] == peak && peak > 0 ? style.bar : style.barDim)
                    .cornerRadius(2)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                if let hour = value.as(String.self).flatMap(Int.init), hour % 6 == 0 {
                    AxisValueLabel { Text("\(hour):00").fixedSize() }
                }
            }
        }
        .chartYAxis { hourAxis(style) }
        .frame(height: 150)
    }
}

struct WeekdayChart: View {
    var days: [WeekdayValue]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        let best = days.map(\.minutes).max() ?? 0
        Chart(days) { day in
            BarMark(x: .value("Day", day.name), y: .value("Hours", day.minutes / 60), width: .ratio(0.6))
                .foregroundStyle(day.minutes == best && best > 0 ? style.bar : style.barDim)
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel() }
        }
        .chartYAxis { hourAxis(style) }
        .frame(height: 150)
    }
}

struct RatingChart: View {
    var buckets: [Bucket]
    var unit: Calendar.Component
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        Chart(buckets) { bucket in
            LineMark(x: .value("Date", bucket.start, unit: unit), y: .value("Rating", bucket.rating ?? 0))
                .foregroundStyle(style.line)
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Date", bucket.start, unit: unit), y: .value("Rating", bucket.rating ?? 0))
                .foregroundStyle(style.ink)
                .symbolSize(30)
        }
        .chartYScale(domain: 1...5)
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { _ in
                AxisGridLine().foregroundStyle(style.grid)
                AxisValueLabel()
            }
        }
        .frame(height: 140)
    }
}

/// A single grayscale bar split by project, with a legend underneath.
struct ProjectShareView: View {
    var shares: [ProjectShare]
    @Environment(HistoryStore.self) private var history
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let total = max(1, shares.reduce(0) { $0 + $1.minutes })
        let ink = Color.ink(scheme)
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        Rectangle()
                            .fill(ink.opacity(Shade.opacity(index)))
                            .frame(width: max(2, (geo.size.width - CGFloat(shares.count - 1) * 2) * share.minutes / total))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)

            VStack(spacing: 8) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    let project = history.project(share.projectID)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ink.opacity(Shade.opacity(index)))
                            .overlay(Circle().strokeBorder(ink.opacity(0.3), lineWidth: 0.5))
                            .frame(width: 9, height: 9)
                        Image(systemName: project?.symbol ?? "tray")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(project?.name ?? "Unassigned")
                            .foregroundStyle(project == nil ? .secondary : .primary)
                        Spacer()
                        Text(InsightFormat.minutes(share.minutes)).monospacedDigit()
                        Text("\(Int((share.minutes / total * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
        }
    }
}
