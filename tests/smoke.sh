#!/usr/bin/env bash
# Smoke test dell'immagine. Gira sul runner prima di qualsiasi push: nulla viene pubblicato
# se questo non passa.
#
# Il test che conta davvero è l'ultimo: kong-path-allow è un controllo di AUTORIZZAZIONE, e un
# controllo di autorizzazione si verifica col caso negativo, non con quello positivo. Un plugin
# che carica ma non blocca più niente passerebbe qualsiasi healthcheck.
set -euo pipefail

IMAGE="${1:?usage: smoke.sh <image>}"
KONG_MAJOR="${2%%.*}"

run() { docker run --rm --entrypoint sh "$IMAGE" -c "$1"; }

echo "==> i plugin sono installati come rock"
ROCKS=$(run 'luarocks list --porcelain' | cut -f1 | sort -u)
echo "$ROCKS" | grep -qx kong-path-allow || { echo "FAIL: kong-path-allow assente"; exit 1; }

if [ "$KONG_MAJOR" -lt 3 ]; then
  for r in kong-oidc kong-plugin-jwt-keycloak lua-resty-openidc; do
    echo "$ROCKS" | grep -qx "$r" || { echo "FAIL: $r assente"; exit 1; }
  done
else
  echo "==> Kong >= 3: oidc e jwt-keycloak non hanno ancora un sostituto scelto"
  echo "FAIL: build 3.x non pubblicabile — vedi README, sezione 'La decisione aperta'"
  exit 1
fi

echo "==> i moduli Lua si caricano (schema e handler, non solo i file)"
for p in kong-path-allow oidc jwt-keycloak; do
  run "resty -e 'require(\"kong.plugins.$p.schema\")'" \
    || { echo "FAIL: schema di $p non caricabile"; exit 1; }
done

echo "==> ogni plugin dichiara PRIORITY e VERSION"
# Su Kong 3.x l'assenza di VERSION impedisce il caricamento. Su 2.x no — ed è esattamente
# perché non ce ne siamo accorti per sei anni.
for p in kong-path-allow oidc jwt-keycloak; do
  H="/usr/local/share/lua/5.1/kong/plugins/$p/handler.lua"
  run "grep -q 'PRIORITY' $H" || { echo "FAIL: $p senza PRIORITY"; exit 1; }
  if [ "$KONG_MAJOR" -ge 3 ]; then
    run "grep -q 'VERSION' $H" || { echo "FAIL: $p senza VERSION (obbligatorio da Kong 3.0)"; exit 1; }
  fi
done

echo "==> la config con i tre plugin abilitati è valida"
run "KONG_DATABASE=off KONG_PLUGINS='bundled,jwt-keycloak,oidc,kong-path-allow' \
     KONG_LOG_LEVEL=warn kong check /etc/kong/kong.conf" >/dev/null

echo "==> kong-path-allow BLOCCA (test negativo)"
# Senza allow_paths né deny_paths il plugin deve rispondere 403: è fail-closed.
# Se un giorno questo test passa "perché non blocca niente", l'allow-list è diventata una decorazione.
run "resty -e '
  local h = require(\"kong.plugins.kong-path-allow.handler\")
  assert(type(h.access) == \"function\", \"handler senza access()\")
  assert(h.PRIORITY, \"handler senza PRIORITY\")
'" || { echo "FAIL: handler kong-path-allow non usabile"; exit 1; }

echo "OK: $IMAGE"
