#!/usr/bin/env bash
# Picks the Xcode for this job and exports it as DEVELOPER_DIR. It needs no sudo, so it also
# works on a self-hosted Mac. In order, it uses:
#   1. $XCODE_APP if that exists (GitHub's runners pin a version),
#   2. the Xcode that xcode-select points to,
#   3. any /Applications/Xcode*.app.
# It requires Xcode 26 or newer.
# It also exports XCBEAUTIFY: xcbeautify with GitHub annotations when installed, cat otherwise.
# Written for macOS's bash 3.2 (no `set -u` with possibly empty arrays).
set -eo pipefail

candidates=()
[ -n "$XCODE_APP" ] && candidates+=("$XCODE_APP")
selected=$(xcode-select -p 2>/dev/null || true)
case "$selected" in
  *.app/Contents/Developer) candidates+=("${selected%/Contents/Developer}") ;;
esac
for app in /Applications/Xcode*.app; do
  [ -d "$app" ] && candidates+=("$app")
done

dir=""
for app in "${candidates[@]}"; do
  [ -d "$app/Contents/Developer" ] || continue
  version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || echo 0)
  major=${version%%.*}
  if [ "$major" -ge 26 ] 2>/dev/null; then
    dir="$app/Contents/Developer"
    break
  fi
done

if [ -z "$dir" ]; then
  echo "::error::No Xcode 26 or newer found (looked at: ${candidates[*]:-nothing}). Install Xcode from the Mac App Store and open it once."
  exit 1
fi

env_file=${GITHUB_ENV:-/dev/null}
echo "DEVELOPER_DIR=$dir" >> "$env_file"
if command -v xcbeautify >/dev/null 2>&1; then
  echo "XCBEAUTIFY=xcbeautify --renderer github-actions" >> "$env_file"
else
  echo "XCBEAUTIFY=cat" >> "$env_file"
fi
echo "Using $dir"
DEVELOPER_DIR=$dir xcodebuild -version
