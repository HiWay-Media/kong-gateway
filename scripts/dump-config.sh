#!/usr/bin/env bash
# Takes a copy of a running Kong's configuration, with the secrets stripped out.
#
#   scripts/dump-config.sh <kong-admin-url> <output-directory>
#
# The configuration of the gateway this repository replaces lives in a database and nowhere else:
# not in git, not in the deployment manifests, which carry only the plugin list. So nobody can diff
# two zones, review a change before it is applied, or restore anything without a database backup.
# This writes it to a file, so all three become possible.
#
# ⛔ It refuses to write inside this repository. This is a public build recipe; a gateway's
# configuration names upstream hosts and is not public. The dump belongs in a private repository —
# passing a path in here is the mistake this check exists to stop, not a preference.
#
# Read-only against Kong: GETs, and no writes of any kind.
set -uo pipefail

ADMIN="${1:?usage: dump-config.sh <kong-admin-url> <output-directory>}"
OUTDIR="${2:?usage: dump-config.sh <kong-admin-url> <output-directory>}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ABS="$(cd "$(dirname "$OUTDIR")" 2>/dev/null && pwd)/$(basename "$OUTDIR")" || OUT_ABS="$OUTDIR"
case "$OUT_ABS/" in
  "$ROOT"/*)
    cat >&2 <<MSG
FAIL: refusing to write inside this repository.

      A gateway's configuration names upstream hosts and services. This repository is public, and a
      file that lands here is public the moment it is pushed — after which removing it from history
      is not a fix, because the clone and the fork already have it.

      Write it to a private repository instead:
          scripts/dump-config.sh $ADMIN ~/some/private/repo/kong-config
MSG
    exit 2 ;;
esac

command -v python3 >/dev/null || { echo "FAIL: python3 is required" >&2; exit 1; }
mkdir -p "$OUT_ABS" || exit 1

echo "==> reading $ADMIN"
raw="$OUT_ABS/.raw.json"; : >"$raw"
# `targets` is deliberately absent: it is not a top-level collection on every Kong line — on 2.8 it
# hangs off each upstream — and asking for it returns 404. A collection missing is normal; a
# collection that errors for another reason is not, and the two are told apart below.
for collection in services routes plugins consumers upstreams certificates; do
  url="${ADMIN%/}/$collection?size=1000"
  while [ -n "$url" ]; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$url")
    if [ "$code" = "404" ]; then
      echo "    (no $collection on this Kong — skipped)"
      break
    fi
    body=$(curl -fsS "$url") || { echo "FAIL: cannot read $url (HTTP $code)" >&2; rm -f "$raw"; exit 1; }
    printf '%s\n' "$body" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({'collection':'$collection','data':d.get('data',[])}))" >>"$raw"
    url=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("next") or "")')
  done
done

python3 - "$raw" "$OUT_ABS" <<'PY'
import json, re, sys, collections
from pathlib import Path

raw, outdir = Path(sys.argv[1]), Path(sys.argv[2])

# Anything whose name says "secret" is redacted, plus the ones whose names do not: session and
# cookie keys are as good as a password, and a dump that carries them is a credential store with a
# .json extension.
SECRET = re.compile(
    r"(secret|password|passwd|token|private_key|key_hex|client_secret|session_secret|"
    r"cookie_(hash|block)_key)", re.I)
# ASCII on purpose: json.dumps escapes anything else as \u00ab, and the leftover scan below then
# fails to recognise its own marker and reports every redacted field as a leak. A warning that cries
# wolf on every run is a warning people learn to scroll past.
REDACTED = "[redacted by scripts/dump-config.sh]"

def scrub(node):
    if isinstance(node, dict):
        return {k: (REDACTED if SECRET.search(k) and node[k] not in (None, "", [], {})
                    else scrub(v)) for k, v in node.items()}
    if isinstance(node, list):
        return [scrub(v) for v in node]
    return node

grouped = collections.defaultdict(list)
for line in raw.read_text().splitlines():
    if line.strip():
        doc = json.loads(line)
        grouped[doc["collection"]].extend(doc["data"])

summary = []
for collection, rows in sorted(grouped.items()):
    path = outdir / f"{collection}.json"
    path.write_text(json.dumps(scrub(rows), indent=2, sort_keys=True) + "\n")
    summary.append((collection, len(rows)))

raw.unlink()

# Left behind for a human to check before the file is committed anywhere. The regex above catches
# field names, not values: an API key sitting in a header transformation is invisible to it.
# Names alone produce noise: `token_endpoint_auth_method` holds "client_secret_post", which is a
# setting, not a credential. So a field is only reported when its VALUE could plausibly be one —
# long, or shaped like hex or base64. False alarms on every run teach people to ignore the alarm.
def plausible_secret(value):
    if value == REDACTED or len(value) < 20:
        return False
    return bool(re.fullmatch(r"[A-Za-z0-9+/=_-]{20,}", value))

leftovers = []
for path in sorted(outdir.glob("*.json")):
    for m in re.finditer(r'"([^"]*(?:secret|password|token|key|credential)[^"]*)"\s*:\s*"([^"]+)"',
                         path.read_text(), re.I):
        if plausible_secret(m.group(2)):
            leftovers.append(f"{path.name}: {m.group(1)}")

print()
for collection, n in summary:
    print(f"  {n:>4}  {collection}")
print()
if leftovers:
    print("  ⛔ these look like secrets and were NOT redacted — read them before committing anything:")
    for line in sorted(set(leftovers))[:10]:
        print(f"       {line}")
else:
    print("  ✅ no field whose name suggests a secret survived the scrub.")
print("     The scrub matches field NAMES. A credential pasted into a header transformation, a URL")
print("     or a custom plugin's free-text field is invisible to it — read the dump before it is")
print("     committed anywhere, including a private repository.")
PY

echo
echo "==> written to $OUT_ABS"
echo "    Now answer the two questions that block the migration:"
echo
echo "      scripts/check-live-config.sh $OUT_ABS/plugins.json"
