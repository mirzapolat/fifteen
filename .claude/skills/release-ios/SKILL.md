---
name: release-ios
description: Upload a new build of Fifteen for iPhone and iPad to TestFlight (App Store Connect). Bumps the build number, commits, archives with App Store signing and uploads with scripts/release-ios.sh. Use when the user wants to test on TestFlight, upload an iOS build, or ship the iPhone app.
---

# Upload Fifteen for iPhone to TestFlight

The iPhone and iPad app is `com.mirzapolat.fifteen` in App Store Connect (team 56746T8S3D).
`scripts/release-ios.sh` archives the `Fifteen-iOS` scheme and uploads it with the Apple account
signed in to Xcode; the build shows up in TestFlight after 10–30 minutes of processing.

## Steps

1. **Preflight.** Uncommitted changes: list them and ask whether they go into this build.
   The iOS app and the Mac app both build:
   `xcodebuild -scheme Fifteen-iOS -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios build`
   and `xcodebuild -scheme Fifteen -derivedDataPath build/dd build`.
2. **Build number.** Raise `CURRENT_PROJECT_VERSION` in `project.yml` by one. It's shared with the
   Mac app, and App Store Connect refuses a number it has seen, so it only ever goes up. Raise
   `MARKETING_VERSION` only when the user asks for a new version.
3. **Commit** the bump (and anything the user said belongs in it): `iOS build <version> (<build>)`.
4. **Upload:** `scripts/release-ios.sh` (long; run it in the background). If it fails with
   "No suitable application records", the app record is missing in App Store Connect; with a
   duplicate build number, go back to step 2.
5. **Report** the version and build, and that it appears under App Store Connect → TestFlight once
   processed. Internal testers get it straight away; external testers need a short beta review
   for the first build of each version.
