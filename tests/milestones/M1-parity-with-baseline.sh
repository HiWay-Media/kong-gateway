#!/usr/bin/env bash
# M1 — What the Dockerfile produces matches what was actually running.
#
# reference/baseline-2.0.3/ holds the plugin sources extracted from the image being replaced. This
# used to compare module NAMES, which was reassuring and nearly meaningless: the names matched while
# six files differed in content, because the replaced image carried locally modified plugins.
#
# So it compares contents, with those six listed below as declared exceptions. Two things then fail:
# a seventh file drifting, and one of the six ceasing to differ. The second matters as much as the
# first — it would mean the modification arrived in the upstream rock, or someone vendored it here,
# and either is news.
#
# The exceptions are not permission to ignore them. They are the open decision in BL-05, and
# scripts/check-live-config.sh says whether the running configuration depends on any of it.
source "$(dirname "$0")/../lib.sh"

milestone M1 "Source parity with the extracted 2.0.3 baseline, minus six declared differences"
expect pass
only_major lt 3
only_provider kong-oidc

[ -d "$BASELINE_DIR" ] || { echo "  FAIL baseline missing: $BASELINE_DIR"; exit 1; }

# file → why it differs. Measured 2026-09-15 against the upstream rocks.
known_difference() {
  case "$1" in
    oidc/schema.lua)                  echo "adds the config field 'timeout'" ;;
    oidc/utils.lua)                   echo "passes 'timeout' through, and injects X-Access-Token / X-ID-Token" ;;
    oidc/handler.lua)                 echo "calls those header injectors after authentication" ;;
    jwt-keycloak/schema.lua)          echo "adds 'internal_request_headers' and 'redirect_after_authentication_failed_uri'" ;;
    jwt-keycloak/handler.lua)         echo "implements both, reading a token another plugin left in kong.ctx.shared" ;;
    jwt-keycloak/validators/roles.lua) echo "logging only — no behaviour change" ;;
    *) return 1 ;;
  esac
}

digest_in_image() { run "sha256sum '$1' 2>/dev/null || shasum -a 256 '$1'" | cut -d' ' -f1; }

for p in kong-path-allow oidc jwt-keycloak; do
  [ -d "$BASELINE_DIR/$p" ] || continue
  while IFS= read -r m; do
    rel="$p/$m"
    base=$(shasum -a 256 "$BASELINE_DIR/$rel" | cut -d' ' -f1)
    img=$(digest_in_image "$PLUGIN_DIR/$rel")
    if reason=$(known_difference "$rel"); then
      if [ "$base" != "$img" ]; then
        printf '  ok   %s differs, as recorded: %s\n' "$rel" "$reason"
      else
        printf '  FAIL %s no longer differs — the recorded exception is stale\n' "$rel"
        _FAILS=$((_FAILS + 1))
      fi
    elif [ -z "$img" ]; then
      printf '  FAIL %s is missing from the image\n' "$rel"
      _FAILS=$((_FAILS + 1))
    elif [ "$base" = "$img" ]; then
      printf '  ok   %s is byte-for-byte what was running\n' "$rel"
    else
      printf '  FAIL %s differs from the baseline and is not a recorded exception\n' "$rel"
      _FAILS=$((_FAILS + 1))
    fi
    _CHECKS=$((_CHECKS + 1))
  done < <(cd "$BASELINE_DIR/$p" && find . -name '*.lua' | sed 's|^\./||' | sort)
done
