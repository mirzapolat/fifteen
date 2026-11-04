# Fifteen

**One timer. One thing.**

Fifteen is a calm, black-and-white Pomodoro timer for your Mac, iPhone and iPad.
It stays out of your way until you need it, then helps you do one thing well:
focus, rest, repeat.

Free. No account. No ads. Your history never leaves your device.

---

## Why Fifteen

Most focus apps want your attention. Fifteen gives it back.

- **Nothing to set up.** Open it, tap the ring, and you're focusing. The classic rhythm (25 minutes
  of focus, a 5-minute break, a longer one every four rounds) is ready from the first second.
- **Nothing to distract you.** Black and white, Liquid Glass, one ring. No streak guilt, no badges, no
  feed. Streaks exist only if you turn them on.
- **Nothing to sign up for.** No account, no tracking, no ads. Sessions, notes and projects stay on
  your device. Export them whenever you like.

## Focus together with Link

Studying with a friend? Working with your team across town?
**Start a group, share the 6-letter code, and you're on one timer.** When anyone starts, pauses,
adds time or takes a break, it happens for everyone, Mac and iPhone alike. A quiet line under the
ring says who did what ("Mira paused").

Only the timer is shared. Your intentions, notes, ratings and projects stay yours.

## On your Mac: right in the menu bar

- **Always one glance away.** The menu bar shows the time, a tiny ring that empties as you go, or both.
- **A Liquid Glass bubble** grows out of the menu bar when you click. Right-click for a quick menu;
  ⌥-click to start or pause without opening anything.
- **Keyboard first.** ⌃⌥P starts or pauses from any app, and ⌃⌥O opens Fifteen.
- **Hide the noise.** Fifteen can hide (or quit) distracting apps while you focus, and logs every
  attempt as a distraction. Mid-session, you can tighten the rules but not loosen them.
- **Breaks that actually happen.** An optional full-screen curtain with a slow breathing circle and
  a suggestion for what to do. Esc skips, if you must.
- **Do Not Disturb while you focus.** After a one-time setup, notifications go quiet when focus
  starts and come back for your break.
- **Your Shortcuts, your rituals.** Start a playlist when focus begins, set your status when it ends.
- **It knows when you've stepped away.** Focus pauses when your Mac locks or sleeps and picks up when you return.
- **Make it yours.** Four app icons, and a menu bar that shows exactly what you want.

## On iPhone & iPad: a timer that fills the screen

- **The ring is the whole interface.** Drag around it to set the minutes like a kitchen timer, and tap it to start.
- **Always in reach.** The countdown lives on your Lock Screen and in the Dynamic Island, with
  **Pause, Resume and Reset right there.** No need to unlock or open the app.
- **Four simple tabs:** Link, Timer, Analytics and Settings, on a Liquid Glass tab bar. On the other
  tabs, your running session rides along just above it.
- **Made for the desk.** Keep the screen on while the timer runs, with a gentle tap of haptics when you start and pause.
- Built for iPad and landscape, too.

## Everywhere: the details that matter

- **"What's the one thing?"** Name your intention and file it under a project before you begin.
- **"How did it go?"** After each session, rate your focus with five stars and jot down what you got done.
- **Flow mode.** In the zone? Fifteen keeps counting instead of cutting you off, and adds the extra minutes to your session.
- **Flowtime.** Prefer no fixed length? Count up, stop when your focus fades, and get a break sized to the session.
- **Presets** for work, study and reading, each with its own rhythm.
- **Sounds made from scratch:** a bell, a singing bowl, a wood block, an optional ticking clock, and
  white noise, rain or a deep rumble to settle into.
- **Smart notifications** with "Start Next" and "5 More Minutes" right in the banner.
- **Siri and Shortcuts:** start focus or a break, pause, stop, or ask how much time is left.

## Analytics that tell a story

See where your focus really goes, by week, month, year or all time:
your focus time against last period, when in the day you work best, your strongest weekdays,
a calendar heatmap of the whole year, how your time splits across projects, and how your focus
quality changes. Set daily and weekly goals, opt into streaks with rest days, and export everything
as CSV or a full backup whenever you like.

## Get Fifteen

