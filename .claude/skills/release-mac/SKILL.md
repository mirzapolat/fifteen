---
name: release-mac
description: Release a new version of Fifteen for Mac end to end. Picks and bumps the version and build number, writes the release notes, commits and pushes, then builds, notarizes, Sparkle-signs and publishes the GitHub release with scripts/release-mac.sh --publish, and verifies the live update feed. Use when the user says they want to release, ship, publish or put out a new Mac version.
---

# Release Fifteen for Mac

Fifteen for Mac ships as a notarized Developer ID download on GitHub Releases
(`github.com/mirzapolat/fifteen`). Installed copies update through Sparkle from
`https://github.com/mirzapolat/fifteen/releases/latest/download/appcast.xml`.
`scripts/release-mac.sh` does the build and publish; this skill is everything around it.

Publishing is public and can't be quietly undone: once installed copies see a version, they offer it.
Confirm the version and notes with the user once (step 3), then go through to the end without
further check-ins unless something fails.

## 1. Preflight (stop and report anything that fails)

- On `main`, in sync with `origin/main` (`git fetch && git status -sb`). Uncommitted changes: list
  them and ask whether they belong in this release (commit them) or should wait.
- Builds and tests pass:
  - `xcodebuild -scheme Fifteen -derivedDataPath build/dd -clonedSourcePackagesDirPath build/spm build`
  - `xcodebuild -scheme FifteenTests -derivedDataPath build/dd test`
  - `(cd server/link && npm test)` if `server/link` changed since the last release
- Signing and publishing are set up (all one-time; if one is missing, give the user the fix):
  - Developer ID: `security find-identity -v -p codesigning | grep "Developer ID Application"` shows team 56746T8S3D.
    Fix: create it at developer.apple.com → Certificates → Developer ID Application (G2), from a CSR.
  - Notary credentials: `xcrun notarytool history --keychain-profile fifteen-notary` succeeds.
    Fix: the user runs `! xcrun notarytool store-credentials fifteen-notary --apple-id <Apple ID> --team-id 56746T8S3D`.
  - Sparkle key: `build/spm/artifacts/sparkle/Sparkle/bin/generate_keys -p` prints
    `D8vjG57p09kEOgZWkci15kU5ICuAEnxhiI2TMZWXNCA=` (the key in project.yml `SUPublicEDKey`).
    **Never generate a new key.** A different key means installed copies reject every future update.
    If it's missing, the user restores it from their backup: `generate_keys -f <backup file>`.
  - GitHub: `gh auth status`.

## 2. Work out the version

- Published now: `gh release list --repo mirzapolat/fifteen --limit 1`, and the `<sparkle:version>` in
  the live appcast (`curl -fsL <feed URL>`).
- What changed: `git log --oneline <last tag>..HEAD` (tags are `v1.0`, `v1.1`, …).
- Suggest the next `MARKETING_VERSION`: x.y+1 for features, x.y.z+1 for fixes only, x+1.0 if the user
  says it's a big one.
- `CURRENT_PROJECT_VERSION` is the build number Sparkle compares. It **must** be higher than the
  published `<sparkle:version>`: set it to published + 1.

## 3. Release notes, then one confirmation

Write `release-notes/<version>.html`: an `<h2>Fifteen <version></h2>`, one short line, then a `<ul>` of
3–6 user-facing changes from the git log, in the app's voice (short, plain, no jargon, no internal
refactors). The same file is shown in Sparkle's update window and on the GitHub release.

Show the user the version, build number and the notes, and ask once: publish this? Apply any
changes they ask for.

## 4. Bump, commit, push

- In `project.yml`: set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (under `settings: base:`).
- `xcodegen generate --quiet`
- Commit `project.yml`, `Fifteen.xcodeproj`, `release-notes/<version>.html` (plus anything the user
  said belongs in the release) as `Release <version>`, with the attribution trailer, then
  `git push origin main`. The GitHub release is tagged at what's on GitHub, so push first.

## 5. Build and publish

`scripts/release-mac.sh --publish` (allow 10 minutes; notarization usually takes 1–5).
It archives, exports with Developer ID, makes `build/release/Fifteen-<version>.dmg`, notarizes and
staples it, checks it with Gatekeeper, signs it for Sparkle, writes `appcast.xml`, refuses a build
number that isn't higher than the published one, and creates the GitHub release `v<version>`.

If notarization fails, read `build/release/notary-log.json` and report the actual issues.
If it fails after the release was created, don't delete or recreate the release without asking.

## 6. Verify what's live

Download the live appcast and the DMG it points to, as an installed copy would:
- the appcast's `<sparkle:shortVersionString>` is the new version and its URL is the new DMG
- `sign_update --verify <downloaded dmg> <edSignature from the appcast>` passes
- `spctl --assess --type open --context context:primary-signature -v <dmg>` says
  "accepted, source=Notarized Developer ID"

## 7. Report

The release link (`https://github.com/mirzapolat/fifteen/releases/latest`), the version and build,
and what was checked. For the first few releases, remind the user to try **Check for Updates…** on
the previous version, because updating from one version to the next can only be tested once both
are live (it hadn't been tested as of 1.0).

## Not covered

The iPhone/iPad app (App Store, not released yet) and a Mac App Store build (needs the App Sandbox;
the app blocker's Quit mode and the icon picker don't work there).
