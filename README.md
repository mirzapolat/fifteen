# Fifteen

A minimalist black-and-white Pomodoro timer that lives in your Mac's menu bar, and on iPhone and iPad.
One timer. One thing. Free, with no account and no ads.

## Run it

```sh
brew install xcodegen      # once
xcodegen generate          # after adding/removing files
open Fifteen.xcodeproj     # scheme "Fifteen" (Mac) or "Fifteen-iOS" (iPhone & iPad)
```

From the terminal: `xcodebuild -scheme Fifteen -derivedDataPath build/dd build`, then
`open build/dd/Build/Products/Debug/Fifteen.app --args --open` (`--open` shows the bubble right away).

The Mac app is ad-hoc signed so it runs locally. For an iPhone/iPad device, set your team in
`project.yml` (`DEVELOPMENT_TEAM`) and regenerate.

## What's in it

**Mac menu bar**
- Menu bar shows the time (the default), the icon, or both (Settings → General). The icon is a tiny ring that empties as time passes, with pause bars when paused.
- The bubble can pop open by itself when a session ends (Settings → General).
- Four app icons to choose from: the bold "15" or a minimal ring, each dark or light (Settings → Display).
- Click opens a Liquid Glass bubble that grows out of the menu bar. Right-click opens a quick menu (start/pause, skip, Insights, Settings, Quit); ⌥-click starts/pauses without opening anything.
- **Link**: focus together with friends. Start a group, share its 6-letter code, and everyone's
  timer starts, pauses, resets and takes breaks together. Ratings, notes and projects stay private.
  The relay in `server/link` runs at `wss://fifteen.mirzapolat.com` and deploys on push to main
  (`.github/workflows/deploy-link.yml`). Locally: `cd server/link && npm install && npm start`, then
  `defaults write com.mirzapolat.fifteen linkServerURL ws://localhost:8787`.
- Global shortcuts: ⌃⌥P start/pause, ⌃⌥O open the bubble.
- Hide distracting apps during focus, paused time included (each one hidden is logged as a distraction). While a session runs, blocking can be tightened but not loosened in Settings.
- Optional full-screen break curtain with a breathing circle and a break suggestion. Esc skips.
- Pauses focus when the Mac locks or sleeps and resumes when you unlock.
- Run your own Shortcuts when focus starts and ends (e.g. turn on a Focus mode, start music).
- Open at login.

**The timer (everywhere)**
- Classic Pomodoro rhythm: focus, short break, and a long break every N sessions (dots show the cycle).
- Drag around the ring to set minutes like a kitchen timer; tap the ring to start or pause.
- "What's the one thing?" intention, saved with each session.
- Add time, skip, reset, switch phase, and log distractions (the technique's interruption marks).
- Auto-start breaks and/or focus. "Keep counting" flow mode adds overtime to the session.
- At the end, Start morphs into a tinted "Take a Break" / "Back to Focus" pill.
- Synthesized sounds (no audio files): bell, singing bowl, wood block, an optional ticking clock, and white noise, rain or deep-rumble background sound.
- Notifications with "Start Next" and "5 More Minutes" actions.
- After focus, "How did it go?" with five stars right in the ring.
- Insights: overview with comparisons and charts, a year heatmap, projects, a searchable session table, goals, opt-in streaks, CSV/JSON export and backup import.
- Shortcuts / Siri: Start Focus (optional minutes), Start Break, Pause or Resume, Stop, Get Time Left.

**iPhone & iPad**
- Full-screen dial that adapts to iPad and landscape, glass pills at the bottom, one-screen onboarding.
- Live Activity on the Lock Screen and in the Dynamic Island, drawn by the system so it ticks while the app sleeps.
- Keep the screen on while running, plus haptics on start and pause.

## Layout

```
Shared/Model      TimerEngine (date-based state machine), Preferences, HistoryStore, Phase
Shared/Services   SoundEngine (AVAudioEngine synthesis), Notifier
Shared/Views      DialView, ControlPills, header/intention/today parts, History, Settings sections
Shared/Intents    App Intents + App Shortcuts
macOS/            Status item, glass panel, menu bar icon, hot keys, integrations, break curtain, Settings
iOS/              App, root view, settings, onboarding, Live Activity controller
Widgets/          Live Activity UI (WidgetKit extension)
Resources/        AppIcon.icon (Icon Composer, Liquid Glass), AccentColor
```

History lives in `~/Library/Application Support/Fifteen/history.json`. An unreadable file is set aside, never overwritten.

## Not yet

Home Screen and desktop widgets, an Apple Watch app with a ring complication, iCloud sync of history,
and website blocking (that needs a browser extension).
