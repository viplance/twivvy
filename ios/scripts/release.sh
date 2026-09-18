#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
node scripts/sync-web.mjs
xcodegen generate --spec project.yml
xcodebuild -project Twivvy.xcodeproj -scheme Twivvy -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Twivvy.xcarchive \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/Twivvy.xcarchive \
  -exportPath build/AppStore -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
