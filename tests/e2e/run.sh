#!/usr/bin/env bash
# End-to-end test of the whole system: Keycloak issuing real tokens, an upstream to protect, and the
# image under test proxying between them.
#
#   ./tests/e2e/run.sh <image> [kong-version]
#
# tests/smoke.sh proves the plugins load; this proves they DECIDE. Most of what follows asserts a
# refusal, because that is the half that cannot be checked by looking at a running gateway: an
# authorization plugin that has stopped blocking looks exactly like one that is working.
set -uo pipefail

IMAGE="${1:?usage: run.sh <image> [kong-version]}"
KONG_VERSION="${2:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROXY=http://127.0.0.1:18000
IDP=http://127.0.0.1:18080
ISSUER=http://keycloak:8080/realms/kong

export KONG_IMAGE="$IMAGE"
export KONG_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"

compose() { docker compose -f "$HERE/docker-compose.yml" "$@"; }

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

cleanup() {
  local rc=$?
  if [ "$fails" -gt 0 ] || [ "$rc" -ne 0 ]; then
    echo
    echo "---- kong logs (last 40 lines) ----"
    compose logs --no-color --tail 40 kong 2>&1 | sed 's/^/  /'
  fi
  compose down -v --remove-orphans >/dev/null 2>&1
}
trap cleanup EXIT

# Wait for a URL to answer, rather than sleeping a guessed number of seconds: Kong under emulation
# and Keycloak importing a realm take wildly different times on different machines.
wait_for() {
  local url="$1" what="$2" tries="${3:-90}"
  for _ in $(seq 1 "$tries"); do
    curl -fsS -o /dev/null "$url" 2>/dev/null && { echo "==> $what is up"; return 0; }
    sleep 2
  done
  echo "FAIL: $what never became ready at $url" >&2
  return 1
}

# expects <description> <status> <curl args...>
expects() {
  local desc="$1" want="$2"; shift 2
  local got
  got=$(curl -s -o /dev/null -w '%{http_code}' "$@")
  [ "$got" = "$want" ] && ok "$desc (HTTP $got)" || bad "$desc — expected HTTP $want, got $got"
}

echo "==> starting the stack with $IMAGE"
compose up -d --quiet-pull >/dev/null || { echo "FAIL: the stack did not start"; exit 1; }

wait_for "$IDP/realms/kong/.well-known/openid-configuration" "Keycloak realm" || exit 1
wait_for "$PROXY/open/allowed" "Kong proxy" || exit 1

echo
echo "==> kong-path-allow decides which paths exist at all"
expects "an allowed path reaches the upstream" 200 "$PROXY/open/allowed"
# The one that matters. If this ever returns 200, the allow-list has become decoration and every
# other test in this file would still pass.
expects "a path outside the allow-list is REFUSED" 403 "$PROXY/open/secret"
expects "a path that merely starts like an allowed one is still checked" 403 "$PROXY/open/other"

echo
echo "==> the upstream is actually behind Kong, not being answered by it"
if curl -fsS "$PROXY/open/allowed" | grep -q '"upstream":"reached"'; then
  ok "the 200 came from the upstream"
else
  bad "the 200 did not come from the upstream — Kong answered on its own"
fi

echo
echo "==> jwt-keycloak refuses before it accepts"
expects "no token is refused" 401 "$PROXY/jwt/anything"
expects "a malformed token is refused" 401 -H 'Authorization: Bearer not-a-jwt' "$PROXY/jwt/anything"
# Correctly formed, signed by nobody: this is the case a plugin that only parses would let through.
FORGED='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwOi8va2V5Y2xvYWs6ODA4MC9yZWFsbXMva29uZyIsImV4cCI6NDEwMjQ0NDgwMH0.bm90LWEtc2lnbmF0dXJl'
expects "a well-formed token with an invalid signature is refused" 401 \
  -H "Authorization: Bearer $FORGED" "$PROXY/jwt/anything"

TOKEN=$(curl -s -X POST "$IDP/realms/kong/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=kong-e2e -d client_secret=kong-e2e-secret \
  -d username=alice -d password=alice-password \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)

if [ -z "$TOKEN" ]; then
  bad "Keycloak issued no token — the realm import or the client is wrong"
else
  ok "Keycloak issued a token for alice"
  expects "a real token from the realm is accepted" 200 \
    -H "Authorization: Bearer $TOKEN" "$PROXY/jwt/anything"
fi

echo
echo "==> oidc starts an authorization code flow instead of passing the request through"
LOCATION=$(curl -s -o /dev/null -w '%{redirect_url}' "$PROXY/oidc/anything")
case "$LOCATION" in
  "$ISSUER"/protocol/openid-connect/auth*|http://keycloak:8080/realms/kong/protocol/openid-connect/auth*)
    ok "an unauthenticated request is redirected to the identity provider" ;;
  "") bad "no redirect: the request was not challenged at all" ;;
  *)  bad "redirected somewhere unexpected: $LOCATION" ;;
esac

echo
if [ "$fails" -eq 0 ]; then
  echo "OK: end-to-end${KONG_VERSION:+ (Kong $KONG_VERSION)} — $IMAGE"
  exit 0
fi
echo "RED: $fails end-to-end check(s) failed"
exit 1
