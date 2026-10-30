#!/usr/bin/env bash
# Archives one scheme and uploads it to App Store Connect, signed automatically through the
# App Store Connect API key (no certificates or profiles in the repo).
# usage: archive-upload.sh <scheme> <destination> <label>
# env:   APPLE_TEAM_ID ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH BUILD_NUMBER
set -euo pipefail
scheme=$1
destination=$2
label=$3
: "${APPLE_TEAM_ID:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}" "${BUILD_NUMBER:?}"

work="${RUNNER_TEMP:-/tmp}/theo-$label"
rm -rf "$work"
mkdir -p "$work"
auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

xcodebuild archive \
  -project Theo.xcodeproj -scheme "$scheme" -configuration Release \
  -destination "$destination" -archivePath "$work/$scheme.xcarchive" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${auth[@]}" 2>&1 | tee "$label-archive.log" | xcbeautify --renderer github-actions

cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$work/$scheme.xcarchive" -exportOptionsPlist "$work/ExportOptions.plist" \
  -exportPath "$work/export" "${auth[@]}" 2>&1 | tee "$label-upload.log"
