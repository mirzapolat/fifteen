#!/usr/bin/env bash
# Builds a notarized, direct-download Fifteen for the Mac:
#   archive → export with Developer ID → DMG → notarize → staple → check with Gatekeeper
#   → sign for Sparkle → appcast.xml → (with --publish) a GitHub release that installed copies update from.
#
# One-time setup (see README → "Release the Mac app"):
#   1. A "Developer ID Application" certificate in your keychain (Xcode → Settings → Accounts →
#      Manage Certificates → + → Developer ID Application).
#   2. Notary credentials saved in the keychain under the profile name below:
#        xcrun notarytool store-credentials fifteen-notary --apple-id <you@example.com> --team-id 56746T8S3D
#      (it asks for an app-specific password from account.apple.com).
#   3. The Sparkle update key in the keychain (made once with Sparkle's generate_keys; back it up with
#      `generate_keys -x <file>`, because without it installed copies can't take updates).
#
# Each release: bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml (the build number
# must go up every time, or Sparkle won't offer the update), and optionally write
# release-notes/<version>.html: it's shown in the update window and on the GitHub release.
#
# Usage:
#   scripts/release-mac.sh                  # build, notarize, write the appcast; prints how to publish
#   scripts/release-mac.sh --publish        # …and create the GitHub release (needs `gh auth login`)
#   scripts/release-mac.sh --skip-notarize  # signed DMG only, to try the steps before notarizing
#   NOTARY_PROFILE=other scripts/release-mac.sh
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="56746T8S3D"
REPO="mirzapolat/fifteen"
FEED="https://github.com/$REPO/releases/latest/download/appcast.xml"
PROFILE="${NOTARY_PROFILE:-fifteen-notary}"
OUT="build/release"
ARCHIVE="$OUT/Fifteen.xcarchive"
EXPORT="$OUT/export"
PACKAGES="build/spm"
SPARKLE_BIN="$PACKAGES/artifacts/sparkle/Sparkle/bin"
NOTARIZE=1
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) NOTARIZE=0 ;;
    --publish) PUBLISH=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
[[ $NOTARIZE == 0 && $PUBLISH == 1 ]] && { echo "--publish needs a notarized build." >&2; exit 2; }

step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ─── Preflight ────────────────────────────────────────────────────────────
step "Checking signing and notary setup"
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
[[ -n "$IDENTITY" ]] || fail "No \"Developer ID Application\" certificate for team $TEAM_ID in the keychain.
  Create one in Xcode → Settings → Accounts → (your team) → Manage Certificates → + → Developer ID Application."
echo "Signing as: $IDENTITY"
if [[ $NOTARIZE == 1 ]]; then
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "No notary credentials saved as \"$PROFILE\". Run once:
  xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id $TEAM_ID"
fi
if [[ $PUBLISH == 1 ]]; then
  gh auth status >/dev/null 2>&1 || fail "Not logged in to GitHub. Run: gh auth login"
  [[ -z "$(git status --porcelain)" ]] || echo "Note: there are uncommitted changes; the release is tagged at what's on GitHub."
fi

# ─── Build ────────────────────────────────────────────────────────────────
rm -rf "$OUT"
mkdir -p "$OUT"

step "Generating the Xcode project"
xcodegen generate --quiet

step "Archiving (Release)"
xcodebuild -scheme Fifteen -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -clonedSourcePackagesDirPath "$PACKAGES" \
  -allowProvisioningUpdates \
  archive -quiet

step "Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist scripts/ExportOptions-DeveloperID.plist \
  -allowProvisioningUpdates -quiet

APP="$EXPORT/Fifteen.app"
[[ -d "$APP" ]] || fail "Export didn't produce $APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$APP/Contents/Info.plist")
echo "Fifteen $VERSION ($BUILD)"

# Sparkle compares build numbers: one that doesn't go up is never offered to anyone.
PUBLISHED=$(curl -fsL "$FEED" 2>/dev/null | sed -nE 's/.*<sparkle:version>([^<]+)<.*/\1/p' | head -1 || true)
if [[ -n "$PUBLISHED" && $NOTARIZE == 1 ]]; then
  echo "Published now: build $PUBLISHED"
  [[ "$BUILD" -gt "$PUBLISHED" ]] || fail "Build $BUILD isn't newer than the published build $PUBLISHED.
  Raise CURRENT_PROJECT_VERSION in project.yml."
fi

step "Verifying the app's signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID Application|flags=.*runtime" \
  || fail "The app isn't signed with Developer ID and the hardened runtime."

# ─── Disk image ───────────────────────────────────────────────────────────
step "Making the disk image"
DMG="$OUT/Fifteen-$VERSION.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Fifteen" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ $NOTARIZE == 0 ]]; then
  step "Done (not notarized): $DMG"
  exit 0
fi

# ─── Notarize ─────────────────────────────────────────────────────────────
step "Notarizing (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format plist > "$OUT/notary.plist" || true
STATUS=$(/usr/libexec/PlistBuddy -c "Print status" "$OUT/notary.plist" 2>/dev/null || echo "Unknown")
if [[ "$STATUS" != "Accepted" ]]; then
  ID=$(/usr/libexec/PlistBuddy -c "Print id" "$OUT/notary.plist" 2>/dev/null || echo "")
  [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "$OUT/notary-log.json" || true
  fail "Notarization status: $STATUS. Details: $OUT/notary-log.json"
fi

step "Stapling the ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

step "Checking with Gatekeeper"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

shasum -a 256 "$DMG" | tee "$DMG.sha256"

# ─── Sparkle ──────────────────────────────────────────────────────────────
step "Signing the update for Sparkle"
[[ -x "$SPARKLE_BIN/sign_update" ]] || fail "Sparkle's tools aren't in $SPARKLE_BIN."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG") || fail "sign_update failed (is the Sparkle key in the keychain?)"
TAG="v$VERSION"
NAME=$(basename "$DMG")
URL="https://github.com/$REPO/releases/download/$TAG/$NAME"
NOTES_FILE="release-notes/$VERSION.html"
if [[ -f "$NOTES_FILE" ]]; then
  NOTES=$(cat "$NOTES_FILE")
else
  echo "No $NOTES_FILE; the update window will show a plain line."
  NOTES="<p>Fifteen $VERSION</p>"
fi

step "Writing the appcast"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Fifteen</title>
    <link>https://github.com/$REPO</link>
    <language>en</language>
    <item>
      <title>Fifteen $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT/appcast.xml" || fail "The appcast isn't valid XML."
printf '%s\n' "$NOTES" > "$OUT/notes.html"

PUBLISH_CMD="gh release create $TAG \"$DMG\" \"$OUT/appcast.xml\" \"$DMG.sha256\" --repo $REPO --title \"Fifteen $VERSION\" --notes-file \"$OUT/notes.html\""
if [[ $PUBLISH == 1 ]]; then
  step "Publishing $TAG on GitHub"
  gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && fail "Release $TAG already exists on GitHub."
  eval "$PUBLISH_CMD"
  step "Published. Installed copies will offer $VERSION within a day."
else
  step "Ready: $DMG and $OUT/appcast.xml"
  echo "To publish (installed copies then offer it within a day):"
  echo "  $PUBLISH_CMD"
  echo "or run again with --publish."
fi
