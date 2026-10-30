#!/usr/bin/env bash
# Force-pushes a directory to the `ci-output` branch so results can be read with plain git
# (useful where Actions logs/artifacts are not reachable).
# usage: publish-ci-output.sh <dir> <message> [branch]
set -euo pipefail
dir=$1
msg=$2
branch=${3:-ci-output}
cd "$dir"
git init -q -b "$branch"
git config user.name "Theo CI"
git config user.email "ci@users.noreply.github.com"
date -u > published-at.txt
git add -A
git commit -q -m "$msg"
git push -q -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$branch"
echo "published to $branch: $msg"
