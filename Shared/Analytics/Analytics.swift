import Foundation

/// Every number in Insights comes from here: pure, synchronous, and unit-tested.
///
/// Rules:
/// - A session belongs to the "day" of its **end**, where a day starts at `dayStartHour`
///   (so 01:30 still counts as yesterday with the default of 04:00).
/// - Day keys are the midnight of that calendar day.
/// - Weeks follow the calendar's `firstWeekday`.

enum PeriodKind: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, all
    var id: Self { self }
    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .all: "All"
        }
    }
}

struct Period: Hashable, Sendable {
    var kind: PeriodKind
    var anchor: Date
}

struct Bucket: Identifiable, Hashable, Sendable {
    var start: Date
    var minutes: Double
    var sessions: Int
    var rating: Double?
    var id: Date { start }
}

struct Summary: Equatable, Sendable {
    var focus: TimeInterval = 0
    var sessions = 0
    var average: TimeInterval = 0
    var longest: TimeInterval = 0
    var activeDays = 0
    var averageRating: Double?
    var distractionsPerHour: Double = 0
    static let zero = Summary()
}

struct ProjectShare: Identifiable, Hashable, Sendable {
    var projectID: UUID?
    var minutes: Double
    var sessions: Int
    var id: String { projectID?.uuidString ?? "unassigned" }
}

struct WeekdayValue: Identifiable, Hashable, Sendable {
    var weekday: Int // 1 = Sunday … 7 = Saturday
    var name: String
    var minutes: Double
    var id: Int { weekday }
}

struct HeatCell: Identifiable, Hashable, Sendable {
    var day: Date
    var minutes: Double
    /// 0 = nothing, 1…4 = quartiles of your own active days.
    var level: Int
    var id: Date { day }
}

struct MonthLabel: Identifiable, Hashable, Sendable {
    var column: Int
    var date: Date
    var id: Int { column }
}

struct HeatmapData: Sendable {
    /// Week columns of seven rows; nil outside the year.
    var columns: [[HeatCell?]]
    var months: [MonthLabel]
}

struct StreakRule: Sendable {
    /// A day counts when it has at least this many minutes (and at least one session).
    var minimumMinutes: Double = 0
    /// Weekdays (1 = Sunday … 7 = Saturday) that never break a streak.
    var restWeekdays: Set<Int> = []
}

struct Streaks: Equatable, Sendable {
    var current: Int
    var longest: Int
}

struct DayStat: Sendable {
    var minutes: Double = 0
    var sessions = 0
    var ratingSum = 0
    var ratingCount = 0
}

struct Analytics: Sendable {
    let records: [FocusRecord]
    let calendar: Calendar
    let dayStartHour: Int
    let byDay: [Date: DayStat]

    init(records: [FocusRecord], calendar: Calendar = .current, dayStartHour: Int = 4) {
        self.records = records
        self.calendar = calendar
        self.dayStartHour = dayStartHour
        var map: [Date: DayStat] = [:]
        for record in records {
            let key = Self.dayKey(record.end, hour: dayStartHour, calendar: calendar)
            map[key, default: DayStat()].minutes += record.duration / 60
            map[key, default: DayStat()].sessions += 1
            if let rating = record.rating {
                map[key, default: DayStat()].ratingSum += rating
                map[key, default: DayStat()].ratingCount += 1
            }
        }
        byDay = map
    }

    // MARK: Days

