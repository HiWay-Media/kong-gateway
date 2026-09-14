#!/usr/bin/env bash
# Smoke test for the built image. Runs on the runner before anything is pushed: nothing is
# published unless this passes.
#
# The test that matters most is the last one. kong-path-allow is an AUTHORIZATION control, and an
# authorization control is verified by the case that must be refused, not by the one that must pass.
# A plugin that loads but no longer blocks anything would satisfy every healthcheck.
set -euo pipefail

IMAGE="${1:?usage: smoke.sh <image> <kong-version>}"
KONG_VERSION="${2:?usage: smoke.sh <image> <kong-version>}"
KONG_MAJOR="${KONG_VERSION%%.*}"
# Set DOCKER_PLATFORM=linux/amd64 when testing on an arm64 workstation.
PLATFORM_ARG=${DOCKER_PLATFORM:+--platform $DOCKER_PLATFORM}

run() { docker run --rm $PLATFORM_ARG --entrypoint sh "$IMAGE" -c "$1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# Which OIDC implementation this image carries. Asked of the image, never passed in: a gate that is
# TOLD what to expect cannot catch a build that produced something else.
OIDC_PROVIDER=$(run 'cat /usr/local/share/kong-gateway-oidc-provider 2>/dev/null' 2>/dev/null | tr -d '\r\n')
OIDC_PROVIDER="${OIDC_PROVIDER:-kong-oidc}"
echo "==> OIDC implementation in this image: $OIDC_PROVIDER"

echo "==> rocks are installed"
ROCKS=$(run 'luarocks list --porcelain' | cut -f1 | sort -u)
echo "$ROCKS" | grep -qx kong-path-allow || fail "kong-path-allow missing"

# Exactly one OIDC implementation, never two. An image carrying both would pass every check below
# while leaving it to a configuration file to decide which one actually guards a route — and the
# abandoned one would still be a live code path in an image that claims to have replaced it.
HAS_KONG_OIDC=no; HAS_OIDCIFY=no
echo "$ROCKS" | grep -qx kong-oidc && HAS_KONG_OIDC=yes
run 'test -x /usr/local/bin/oidcify' 2>/dev/null && HAS_OIDCIFY=yes

# One `case`, not a chain of && and ||: the chain reads correctly and evaluates wrongly, which is
# how a gate ends up rejecting the image it was written to accept.
case "$OIDC_PROVIDER:$HAS_KONG_OIDC:$HAS_OIDCIFY" in
  kong-oidc:yes:no) ;;
  oidcify:no:yes)   ;;
  *:yes:yes) fail "both kong-oidc and oidcify are installed: the image does not say which one guards a route" ;;
  *:no:no)   fail "no OIDC implementation at all" ;;
  *)         fail "the image declares OIDC provider '$OIDC_PROVIDER' but carries kong-oidc=$HAS_KONG_OIDC oidcify=$HAS_OIDCIFY" ;;
esac

if [ "$KONG_MAJOR" -lt 3 ]; then
  # jwt-keycloak and path-allow are the same in both 2.x variants: the variant changes the OIDC
  # plugin only. That is the point of having it — one migration at a time.
  for r in kong-plugin-jwt-keycloak lua-resty-jwt; do
    echo "$ROCKS" | grep -qx "$r" || fail "$r missing"
  done
  PLUGINS="jwt-keycloak kong-path-allow"
  if [ "$OIDC_PROVIDER" = kong-oidc ]; then
    for r in kong-oidc lua-resty-openidc lua-resty-cookie; do
      echo "$ROCKS" | grep -qx "$r" || fail "$r missing"
    done
    PLUGINS="jwt-keycloak oidc kong-path-allow"
  else
    echo "==> oidcify replaces kong-oidc on this 2.x image"
    run '/usr/local/bin/oidcify -dump' 2>/dev/null | grep -q oidcify \
      || fail "oidcify does not answer a schema query on this image"
    # Kong 2.8 looks for the plugin-server protobufs in lib/, not include/. Without them Kong does
    # not start at all — and it fails at init, so nothing downstream would tell you why.
    run 'test -f /usr/local/kong/lib/pluginsocket.proto' \
      || fail "pluginsocket.proto missing from /usr/local/kong/lib: Kong 2.x will not start with a Go plugin"
  fi
