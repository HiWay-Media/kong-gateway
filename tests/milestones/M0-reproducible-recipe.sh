#!/usr/bin/env bash
# M0 — The image has a recipe, and the recipe produces what it claims.
#
# This is the milestone that closes the gap this repository exists for: the image it replaces was
# two `docker commit` layers on top of an official one, with no Dockerfile and no history. What is
# checked here is the bare minimum — but the bare minimum did not exist before.
source "$(dirname "$0")/../lib.sh"

milestone M0 "Reproducible recipe: the build produces the Kong version it declares"
expect pass

check "Kong in the image really is $KONG_VERSION" \
  run "kong version 2>/dev/null | grep -qx '$KONG_VERSION'"

check "luarocks is present (plugins are rocks, not hand-copied files)" \
  run 'command -v luarocks'

check "kong-path-allow is installed as a rock on both lines" \
  has_rock kong-path-allow

# The Dockerfile drops back to USER kong after installing. An image left running as root is a
# silent regression: it breaks nothing until it matters.
check "the default process does NOT run as root" \
  run 'test "$(id -un)" = kong'
