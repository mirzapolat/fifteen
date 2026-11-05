#!/usr/bin/env bash
# Builds Fifteen for iPhone and iPad and uploads it to App Store Connect, where it shows up in
# TestFlight after processing (10–30 minutes).
#   archive (App Store signing) → export → upload, using the Apple account signed in to Xcode.
#
# One-time setup: the app exists in App Store Connect with bundle ID com.mirzapolat.fifteen, and
# Xcode → Settings → Accounts is signed in to team 56746T8S3D.
#
# Each upload: CURRENT_PROJECT_VERSION in project.yml must be higher than every build uploaded
# before (it's shared with the Mac app, so one counter that only goes up serves both).
# MARKETING_VERSION is the version testers see.
#
# Usage:
#   scripts/release-ios.sh            # archive and upload
#   scripts/release-ios.sh --no-upload  # archive and export an .ipa only (build/ios-release/)
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="build/ios-release"
ARCHIVE="$OUT/Fifteen.xcarchive"
OPTIONS="scripts/ExportOptions-iOS.plist"
UPLOAD=1
for arg in "$@"; do
  case "$arg" in
    --no-upload) UPLOAD=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

version=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/')
build=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/')
echo "▸ Fifteen for iPhone $version ($build)"

command -v xcodegen >/dev/null && xcodegen generate >/dev/null
rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ Archiving…"
xcodebuild archive \
  -scheme Fifteen-iOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath build/ios-archive \
  -allowProvisioningUpdates \
  -quiet

options="$OPTIONS"
if [[ $UPLOAD == 0 ]]; then
  options="$OUT/ExportOptions.plist"
  sed 's#<string>upload</string>#<string>export</string>#' "$OPTIONS" > "$options"
fi

echo "▸ $([[ $UPLOAD == 1 ]] && echo "Uploading to App Store Connect…" || echo "Exporting…")"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$options" \
  -exportPath "$OUT" \
  -allowProvisioningUpdates

if [[ $UPLOAD == 1 ]]; then
  echo "✓ Uploaded $version ($build). It appears in App Store Connect → TestFlight once processed."
else
  echo "✓ Exported to $OUT"
fi