- **Mac:** a free, notarized download for macOS 26 or later, from
  [GitHub Releases](https://github.com/mirzapolat/fifteen/releases/latest). It keeps itself up to date.
- **iPhone & iPad:** coming soon (iOS 26 or later).

---

## For developers

Fifteen is native Swift and SwiftUI, with one codebase for macOS, iOS and iPadOS.

### Run it

```sh
brew install xcodegen      # once
xcodegen generate          # after adding or removing files
open Fifteen.xcodeproj     # scheme "Fifteen" (Mac) or "Fifteen-iOS" (iPhone & iPad)
```

From the terminal: `xcodebuild -scheme Fifteen -derivedDataPath build/dd build`, then
`open build/dd/Build/Products/Debug/Fifteen.app --args --open` (`--open` shows the bubble right away).
On iOS, `--tab link|analytics|settings`, `--start` and `--demo` help with screenshots.

Debug builds of the Mac app are ad-hoc signed so they run locally. Release builds and iPhone/iPad
device builds use the team in `project.yml` (`DEVELOPMENT_TEAM`).

### Release the Mac app

The Mac app ships as a notarized download (Developer ID), outside the Mac App Store.

Once per Mac:
1. A **Developer ID Application** certificate in the keychain (Xcode → Settings → Accounts → Manage
   Certificates, or developer.apple.com → Certificates).
2. Notary credentials in the keychain (asks for an app-specific password from account.apple.com):
   `xcrun notarytool store-credentials fifteen-notary --apple-id <your Apple ID> --team-id 56746T8S3D`

Each release:
1. Bump `MARKETING_VERSION` **and** `CURRENT_PROJECT_VERSION` in `project.yml`. The build number must
   go up every time, or Sparkle won't offer the update.
2. Optionally write `release-notes/<version>.html`. It's shown in the update window and on GitHub.
3. Run `scripts/release-mac.sh --publish`.

The script archives the app, exports it with Developer ID, builds `build/release/Fifteen-<version>.dmg`,
notarizes and staples it, checks it with Gatekeeper, signs it for Sparkle and writes `appcast.xml`.
With `--publish` it creates the GitHub release `v<version>`; installed copies offer the update within
a day. Without `--publish` it prints the command instead, and `--skip-notarize` stops after the signed DMG.
Updates use Sparkle; see [`docs/SPARKLE_PLAN.md`](docs/SPARKLE_PLAN.md), including how to back up the update key.

### Link relay

The relay in `server/link` runs at `wss://fifteen.mirzapolat.com` and deploys on every push to main
(`.github/workflows/deploy-link.yml`). To run it locally: `cd server/link && npm install && npm start`,
then `defaults write com.mirzapolat.fifteen linkServerURL ws://localhost:8787`.

### Layout

```
Shared/Model         TimerEngine (date-based state machine), Preferences, HistoryStore, Phase
Shared/Analytics     Everything Insights computes
Shared/Link          LinkSession (the relay client), the shared timer, avatars
Shared/Services      SoundEngine (AVAudioEngine synthesis), Notifier, Haptics
Shared/Views         Dial, header, controls, Insights, Settings sections
Shared/Intents       App Intents + App Shortcuts
Shared/LiveActivity  Live Activity attributes and its Pause/Reset buttons
macOS/               Menu bar item, glass bubble, Link card, hot keys, app blocker, break curtain, Settings
iOS/                 Tabs, timer controls, Link, Settings, onboarding, Live Activity controller
Widgets/             Lock Screen and Dynamic Island (WidgetKit extension)
Resources/           AppIcon.icon (Icon Composer, Liquid Glass), AccentColor
scripts/             release-mac.sh (notarized DMG, Sparkle appcast, GitHub release)
release-notes/       <version>.html, shown in the update window
server/link          The Link relay (Node, Docker)
website/             getfifteen.de (React + Vite, deploys on push to main via deploy-website.yml)
```

History lives in `~/Library/Application Support/Fifteen/history.json`. An unreadable file is set
aside, never overwritten.

### Not yet

Home Screen and desktop widgets, an Apple Watch app, iCloud sync of history, and website blocking
(that needs a browser extension).
