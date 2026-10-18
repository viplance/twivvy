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
node scripts/sync-web.mjs
xcodegen generate --spec project.yml
xcodebuild -project Twivvy.xcodeproj -scheme Twivvy -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Twivvy.xcarchive \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/Twivvy.xcarchive \
  -exportPath build/AppStore -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
if [[ "$upload" == true ]]; then
  upload_options=$(mktemp "${TMPDIR:-/tmp}/twivvy-upload.XXXXXX")
  trap 'rm -f "$upload_options"' EXIT
  cp ExportOptions.plist "$upload_options"
  /usr/bin/plutil -replace destination -string upload "$upload_options"
  xcodebuild -exportArchive -archivePath build/Twivvy.xcarchive \
    -exportPath build/Upload -exportOptionsPlist "$upload_options" \
    -allowProvisioningUpdates
fi
