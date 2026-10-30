#!/usr/bin/env bash
# Runs XcodeGen: the installed one if present, otherwise a pinned release downloaded once.
set -euo pipefail
VERSION=${XCODEGEN_VERSION:-2.46.0}
if command -v xcodegen >/dev/null 2>&1; then
  exec xcodegen "$@"
fi
dir=".build/xcodegen-$VERSION"
if [ ! -x "$dir/xcodegen/bin/xcodegen" ]; then
  mkdir -p "$dir"
  curl -sSL -o "$dir/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
  unzip -q -o "$dir/xcodegen.zip" -d "$dir"
fi
exec "$dir/xcodegen/bin/xcodegen" "$@"