    static func dayKey(_ date: Date, hour: Int, calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .hour, value: -hour, to: date) ?? date)
    }

    func day(of date: Date) -> Date { Self.dayKey(date, hour: dayStartHour, calendar: calendar) }

    func minutes(onDayOf date: Date) -> Double { byDay[day(of: date)]?.minutes ?? 0 }

    func sessions(onDayOf date: Date) -> Int { byDay[day(of: date)]?.sessions ?? 0 }

    func minutes(inWeekOf date: Date) -> Double {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: day(of: date)) else { return 0 }
        return byDay.filter { week.contains($0.key) }.reduce(0) { $0 + $1.value.minutes }
    }

    // MARK: Periods

    func interval(_ period: Period, now: Date = .now) -> DateInterval {
        let anchor = day(of: period.anchor)
        switch period.kind {
        case .week: return calendar.dateInterval(of: .weekOfYear, for: anchor)!
        case .month: return calendar.dateInterval(of: .month, for: anchor)!
        case .year: return calendar.dateInterval(of: .year, for: anchor)!
        case .all:
            let first = byDay.keys.min() ?? anchor
            let last = max(day(of: now), anchor)
            return DateInterval(start: calendar.dateInterval(of: .month, for: first)!.start,
                                end: calendar.dateInterval(of: .month, for: last)!.end)
        }
    }

    func shifted(_ period: Period, by steps: Int) -> Period {
        let component: Calendar.Component
        switch period.kind {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        case .all: return period
        }
        return Period(kind: period.kind, anchor: calendar.date(byAdding: component, value: steps, to: period.anchor)!)
    }

    func isCurrent(_ period: Period, now: Date = .now) -> Bool {
        period.kind == .all || interval(period, now: now).contains(day(of: now))
    }

    /// Bars are days for a week or month, months for a year or all time.
    func bucketUnit(_ period: Period) -> Calendar.Component {
        period.kind == .week || period.kind == .month ? .day : .month
    }

    func title(_ period: Period) -> String {
        let range = interval(period)
        var day = Date.FormatStyle.dateTime.day().month(.abbreviated)
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        switch period.kind {
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: range.end)!
            return "\(range.start.formatted(day)) – \(last.formatted(day.year()))"
        case .month:
            return range.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return range.start.formatted(.dateTime.year())
        case .all:
            return "All Time"
        }
    }

    // MARK: Sessions in a period

    func records(in period: Period) -> [FocusRecord] {
        let range = interval(period)
        return records.filter {
            let key = day(of: $0.end)
            return key >= range.start && key < range.end
        }
    }

    func summary(_ period: Period) -> Summary { summary(of: records(in: period)) }

    /// The same-length period just before, for "+18% vs last week". Nil for all time.
    func previousSummary(_ period: Period) -> Summary? {
        period.kind == .all ? nil : summary(shifted(period, by: -1))
    }

    func summary(of records: [FocusRecord]) -> Summary {
        guard !records.isEmpty else { return .zero }
        let focus = records.reduce(0) { $0 + $1.duration }
        let ratings = records.compactMap(\.rating)
        let distractions = records.reduce(0) { $0 + $1.distractions }
        return Summary(
            focus: focus,
            sessions: records.count,
            average: focus / Double(records.count),
            longest: records.map(\.duration).max() ?? 0,
            activeDays: Set(records.map { day(of: $0.end) }).count,
            averageRating: ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count),
            distractionsPerHour: focus > 0 ? Double(distractions) / (focus / 3600) : 0
        )
    }

    // MARK: Charts

    /// One bucket per day (week, month) or per month (year, all), empty ones included.
    func series(_ period: Period, where include: (FocusRecord) -> Bool = { _ in true }) -> [Bucket] {
        let range = interval(period)
        let unit = bucketUnit(period)
        var starts: [Date] = []
        var cursor = range.start
        while cursor < range.end {
            starts.append(cursor)
            cursor = calendar.date(byAdding: unit, value: 1, to: cursor)!
        }
        var buckets = starts.map { Bucket(start: $0, minutes: 0, sessions: 0, rating: nil) }
        var ratingSums = Array(repeating: 0, count: starts.count)
        var ratingCounts = Array(repeating: 0, count: starts.count)
        for record in records where include(record) {
            let key = day(of: record.end)
            guard key >= range.start, key < range.end,
                  let index = starts.lastIndex(where: { $0 <= key }) else { continue }
            buckets[index].minutes += record.duration / 60
            buckets[index].sessions += 1
            if let rating = record.rating {
                ratingSums[index] += rating
                ratingCounts[index] += 1
            }
        }
        for index in buckets.indices where ratingCounts[index] > 0 {
            buckets[index].rating = Double(ratingSums[index]) / Double(ratingCounts[index])
        }
        return buckets
    }

    /// 7-day rolling average of daily minutes (only meaningful for daily buckets).
    func rollingAverage(_ period: Period, days: Int = 7, now: Date = .now) -> [Bucket] {
        guard bucketUnit(period) == .day else { return [] }
        let today = day(of: now)
        // Stops at today: an average of days that haven't happened yet would be misleading.
        return series(period).filter { $0.start <= today }.map { bucket in
            var total = 0.0
            for offset in 0..<days {
                let day = calendar.date(byAdding: .day, value: -offset, to: bucket.start)!
                total += byDay[day]?.minutes ?? 0
            }
            return Bucket(start: bucket.start, minutes: total / Double(days), sessions: 0, rating: nil)
        }
    }

    /// Minutes focused in each hour of the day (0–23), splitting sessions that cross an hour.
    func hourOfDay(_ period: Period) -> [Double] {
        var hours = Array(repeating: 0.0, count: 24)
        for record in records(in: period) {
            var cursor = record.end.addingTimeInterval(-record.duration)
            while cursor < record.end {
                let hour = calendar.component(.hour, from: cursor)
                let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end ?? record.end
                let segmentEnd = min(hourEnd, record.end)
                hours[hour] += segmentEnd.timeIntervalSince(cursor) / 60
                cursor = segmentEnd
            }
        }
        return hours
    }

    /// Minutes per weekday, ordered from the calendar's first weekday.
    func weekdays(_ period: Period) -> [WeekdayValue] {
        var totals = Array(repeating: 0.0, count: 8)
        for record in records(in: period) {
            totals[calendar.component(.weekday, from: day(of: record.end))] += record.duration / 60
        }
        return (0..<7).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            return WeekdayValue(weekday: weekday, name: calendar.shortWeekdaySymbols[weekday - 1], minutes: totals[weekday])
        }
    }

    func projectShares(_ period: Period) -> [ProjectShare] {
        Dictionary(grouping: records(in: period), by: \.projectID)
            .map { ProjectShare(projectID: $0.key, minutes: $0.value.reduce(0) { $0 + $1.duration } / 60, sessions: $0.value.count) }
            .sorted { $0.minutes > $1.minutes }
    }

    // MARK: Calendar heatmap

    func heatmap(year: Int) -> HeatmapData {
        let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart)!
        let gridStart = calendar.dateInterval(of: .weekOfYear, for: yearStart)!.start

        // Levels are quartiles of *your* active days, so light and heavy users both get a useful spread.
        let active = byDay.filter { $0.key >= yearStart && $0.key < yearEnd && $0.value.minutes > 0 }
            .map(\.value.minutes).sorted()
        func quantile(_ fraction: Double) -> Double {
            active.isEmpty ? 0 : active[min(active.count - 1, Int(Double(active.count - 1) * fraction))]
        }
        let thresholds = [quantile(0.25), quantile(0.5), quantile(0.75)]
        func level(_ minutes: Double) -> Int {
            guard minutes > 0 else { return 0 }
            return 1 + thresholds.filter { minutes > $0 }.count
        }

        var columns: [[HeatCell?]] = []
        var months: [MonthLabel] = []
        var cursor = gridStart
        var index = 0
        while cursor < yearEnd {
            let column = index / 7
            if index % 7 == 0 { columns.append(Array(repeating: nil, count: 7)) }
            if cursor >= yearStart {
                let minutes = byDay[cursor]?.minutes ?? 0
                columns[column][index % 7] = HeatCell(day: cursor, minutes: minutes, level: level(minutes))
                if calendar.component(.day, from: cursor) == 1 { months.append(MonthLabel(column: column, date: cursor)) }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            index += 1
        }
        return HeatmapData(columns: columns, months: months)
    }

    // MARK: Streaks

    /// Consecutive counting days. Rest days never break a streak, and today doesn't break it
    /// until it's over.
    func streaks(_ rule: StreakRule = StreakRule(), today: Date = .now) -> Streaks {
        guard let first = byDay.keys.min() else { return Streaks(current: 0, longest: 0) }
        let todayKey = day(of: today)
        var cursor = first
        var run = 0
        var longest = 0
        while cursor <= todayKey {
            let minutes = byDay[cursor]?.minutes ?? 0
            if minutes > 0 && minutes >= rule.minimumMinutes {
                run += 1
                longest = max(longest, run)
            } else if rule.restWeekdays.contains(calendar.component(.weekday, from: cursor)) || cursor == todayKey {
                // A rest day, or today still in progress: neither counts nor breaks.
            } else {
                run = 0
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return Streaks(current: run, longest: longest)
    }

    // MARK: Export

    func dailyCSV() -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var lines = ["date,minutes,sessions,average_rating"]
        for key in byDay.keys.sorted() {
            let stat = byDay[key]!
            let rating = stat.ratingCount > 0 ? String(format: "%.2f", Double(stat.ratingSum) / Double(stat.ratingCount)) : ""
            lines.append("\(formatter.string(from: key)),\(Int(stat.minutes.rounded())),\(stat.sessions),\(rating)")
        }
        return lines.joined(separator: "\n")
    }
}
