#!/usr/bin/env bash
# Milestone test runner.
#
#   ./tests/run.sh <image> <kong-version>
#
# Runs every milestone in order and prints a summary. It exits RED when:
#   FAIL  — a milestone that had been reached has regressed;
#   XPASS — a milestone declared unreachable now passes: drop `expect xfail` and update docs/milestones.md.
#
# XFAIL is not red. It is declared, outstanding work — the difference between "the 3.x build fails
# and we know why" and "the 3.x build fails, and nobody has read that log in a year".
set -euo pipefail

IMAGE="${1:?usage: run.sh <image> <kong-version>}"
KONG_VERSION="${2:?usage: run.sh <image> <kong-version>}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MILESTONE_RESULTS="$(mktemp)"
trap 'rm -f "$MILESTONE_RESULTS"' EXIT

echo "Image: $IMAGE   Kong: $KONG_VERSION"

for t in "$HERE"/milestones/M*.sh; do
  "$t" "$IMAGE" "$KONG_VERSION" || true
done

echo
echo "== Summary"
rc=0
publishable=true
while IFS=$'\t' read -r id status _expect title; do
  printf '  %-6s %-3s %s\n' "$status" "$id" "$title"
  case "$status" in
    FAIL|XPASS) rc=1; publishable=false ;;
    # An XFAIL is not red, but it is still an unmet milestone: this line is not publishable.
    # Without this the 3.x image would be pushed on a tag, having declared itself not ready.
    XFAIL)      publishable=false ;;
  esac
done <"$MILESTONE_RESULTS"

[ -z "${GITHUB_OUTPUT:-}" ] || echo "publishable=$publishable" >>"$GITHUB_OUTPUT"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    printf '### Milestones — Kong %s\n\n' "$KONG_VERSION"
    printf '| Result | Milestone | Exit criterion |\n|---|---|---|\n'
    while IFS=$'\t' read -r id status _expect title; do
      printf '| %s | %s | %s |\n' "$status" "$id" "$title"
    done <"$MILESTONE_RESULTS"
    printf '\nXFAIL = milestone declared not reached yet (see `docs/milestones.md`).\n'
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [ "$rc" -ne 0 ]; then
  echo "RED: see above"
elif [ "$publishable" = true ]; then
  echo "OK: $IMAGE"
else
  echo "OK: $IMAGE — not publishable: milestones still declared XFAIL"
fi
exit "$rc"
