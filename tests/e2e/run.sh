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

# --db runs the stack on real databases instead of DB-less Kong and Keycloak's dev file store. It
# is a different system, not a detail: DB-less Kong is configured by a declarative file and exposes
# no Admin API, while a Postgres Kong is configured through migrations and an imported config.
#
#   --db postgres   Kong and Keycloak both on Postgres, as in production.
#
# Postgres is not a preference for Kong: `kong.conf` accepts `postgres` and `off` and nothing else
# (2.8 also listed Cassandra, removed in 3.4).
E2E_DB=off
if [ "${1:-}" = "--db" ]; then E2E_DB="${2:?usage: run.sh [--db postgres] <image> [kong-version]}"; shift 2; fi
case "$E2E_DB" in
  off|postgres) ;;
  *) echo "unknown --db value '$E2E_DB' (use postgres)" >&2; exit 2 ;;
esac

IMAGE="${1:?usage: run.sh [--db postgres] <image> [kong-version]}"
KONG_VERSION="${2:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROXY=http://127.0.0.1:18000
IDP=http://127.0.0.1:18080
ISSUER=http://keycloak:8080/realms/kong

STACK_DIR="$HERE"
# shellcheck source=tests/e2e/stack.sh
. "$HERE/stack.sh"

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

cleanup() {
  local rc=$?
  if [ "$fails" -gt 0 ] || [ "$rc" -ne 0 ]; then
    echo
    echo "---- kong logs (last 30 lines) ----"
    compose logs --no-color --tail 30 kong 2>&1 | sed 's/^/  /'
    # Keycloak too: when it is the one that failed to start, kong's logs say nothing about it —
    # which is exactly how an empty KC_DB stayed invisible through a whole release.
    echo "---- keycloak logs (last 15 lines) ----"
    compose logs --no-color --tail 15 keycloak 2>&1 | sed 's/^/  /'
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

# Asks Keycloak for tokens as alice. <field> is access_token or id_token: oidcify validates the ID
# token, jwt-keycloak the access token, and sending the wrong one is an easy way to spend an hour.
token_for() {
  curl -s -X POST "$IDP/realms/kong/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=kong-e2e -d client_secret=kong-e2e-secret \
    -d scope=openid -d username=alice -d password=alice-password \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null
}

# A token from the short-lived client: its access tokens last one second, which is the only way to
# test expiry without waiting out a realm's normal lifespan. Kong caches realm keys, not tokens, so
# nothing else in the suite is affected.
short_lived_token() {
  curl -s -X POST "$IDP/realms/kong/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=kong-e2e-short -d client_secret=kong-e2e-short-secret \
    -d scope=openid -d username=alice -d password=alice-password \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null
}

# expects <description> <status> <curl args...>
expects() {
  local desc="$1" want="$2"; shift 2
  local got
  got=$(curl -s -o /dev/null -w '%{http_code}' "$@")
  [ "$got" = "$want" ] && ok "$desc (HTTP $got)" || bad "$desc — expected HTTP $want, got $got"
}

# The full round trip, run from inside the network by a container with curl. Everything else here
# proves the door is locked; this proves it opens for someone who has the key.
assert_login_round_trip() {
  local path="${1:-/oidc/anything}" out
  echo
  echo "==> the whole authorization code flow, driven as a browser"
  if out=$(compose run --rm -T tester /t/login-flow.sh https://kong:8443 "$path" 2>&1); then
    printf '%s\n' "$out" | sed 's/^/       /'
    ok "a user can actually log in and reach the upstream"
  else
    printf '%s\n' "$out" | sed 's/^/       /'
    bad "the login round trip failed — see the steps above"
  fi
}

assert_oidcify() {
  # oidcify is an external plugin server: Kong starts the Go process lazily, on the first request
  # that touches the plugin, and requests arriving before its socket exists get a 500. That is a
  # real operational property of this plugin model, not a flake — it is waited out here and written
  # down in the docs, rather than hidden behind a retry.
  echo
  echo "==> waiting for the oidcify plugin server to come up (cold start)"
  for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$PROXY/api/anything")
    [ "$code" = "500" ] || break
    sleep 1
  done
  [ "$code" = "500" ] && bad "the oidcify plugin server never came up" \
                      || ok "the plugin server answered after $code on a credential-less request"

  echo
  echo "==> oidcify refuses before it accepts (API route: refusals, not redirects)"
  expects "no token is refused" 401 "$PROXY/api/anything"
  expects "a malformed bearer token is refused" 401 \
    -H 'Authorization: Bearer not-a-jwt' "$PROXY/api/anything"
  FORGED='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwOi8va2V5Y2xvYWs6ODA4MC9yZWFsbXMva29uZyIsImF1ZCI6ImtvbmctZTJlIiwiZXhwIjo0MTAyNDQ0ODAwfQ.bm90LWEtc2lnbmF0dXJl'
  expects "a well-formed bearer token with an invalid signature is refused" 401 \
    -H "Authorization: Bearer $FORGED" "$PROXY/api/anything"

  # The access token is genuine and signed by the realm, but carries a different audience than the
  # ID token. An audience check that never refuses anything is not a check.
  ACCESS=$(token_for access_token)
  if [ -n "$ACCESS" ]; then
    expects "a genuine token with the wrong audience is refused" 401 \
      -H "Authorization: Bearer $ACCESS" "$PROXY/api/anything"
  else
    bad "Keycloak issued no access token"
  fi

  ID_TOKEN=$(token_for id_token)
  if [ -z "$ID_TOKEN" ]; then
    bad "Keycloak issued no ID token — the client may not have the openid scope"
  else
    ok "Keycloak issued an ID token for alice"
    expects "a real ID token from the realm is accepted" 200 \
      -H "Authorization: Bearer $ID_TOKEN" "$PROXY/api/anything"
    if curl -fsS -H "Authorization: Bearer $ID_TOKEN" "$PROXY/api/anything" | grep -q '"upstream":"reached"'; then
      ok "the authenticated request reached the upstream"
    else
      bad "the authenticated request did not reach the upstream"
    fi
  fi

  # Only the 3.x config carries this route: it is the measurement behind M3b. On the 2.x variant
  # jwt-keycloak is still installed, so the question does not arise there.
  if [ "$KONG_MAJOR" -ge 3 ]; then
    echo
    echo "==> oidcify also validates ACCESS tokens — what jwt-keycloak does on the 2.x line"
    expects "no token is refused" 401 "$PROXY/api-access/x"
    expects "a malformed token is refused" 401 \
      -H 'Authorization: Bearer not-a-jwt' "$PROXY/api-access/x"
    FORGED_ACC='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwOi8va2V5Y2xvYWs6ODA4MC9yZWFsbXMva29uZyIsImF1ZCI6ImFjY291bnQiLCJleHAiOjQxMDI0NDQ4MDB9.bm90LWEtc2lnbmF0dXJl'
    expects "an invalid signature is refused" 401 \
      -H "Authorization: Bearer $FORGED_ACC" "$PROXY/api-access/x"
    ACC=$(token_for access_token)
    ID_FOR_ACC=$(token_for id_token)
    if [ -n "$ACC" ] && [ -n "$ID_FOR_ACC" ]; then
      expects "a real access token from the realm is accepted" 200 \
        -H "Authorization: Bearer $ACC" "$PROXY/api-access/x"
      # The audiences are not interchangeable, and a route that accepted both would be checking
      # nothing: the ID token carries the client as its audience, not `account`.
      expects "an ID token is refused on the access-token route" 401 \
        -H "Authorization: Bearer $ID_FOR_ACC" "$PROXY/api-access/x"
    else
      bad "Keycloak issued no tokens for the access-token checks"
    fi
  fi

  if [ "$KONG_MAJOR" -ge 3 ]; then
    echo
    echo "==> an expired token is refused"
    EXPIRING_ACC=$(short_lived_token access_token)
    if [ -z "$EXPIRING_ACC" ]; then
      bad "the short-lived client issued no token"
    else
      expects "…and it works while it is valid" 200 \
        -H "Authorization: Bearer $EXPIRING_ACC" "$PROXY/api-access/x"
      sleep 3
      expects "once expired, the same token is refused" 401 \
        -H "Authorization: Bearer $EXPIRING_ACC" "$PROXY/api-access/x"
    fi

    echo
    echo "==> authorization by group: oidcify feeds Kong's ACL plugin, in both directions"
    # This is the half of jwt-keycloak that oidcify does NOT replicate — it puts the token's groups
    # into authenticated_groups and lets the bundled ACL plugin decide. If M3b closes by
    # consolidating, this is the mechanism it would close on, so it is worth proving rather than
    # assuming.
    GROUP_TOKEN=$(token_for id_token)
    if [ -z "$GROUP_TOKEN" ]; then
      bad "Keycloak issued no ID token for the group checks"
    else
      expects "a group alice belongs to lets her through" 200 \
        -H "Authorization: Bearer $GROUP_TOKEN" "$PROXY/group-ok/x"
      expects "a group she does not belong to refuses her" 403 \
        -H "Authorization: Bearer $GROUP_TOKEN" "$PROXY/group-no/x"
    fi
  fi

  echo
  echo "==> on the browser route, a request with no credentials starts the authorization code flow"
  LOCATION=$(curl -s -o /dev/null -w '%{redirect_url}' "$PROXY/oidc/anything")
  case "$LOCATION" in
    "$ISSUER"/protocol/openid-connect/auth*) ok "an unauthenticated request is redirected to the identity provider" ;;
    "") bad "no redirect: the request was not challenged at all" ;;
    *)  bad "redirected somewhere unexpected: $LOCATION" ;;
  esac

  assert_login_round_trip
}

