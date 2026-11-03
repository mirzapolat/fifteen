# Plan: From History to Insights

Turn Fifteen's simple History window into a proper analysis dashboard, called **Insights**, without
breaking what makes the app good: one timer, black and white, quiet.

Status: proposal · Written 3 November 2026

---

## 1. Where we are today

| Area | Today |
|---|---|
| Data | `history.json`: an array of `FocusRecord` with `id, start, end, duration, intention, distractions, note?, rating?` |
| Aggregates | Computed on the fly in `HistoryStore`: today's count and time, last 7 days, grouped by day |
| UI | One `List`: three stat tiles, a 7-day bar chart, sessions grouped by day |
| Goals | Daily session goal (can be off), shown as a small bar in the popup |
| Export | Sessions as CSV |
| Not there | Monthly or yearly views, heatmap, streaks, weekly goal, projects, JSON export or import, tests |

## 2. Principles

1. **Insight, not pressure.** `DESIGN.md` says *"History instead of streaks; no badges or streaks."*
   Streaks and goals are therefore **opt-in, off by default, and forgiving** (see §6). Nothing in the
   popup nags you; analysis lives in its own window and you open it when you want to.
2. **Black and white.** Charts use shades of the ink colour (100 / 70 / 45 / 25 / 10 %), plus patterns or
   labels where shades aren't enough. The accent colour is the only highlight.
3. **One data source, pure maths.** Every number comes from one tested `Analytics` layer, never
   computed separately inside views.
4. **Never lose data.** The format is versioned, migrations are automatic, backups are taken before a
   migration, and export/import works both ways.
5. **Native.** Swift Charts, `NavigationSplitView`, `Table` on the Mac, the system share sheet and save panels.

## 3. Data model changes

### 3.1 Schema v2

```swift
struct HistoryFile: Codable {            // history.json v2
    var schemaVersion = 2
    var sessions: [FocusRecord]
    var projects: [Project]
}

struct FocusRecord: Codable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    var duration: TimeInterval           // focused time (excludes pauses)
    var intention: String
    var distractions: Int
    var note: String?
    var rating: Int?                     // 1–5
    // new
    var projectID: Project.ID?
    var mode: TimerMode                  // pomodoro / flowtime
    var plannedDuration: TimeInterval?   // nil for flowtime
    var endedEarly: Bool                 // "Finish Early"
    var pausedTime: TimeInterval         // total time paused
}

struct Project: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var symbol: String                   // SF Symbol, e.g. "book", "hammer", "pencil"
    var shade: Int                       // 0–4, grayscale slot used in charts
    var weeklyGoalMinutes: Int?          // optional per-project target
    var isArchived: Bool
    var created: Date
}
```

- **Migration v1 → v2:** detect a bare array, copy the file to `history.v1.backup.json`, wrap it in
  `HistoryFile`, and set new fields to defaults (`projectID = nil`, `mode = .pomodoro`, …).
- **Engine:** capture `pausedTime`, `plannedDuration`, `endedEarly`, `mode` and `projectID` when a
  session completes (`TimerEngine.complete()`).
- **Breaks:** optionally log break sessions too (`BreakRecord`), so we can show a focus-to-rest balance.
  Off by default, and kept in a separate array so focus statistics stay simple.

### 3.2 Storage choice

Keep **JSON plus in-memory indexes** for now. Even 10 years of heavy use (about 30k sessions, around 6 MB)
loads in milliseconds.
Revisit **SwiftData + CloudKit** only if iCloud sync becomes a goal (§10). The `Analytics` layer
works on plain arrays, so swapping storage later won't touch the UI.

## 4. Analytics layer

A new `Shared/Analytics/` module of pure, `Sendable`, unit-tested functions. Views only read its output.

```swift
struct AnalyticsInput {
    var sessions: [FocusRecord]
    var projects: [Project]
    var calendar: Calendar               // user's calendar and time zone
    var dayStartHour: Int                // "new day starts at" (default 04:00)
}

enum DateRange { case day(Date), week(Date), month(Date), year(Int), custom(ClosedRange<Date>), all }

struct Summary {                         // for KPI tiles
    var focusTime, averageSession, longestSession: TimeInterval
    var sessions: Int
    var activeDays: Int
    var averageRating: Double?
    var distractionsPerHour: Double
    var completionRate: Double           // completed vs ended early
    var change: Summary.Delta?           // vs the previous period of the same length
}
```

