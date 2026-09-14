#!/usr/bin/env bash
# M3b — The half of the decision still open: what replaces jwt-keycloak on Kong >= 3.0.
#
# gbbirkisson/kong-plugin-jwt-keycloak is archived. The Platformatory fork claims 3.x support but is
# small and lightly used — 4 stars, last pushed July 2024 — which is worth knowing before putting it
# on an authentication path.
#
# EXPECTED RED until that is decided. It is the reason the 3.x image is still not publishable, even
# with oidcify in place: see M4.
#
# Worth asking before picking a fork: oidcify validates bearer ID tokens itself. If the routes using
# jwt-keycloak only need signature, issuer and audience checks, they may not need a second plugin at
# all — consolidating is cheaper than adopting another unmaintained one.
source "$(dirname "$0")/../lib.sh"

milestone M3b "A replacement is chosen for jwt-keycloak on Kong 3.x"
expect xfail
only_major ge 3

check "a jwt-keycloak handler is present on Kong $KONG_VERSION (fork still undecided)" \
  has_file "$PLUGIN_DIR/jwt-keycloak/handler.lua"
