import SwiftUI
import UniformTypeIdentifiers

// MARK: - Insights

/// Insights on iPhone and iPad, opened from This Week in Sessions. Made for a narrow screen:
/// one big number, then short cards that read top to bottom (two across on iPad), with bars
/// laid sideways so every label has room.
struct MobileInsightsView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme
    @State private var period = Period(kind: .week, anchor: .now)

    var body: some View {
        let analytics = Analytics(records: history.records, calendar: .current, dayStartHour: prefs.dayStartsAtHour)
        let summary = analytics.summary(period)
        let records = analytics.records(in: period)
        let shares = analytics.projectShares(period)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PeriodSwitcher(analytics: analytics, period: $period)
                    .padding(.bottom, 4)

                FocusHero(analytics: analytics, period: period, summary: summary)

                if summary.sessions > 0 {
                    StatGrid(summary: summary, days: analytics.daysIn(period), period: period)
                }

                if hasProgress {
                    ProgressCard(analytics: analytics)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)],
                          alignment: .leading, spacing: 14) {
                    MonthHeatCard(analytics: analytics, period: period)
                    if summary.sessions > 0 {
                        TimeOfDayCard(hours: analytics.hourOfDay(period))
                        WeekdayCard(days: analytics.weekdays(period))
                        if records.contains(where: { $0.rating != nil }) {
                            QualityCard(records: records)
                        }
                        if prefs.projectsActive && !history.projects.isEmpty && !shares.isEmpty {
                            ProjectsCard(shares: shares)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasProgress: Bool {
        prefs.dailyGoal > 0 || prefs.dailyGoalMinutes > 0 || prefs.weeklyGoalMinutes > 0 || prefs.streaksEnabled
    }
}

private extension Analytics {
    func daysIn(_ period: Period) -> Int {
        let range = interval(period)
        return calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 0
    }
}

/// Week / Month / Year / All across the width, and under it the period with back and forward.
private struct PeriodSwitcher: View {
    var analytics: Analytics
    @Binding var period: Period

    var body: some View {
        VStack(spacing: 12) {
            InkSegmented(selection: Binding(get: { period.kind },
                                            set: { kind in withAnimation(.snappy) { period = Period(kind: kind, anchor: .now) } }),
                         items: PeriodKind.allCases, fill: true) { Text($0.title) }
            HStack {
                step(-1, symbol: "chevron.left", label: "Previous")
                    .disabled(period.kind == .all)
                Spacer(minLength: 8)
                Text(analytics.title(period))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                step(1, symbol: "chevron.right", label: "Next")
                    .disabled(analytics.isCurrent(period))
            }
        }
    }

    private func step(_ delta: Int, symbol: String, label: String) -> some View {
        Button {
            Haptics.play(.select)
            withAnimation(.snappy) { period = analytics.shifted(period, by: delta) }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}

/// The period's focus time, how it compares, and the bars underneath.
private struct FocusHero: View {
    var analytics: Analytics
    var period: Period
    var summary: Summary
    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus time")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(InsightFormat.minutes(summary.focus / 60))
                        .font(.system(size: 44, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                if let change = change {
                    Label(change.text, systemImage: change.up ? "arrow.up.right" : "arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.14 : 0.07)))
                }
            }
            if summary.sessions == 0 {
                VStack(spacing: 6) {
                    Image(systemName: "circle.dashed").font(.title2)
                    Text("No focus sessions here yet").font(.subheadline.weight(.medium))
                    Text("Try another period, or start one.").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                FocusTimeChart(series: analytics.series(period),
                               average: analytics.rollingAverage(period),
                               unit: analytics.bucketUnit(period),
                               goal: analytics.bucketUnit(period) == .day && prefs.dailyGoalMinutes > 0
                                   ? Double(prefs.dailyGoalMinutes) : nil,
                               calendar: analytics.calendar)
                    .frame(height: 200)
                Text(analytics.bucketUnit(period) == .day ? "Per day · dashed: 7-day average · touch a bar for details" : "Per month · touch a bar for details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(InsightStyle(scheme: scheme).card(22))
    }

    /// "+18% vs last week", with which way it went.
    private var change: (text: String, up: Bool)? {
        guard let before = analytics.previousSummary(period)?.focus,
              let text = InsightFormat.change(summary.focus, before, period.kind) else { return nil }
        return (text, summary.focus >= before)
    }
}

/// Six small numbers, three across.
private struct StatGrid: View {
    var summary: Summary
    var days: Int
    var period: Period
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let items: [(String, String, String)] = [
            ("Sessions", "\(summary.sessions)", "number"),
            ("Average", InsightFormat.minutes(summary.average / 60), "clock"),
            ("Longest", InsightFormat.minutes(summary.longest / 60), "arrow.up.to.line"),
            ("Active days", period.kind == .all ? "\(summary.activeDays)" : "\(summary.activeDays)/\(days)", "calendar"),
            ("Rating", summary.averageRating.map { String(format: "%.1f", $0) } ?? "–", "star"),
            ("Distractions", String(format: "%.1f/h", summary.distractionsPerHour), "exclamationmark.bubble"),
        ]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(items, id: \.0) { title, value, symbol in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(InsightStyle(scheme: scheme).card(16))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Goals as rings, and the streak beside them.
private struct ProgressCard: View {
    var analytics: Analytics
    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Progress").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    if prefs.dailyGoal > 0 {
                        let count = analytics.sessions(onDayOf: .now)
                        ring("Sessions today", Double(count) / Double(prefs.dailyGoal), "\(count)", "of \(prefs.dailyGoal)")
                    }
                    if prefs.dailyGoalMinutes > 0 {
                        let value = analytics.minutes(onDayOf: .now)
                        ring("Today", value / Double(prefs.dailyGoalMinutes), InsightFormat.minutes(value),
                             "of \(InsightFormat.minutes(Double(prefs.dailyGoalMinutes)))")
                    }
                    if prefs.weeklyGoalMinutes > 0 {
                        let value = analytics.minutes(inWeekOf: .now)
                        ring("This week", value / Double(prefs.weeklyGoalMinutes), InsightFormat.minutes(value),
                             "of \(InsightFormat.minutes(Double(prefs.weeklyGoalMinutes)))")
                    }
                    if prefs.streaksEnabled {
                        let streaks = analytics.streaks(prefs.streakRule)
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(Color.ink(scheme).opacity(0.07))
                                VStack(spacing: 0) {
                                    Image(systemName: "flame.fill").font(.caption)
                                    Text("\(streaks.current)")
                                        .font(.title3.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }
                            .frame(width: 64, height: 64)
                            Text("Day streak").font(.caption.weight(.medium))
                            Text("Best \(streaks.longest)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightStyle(scheme: scheme).card(20))
    }

    private func ring(_ title: String, _ progress: Double, _ value: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                GoalRing(progress: progress)
                Text("\(min(999, Int((progress * 100).rounded())))%")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 64, height: 64)
            Text(title).font(.caption.weight(.medium))
            Text("\(value) \(detail)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A month at a time, as a calendar: each day a square in five shades of ink, the date on top.
/// Tap a day for its sessions.
private struct MonthHeatCard: View {
    var analytics: Analytics
    var period: Period
    @Environment(HistoryStore.self) private var history
    @Environment(\.colorScheme) private var scheme
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selected: Date?

    var body: some View {
        let calendar = analytics.calendar
        let days = monthDays
        let minutes = days.map { analytics.minutes(onDayOf: noon($0)) }
        let top = minutes.max() ?? 0
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let today = analytics.day(of: .now)
        let style = InsightStyle(scheme: scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus calendar").font(.headline)
                    Text("\(InsightFormat.minutes(minutes.reduce(0, +))) · \(minutes.filter { $0 > 0 }.count) active days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                        .accessibilityLabel("Previous month")
                    Text(month, format: .dateTime.month(.abbreviated).year())
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 76)
                    Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                        .disabled(month >= (calendar.dateInterval(of: .month, for: .now)?.start ?? .now))
                        .accessibilityLabel("Next month")
                }
                .buttonStyle(.borderless)
            }

            // Week rows of seven square days. (Plain stacks: a lazy grid nested in the page's
            // two-column grid on iPad gets no width to work with.)
            let slots: [Int?] = Array(repeating: nil, count: lead) + days.indices.map { Optional($0) }
            let weeks = stride(from: 0, to: slots.count, by: 7).map { start in
                Array(slots[start..<min(start + 7, slots.count)]) + Array(repeating: nil, count: max(0, start + 7 - slots.count))
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(calendar.veryShortWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { column in
                            if let index = week[column] {
                                dayCell(days[index], minutes: minutes[index], top: top, today: today, style: style)
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(style.heat(level)).frame(width: 12, height: 12)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }

            if let selected {
                let sessions = analytics.records.filter { analytics.day(of: $0.end) == selected }.sorted { $0.end < $1.end }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(sessions.isEmpty ? "No focus" : "\(sessions.count) · \(InsightFormat.minutes(sessions.reduce(0) { $0 + $1.duration } / 60))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    ForEach(sessions) { record in
                        SessionRow(record: record, project: Preferences.shared.projectsActive ? history.project(record.projectID) : nil)
                            .font(.subheadline)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightStyle(scheme: scheme).card(20))
        .onChange(of: period, initial: true) {
            guard period.kind == .week || period.kind == .month else { return }
            let anchor = min(analytics.interval(period).start, .now)
            month = analytics.calendar.dateInterval(of: .month, for: anchor)?.start ?? month
            selected = nil
        }
    }

    private func dayCell(_ day: Date, minutes: Double, top: Double, today: Date, style: InsightStyle) -> some View {
        let level = level(minutes, top: top)
        let isSelected = selected == day
        return Button {
            Haptics.play(.select)
            withAnimation(.snappy) { selected = isSelected ? nil : day }
        } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(style.heat(level))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text("\(analytics.calendar.component(.day, from: day))")
                        .font(.caption.weight(day == today ? .bold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(level >= 3 ? Color.ink(scheme == .dark ? .light : .dark)
                                         : Color.primary.opacity(day > today ? 0.3 : 0.8))
                }
                .overlay {
                    if isSelected || day == today {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.ink(scheme), lineWidth: isSelected ? 2 : 1)
                            .padding(-2)
                    }
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(day > today)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(InsightFormat.minutes(minutes))")
    }

    private var monthDays: [Date] {
        let calendar = analytics.calendar
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func noon(_ day: Date) -> Date {
        analytics.calendar.date(byAdding: .hour, value: 12 + analytics.dayStartHour, to: day) ?? day
    }

    private func level(_ minutes: Double, top: Double) -> Int {
        guard minutes > 0, top > 0 else { return 0 }
        return min(4, max(1, Int((minutes / top * 4).rounded(.up))))
    }

    private func step(_ delta: Int) {
        Haptics.play(.select)
        withAnimation(.snappy) {
            month = analytics.calendar.date(byAdding: .month, value: delta, to: month) ?? month
            selected = nil
        }
    }
}

/// A horizontal bar with a label on the left and the value on the right. The strongest one is solid.
private struct BarRow: View {
    var title: String
    var detail: String?
    var value: Double
    var top: Double
    var strongest: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.weight(strongest ? .semibold : .regular))
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(style.empty)
                    Capsule()
                        .fill(strongest ? style.ink : style.barDim)
                        .frame(width: top > 0 && value > 0 ? max(8, geo.size.width * value / top) : 0)
                }
            }
            .frame(height: 10)
            Text(InsightFormat.minutes(value))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? .primary : .secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// When in the day you focus, in five parts rather than 24 thin bars.
private struct TimeOfDayCard: View {
    var hours: [Double]
    @Environment(\.colorScheme) private var scheme

    private static let parts: [(String, Int, Int)] = [
        ("Early", 5, 9), ("Morning", 9, 12), ("Afternoon", 12, 17), ("Evening", 17, 21), ("Night", 21, 29),
    ]

    var body: some View {
        let values = Self.parts.map { _, from, to in (from..<to).reduce(0) { $0 + hours[$1 % 24] } }
        let top = values.max() ?? 0
        let best = values.firstIndex(of: top)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("When you focus").font(.headline)
                if let best, top > 0 {
                    Text("Mostly in the \(Self.parts[best].0 == "Early" ? "early morning" : Self.parts[best].0.lowercased())")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(Self.parts.enumerated()), id: \.offset) { index, part in
                BarRow(title: part.0, detail: "\(part.1):00–\(part.2 % 24):00", value: values[index], top: top,
                       strongest: index == best && top > 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightStyle(scheme: scheme).card(20))
    }
}

/// Which days of the week, as columns.
private struct WeekdayCard: View {
    var days: [WeekdayValue]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        let top = days.map(\.minutes).max() ?? 0
        let best = days.first { $0.minutes == top && top > 0 }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Best days").font(.headline)
                if let best {
                    Text("\(Calendar.current.weekdaySymbols[best.weekday - 1])s are your strongest")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    let strongest = day.id == best?.id
                    VStack(spacing: 6) {
                        Text(day.minutes > 0 ? InsightFormat.axis(day.minutes) : "")
                            .font(.caption2.weight(strongest ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(strongest ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        ZStack(alignment: .bottom) {
                            Capsule().fill(style.empty)
                            Capsule()
                                .fill(strongest ? style.ink : style.barDim)
                                .frame(height: top > 0 && day.minutes > 0 ? max(10, 96 * day.minutes / top) : 0)
                        }
                        .frame(height: 96)
                        .frame(maxWidth: 26)
                        Text(day.name.prefix(2))
                            .font(.caption.weight(strongest ? .bold : .medium))
                            .foregroundStyle(strongest ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.name), \(InsightFormat.minutes(day.minutes))")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightStyle(scheme: scheme).card(20))
    }
}

/// How sessions felt: the average in stars, and how often each rating came up.
private struct QualityCard: View {
    var records: [FocusRecord]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let style = InsightStyle(scheme: scheme)
        let ratings = records.compactMap(\.rating)
        let average = Double(ratings.reduce(0, +)) / Double(max(1, ratings.count))
        let counts = (1...5).map { value in ratings.filter { $0 == value }.count }
        let top = counts.max() ?? 0
        VStack(alignment: .leading, spacing: 14) {
            Text("Focus quality").font(.headline)
            HStack(alignment: .center, spacing: 12) {
                Text(String(format: "%.1f", average))
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: Double(star) <= average + 0.25 ? "star.fill"
                                  : Double(star) - 0.5 <= average ? "star.leadinghalf.filled" : "star")
                        }
                    }
                    .font(.footnote)
                    Text("\(ratings.count) rated session\(ratings.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                ForEach((1...5).reversed(), id: \.self) { value in
                    HStack(spacing: 10) {
                        Text(FocusRecord.ratingWords[value])
                            .font(.caption)
                            .frame(width: 78, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(style.empty)
                                Capsule()
                                    .fill(counts[value - 1] == top ? style.ink : style.barDim)
                                    .frame(width: top > 0 && counts[value - 1] > 0 ? max(8, geo.size.width * Double(counts[value - 1]) / Double(top)) : 0)
                            }
                        }
                        .frame(height: 8)
                        Text("\(counts[value - 1])")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightStyle(scheme: scheme).card(20))
    }
}

/// Where the time went: the split as one bar, then each project with its own.
private struct ProjectsCard: View {
    var shares: [ProjectShare]
    @Environment(HistoryStore.self) private var history
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let total = max(1, shares.reduce(0) { $0 + $1.minutes })
        let ink = Color.ink(scheme)
        let style = InsightStyle(scheme: scheme)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Projects").font(.headline)
                Text("Where your focus went").font(.caption).foregroundStyle(.secondary)
            }
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
            .frame(height: 14)

            VStack(spacing: 12) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    let project = history.project(share.projectID)
                    HStack(spacing: 12) {
                        Image(systemName: project?.symbol ?? "tray")
                            .font(.subheadline)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(style.cardFill))
                            .overlay(alignment: .bottomTrailing) {
                                Circle().fill(ink.opacity(Shade.opacity(index)))
                                    .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 1.5))
                                    .frame(width: 11, height: 11)
                            }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project?.name ?? "No project")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(project == nil ? .secondary : .primary)
                                .lineLimit(1)
                            Text("\(share.sessions) session\(share.sessions == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(InsightFormat.minutes(share.minutes))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                            Text("\(Int((share.minutes / total * 100).rounded()))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InsightStyle(scheme: scheme).card(20))
    }
}

// MARK: - Projects

/// Every project: tap one to rename it, change its icon, archive or delete it; add new ones at
/// the bottom. Opened from the folder at the top left of Sessions.
struct ProjectsSheet: View {
    @Environment(HistoryStore.self) private var history
    @Environment(\.dismiss) private var dismiss
    @State private var naming = false
    @State private var newName = ""
    @State private var confirmDelete: Project?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(history.activeProjects) { project in
                        row(project)
                    }
                    Button("New Project", systemImage: "plus") {
                        newName = ""
                        naming = true
                    }
                } footer: {
                    Text("Pick a project from the folder in the timer's intention field. Deleting one keeps its sessions, without a project.")
                }
                let archived = history.projects.filter(\.isArchived)
                if !archived.isEmpty {
                    Section("Archived") {
                        ForEach(archived) { project in row(project) }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .navigationDestination(for: Project.ID.self) { id in
                ProjectEditor(id: id)
            }
            .alert("New Project", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    Haptics.play(.select)
                    withAnimation { _ = history.addProject(named: newName) }
                }
            }
            .confirmationDialog("Delete \u{201C}\(confirmDelete?.name ?? "")\u{201D}?",
                                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Project", role: .destructive) {
                    if let id = confirmDelete?.id { withAnimation { history.deleteProject(id) } }
                    confirmDelete = nil
                }
            } message: {
                Text("Its sessions stay, without a project.")
            }
        }
    }

    private func row(_ project: Project) -> some View {
        let sessions = history.records.filter { $0.projectID == project.id }
        let minutes = sessions.reduce(0) { $0 + $1.duration } / 60
        return NavigationLink(value: project.id) {
            HStack(spacing: 12) {
                Image(systemName: project.symbol)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name)
                        .foregroundStyle(project.isArchived ? .secondary : .primary)
                    Text(sessions.isEmpty ? "No sessions yet" : "\(sessions.count) session\(sessions.count == 1 ? "" : "s") · \(InsightFormat.minutes(minutes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = project }
                .tint(.red)
            Button(project.isArchived ? "Unarchive" : "Archive",
                   systemImage: project.isArchived ? "tray.and.arrow.up" : "archivebox") {
                var p = project
                p.isArchived.toggle()
                withAnimation { history.updateProject(p) }
            }
        }
    }
}

/// One project: its name, its icon, and archiving or deleting it.
private struct ProjectEditor: View {
    var id: Project.ID
    @Environment(HistoryStore.self) private var history
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        if let project = history.project(id) {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit { save() }
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(Project.symbols, id: \.self) { symbol in
                            let selected = symbol == project.symbol
                            Button {
                                Haptics.play(.select)
                                var p = project
                                p.symbol = symbol
                                history.updateProject(p)
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 17))
                                    .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selected ? Color.primary : Color.primary.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Toggle("Archived", isOn: Binding(get: { project.isArchived }, set: {
                        var p = project
                        p.isArchived = $0
                        history.updateProject(p)
                    }))
                } footer: {
                    Text("Archived projects stay in Sessions and Insights, but aren't offered on the timer.")
                }
                Section {
                    Button("Delete Project", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
            .toggleStyle(InkSwitchStyle())
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !loaded else { return }
                name = project.name
                loaded = true
            }
            .onDisappear { save() }
            .confirmationDialog("Delete \u{201C}\(project.name)\u{201D}?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Project", role: .destructive) {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation { history.deleteProject(id) }
                    }
                }
            } message: {
                Text("Its sessions stay, without a project.")
            }
        } else {
            ContentUnavailableView("Project deleted", systemImage: "trash")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard loaded, !trimmed.isEmpty, var project = history.project(id), project.name != trimmed else { return }
        project.name = trimmed
        history.updateProject(project)
    }
}

// MARK: - Your Data

/// Export and import, in Settings.
struct YourDataView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(Preferences.self) private var prefs
    @State private var exportFile: ExportFile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        Form {
            Section {
                row("Sessions", detail: "CSV", symbol: "tablecells") {
                    export(Data(history.sessionsCSV.utf8), .commaSeparatedText, "Fifteen Sessions")
                }
                row("Daily Summary", detail: "CSV", symbol: "calendar") {
                    let analytics = Analytics(records: history.records, calendar: .current, dayStartHour: prefs.dayStartsAtHour)
                    export(Data(analytics.dailyCSV().utf8), .commaSeparatedText, "Fifteen Daily Summary")
                }
                row("Full Backup", detail: "JSON", symbol: "archivebox") {
                    export(history.backupJSON(), .json, "Fifteen Backup")
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Your history stays on this device. Take a copy with you; a full backup brings back sessions and projects.")
            }
            Section {
                Button("Import Backup…", systemImage: "square.and.arrow.down") { showImporter = true }
            } footer: {
                Text("Adds what's in the backup. Sessions you already have aren't doubled.")
            }
        }
        .navigationTitle("Your Data")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $showExporter, document: exportFile,
                      contentType: exportFile?.contentType ?? .json,
                      defaultFilename: exportFile?.filename) { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { importBackup($0) }
        .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func row(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "square.and.arrow.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
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
