#!/usr/bin/env bash
# Shared library for the milestone tests.
#
# The model is TDD applied to an image: every milestone of the upgrade plan has a test file that
# states its exit criterion. A milestone not yet reached declares `expect xfail` — the test FAILS,
# and that is the expected outcome. When the milestone is reached the test passes and the runner
# reports XPASS, which is RED, until docs/milestones.md is updated.
#
# That is deliberate. An untracked red normalises: people stop reading it, and the build that was
# "expected to fail" becomes the build nobody looks at. A green nobody declared is the same problem
# from the other side — like a mutable tag, it stops meaning anything in particular.
#
# Usage in a test file:
#   source "$(dirname "$0")/../lib.sh"
#   milestone M3 "A replacement is chosen for oidc and jwt-keycloak on Kong 3.x"
#   expect xfail
#   only_major ge 3
#   check "the rock is installed" has_rock kong-path-allow

set -euo pipefail

IMAGE="${1:?usage: <test> <image> <kong-version>}"
KONG_VERSION="${2:?usage: <test> <image> <kong-version>}"
KONG_MAJOR="${KONG_VERSION%%.*}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_DIR="$REPO_ROOT/reference/baseline-2.0.3"
PLUGIN_DIR=/usr/local/share/lua/5.1/kong/plugins
# The kong:*-ubuntu images are amd64-only: set DOCKER_PLATFORM=linux/amd64 on an arm64 workstation.
PLATFORM_ARG=${DOCKER_PLATFORM:+--platform $DOCKER_PLATFORM}

_ID=""; _TITLE=""; _EXPECT=pass; _FAILS=0; _CHECKS=0; _SKIP=""; _ROCKS=""

milestone() { _ID="$1"; _TITLE="$2"; printf '\n== %s — %s\n' "$_ID" "$_TITLE"; }

# expect pass  : the milestone is reached; a regression must be red
# expect xfail : the milestone is not reached yet; failing is the declared, expected behaviour
expect() { _EXPECT="$1"; }

# Restrict a test to one Kong major. Skipping is honest; pretending to pass is not.
only_major() {
  local op="$1" n="$2"
  case "$op" in
    ge) [ "$KONG_MAJOR" -ge "$n" ] || _SKIP="needs Kong >= $n (this is $KONG_VERSION)" ;;
    lt) [ "$KONG_MAJOR" -lt "$n" ] || _SKIP="needs Kong < $n (this is $KONG_VERSION)" ;;
    *)  echo "only_major: unknown operator '$op'" >&2; exit 2 ;;
  esac
  [ -z "$_SKIP" ] || exit 0
}

# Run a command INSIDE the image. Kong's entrypoint is bypassed on purpose: nothing here starts a
# gateway, it inspects what the image contains.
run() { docker run --rm $PLATFORM_ARG --entrypoint sh "$IMAGE" -c "$1"; }

# The pre-push gate lives in tests/smoke.sh; milestones call it instead of restating it. Two copies
# of the same check drift, and then neither can be trusted to describe the image.
smoke() { "$REPO_ROOT/tests/smoke.sh" "$IMAGE" "$KONG_VERSION"; }

# Loaded once per test: each call is a container start, and under emulation that is not cheap.
rocks() {
  [ -n "$_ROCKS" ] || _ROCKS="$(run 'luarocks list --porcelain' | cut -f1 | sort -u)"
  printf '%s\n' "$_ROCKS"
}

# Deliberately not `rocks | grep -qx`: grep -q exits at the first match and closes the pipe, the
# docker client dies of SIGPIPE, and under `pipefail` the whole pipeline reports failure even though
# the rock was found. That produced a FAIL that moved between runs — the worst kind of test, since
# it teaches people to re-run instead of to read.
has_rock() {
  rocks >/dev/null                       # memoise before matching
  case $'\n'"$_ROCKS"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *)                 return 1 ;;
  esac
}
has_file()  { run "test -f '$1'"; }
file_has()  { run "grep -q '$2' '$1'"; }
lua_loads() { run "resty -e 'require(\"$1\")'"; }

note() { printf '  ..   %s\n' "$*"; }

check() {
  local desc="$1"; shift
  _CHECKS=$((_CHECKS + 1))
  if "$@" >/dev/null 2>&1; then
    printf '  ok   %s\n' "$desc"
  else
    printf '  FAIL %s\n' "$desc"
    _FAILS=$((_FAILS + 1))
  fi
}

_finish() {
  local rc=$? status
  if [ -n "$_SKIP" ]; then
    status=SKIP
    printf '  --   skipped: %s\n' "$_SKIP"
  elif [ "$_FAILS" -gt 0 ] || [ "$rc" -ne 0 ]; then
    status=$([ "$_EXPECT" = xfail ] && echo XFAIL || echo FAIL)
  else
    status=$([ "$_EXPECT" = xfail ] && echo XPASS || echo PASS)
  fi

  case "$status" in
    PASS)  printf '  => PASS  (%d checks)\n' "$_CHECKS"; rc=0 ;;
    FAIL)  printf '  => FAIL  (%d of %d checks failed)\n' "$_FAILS" "$_CHECKS"; rc=1 ;;
    XFAIL) printf '  => XFAIL (expected: milestone not reached yet)\n'; rc=0 ;;
    XPASS) printf '  => XPASS milestone %s REACHED: drop `expect xfail` and update docs/milestones.md\n' "$_ID"; rc=1 ;;
    SKIP)  rc=0 ;;
  esac

  [ -z "${MILESTONE_RESULTS:-}" ] || printf '%s\t%s\t%s\t%s\n' "$_ID" "$status" "$_EXPECT" "$_TITLE" >>"$MILESTONE_RESULTS"
  trap - EXIT
  exit "$rc"
}
trap _finish EXIT