echo "==> starting the stack with $IMAGE (Kong $KONG_MAJOR.x, OIDC: $OIDC_PROVIDER, storage: $E2E_DB)"

stack_prepare_db || { echo "FAIL: Postgres did not start, or the migrations failed"; exit 1; }

stack_up || { echo "FAIL: the stack did not start"; exit 1; }

stack_reject_unsupported || exit 1

stack_load_config || { echo "FAIL: decK could not load the configuration"; exit 1; }

wait_for "$IDP/realms/kong/.well-known/openid-configuration" "Keycloak realm" || exit 1
wait_for "$PROXY/open/allowed" "Kong proxy" || exit 1

if [ "$E2E_DB" != off ]; then
  echo
  echo "==> both databases are actually being used, not silently bypassed"
  # Without this, a mode that quietly fell back — Kong to DB-less, Keycloak to its dev file store —
  # would pass every assertion below and prove nothing about running on a database.
  routes=$(compose exec -T postgres psql -U kong -d kong -tAc \
    'select count(*) from routes' 2>/dev/null | tr -d ' \r')
  case "${routes:-0}" in
    ''|0) bad "Kong's routes table is empty: the config import did not reach Postgres" ;;
    *)    ok "Kong reads its routes from Postgres ($routes of them)" ;;
  esac
  realms=$(compose exec -T postgres psql -U kong -d keycloak -tAc \
    "select count(*) from realm where name = 'kong'" 2>/dev/null | tr -d ' \r')
  case "${realms:-0}" in
    ''|0) bad "the kong realm is not in Postgres: Keycloak fell back to its dev store" ;;
    *)    ok "Keycloak stores the realm in Postgres" ;;
  esac
