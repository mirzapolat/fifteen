# Link: focus together

An accountability feature. Friends link their devices with a 6-letter code, and from then on they
share **one timer**: when anyone starts, pauses, resumes, resets or changes the minutes, everyone's
timer does the same. Settings, history, projects and intentions stay personal.

## Status (Mac, first version: built)

- **Decided:** the code lasts as long as the group. Every change to the active timer reaches
  everyone, in focus, short breaks and long breaks alike. Ratings, notes, projects and intentions stay
  private. Mac only for now.
- **Relay:** `server/link` (Node + `ws`, groups in memory, `npm test`). Dockerfile included; not
  deployed yet. The app uses `wss://fifteen.mirzapolat.com` unless
  `defaults write com.mirzapolat.fifteen linkServerURL ws://localhost:8787` points it at a local relay.
- **App:** `Shared/Link/SharedTimer.swift` (what's shared and how changes are named),
  `TimerEngine.shared` / `adopt(_:)`, `macOS/LinkSession.swift` (connection), `macOS/LinkViews.swift`
  (the Link pill and card).
- **Built differently from §2 below:** instead of the relay replaying intents, each device sends the
  timer's *resulting* state with the revision it was based on. The relay keeps the first update
  per revision. Same "first one wins", and the relay needs no timer logic at all.

## 1. The idea, refined

### Words
- **Device name**: what others see, e.g. "John's Mac". Set once; defaults to the computer's name.
- **Group**: the linked devices (2–8). One group at a time per device.
- **Code**: 6 letters that let someone join, e.g. `KQX MRT`. Read out loud or sent in a chat.
  Letters only, without I and O (they look like 1 and 0): 24⁶ ≈ 190 million codes.

### Joining
1. John clicks **Link → Start a Group**. Fifteen shows a code.
2. Mira clicks **Link → Join**, types the code, and is in. Both see "John's Mac · Mira's MacBook".
3. The code works for as long as the group exists, so a third friend can join later.
   Anyone in the group can show it again.
4. **Leave** takes you out. Your timer keeps running on its own from where it was.
   The group ends when the last person leaves, or after 12 hours with nobody connected.

### What is shared: only the timer
| Shared (the group's) | Personal (each device's own) |
|---|---|
| Phase: focus, short break, long break | All settings: lengths, sounds, blocker, goals |
| Running / paused / idle / finished | History: everyone records their own sessions |
| Length of the session that's set or running | Project and "one thing" intention |
| When it ends (or how much is left while paused) | Cycle count toward the long break |
| Mode of the current session (Pomodoro or Flowtime) | Rating and notes after a session |

### The rules
- **Start, pause, resume, reset, skip, switch phase, add time**: anyone can do it, and it happens
  for everyone right away.
- **Changing the minutes** (dragging the ring, the length menu, a preset) while idle sets the group's
  next session length. It doesn't touch anyone's settings.
- **When focus ends**, everyone sees "How did it go?" and a "Take a Break" pill.
  **The first person to start the break decides it**: their kind of break (short or long, from
  their own rhythm) and their length apply to everyone. Starting the next focus works the same way.
- **Auto-start** counts as "being first": if someone has *Start breaks automatically* on, their
  device starts the break for the group the moment focus ends.
- **Finish early** (and Flowtime's Finish) ends the session for everyone. Everyone's history records
  the time actually spent.
- **Keep counting** (overtime) is shown only to people who turned it on. Overtime ends when
  anyone starts the break.
- **Pause when the Mac locks** is switched off while linked, because it would pause everyone
  whenever one person walks away. (Settings says so.)
- **App blocker, Do Not Disturb and the break curtain** stay personal. They follow the shared timer,
  so a friend's reset releases your blocked apps too. That's the accountability.

### Making it feel like accountability
- **Who did it**: every change shows briefly under the ring: "Mira paused", "John added 5 min".
- **Who's here**: small initials at the top of the bubble, with a dot for online or away.
  "Away" means the device is asleep or offline.
- **Afterwards**: sessions record who you focused with, and Insights can show it later
  ("12 sessions with Mira this month").
- **Later, optional**: a "pause needs a yes" mode, where a pause is a request the others can accept.

## 2. How to build it

### Options for moving the state between devices
| Option | Works across the internet | Real-time | Code join | Notes |
|---|---|---|---|---|
| CloudKit share | yes | no (push, seconds) | awkward (shares are links) | Needs iCloud on every device; latency and ordering are poor for a live timer |
| SharePlay (GroupActivities) | yes | yes | no | Needs an active FaceTime call or Messages session |
| Multipeer / Bonjour | local network only | yes | possible | Friends are rarely on the same Wi-Fi |
| Hosted realtime (Firebase, Supabase, PartyKit) | yes | yes | yes | Fast to build; a third party and its pricing |
| **Own tiny relay server** | yes | yes | yes | Full control, no accounts. Fits the existing self-hosted VPS setup (Docker + Traefik) |

**Recommendation: a small WebSocket relay that we run ourselves, with the server in charge of the
group's timer.** It only holds a few hundred bytes per group in memory: no accounts and no
database. Cloudflare Durable Objects is a good no-ops alternative (one object per group).

### The server decides, the clients follow
- Clients send **intents**, not states: `start`, `pause`, `resume`, `reset`, `setMinutes(25)`,
  `extend(300)`, `finishEarly`, `startPhase(.shortBreak, minutes: 7)`, `skip`.
- The server applies each intent to the group's timer **in the order it arrives**, stamps it with
  its own clock, bumps a `revision`, and sends the new state plus "who did what" to everyone.
- An intent that no longer fits is dropped, and the sender simply gets the current state.
  This is how "the first one wins" works: the second `startPhase` arrives when the break is
  already running, so it is ignored. The same goes for a second `pause` or a `setMinutes` while
  running. That's why intents are explicit (`pause`, `resume`), never a toggle: a toggle that
  arrives late would flip the timer back.
- The server never ticks. A running timer is just `endsAt`; everyone works out the finish locally,
  and the server treats `running && endsAt < now` as finished.

```swift
/// Lives in a small Swift package used by both the app and the server, so the rules can't drift.
struct GroupTimer: Codable, Equatable {
    var phase: Phase
    var mode: TimerMode
    var state: RunState
    var total: TimeInterval
    var endsAt: Date?               // server clock, while running
    var pausedRemaining: TimeInterval?
    var sessionID: UUID              // new for each started session
    var revision: Int
}

enum Intent: Codable {
    case start, pause, resume, reset, skip, finishEarly
    case setMinutes(Int)
    case extend(TimeInterval)
    case startPhase(Phase, minutes: Int)
}

/// Pure and easy to test: nil means "doesn't apply right now, drop it".
func reduce(_ timer: GroupTimer, _ intent: Intent, now: Date) -> GroupTimer?
```

### Wire protocol (JSON over WebSocket, TLS)
```text
→ hello      { protocol: 1, deviceName, memberToken? }
← welcome    { serverTime }                      // clock sync, see below
→ create     {}                                  ← joined { groupID, code, memberToken, timer, members }
→ join       { code }                            ← joined { … }  |  error { "noSuchCode" }
→ intent     { intent, basedOn: revision }
← state      { timer, by: "Mira's MacBook", action: "paused" }
← members    [{ id, name, online }]
→ leave      {}
```
- **Clock sync**: on connect, the client pings a few times and keeps
  `offset = serverTime − (sent + received) / 2`. It converts `endsAt` to local time with that offset,
  so everyone's ring hits zero at the same moment even if their clocks are a few seconds apart.
- **Reconnecting**: the `memberToken` (random, kept in the Keychain) puts a device back in its group
  after sleep or a network change. It then gets the latest state and catches up. The timer is
  date-based, so a missed pause or start just snaps into place.
- **Server restart**: groups live in memory. If one vanishes, the first client to reconnect
  re-creates it from its last known state with the same code.

### Inside Fifteen
- **`Shared/Link/LinkSession.swift`** (`@Observable`): connection, device name, group, members,
  the last "who did what", and clock offset.
- **`TimerEngine` gets one seam.** While linked, its public actions (`start`, `pause`, `setIdleMinutes`,
  `advance`, …) **apply locally right away** (so the click feels instant) **and send the intent**.
  When the server's state comes back, `engine.apply(remote:)` adopts it. Usually that changes
  nothing; if someone else won the race, it corrects the timer.
  - `apply(remote:)` emits the usual `TimerEvent`s, so the app blocker, Do Not Disturb, sounds,
    notifications, the break curtain and the Live Activity all keep working untouched.
  - `complete()` stays local: each device writes its own `FocusRecord`, plus a new
    `linkedWith: [String]` field (schema v3) for the "focused with" insights.
  - Hot keys, the menu bar menu and Shortcuts already go through the engine, so they're covered.
- **`advance(autoStart:)`** sends `startPhase(nextPhase, minutes: myLength)`: "your break, your length".
- **UI**
  - Link pill → popover: name field, **Start a Group** / **Join** (6 boxes, auto-uppercase,
    paste-friendly). When linked: the code, the members, **Leave**.
  - Linked: the pill shows initials ("JM"); the ring's subtitle briefly shows "Mira paused".
  - Menu bar: a small link mark next to the time, so you know you're in a group.

### Edge cases worth deciding up front
- **Two people press at the same time**: the server's order decides; the other press is dropped.
- **Someone is offline when the session ends**: their device finishes and records locally anyway.
  If, on reconnecting, it turns out the group had been reset first, the record stays (they did focus).
- **Different Fifteen versions**: `protocol` in `hello`; refuse politely when they're incompatible.
- **iPhone in the background**: the socket dies. v1 catches up when the app opens. Later, the server
  can send ActivityKit push updates so the Live Activity follows the group while the phone sleeps.
- **Abuse**: rate-limit joins per IP (stops code guessing), at most 8 members, codes die with the group.
- **Privacy**: only device names and timer state go to the server, in memory, over TLS. No account,
  no history, no intentions. Worth saying exactly that in the Link popover.

## 3. Steps
1. **Rules first**: the `GroupTimer` + `reduce` package with unit tests for every race above.
2. **Server**: a WebSocket relay (Swift on Hummingbird, sharing the package), with groups in memory,
   Dockerised for the VPS.
3. **Mac ↔ Mac**: `LinkSession`, the engine seam, the Link popover, members and "who did what".
4. **Polish**: the link mark in the menu bar, the "focused with" field, and Insights.
5. **iPhone & iPad**: same client; Live Activity push updates.

## 4. Open questions
1. Hosting: self-hosted on the VPS (Dockerfile ready), or Cloudflare Durable Objects?
2. Should the "one thing" intention ever be shareable, opt-in? (Private for now.)

Answered: finish early and skip apply to everyone (every timer action does); codes last as long as
the group; Mac only first.
