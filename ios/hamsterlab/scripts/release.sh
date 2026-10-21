#!/bin/bash
set -euo pipefail
upload=false
case "${1:-}" in
  "") ;;
  --upload) upload=true ;;
  *) echo "Usage: $0 [--upload]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  echo "Usage: $0 [--upload]" >&2
  exit 2
fi
cd "$(dirname "$0")/.."
# Older SDKs force iPhone Duo into a compatibility window.
release_sdk=$(xcrun --sdk iphoneos --show-sdk-version)
IFS=. read -r sdk_major sdk_minor sdk_patch <<< "$release_sdk"
if (( sdk_major < 27 || (sdk_major == 27 && ${sdk_minor:-0} < 1) )); then
  echo "HamsterLab releases require iOS SDK 27.1 or later for iPhone Duo (selected: $release_sdk)." >&2
  exit 1
fi
node scripts/sync-web.mjs
xcodegen generate --spec project.yml
xcodebuild -project HamsterLab.xcodeproj -scheme HamsterLab -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/HamsterLab.xcarchive \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/HamsterLab.xcarchive \
  -exportPath build/AppStore -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
if [[ "$upload" == true ]]; then
  upload_options=$(mktemp "${TMPDIR:-/tmp}/hamsterlab-upload.XXXXXX")
  trap 'rm -f "$upload_options"' EXIT
  cp ExportOptions.plist "$upload_options"
  /usr/bin/plutil -replace destination -string upload "$upload_options"
  xcodebuild -exportArchive -archivePath build/HamsterLab.xcarchive \
    -exportPath build/Upload -exportOptionsPlist "$upload_options" \
    -allowProvisioningUpdates
fi
