#!/usr/bin/env bash
# How this stack is wired, in one place.
#
# Two things start it: the end-to-end suite, which asserts against it and tears it down, and
# scripts/run-local.sh, which leaves it up for someone to poke at. They must agree on which
# declarative config, which plugin list and which storage mode go together — a second copy of that
# mapping would drift, and the first sign would be a test passing against a stack nobody else runs.
#
# Sourced, not executed. The caller sets IMAGE, KONG_VERSION and E2E_DB first.

KONG_MAJOR="${KONG_VERSION%%.*}"
KONG_MAJOR="${KONG_MAJOR:-2}"

export KONG_IMAGE="$IMAGE"
export KONG_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"

# Which OIDC implementation this image carries, asked of the image rather than passed in: a test
# that is TOLD what to expect cannot notice that the build produced something else.
OIDC_PROVIDER=$(docker run --rm ${DOCKER_PLATFORM:+--platform $DOCKER_PLATFORM} \
  --entrypoint sh "$IMAGE" -c 'cat /usr/local/share/kong-gateway-oidc-provider 2>/dev/null' \
  2>/dev/null | tr -d '\r\n')
OIDC_PROVIDER="${OIDC_PROVIDER:-kong-oidc}"

# The two lines are not the same system, and the test says so out loud rather than papering over it.
# 2.x runs the Lua oidc and jwt-keycloak plugins; 3.x runs oidcify, a Go binary Kong starts as an
# external plugin server, and has no jwt-keycloak at all.
if [ "$OIDC_PROVIDER" = oidcify ] && [ "$KONG_MAJOR" -lt 3 ]; then
  # The variant: production's Kong and production's jwt-keycloak, with the dead OIDC plugin
  # replaced. One change under test, not two.
  export KONG_CONFIG=./kong/kong.2x-oidcify.yml
  export KONG_PLUGINS_LIST=bundled,jwt-keycloak,oidcify,kong-path-allow
  export KONG_PLUGINSERVER_NAMES=oidcify
  export KONG_PLUGINSERVER_OIDCIFY_QUERY_CMD="/usr/local/bin/oidcify -dump"
  export KONG_PLUGINSERVER_OIDCIFY_START_CMD="/usr/local/bin/oidcify"
elif [ "$KONG_MAJOR" -ge 3 ]; then
  export KONG_CONFIG=./kong/kong.3x.yml
  export KONG_PLUGINS_LIST=bundled,oidcify,kong-path-allow
  export KONG_PLUGINSERVER_NAMES=oidcify
  export KONG_PLUGINSERVER_OIDCIFY_QUERY_CMD="/usr/local/bin/oidcify -dump"
  export KONG_PLUGINSERVER_OIDCIFY_START_CMD="/usr/local/bin/oidcify"
else
  export KONG_CONFIG=./kong/kong.yml
  export KONG_PLUGINS_LIST=bundled,jwt-keycloak,oidc,kong-path-allow
  # Explicitly unset, not set to empty: Kong reads an empty KONG_PLUGINSERVER_* as the boolean true
  # and then refuses to start. Inherited from an earlier shell, these would break the 2.x line.
  unset KONG_PLUGINSERVER_NAMES KONG_PLUGINSERVER_OIDCIFY_QUERY_CMD KONG_PLUGINSERVER_OIDCIFY_START_CMD
fi


if [ "$E2E_DB" = off ]; then
  export KONG_DECLARATIVE_CONFIG=/kong/kong.yml
else
  export COMPOSE_PROFILES=db
  # Kong: Postgres in both modes, because it has no other option.
  export KONG_DB_MODE=postgres KONG_PG_HOST=postgres KONG_PG_USER=kong KONG_PG_PASSWORD=kong
  export KONG_ADMIN_LISTEN_ADDR=0.0.0.0:8001
  unset KONG_DECLARATIVE_CONFIG
  export KC_DB=postgres KC_DB_URL_HOST=postgres KC_DB_URL_DATABASE=keycloak \
         KC_DB_USERNAME=kong KC_DB_PASSWORD=kong
fi


# Kong 3.x with an external plugin cannot be configured through its Admin API at all, so a stack
# that combines the two cannot be brought up in a usable state. Better to refuse with the reason
# than to produce a confusing failure two steps later.
stack_reject_unsupported() {
  [ "$E2E_DB" = off ] && return 0
  [ "$KONG_MAJOR" -ge 3 ] && [ "$OIDC_PROVIDER" = oidcify ] || return 0
  cat >&2 <<'MSG'
FAIL: Kong 3.x with an external plugin cannot be configured through its Admin API.
      GET / answers 500 — 'Cannot serialise cdata: type not supported' — because the schema the
      plugin server returns contains a value Kong cannot encode, and decK reads that endpoint
      first. Kong 2.8.5 with the same plugin answers 200; DB-less 3.x works too.
      See docs/end-to-end.md, 'Storage modes'. Run this combination without --db.
MSG
  return 1
}

# --force-recreate, because a bind-mounted config file changing does not make compose replace a
# running container: a stack left over from an earlier run would be reused, serving the previous
# declarative config while the caller reports on the current one. That produced a confident, wrong
# red once already.
stack_up() {
  compose up -d --quiet-pull --force-recreate upstream keycloak kong >/dev/null
}

compose() { docker compose -f "$STACK_DIR/docker-compose.yml" "$@"; }

# Brings up the databases and loads the configuration when a database is in use. Kong reads a
# declarative file in DB-less mode and knows nothing of it otherwise, so the configuration has to
# arrive over the Admin API — decK does that, from the same file, so the two modes cannot drift.
stack_prepare_db() {
  [ "$E2E_DB" = off ] && return 0
  echo "==> bringing up Postgres and running Kong's migrations"
  compose up -d --quiet-pull --wait postgres >/dev/null || return 1
  compose run --rm -T kong-migrations >/dev/null || return 1
}

stack_load_config() {
  [ "$E2E_DB" = off ] && return 0
  echo "==> loading the configuration into Kong with decK"
  compose run --rm -T deck \
    'for i in $(seq 1 40); do deck gateway ping --kong-addr http://kong:8001 >/dev/null 2>&1 && break; sleep 2; done
     deck gateway sync /kong/kong.yml --kong-addr http://kong:8001' >/dev/null
}

# Waits for a URL to answer rather than sleeping a guessed number of seconds: Kong under emulation
# and Keycloak importing a realm take wildly different times on different machines.
stack_wait_for() {
  local url="$1" what="$2" tries="${3:-90}"
  for _ in $(seq 1 "$tries"); do
    curl -fsS -o /dev/null "$url" 2>/dev/null && { echo "==> $what is up"; return 0; }
    sleep 2
  done
  echo "FAIL: $what never became ready at $url" >&2
  return 1
}
