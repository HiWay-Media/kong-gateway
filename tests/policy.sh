#!/usr/bin/env bash
# Publishing policy tests.
#
# The milestone suite checks what is inside an image. This one checks what gets published under
# which name — the part nobody can verify by pulling, because a wrong tag looks exactly like a right
# one until somebody deploys it.
#
# It needs no image and no Docker: scripts/publish-tags.sh decides the tag list, and deciding it in
# a script rather than in a YAML expression is what makes the decision testable at all.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
TAGS="$REPO_ROOT/scripts/publish-tags.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/image.yml"
IMAGE=ghcr.io/example/kong-gateway
LATEST_LINE=2.8.5

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# case: <description> <kong> <ref> <expected tags, comma-separated> [variant]
case_is() {
  local desc="$1" kong="$2" ref="$3" want="$4" variant="${5:-}" got
  got=$("$TAGS" "$IMAGE" "$kong" "$LATEST_LINE" "$ref" "$variant" | paste -sd, -)
  [ "$got" = "$want" ] && ok "$desc" || bad "$desc
         expected: $want
         got:      $got"
}

echo "==> which tags a publish produces"

case_is "an annotated tag publishes the version, the release, and latest for the current line" \
  2.8.5 refs/tags/v1.0.1 \
  "$IMAGE:2.8.5,$IMAGE:2.8.5-v1.0.1,$IMAGE:latest"

# latest must name one image, and the line carrying it is a decision, not whichever matrix entry
# finished last. Two lines both claiming latest is how a pull silently changes major version.
case_is "a second Kong line never claims latest" \
  3.9.3 refs/tags/v1.0.1 \
  "$IMAGE:3.9.3,$IMAGE:3.9.3-v1.0.1"

# The whole point of `latest`: it means the last release. A manual dispatch from a branch is not one.
case_is "a manual dispatch from main publishes no latest and no release tag" \
  2.8.5 refs/heads/main \
  "$IMAGE:2.8.5"

case_is "a pre-release tag publishes the release but does not move latest" \
  2.8.5 refs/tags/v1.1.0-rc.1 \
  "$IMAGE:2.8.5,$IMAGE:2.8.5-v1.1.0-rc.1"

# A variant is the same Kong with a different plugin set, so it cannot answer to the same names.
# `2.8.5` must keep meaning the image that reproduces production; the variant lives beside it under
# its own suffix, and never takes `latest` — that would silently move every deployment following the
# tag onto a different authentication plugin.
case_is "a variant publishes under its own suffix" \
  2.8.5 refs/tags/v1.5.0 \
  "$IMAGE:2.8.5-oidcify,$IMAGE:2.8.5-oidcify-v1.5.0" \
  oidcify

case_is "a variant never takes latest, even on the line that carries it" \
  2.8.5 refs/tags/v1.5.0 \
  "$IMAGE:2.8.5-oidcify,$IMAGE:2.8.5-oidcify-v1.5.0" \
  oidcify

case_is "the default build of the same line still takes latest" \
  2.8.5 refs/tags/v1.5.0 \
  "$IMAGE:2.8.5,$IMAGE:2.8.5-v1.5.0,$IMAGE:latest"

echo "==> the workflow actually uses that decision"

grep -q 'scripts/publish-tags.sh' "$WORKFLOW" \
  && ok "the publish step takes its tags from scripts/publish-tags.sh" \
  || bad "the workflow builds its tag list inline — then this file tests nothing"

# A milestone still declared XFAIL means the line is not ready; the gate exists so that a tag cannot
# publish it anyway.
if [ "$(grep -c "steps.milestones.outputs.publishable == 'true'" "$WORKFLOW")" -ge 3 ]; then
  ok "login, push and digest are gated on the milestones being met"
else
  bad "a publish step is not gated on publishable"
fi

grep -q "startsWith(github.ref, 'refs/tags/v') || inputs.publish" "$WORKFLOW" \
  && ok "publishing happens only from a v* tag or an explicit dispatch" \
  || bad "the publish condition changed: a push to main may now publish"

# A `paths:` filter on the push trigger also applies to TAG pushes: GitHub evaluates it against the
# tagged commit, so tagging a release whose commit only touched docs would skip the workflow
# entirely — no build, no publish, no `latest`, and nothing anywhere saying why. A release that
# quietly publishes nothing is worse than a pipeline that runs a few minutes too often, so the push
# trigger carries no filter. Checked by text, so this test needs nothing installed but a shell.
PUSH_BLOCK=$(awk '/^  push:/ {inside = 1; next} /^  [a-z_]+:/ {inside = 0} inside' "$WORKFLOW")
case "$PUSH_BLOCK" in
  *paths:*) bad "the push trigger has a paths filter: a docs-only release tag would publish nothing" ;;
  *)        ok  "the push trigger has no paths filter, so a release tag always builds" ;;
esac

[ "$fails" -eq 0 ] && { echo "OK: publishing policy"; exit 0; }
echo "RED: $fails policy check(s) failed"; exit 1
