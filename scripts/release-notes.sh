#!/usr/bin/env bash
# Prints the changelog section for one version, for a release body.
#
#   scripts/release-notes.sh 1.18.0
#
# The release notes are the changelog entry, not a second description written for the occasion.
# Two accounts of the same change drift, and the one nobody edits is the one people read.
set -uo pipefail

VERSION="${1:?usage: release-notes.sh <version>}"
VERSION="${VERSION#v}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# From the heading of this version to the heading of the next one, exclusive. `exit` rather than a
# flag, so a malformed file cannot silently print the whole changelog as one release's notes.
section=$(awk -v v="## [$VERSION]" '
  index($0, v) == 1 { found = 1; next }
  found && /^## \[/ { exit }
  found { print }
' "$ROOT/CHANGELOG.md")

if [ -z "$(printf '%s' "$section" | tr -d '[:space:]')" ]; then
  echo "no changelog section for $VERSION" >&2
  exit 1
fi

printf '%s\n' "$section" | sed -e '/./,$!d' | awk 'BEGIN{b=0} {lines[NR]=$0} END{while (NR>0 && lines[NR] ~ /^[[:space:]]*$/) NR--; for(i=1;i<=NR;i++) print lines[i]}'
