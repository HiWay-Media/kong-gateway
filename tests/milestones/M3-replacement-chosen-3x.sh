#!/usr/bin/env bash
# M3 — The open decision: what replaces oidc and jwt-keycloak on Kong >= 3.0.
#
# nokia/kong-oidc uses BasePlugin, removed in Kong 3.0. Upstream archived it and its README now
# says the project is not maintained and not recommended in production; last code change: 2019.
# gbbirkisson/kong-plugin-jwt-keycloak is archived. This test is EXPECTED RED (`expect xfail`)
# until that decision is made.
#
# It does not impose WHICH fork: it checks the modules are present, whatever rock provides them.
# The day the Dockerfile installs them this turns XPASS and the runner goes red — which forces
# docs/milestones.md to record the choice instead of leaving a silent green behind.
#
# ⚠️ Replacing abandoned forks with other abandoned forks, on the authentication path, is not a net
# security gain. It is a decision to take, not one to drift into.
source "$(dirname "$0")/../lib.sh"

milestone M3 "A replacement is chosen for oidc and jwt-keycloak on Kong 3.x"
expect xfail
only_major ge 3

for p in oidc jwt-keycloak; do
  check "$p present on Kong $KONG_VERSION (fork still undecided)" \
    has_file "$PLUGIN_DIR/$p/handler.lua"
done
