#!/usr/bin/env bash
# M3 — The open decision on `oidc`, now taken: oidcify.
#
# Every Lua candidate was already dead. nokia/kong-oidc is archived and its README says not to use it
# in production; revomatico/kong-oidc, the best-known 3.x fork, is archived too. What is NOT dead is
# lua-resty-openidc, the library both of them wrap: the wrappers keep being abandoned, the library
# does not.
#
# oidcify is maintained and Apache-2.0, but it is a Go binary Kong runs as an external plugin server:
# one more process, and authentication stops if it dies. That trade is written up in the docs. What
# is checked here is that the binary is present, that it answers Kong's schema query on this base
# image, and that the dead plugin was REMOVED rather than left lying next to its replacement.
source "$(dirname "$0")/../lib.sh"

milestone M3 "A replacement is chosen for oidc on Kong 3.x — oidcify"
expect pass
only_major ge 3

check "the oidcify binary is installed" run 'test -x /usr/local/bin/oidcify'
check "it runs on this base image and answers a schema query" \
  run '/usr/local/bin/oidcify -dump | grep -q oidcify'
check "the abandoned Lua oidc plugin is not shipped alongside it" \
  lacks_file "$PLUGIN_DIR/oidc/handler.lua"
