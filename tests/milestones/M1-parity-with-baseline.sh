#!/usr/bin/env bash
# M1 — What the Dockerfile produces matches what was actually running.
#
# reference/baseline-2.0.3/ holds the plugin sources extracted from the image being replaced. It is
# the baseline: without this comparison, "rebuilding the image" only means "building an image".
# If a module from the baseline is missing, the Dockerfile installs something else — and that has
# to be known before a deployment, not after.
source "$(dirname "$0")/../lib.sh"

milestone M1 "Module parity with the extracted 2.0.3 baseline"
expect pass
only_major lt 3

[ -d "$BASELINE_DIR" ] || { echo "  FAIL baseline missing: $BASELINE_DIR"; exit 1; }

for p in kong-path-allow oidc jwt-keycloak; do
  [ -d "$BASELINE_DIR/$p" ] || continue
  while IFS= read -r m; do
    check "$p/$m present, as in the baseline" has_file "$PLUGIN_DIR/$p/$m"
  done < <(cd "$BASELINE_DIR/$p" && find . -name '*.lua' | sed 's|^\./||' | sort)
done
