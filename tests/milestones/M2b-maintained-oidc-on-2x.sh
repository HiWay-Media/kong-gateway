#!/usr/bin/env bash
# M2b — The 2.x variant: production's Kong, with a MAINTAINED OIDC plugin.
#
# This is the milestone that separates two migrations which would otherwise arrive together:
# getting off an abandoned OIDC plugin, and jumping a Kong major. The variant does the first alone.
# Same Kong 2.8.5, same jwt-keycloak, same kong-path-allow — only the OIDC implementation changes,
# so a rollback is one image tag, not a replan.
#
# It works because Kong 2.8 can run Go plugin servers at all, which is not obvious: the image ships
# the protobuf definitions in a directory Kong 2.8 does not search, and without them Kong refuses to
# start with an error that names a .proto file and nothing else. The Dockerfile copies them; this
# checks they are where Kong will look.
source "$(dirname "$0")/../lib.sh"

milestone M2b "Kong 2.x variant carries a maintained OIDC implementation"
expect pass
only_major lt 3
only_provider oidcify

check "the oidcify binary is installed" run 'test -x /usr/local/bin/oidcify'
check "it answers Kong's schema query on this base image" \
  run '/usr/local/bin/oidcify -dump | grep -q oidcify'
check "the protobuf definitions are where Kong 2.x looks for them" \
  has_file /usr/local/kong/lib/pluginsocket.proto
check "the abandoned kong-oidc is not shipped alongside it" \
  lacks_file "$PLUGIN_DIR/oidc/handler.lua"
# The variant changes one thing. If jwt-keycloak went missing, it would be changing two.
check "jwt-keycloak is still present, unchanged" has_rock kong-plugin-jwt-keycloak
check "kong-path-allow is still present, unchanged" has_rock kong-path-allow
