#!/usr/bin/env bash
# Run the gateway locally and leave it running.
#
#   scripts/run-local.sh up [--db postgres] [--variant oidcify] [--kong 2.8.5]
#   scripts/run-local.sh status | logs [service] | token [access|id] | down
#
# The end-to-end suite starts the same stack, asserts against it and tears it down — which is right
# for a test and useless for looking at something. This brings it up and stays out of the way, so a
# route can be poked at by hand, a plugin's behaviour watched in the logs, or a configuration change
# tried before it becomes a commit.
#
# It shares tests/e2e/stack.sh with the suite on purpose: which declarative config, which plugin
# list and which storage mode belong together is decided in one place. A second copy would drift,
# and the first sign of it would be a test passing against a stack nobody else runs.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="$ROOT/tests/e2e"

ACTION="${1:-up}"; shift 2>/dev/null || true

# `logs kong` and `token access` take a positional after the action; everything else is an option.
# Parsing them in the option loop made the script reject the very commands it prints at the end,
# which is a special kind of useless.
SUBARG=""
case "${1:-}" in --*|"") ;; *) SUBARG="$1"; shift ;; esac

E2E_DB=off
VARIANT=""
KONG_VERSION=2.8.5
while [ $# -gt 0 ]; do
  case "$1" in
    --db)      E2E_DB="${2:?--db needs a value (postgres)}"; shift 2 ;;
    --variant) VARIANT="${2:?--variant needs a value (oidcify)}"; shift 2 ;;
    --kong)    KONG_VERSION="${2:?--kong needs a version}"; shift 2 ;;
    *) echo "unknown option '$1'" >&2; exit 2 ;;
  esac
done

IMAGE="kong-gateway:${KONG_VERSION}${VARIANT:+-$VARIANT}"
PROXY=http://127.0.0.1:18000
IDP=http://127.0.0.1:18080

compose() { docker compose -f "$STACK_DIR/docker-compose.yml" "$@"; }

case "$ACTION" in
  down)
    KONG_IMAGE="$IMAGE" COMPOSE_PROFILES=db compose down -v --remove-orphans
    exit 0 ;;
  logs)
    KONG_IMAGE="$IMAGE" compose logs -f "${SUBARG:-kong}"
    exit 0 ;;
  status)
    KONG_IMAGE="$IMAGE" compose ps
    exit 0 ;;
  token)
    # A real token from the realm, for pasting into curl. `id` is what oidcify validates by default;
    # `access` is what jwt-keycloak checks.
    field="${SUBARG:-access}_token"
    curl -s -X POST "$IDP/realms/kong/protocol/openid-connect/token" \
      -d grant_type=password -d client_id=kong-e2e -d client_secret=kong-e2e-secret \
      -d scope=openid -d username=alice -d password=alice-password \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('$field',''))"
    exit 0 ;;
  up) ;;
  *) echo "unknown action '$ACTION' (up, down, status, logs, token)" >&2; exit 2 ;;
esac

# Build on demand: asking someone to remember the two build arguments before they can look at
# anything is how a local-run script goes unused.
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "==> $IMAGE is not here yet, building it"
  docker build ${DOCKER_PLATFORM:+--platform $DOCKER_PLATFORM} \
    --build-arg "KONG_VERSION=$KONG_VERSION" ${VARIANT:+--build-arg "OIDC_PROVIDER=$VARIANT"} \
    -t "$IMAGE" "$ROOT" || { echo "FAIL: the build failed"; exit 1; }
fi

# shellcheck source=tests/e2e/stack.sh
. "$STACK_DIR/stack.sh"

echo "==> starting $IMAGE (Kong $KONG_MAJOR.x, OIDC: $OIDC_PROVIDER, storage: $E2E_DB)"
stack_reject_unsupported || exit 1
stack_prepare_db || { echo "FAIL: Postgres did not start, or the migrations failed"; exit 1; }
stack_up || { echo "FAIL: the stack did not start"; exit 1; }
stack_load_config || { echo "FAIL: decK could not load the configuration"; exit 1; }
stack_wait_for "$IDP/realms/kong/.well-known/openid-configuration" "Keycloak" || exit 1
stack_wait_for "$PROXY/open/allowed" "Kong proxy" || exit 1

ROUTES="/open/allowed and /open/secret (kong-path-allow), /oidc (browser flow)"
[ "$KONG_MAJOR" -ge 3 ] && ROUTES="$ROUTES, /api and /api-access (oidcify)" \
                        || ROUTES="$ROUTES, /jwt (jwt-keycloak)"
[ "$OIDC_PROVIDER" = oidcify ] && [ "$KONG_MAJOR" -lt 3 ] && ROUTES="$ROUTES, /api (oidcify)"

cat <<MSG

  It is up. Nothing here tears it down — run 'scripts/run-local.sh down' when you are finished.

  Proxy      $PROXY        Keycloak  $IDP  (admin / admin)
  Routes     $ROUTES
  User       alice / alice-password, realm 'kong'

  Try the thing that matters — a path outside the allow-list must be refused:

    curl -i $PROXY/open/allowed      # 200, reaches the upstream
    curl -i $PROXY/open/secret       # 403, kong-path-allow refuses it

  With a real token:

    TOKEN=\$(scripts/run-local.sh token access)
    curl -i -H "Authorization: Bearer \$TOKEN" $PROXY/jwt/anything

  Watch it decide:   scripts/run-local.sh logs kong

MSG
