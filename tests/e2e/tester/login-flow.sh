#!/bin/sh
# The full authorization code flow, driven as a browser would: challenge, login form, callback,
# session cookie, authenticated request.
#
# Everything else in this suite asserts that an unauthenticated request is CHALLENGED — a 302 with
# the right Location. That proves the door is locked. It does not prove anyone can get in, and a
# gateway where nobody can log in is broken in a way every other test here would call healthy.
#
# It runs INSIDE the compose network because the whole flow depends on names agreeing: Keycloak
# issues tokens for http://keycloak:8080, Kong expects that issuer, and the callback has to come
# back to a URL both of them can reach. Driving it from the host would need /etc/hosts entries and
# would test a different set of URLs than the ones that are configured.
set -u

BASE="${1:?usage: login-flow.sh <kong-base-url> <path>}"
PATH_="${2:?}"
# -k: Kong serves a self-signed certificate in this stack. TLS is here because the session cookie
# is marked Secure — not to test certificate validation, which belongs to whatever terminates TLS
# in front of Kong in production.
CURL="curl -sk"
JAR=/tmp/cookies.txt
KC_JAR=/tmp/kc-cookies.txt
rm -f "$JAR" "$KC_JAR"

fail() { echo "FAIL: $1"; exit 1; }

echo "1. an unauthenticated request is challenged"
AUTH_URL=$($CURL -o /dev/null -c "$JAR" -w '%{redirect_url}' "$BASE$PATH_")
case "$AUTH_URL" in
  http://keycloak:8080/realms/kong/protocol/openid-connect/auth*) ;;
  "") fail "no challenge at all: the request was let through or died" ;;
  *)  fail "challenged towards an unexpected place: $AUTH_URL" ;;
esac

echo "2. the identity provider serves a login form"
FORM=$($CURL -c "$KC_JAR" "$AUTH_URL")
ACTION=$(printf '%s' "$FORM" | grep -o 'action="[^"]*"' | head -1 | cut -d'"' -f2 | sed 's/&amp;/\&/g')
[ -n "$ACTION" ] || fail "no login form in the provider's response"

echo "3. alice logs in"
CODE_URL=$($CURL -o /dev/null -b "$KC_JAR" -c "$KC_JAR" -w '%{redirect_url}' \
  --data-urlencode 'username=alice' --data-urlencode 'password=alice-password' \
  --data-urlencode 'credentialId=' "$ACTION")
case "$CODE_URL" in
  *code=*) ;;
  "") fail "the provider did not redirect back: the credentials were refused" ;;
  *)  fail "redirected back without an authorization code: $CODE_URL" ;;
esac

echo "4. the gateway exchanges the code and issues a session"
# Kong's callback answers with a redirect to the originally requested path, having set its session
# cookie. Following it here would hide whether the cookie is what carries the session.
CB=$($CURL -o /dev/null -b "$JAR" -c "$JAR" -w '%{http_code} %{redirect_url}' "$CODE_URL")
CB_CODE=${CB%% *}
case "$CB_CODE" in
  30[0-9]|200) ;;
  *) fail "the callback failed with HTTP $CB_CODE — the code exchange did not complete" ;;
esac
grep -qiE 'session|oidc' "$JAR" || fail "no session cookie was set: the next request would challenge again"

echo "5. the authenticated request reaches the upstream"
BODY=$($CURL -b "$JAR" -c "$JAR" -L "$BASE$PATH_")
case "$BODY" in
  *'"upstream":"reached"'*) ;;
  *) fail "the authenticated request did not reach the upstream: $(printf '%s' "$BODY" | head -c 120)" ;;
esac

echo "OK: the full login round trip works"