| Function | Output | Used by |
|---|---|---|
| `summary(range)` | `Summary` with change vs previous period | KPI tiles |
| `dailyTotals(range)` | `[DayTotal(day, minutes, sessions)]` | bar charts, heatmap |
| `weeklyTotals(range)` / `monthlyTotals(range)` | bucketed totals | month and year charts |
| `rollingAverage(days: 7, range)` | line series | trend line |
| `hourOfDay(range)` | 24 buckets | "When you focus best" |
| `weekdayProfile(range)` | 7 buckets | "Best days" |
| `projectBreakdown(range)` | per project: minutes, share, sessions, trend | Projects |
| `ratingTrend(range)` | average rating per day or week | Quality chart |
| `heatmap(year)` | 53×7 grid of `HeatCell(day, minutes, level 0–4)` | Calendar |
| `streaks(rule)` | current, longest, longest range | Streak tile |
| `goalProgress(range)` | daily and weekly target vs actual | Goal rings |

**Rules worth writing down (and testing):**
- A session belongs to the "day" of its **end time**, shifted by `dayStartHour`, which is the existing behaviour.
- A session that crosses the day boundary counts entirely on its end day (simple, predictable).
- Weeks start on the user's calendar `firstWeekday`.
- Heatmap levels: quantiles of the user's own non-zero days (so light and heavy users both get a
  useful spread), capped so one marathon day doesn't wash everything else out.
- Results are cached per `(range, recordsVersion)` and recomputed when `HistoryStore` changes.

## 5. Dashboard design

### 5.1 Structure

Mac and iPad use `NavigationSplitView`; iPhone uses a scrolling Overview with push navigation to the other sections.

```
┌──────────────┬────────────────────────────────────────────────┐
│ Overview     │  [ Day | Week | Month | Year | All ]  ‹  ›  ⤓    │
│ Calendar     │                                                │
│ Projects     │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐  │
│ Sessions     │  │ 12h  │ │  29  │ │ 25m  │ │ 4.1  │ │ 6 d  │  │
│              │  │ focus│ │ sess.│ │ avg  │ │ focus│ │streak│  │
│              │  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘  │
│              │  ▁▃▅▇▅▂▁  focus time per day   ── 7-day avg     │
│              │  goal ring · hour-of-day · project share       │
└──────────────┴────────────────────────────────────────────────┘
```

The toolbar holds the range picker, previous/next period, and Export. The selected range is remembered
per window.

### 5.2 Sections

**Overview**
- KPI tiles: Focus time, Sessions, Average session, Focus rating, Goal progress, plus Streak (only if
  enabled). Each shows a quiet change vs the previous period ("+18% vs last week").
- **Focus time chart** (Swift Charts `BarMark`): per day for Week and Month, per week for Year, per month for All.
  Includes a `RuleMark` for the daily goal and a `LineMark` for the 7-day average. Hover or tap shows exact values.
- **When you focus best:** a 24-hour histogram plus a weekday profile.
- **Goal:** today's ring and this week's ring (daily and weekly targets).
- **Quality:** average rating over time, and distractions per hour.

**Calendar**
- A GitHub-style **heatmap** for a year: 53 columns × 7 rows of rounded squares in five ink levels,
  with month labels, a weekday legend and a "Less ▢▢▢▢▢ More" key. You can switch between years.
- Hover or tap a day for a popover (focus time, sessions, projects, notes); click to open that day in Sessions.
- Below it: a month grid with a small ring per day (goal progress), for a closer look.

**Projects**
- A list with symbol, total time, share and trend sparkline. The detail view shows the same charts
  filtered to that project, plus its weekly goal.
- Share of time as a horizontal stacked bar in grayscale shades (more legible than a donut in black and white).
- An "Unassigned" bucket so nothing disappears.

**Sessions**
- On the Mac, a `Table` with sortable columns: date, time, duration, project, intention, rating,
  distractions, note. On iPhone, a list.
- Search across intention and notes; filters for project, rating, has note, ended early, mode.
- Edit a past session (project, intention, note, rating) and delete with undo.

### 5.3 Visual rules
- Shades of ink only; the selected or current bar is 100 %, others 35 %. Gridlines are 8 %.
- Monospaced digits everywhere; one body style, with headings as the only exception.
- Liquid Glass only for floating controls (range picker, export), never behind charts.
- Empty states: "No sessions this week yet," with a button to start one.

## 6. Goals and streaks (opt-in)

- **Goals:** keep the daily session goal and add **daily minutes**, **weekly minutes** and optional
  **per-project weekly** targets. All are off by default.
