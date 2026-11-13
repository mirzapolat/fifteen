# Developing Fifteen

Fifteen is native Swift and SwiftUI, with one codebase for macOS, iOS and iPadOS.

## Run it

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

## Release the Mac app

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
Updates use Sparkle. Back up the Sparkle update key: without it, installed copies can't verify new releases.

## Calendar

Settings → Calendar (off by default) shows today's events next to the timer and can write finished
focus sessions back as events. Apple Calendar goes through EventKit and needs nothing extra.

Google Calendar signs in directly (OAuth for desktop apps: PKCE, loopback redirect to 127.0.0.1).
It needs an OAuth client of type **Desktop app** from Google Cloud Console with the Google Calendar
API enabled. Put its ID and secret in `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` in `project.yml`
and run `xcodegen generate`. Left empty, the Google option says it isn't set up in this build.
The scopes are `calendar.calendarlist.readonly` and `calendar.events`, which are sensitive scopes:
until Google verifies the app, only test users listed on the OAuth consent screen can sign in.
Google accounts added to the Calendar app (Internet Accounts) work through Apple Calendar either way.

## Link relay

The relay in `server/link` runs at `wss://fifteen.mirzapolat.com` and deploys on every push to main
(`.github/workflows/deploy-link.yml`). To run it locally: `cd server/link && npm install && npm start`,
then `defaults write com.mirzapolat.fifteen linkServerURL ws://localhost:8787`.

## Layout

```
Shared/Model         TimerEngine (date-based state machine), Preferences, HistoryStore, Phase
Shared/Analytics     Everything Insights computes
Shared/Link          LinkSession (the relay client), the shared timer, avatars
Shared/Services      SoundEngine (AVAudioEngine synthesis), Notifier, Haptics
Shared/Views         Dial, header, controls, Insights, Settings sections
Shared/Intents       App Intents + App Shortcuts
Shared/LiveActivity  Live Activity attributes and its Pause/Reset buttons
macOS/               Menu bar item, glass bubble, Link card, hot keys, app blocker, break curtain, Settings
macOS/Calendar       Calendar box beside the bubble, Apple (EventKit) and Google providers, session logging
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

## Not yet

Home Screen and desktop widgets, an Apple Watch app, iCloud sync of history, and website blocking
(that needs a browser extension).