fi

echo
echo "==> kong-path-allow decides which paths exist at all"
expects "an allowed path reaches the upstream" 200 "$PROXY/open/allowed"
# The one that matters. If this ever returns 200, the allow-list has become decoration and every
# other test in this file would still pass.
expects "a path outside the allow-list is REFUSED" 403 "$PROXY/open/secret"
expects "a path that merely starts like an allowed one is still checked" 403 "$PROXY/open/other"

echo
echo "==> how kong-path-allow actually matches, not how it reads"
# The plugin anchors the start of the match and leaves the end open. `/public` therefore also
# permits `/publicsecret` — for a deny list that errs safe, for an ALLOW list it errs the other way.
# Asserted rather than described, so a change in that behaviour shows up here instead of quietly
# widening an allow-list somebody wrote years ago.
expects "an allowed prefix passes" 200 "$PROXY/anchor/public"
expects "a longer path with that prefix ALSO passes — the end is not anchored" 200 \
  "$PROXY/anchor/publicsecret"
expects "an explicitly anchored pattern refuses the longer path" 403 "$PROXY/anchor/exactly"
expects "…and still allows the exact one" 200 "$PROXY/anchor/exact"

echo
echo "==> the upstream is actually behind Kong, not being answered by it"
if curl -fsS "$PROXY/open/allowed" | grep -q '"upstream":"reached"'; then
  ok "the 200 came from the upstream"