- **Streaks:** off by default (to stay true to `DESIGN.md`). When on, you choose what counts:
  - *A day with at least one session* (default) or *a day that meets the daily goal*.
  - **Rest days:** pick weekdays that don't break a streak (e.g. weekends).
  - **Grace:** one missed day per week doesn't break it (optional).
  - Shown as a number and a "best" in Insights only, never in the popup or menu bar, and no badges.

## 7. Projects in the timer

- In the popup, under the intention field, add a small **project chip** (symbol and name) that opens a
  menu: recent projects, "New Project…", "None". Its last value is remembered.
- Optional: suggest a project from the intention text, based on past sessions with the same intention.
- Settings → Projects: create, rename, choose a symbol and shade, archive, set weekly goals, merge two projects.
- Shortcuts: give "Start Focus" an optional *Project* parameter (an `AppEntity`), so Siri can start a
  "Thesis" session.

## 8. Export and import

| Format | Contents |
|---|---|
| **CSV, sessions** | one row per session, all fields, ISO 8601 dates, project name |
| **CSV, daily summary** | date, focus minutes, sessions, average rating, goal met |
| **JSON, full backup** | `HistoryFile` v2 (sessions + projects) plus app version and export date |

- Choose a date range and a project filter before exporting; the Mac uses `NSSavePanel`, iOS uses `ShareLink`.
- **Import JSON:** merge by `id` (skip duplicates), with a preview ("142 new sessions, 3 projects").
- Optional **automatic weekly backup** to a folder you choose (Mac).

## 9. Delivery plan

| Phase | Scope | Done when | Effort |
|---|---|---|---|
| **1. Foundation** | Schema v2 and migration with backup; new `FocusRecord` fields captured by the engine; `Project` model; `Analytics` module; a **new unit-test target** | Tests green for day boundaries, DST, time zones, `dayStartHour`, week starts | 2–3 days |
| **2. Overview** | Insights window (split view), range picker and navigation, KPI tiles with change, focus-time chart with average and goal line | Week/Month/Year/All all render from `Analytics` | 2–3 days |
| **3. Calendar** | Heatmap (year), day popover and drill-down, month grid | Smooth with 5 years of data | 1–2 days |
| **4. Projects** | Project chip in popup and iOS, Projects settings, Projects section, project filter everywhere, Shortcuts parameter | Every chart can be filtered by project | 2–3 days |
| **5. Goals & streaks** | Daily and weekly minute goals, goal rings, opt-in streaks with rest days and grace | All off by default; nothing appears unless enabled | 1–2 days |
| **6. Sessions** | `Table` with search, filters, editing, undo | Edit a past session's project and rating | 1–2 days |
| **7. Export/import** | CSV (sessions and daily), JSON backup and import with merge preview | Round trip: export → delete → import → identical | 1 day |
| **8. Polish** | Accessibility (VoiceOver chart descriptions via `AXChartDescriptor`, audio graphs), Dynamic Type, dark mode, empty states, performance pass | Instruments: open Insights with 30k sessions in under 150 ms | 1–2 days |

Total is roughly **2–3 weeks** of focused work. Each phase ships on its own.

## 10. Later
- **Widgets:** today's ring, this week's bars, a small heatmap (needs an App Group for shared data).
- **iCloud sync** between Mac, iPhone and iPad (SwiftData + CloudKit, or a CloudKit-backed JSON document).
- **Weekly recap** notification (opt-in): "You focused 9h 20m this week, mostly on Thesis."
- **Apple Watch** complication with today's ring.

## 11. Testing
- Unit tests for every `Analytics` function, with fixed calendars (Gregorian, ISO 8601, first weekday
  Sunday vs Monday), the DST changeover weeks in March and October, a `dayStartHour` of 0 and 4, and
  sessions that cross midnight.
- Migration tests: a v1 file becomes v2 with a backup; a corrupt file is set aside and never overwritten.
- Performance: a generated history of 30k sessions; a budget for opening the dashboard and switching ranges.
- Screenshot checks of each section in light and dark mode at Mac, iPad and iPhone sizes.

## 12. Decisions needed

1. **Streaks:** add them opt-in as above, or leave them out entirely to stay true to `DESIGN.md`?
2. **Projects vs tags:** one project per session (simpler, cleaner charts) or several tags?
3. **Flowtime and overtime:** count all focused time (proposed), or cap at the planned length?
4. **Breaks:** record break sessions for a focus-to-rest balance, or keep stats focus-only?
5. **Sync:** is iCloud sync planned soon? If yes, move to SwiftData in Phase 1 instead of later.
6. **Name:** "Insights", "Stats", or keep "History"?
