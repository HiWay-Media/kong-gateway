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
# MEASURED on 2026-09-14, and it narrows the question rather than answering it: oidcify validates
# Keycloak ACCESS tokens too, not only ID tokens — configure `bearer_jwt_allowed_auds: ['account']`
# and a real access token is accepted while no token, a malformed one, an invalid signature and a
# token with the wrong audience are each refused with 401. The end-to-end suite asserts all five.
#
# So the AUTHENTICATION half of jwt-keycloak needs no fork at all. What remains is the
# AUTHORIZATION half: jwt-keycloak also validates `scope`, `roles`, `realm_roles` and
# `client_roles`, and can map a claim onto a Kong consumer. oidcify maps a groups claim into
# `authenticated_groups` for Kong's ACL plugin instead — a different shape, not a missing one.
#
# The open question is therefore no longer "which fork?" but "do any routes use those validators?".
# If none do, this milestone closes by consolidation, with no new dependency on the auth path. That
# is a question about the live configuration, so it stays the service owner's to answer.
source "$(dirname "$0")/../lib.sh"

milestone M3b "A replacement is chosen for jwt-keycloak on Kong 3.x"
expect xfail
only_major ge 3

check "a jwt-keycloak handler is present on Kong $KONG_VERSION (fork still undecided)" \
  has_file "$PLUGIN_DIR/jwt-keycloak/handler.lua"