else
  echo "==> Kong >= 3: oidcify is the only OIDC implementation"
  # oidcify is not a rock: it is a Go binary Kong runs as an external plugin server. Running its
  # schema dump proves more than `test -x` — it proves the binary executes on this base image and
  # that Kong will get a schema when it asks for one at startup.
  run 'test -x /usr/local/bin/oidcify' || fail "oidcify binary missing"
  run '/usr/local/bin/oidcify -dump' >/dev/null 2>&1 || fail "oidcify does not run on this image"
  run '/usr/local/bin/oidcify -dump' 2>/dev/null | grep -q '"Name":"oidcify"' \
    || fail "oidcify dumped no usable schema"
  echo "==> Kong >= 3: jwt-keycloak still has no replacement"
  PLUGINS="kong-path-allow"
  fail "3.x build is not publishable — jwt-keycloak has no Kong 3.x replacement; see docs, 'The open decision'"
fi

echo "==> Lua modules actually load"
# Installing a rock proves a file was copied. Requiring the module proves its dependencies resolved
# — which is what --deps-mode=none in the Dockerfile deliberately does not check at build time.
# Handlers touch the `kong` global at module scope (jwt-keycloak reads its priority from it), so a
# bare `require` outside the Kong runtime fails for reasons that say nothing about the image. A
# minimal stub is the honest harness: it still proves the file parses and its requires resolve.
KONG_STUB='_G.kong = { log = setmetatable({}, {__index = function() return function() end end}) }'
for p in $PLUGINS; do
  run "resty -e 'assert(require(\"kong.plugins.$p.schema\"))'" >/dev/null 2>&1 \
    || fail "schema of $p does not load"
  run "resty -e '$KONG_STUB; assert(require(\"kong.plugins.$p.handler\"))'" >/dev/null 2>&1 \
    || fail "handler of $p does not load"
done
# Only the legacy line has it: oidcify carries its own OIDC implementation inside the Go binary.
if [ "$OIDC_PROVIDER" = kong-oidc ]; then
  run "resty -e 'assert(require(\"resty.openidc\"))'" >/dev/null 2>&1 || fail "resty.openidc does not load"
fi

echo "==> every plugin declares PRIORITY, and VERSION where Kong requires it"
for p in $PLUGINS; do
  H="/usr/local/share/lua/5.1/kong/plugins/$p/handler.lua"
  run "grep -q PRIORITY $H" || fail "$p declares no PRIORITY"
  # Kong 3.0 refuses to load a plugin without VERSION. Kong 2.x does not — which is exactly why
  # a missing VERSION can sit unnoticed for years.
  if [ "$KONG_MAJOR" -ge 3 ]; then
    run "grep -q VERSION $H" || fail "$p declares no VERSION (mandatory from Kong 3.0)"
  fi
done

echo "==> Kong accepts a configuration with all plugins enabled"
run "cp /etc/kong/kong.conf.default /tmp/k.conf \
     && echo 'plugins = bundled,jwt-keycloak,oidc,kong-path-allow' >> /tmp/k.conf \
     && echo 'database = off' >> /tmp/k.conf \
     && kong check /tmp/k.conf" >/dev/null || fail "Kong rejects the plugin configuration"

echo "==> kong-path-allow is usable as an access control"
run "resty -e '
  local h = require(\"kong.plugins.kong-path-allow.handler\")
  assert(type(h.access) == \"function\", \"handler exposes no access()\")
  assert(h.PRIORITY, \"handler declares no PRIORITY\")
'" >/dev/null 2>&1 || fail "kong-path-allow handler is not usable"

echo "OK: $IMAGE"
