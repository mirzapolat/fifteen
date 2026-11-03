import Foundation
import Testing

/// Analytics is pure, so these tests pin down the rules everything in Insights relies on:
/// day boundaries, buckets across DST, heatmap levels, hour splitting, streaks and comparisons.
struct AnalyticsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2 // Monday
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func session(ending end: Date, minutes: Double, project: UUID? = nil, rating: Int? = nil, distractions: Int = 0) -> FocusRecord {
        FocusRecord(start: end.addingTimeInterval(-minutes * 60), end: end, duration: minutes * 60,
                    intention: "", distractions: distractions, rating: rating, projectID: project)
    }

    func analytics(_ records: [FocusRecord], hour: Int = 4) -> Analytics {
        Analytics(records: records, calendar: calendar, dayStartHour: hour)
    }

    // MARK: Day boundaries

    @Test func lateNightCountsAsThePreviousDay() {
        let a = analytics([session(ending: date(2026, 11, 4, 2), minutes: 25)])
        #expect(a.day(of: date(2026, 11, 4, 2)) == date(2026, 11, 3, 0))
        #expect(a.minutes(onDayOf: date(2026, 11, 3, 15)) == 25)
        #expect(a.minutes(onDayOf: date(2026, 11, 4, 15)) == 0)
    }

    @Test func midnightBoundaryWhenDayStartsAtZero() {
        let a = analytics([session(ending: date(2026, 11, 4, 0, 30), minutes: 25)], hour: 0)
        #expect(a.minutes(onDayOf: date(2026, 11, 4, 15)) == 25)
    }

    // MARK: Buckets

    @Test func weekHasSevenDailyBucketsStartingMonday() {
        let a = analytics([session(ending: date(2026, 11, 4), minutes: 50)])
        let series = a.series(Period(kind: .week, anchor: date(2026, 11, 4)))
        #expect(series.count == 7)
        #expect(series.first?.start == date(2026, 11, 2, 0))
        #expect(series.reduce(0) { $0 + $1.minutes } == 50)
    }

    @Test func monthBucketsMatchDaysInMonth() {
        #expect(analytics([]).series(Period(kind: .month, anchor: date(2026, 2, 10))).count == 28)
        #expect(analytics([]).series(Period(kind: .month, anchor: date(2028, 2, 10))).count == 29)
    }

    @Test func daylightSavingWeekStillHasSevenDays() {
        // Clocks go back in Berlin on Sunday 25 October 2026.
        let series = analytics([]).series(Period(kind: .week, anchor: date(2026, 10, 22)))
        #expect(series.count == 7)
        #expect(Set(series.map { calendar.component(.day, from: $0.start) }).count == 7)
    }

    @Test func yearUsesMonthlyBuckets() {
        let a = analytics([session(ending: date(2026, 3, 10), minutes: 30), session(ending: date(2026, 3, 20), minutes: 30)])
        let series = a.series(Period(kind: .year, anchor: date(2026, 6, 1)))
        #expect(series.count == 12)
        #expect(series[2].minutes == 60)
        #expect(series[2].sessions == 2)
    }

    // MARK: Summary

    @Test func summaryComparesWithPreviousPeriod() {
        let a = analytics([
            session(ending: date(2026, 11, 3), minutes: 60, rating: 4, distractions: 2),
            session(ending: date(2026, 10, 27), minutes: 30),
        ])
        let week = Period(kind: .week, anchor: date(2026, 11, 3))
        let summary = a.summary(week)
        #expect(summary.focus == 3600)
        #expect(summary.sessions == 1)
        #expect(summary.averageRating == 4)
        #expect(summary.distractionsPerHour == 2)
        #expect(a.previousSummary(week)?.focus == 1800)
    }

    // MARK: Hours, weekdays, projects

    @Test func hourOfDaySplitsSessionsAcrossHours() {
        let hours = analytics([session(ending: date(2026, 11, 3, 10, 20), minutes: 40)])
            .hourOfDay(Period(kind: .week, anchor: date(2026, 11, 3)))
        #expect(abs(hours[9] - 20) < 0.001)
        #expect(abs(hours[10] - 20) < 0.001)
    }

    @Test func weekdaysStartOnTheCalendarsFirstWeekday() {
        let days = analytics([]).weekdays(Period(kind: .week, anchor: date(2026, 11, 3)))
        #expect(days.first?.weekday == 2)
        #expect(days.count == 7)
    }

    @Test func projectSharesAreSortedLargestFirst() {
        let thesis = UUID(), reading = UUID()
        let shares = analytics([
            session(ending: date(2026, 11, 3, 10), minutes: 30, project: reading),
            session(ending: date(2026, 11, 3, 12), minutes: 90, project: thesis),
            session(ending: date(2026, 11, 3, 14), minutes: 15),
        ]).projectShares(Period(kind: .week, anchor: date(2026, 11, 3)))
        #expect(shares.map(\.projectID) == [thesis, reading, nil])
    }

    // MARK: Heatmap

    @Test func heatmapLevelsFollowYourOwnQuartiles() {
        let a = analytics([
            session(ending: date(2026, 1, 5), minutes: 10),
            session(ending: date(2026, 1, 6), minutes: 20),
            session(ending: date(2026, 1, 7), minutes: 30),
            session(ending: date(2026, 1, 8), minutes: 40),
        ])
        let cells = a.heatmap(year: 2026).columns.flatMap { $0 }.compactMap { $0 }
        func level(_ day: Int) -> Int? { cells.first { calendar.component(.day, from: $0.day) == day && calendar.component(.month, from: $0.day) == 1 }?.level }
        #expect(level(5) == 1)
        #expect(level(6) == 2)
        #expect(level(7) == 3)
        #expect(level(8) == 4)
        #expect(level(9) == 0)
        #expect(cells.count == 365)
    }

    @Test func heatmapMarksTwelveMonths() {
        #expect(analytics([]).heatmap(year: 2026).months.count == 12)
    }

    // MARK: Streaks

    @Test func streakCountsConsecutiveDays() {
        let a = analytics([3, 4, 5].map { session(ending: date(2026, 11, $0), minutes: 25) })
        #expect(a.streaks(today: date(2026, 11, 5, 18)) == Streaks(current: 3, longest: 3))
    }

    @Test func todayInProgressDoesNotBreakTheStreak() {
        let a = analytics([3, 4].map { session(ending: date(2026, 11, $0), minutes: 25) })
        #expect(a.streaks(today: date(2026, 11, 5, 9)).current == 2)
    }

    @Test func missedDayBreaksTheStreak() {
        let a = analytics([1, 2, 4].map { session(ending: date(2026, 11, $0), minutes: 25) })
        #expect(a.streaks(today: date(2026, 11, 4, 18)) == Streaks(current: 1, longest: 2))
    }

    @Test func restDaysNeverBreakAStreak() {
        // Fri 6, (Sat 7, Sun 8 rest), Mon 9, Tue 10.
        let a = analytics([6, 9, 10].map { session(ending: date(2026, 11, $0), minutes: 25) })
        let rule = StreakRule(restWeekdays: [1, 7])
        #expect(a.streaks(rule, today: date(2026, 11, 10, 18)).current == 3)
        #expect(a.streaks(today: date(2026, 11, 10, 18)).current == 2)
    }

    @Test func goalBasedStreakNeedsEnoughMinutes() {
        let a = analytics([
            session(ending: date(2026, 11, 3), minutes: 120),
            session(ending: date(2026, 11, 4), minutes: 30),
        ])
        let rule = StreakRule(minimumMinutes: 60)
        // While the 4th is still "today", falling short doesn't break the streak yet…
        #expect(a.streaks(rule, today: date(2026, 11, 4, 18)).current == 1)
        // …but once it's over, 30 minutes against a 60-minute goal does.
        #expect(a.streaks(rule, today: date(2026, 11, 5, 18)) == Streaks(current: 0, longest: 1))
    }

    // MARK: Export

    @Test func dailyCSVHasOneRowPerActiveDay() {
        let csv = analytics([
            session(ending: date(2026, 11, 3, 10), minutes: 25, rating: 4),
            session(ending: date(2026, 11, 3, 15), minutes: 25, rating: 2),
        ]).dailyCSV()
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[1] == "2026-11-03,50,2,3.00")
    }
}
