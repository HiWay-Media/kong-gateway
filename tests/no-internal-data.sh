#!/usr/bin/env bash
# Refuses to let production details into a public build recipe.
#
# This repository is read by anyone. It also gets worked on by people — and agents — who have the
# infrastructure open in another window: a hostname, a database name or an IP is one paste away, and
# once pushed it is in the history whatever anyone does next. The rule is in AGENTS.md; a rule that
# depends on somebody remembering is a rule with an expiry date, so it is also a test.
#
# Two things it deliberately does not do: it cannot know every internal name, and it does not scan
# `reference/`, which is plugin source extracted from the replaced image and reviewed once when it
# arrived. It catches the shapes that leak in practice.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# The fixtures are deliberately fake and local-only: an identity provider nobody can reach, a user
# who exists for twelve seconds at a time, and keys published in this very file. Excluding them by
# name keeps the check honest about everything else.
ALLOW='kong-e2e-secret|kong-e2e-short-secret|alice-password|cookie_(hash|block)_key_hex|POSTGRES_PASSWORD|MARIADB_|admin / admin|KC_BOOTSTRAP_ADMIN|=admin$|127\.0\.0\.1|0\.0\.0\.0|hiway-media/kong-gateway|hiway-media\.github\.io'

# shape → what it would be
check() {
  local pattern="$1" what="$2" hits
  hits=$(git ls-files -z \
    | grep -zZv '^reference/' \
    | xargs -0 grep -nIE "$pattern" 2>/dev/null \
    | grep -vE "$ALLOW" \
    | grep -vE '^tests/no-internal-data\.sh:' \
    | head -5)
  if [ -z "$hits" ]; then
    ok "no $what"
  else
    bad "$what:"
    printf '%s\n' "$hits" | sed 's/^/         /'
  fi
}

echo "==> nothing here should name the infrastructure it runs on"

check '(^|[^0-9.])(10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}' "private IP addresses"
check '\b[a-z0-9-]+\.(internal|lan|intranet|corp)\b'                                "internal hostnames"
check '\b(kong|keycloak)_(sg|ov|cl|prod|dev)[a-z0-9_]*\b'                           "production database names"
check '\b(teamcity|gitlab)\.[a-z0-9.-]+'                                            "internal CI or SCM hosts"
check 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY'                                        "private keys"
check '(password|passwd|secret|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,}' "hardcoded credentials"

echo
if [ "$fails" -eq 0 ]; then
  echo "OK: no internal data"
  exit 0
fi
echo "RED: $fails leak(s) — remove it, and remember that rewriting history after a push is not a fix"
exit 1
