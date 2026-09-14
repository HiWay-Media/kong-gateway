#!/usr/bin/env bash
# Decides which tags a publish produces.
#
#   scripts/publish-tags.sh <image> <kong-version> <latest-line> <github-ref>
#
# It lives in a script, not in a YAML expression, so that tests/policy.sh can exercise it: what an
# image is published AS cannot be verified after the fact by pulling it — a wrong tag looks exactly
# like a right one until somebody deploys it.
#
# The rules:
#   <image>:<kong>              always. The line being published.
#   <image>:<kong>-<git tag>    only from an annotated v* tag. It is the immutable one, and the one
#                               whose digest belongs in a deployment.
#   <image>:latest              only from a v* release tag, only for the designated line, never from
#                               a pre-release. `latest` must mean the last release — not the last
#                               commit, and not whichever matrix entry happened to finish last.
set -euo pipefail

IMAGE="${1:?usage: publish-tags.sh <image> <kong-version> <latest-line> <github-ref>}"
KONG="${2:?}"
LATEST_LINE="${3:?}"
REF="${4:?}"

echo "$IMAGE:$KONG"

case "$REF" in
  refs/tags/v*)
    RELEASE="${REF#refs/tags/}"
    echo "$IMAGE:$KONG-$RELEASE"
    # A pre-release carries a suffix (v1.1.0-rc.1): it is published, but it does not move latest.
    case "$RELEASE" in
      *-*) ;;
      *)   [ "$KONG" != "$LATEST_LINE" ] || echo "$IMAGE:latest" ;;
    esac
    ;;
esac
