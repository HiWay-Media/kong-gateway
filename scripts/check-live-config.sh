#!/usr/bin/env bash
# Answers the two questions blocking M1 and M3b, against a running Kong.
#
#   scripts/check-live-config.sh http://<kong-admin-host>:8001
#   scripts/check-live-config.sh path/to/kong-export.json
#
# The image this repository builds installs the plugins from their upstream rocks. The image it
# replaces carried LOCALLY MODIFIED copies, which accept configuration fields upstream does not
# have. A route using one of those fields does not degrade — Kong refuses the configuration
# outright. This says whether any route does, before a rollout finds out.
#
# It also reports whether jwt-keycloak's authorization validators are in use, which is what decides
# whether the Kong 3.x line needs a replacement plugin at all.
#
# Read-only: it performs GET requests and writes nothing.
set -uo pipefail

TARGET="${1:?usage: check-live-config.sh <kong-admin-url|export.json>}"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

if [ -f "$TARGET" ]; then
  cp "$TARGET" "$WORK/plugins.json"
  SOURCE="file $TARGET"
else
  # The Admin API pages at 100 by default; ask for more and follow `next` until it runs out, or a
  # large estate reports on its first hundred plugins and calls it a survey.
  : >"$WORK/plugins.json"
  url="${TARGET%/}/plugins?size=1000"
  while [ -n "$url" ]; do
    body=$(curl -fsS "$url") || { echo "FAIL: cannot read $url" >&2; exit 1; }
    printf '%s\n' "$body" >>"$WORK/plugins.json"
    url=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("next") or "")')
  done
  SOURCE="$TARGET"
fi

echo "==> reading plugin configuration from $SOURCE"

python3 - "$WORK/plugins.json" <<'PY'
import json, sys, collections

# Fields only the modified plugins accept. A configuration using one of them is rejected by an image
# built from the upstream rocks — Kong refuses to load it, so this is a boot failure, not a
# behaviour change.
MODIFIED_ONLY = {
    "jwt-keycloak": ["internal_request_headers", "redirect_after_authentication_failed_uri"],
    "oidc": ["timeout"],
}
# jwt-keycloak's authorization half. oidcify does not replicate these; it feeds Kong's ACL plugin
# instead. Whether any route uses them decides whether the 3.x line needs a second plugin at all.
AUTHZ = ["roles", "realm_roles", "client_roles", "scope", "consumer_match"]

# One file may hold a single document (an export someone saved) or several concatenated ones (the
# paging loop above, one per page). Splitting on newlines handled only the second, and broke on the
# first the moment anyone pretty-printed it — so decode documents in sequence instead.
raw = open(sys.argv[1]).read().strip()
docs, decoder, idx = [], json.JSONDecoder(), 0
while idx < len(raw):
    while idx < len(raw) and raw[idx].isspace():
        idx += 1
    if idx >= len(raw):
        break
    doc, idx = decoder.raw_decode(raw, idx)
    docs.append(doc)

# Three shapes reach this: the Admin API's {"data": [...]}, a decK export, and the bare list that
# scripts/dump-config.sh writes. The last one was not handled, and the two scripts in this
# repository that are meant to be used together did not fit each other.
plugins = []
for d in docs:
    if isinstance(d, list):
        plugins.extend(d)
    elif isinstance(d, dict):
        plugins.extend(d.get("data", []))

if not plugins:
    print("  no plugins found — is this the right Kong, and does it have any configured?")
    sys.exit(2)

counts = collections.Counter(p.get("name") for p in plugins)
print(f"  {len(plugins)} plugin instances: " + ", ".join(f"{n}×{c}" for n, c in counts.most_common()))

blocking, authz_used = [], []
for p in plugins:
    name, cfg = p.get("name"), p.get("config") or {}
    where = p.get("route", {}) or p.get("service", {}) or {}
    where = where.get("id", "global") if isinstance(where, dict) else "global"
    for field in MODIFIED_ONLY.get(name, []):
        if cfg.get(field) not in (None, [], "", {}):
            blocking.append((name, field, where))
    if name == "jwt-keycloak":
        for field in AUTHZ:
            if cfg.get(field) not in (None, [], "", {}, False):
                authz_used.append((field, where, cfg.get(field)))

print()
if blocking:
    print("  ⛔ fields only the MODIFIED plugins accept — this configuration would be REJECTED:")
    for name, field, where in blocking:
        print(f"       {name}.{field}  (on {where})")
    print("     Either port that behaviour forward, or change those routes before rolling out.")
else:
    print("  ✅ no route uses a field that only the modified plugins accept.")
    print("     An image built from the upstream rocks would load this configuration as it stands.")

print()
if authz_used:
    print("  ⚠️  jwt-keycloak is doing authorization, not just authentication:")
    for field, where, value in authz_used:
        print(f"       {field} = {value}  (on {where})")
    print("     On Kong 3.x these have no direct equivalent: oidcify feeds `authenticated_groups`")
    print("     to Kong's ACL plugin, so each of these becomes a group. Mapping them is the work.")
else:
    print("  ✅ jwt-keycloak validates tokens but enforces no roles or scopes.")
    print("     On Kong 3.x oidcify covers this case outright — no replacement plugin needed.")

print()
print("  ⚠️  One thing this cannot see, and it is the one that fails silently:")
print("     the modified `oidc` plugin injects X-Access-Token and X-ID-Token headers into every")
print("     authenticated request. Upstream services may read them. The upstream rock does NOT,")
print("     so those headers simply stop arriving — no error, anywhere. Grep the services behind")
print("     this gateway for those header names before rolling out:")
print()
print("       grep -ril 'X-ID-Token\\|X-Access-Token' <service sources>")
sys.exit(1 if blocking else 0)
PY