else
  bad "the 200 did not come from the upstream — Kong answered on its own"
fi

if [ "$KONG_MAJOR" -lt 3 ]; then
  echo
  echo "==> jwt-keycloak refuses before it accepts"
  expects "no token is refused" 401 "$PROXY/jwt/anything"
  expects "a malformed token is refused" 401 -H 'Authorization: Bearer not-a-jwt' "$PROXY/jwt/anything"
  # Correctly formed, signed by nobody: this is the case a plugin that only parses would let through.
  FORGED='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwOi8va2V5Y2xvYWs6ODA4MC9yZWFsbXMva29uZyIsImV4cCI6NDEwMjQ0NDgwMH0.bm90LWEtc2lnbmF0dXJl'
  expects "a well-formed token with an invalid signature is refused" 401 \
    -H "Authorization: Bearer $FORGED" "$PROXY/jwt/anything"

  TOKEN=$(token_for access_token)
  if [ -z "$TOKEN" ]; then
    bad "Keycloak issued no token — the realm import or the client is wrong"
  else
    ok "Keycloak issued a token for alice"
    expects "a real token from the realm is accepted" 200 \
      -H "Authorization: Bearer $TOKEN" "$PROXY/jwt/anything"
  fi

  echo
  echo "==> an expired token is refused"
  # Signed by the realm, well formed, correct issuer — and past its expiry. A plugin that verifies
  # the signature but forgets `exp` passes every other check in this file.
  EXPIRING=$(short_lived_token access_token)
  if [ -z "$EXPIRING" ]; then
    bad "the short-lived client issued no token"
  else
    expects "…and it works while it is valid" 200 \
      -H "Authorization: Bearer $EXPIRING" "$PROXY/jwt/anything"
    sleep 3
    expects "once expired, the same token is refused" 401 \
      -H "Authorization: Bearer $EXPIRING" "$PROXY/jwt/anything"
  fi

  echo
  echo "==> jwt-keycloak enforces realm roles, in both directions"
  if [ -n "$TOKEN" ]; then
    expects "a role alice holds lets her through" 200 \
      -H "Authorization: Bearer $TOKEN" "$PROXY/role-ok/x"
    expects "a role nobody holds refuses her" 403 \
      -H "Authorization: Bearer $TOKEN" "$PROXY/role-no/x"
  fi

  if [ "$OIDC_PROVIDER" = oidcify ]; then
    assert_oidcify
  else
    echo
    echo "==> oidc starts an authorization code flow instead of passing the request through"
    LOCATION=$(curl -s -o /dev/null -w '%{redirect_url}' "$PROXY/oidc/anything")
    case "$LOCATION" in
      "$ISSUER"/protocol/openid-connect/auth*) ok "an unauthenticated request is redirected to the identity provider" ;;
      "") bad "no redirect: the request was not challenged at all" ;;
      *)  bad "redirected somewhere unexpected: $LOCATION" ;;
    esac
    assert_login_round_trip
  fi
else
  assert_oidcify
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "OK: end-to-end${KONG_VERSION:+ (Kong $KONG_VERSION)}, storage $E2E_DB — $IMAGE"
  exit 0
fi
echo "RED: $fails end-to-end check(s) failed"
exit 1
