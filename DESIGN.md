# Design Language

How Penns looks and behaves, for reuse in other one-thing apps.

## Philosophy
- **One thing, one glance away.** One object (one note, one timer), with no lists or folders to manage.
- **Feature filter:** a feature must make the thing easier to *see*, faster to *start* or easier to *let go of*. Nothing that nags.
- **Free, no account, no ads.** Never lose the user's data.

## Look
- **Native first:** use system menus, pickers, the share sheet and a `Form` for Settings.
- **Liquid Glass:** the content fills the screen, and controls float as glass capsules in a `GlassEffectContainer`. No other chrome.
- **Color:** semantic system colors only. The accent is the only highlight, plus a small dot if things need telling apart.
- **Type:** one body style; only headings differ.
- **Spacing:** one 16 pt margin on every side. Pills are 44 pt tall on iOS and 30 pt on Mac, with 10 pt between them.
- **Crowded rows:** important pills keep full size (`fixedSize` + `layoutPriority`); less important ones shrink to an icon (`ViewThatFits`). Everything else goes into a "…" menu.

## Behavior
- **Nothing new appears:** at the natural end, an existing pill grows into a tinted, labeled pill (spring 0.4 s, bounce 0.25).
- **Opens ready:** straight into the main thing, focused.
- **Quiet:** one haptic on the key action; no badges or streaks.
- **Onboarding** gets its own 1–2 screens and never appears inside the main view.
- **Lives everywhere:** menu bar, widgets, Live Activity, watch, Shortcuts.

## Copy
Down-to-earth: a clear promise, a few concrete benefits, where it lives, and the philosophy as the last line. No hype.

## For a Pomodoro app
- One timer; a large `.monospacedDigit()` countdown fills the screen.
- Pills: duration (shrinks to a `timer` icon when crowded) · Start/Pause · "…" (History, Settings).
- When a session ends, Start grows into a tinted "Take a Break", then "Back to Focus".
- Live Activity with `Text(timerInterval:)`, the remaining time in the menu bar, and a ring complication on the watch.
- History instead of streaks; the count resets each morning.
