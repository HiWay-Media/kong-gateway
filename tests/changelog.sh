#!/usr/bin/env bash
# The changelog keeps the promise the commit message makes.
#
# Every commit here claims a release in its last line — "(v1.12.0)" — and the rule at the top of
# CHANGELOG.md says that release gets a section. Those two can come apart silently: an edit whose
# anchor text no longer exists writes nothing, the commit still says (v1.12.0), the tag is still
# created, and the release exists everywhere except in the file people read to find out what
# changed. That happened, which is why this test exists.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

echo "==> the changelog is ordered and unique"
VERSIONS=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | tr -d '#[] ')
DUPES=$(printf '%s\n' "$VERSIONS" | sort | uniq -d)
[ -z "$DUPES" ] && ok "no version appears twice" || bad "duplicate sections: $DUPES"

SORTED=$(printf '%s\n' "$VERSIONS" | sort -rV)
[ "$VERSIONS" = "$SORTED" ] && ok "versions are newest first" \
  || bad "sections are out of order — newest must come first"

echo "==> the release the commit claims has a section"
# Commits here end with "(vX.Y.Z)". A merge commit does not, and neither does a commit that is
# deliberately exempt, so the absence of a claim is not a failure — a broken claim is.
CLAIMED=$(git -C "$ROOT" log -1 --pretty=%B | grep -oE '\(v[0-9]+\.[0-9]+\.[0-9]+\)$' | tr -d '()v')
if [ -z "$CLAIMED" ]; then
  ok "the last commit claims no release (nothing to check)"
elif printf '%s\n' "$VERSIONS" | grep -qx "$CLAIMED"; then
  ok "the last commit claims v$CLAIMED, and the changelog has it"
else
  bad "the last commit claims v$CLAIMED but CHANGELOG.md has no [$CLAIMED] section"
fi

echo "==> the release notes can be extracted from it"

# The release body is this file's section for that version. If the extractor cannot find it, a tag
# publishes images and produces an empty release — which is worse than no release, because it looks
# like the change was not worth describing.
NEWEST=$(printf '%s\n' "$VERSIONS" | head -1)
if [ -n "$NEWEST" ] && [ -n "$("$ROOT/scripts/release-notes.sh" "$NEWEST" 2>/dev/null)" ]; then
  ok "the notes for $NEWEST come out non-empty"
else
  bad "scripts/release-notes.sh produces nothing for $NEWEST"
fi

if "$ROOT/scripts/release-notes.sh" 99.99.99 >/dev/null 2>&1; then
  bad "the extractor invents notes for a version that does not exist"
else
  ok "an unknown version is refused rather than guessed"
fi

[ "$fails" -eq 0 ] && { echo "OK: changelog"; exit 0; }
echo "RED: $fails changelog problem(s)"; exit 1
