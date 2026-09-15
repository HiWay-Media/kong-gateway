#!/usr/bin/env bash
# Publishing policy tests.
#
# The milestone suite checks what is inside an image. This one checks what gets published under
# which name — the part nobody can verify by pulling, because a wrong tag looks exactly like a right
# one until somebody deploys it.
#
# It needs no image and no Docker: scripts/publish-tags.sh decides the tag list, and deciding it in
# a script rather than in a YAML expression is what makes the decision testable at all.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
TAGS="$REPO_ROOT/scripts/publish-tags.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/image.yml"
IMAGE=ghcr.io/example/kong-gateway
LATEST_LINE=2.8.5

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# case: <description> <kong> <ref> <expected tags, comma-separated> [variant]
case_is() {
  local desc="$1" kong="$2" ref="$3" want="$4" variant="${5:-}" got
  got=$("$TAGS" "$IMAGE" "$kong" "$LATEST_LINE" "$ref" "$variant" | paste -sd, -)
  [ "$got" = "$want" ] && ok "$desc" || bad "$desc
         expected: $want
         got:      $got"
}

echo "==> which tags a publish produces"

case_is "an annotated tag publishes the version, the release, and latest for the current line" \
  2.8.5 refs/tags/v1.0.1 \
  "$IMAGE:2.8.5,$IMAGE:2.8.5-v1.0.1,$IMAGE:latest"

# latest must name one image, and the line carrying it is a decision, not whichever matrix entry
# finished last. Two lines both claiming latest is how a pull silently changes major version.
case_is "a second Kong line never claims latest" \
  3.9.3 refs/tags/v1.0.1 \
  "$IMAGE:3.9.3,$IMAGE:3.9.3-v1.0.1"

# The whole point of `latest`: it means the last release. A manual dispatch from a branch is not one.
case_is "a manual dispatch from main publishes no latest and no release tag" \
  2.8.5 refs/heads/main \
  "$IMAGE:2.8.5"

case_is "a pre-release tag publishes the release but does not move latest" \
  2.8.5 refs/tags/v1.1.0-rc.1 \
  "$IMAGE:2.8.5,$IMAGE:2.8.5-v1.1.0-rc.1"

# A variant is the same Kong with a different plugin set, so it cannot answer to the same names.
# `2.8.5` must keep meaning the image that reproduces production; the variant lives beside it under
# its own suffix, and never takes `latest` — that would silently move every deployment following the
# tag onto a different authentication plugin.
case_is "a variant publishes under its own suffix" \
  2.8.5 refs/tags/v1.5.0 \
  "$IMAGE:2.8.5-oidcify,$IMAGE:2.8.5-oidcify-v1.5.0" \
  oidcify

case_is "a variant never takes latest, even on the line that carries it" \
  2.8.5 refs/tags/v1.5.0 \
  "$IMAGE:2.8.5-oidcify,$IMAGE:2.8.5-oidcify-v1.5.0" \
  oidcify

case_is "the default build of the same line still takes latest" \
  2.8.5 refs/tags/v1.5.0 \
  "$IMAGE:2.8.5,$IMAGE:2.8.5-v1.5.0,$IMAGE:latest"

echo "==> the workflow actually uses that decision"

grep -q 'scripts/publish-tags.sh' "$WORKFLOW" \
  && ok "the publish step takes its tags from scripts/publish-tags.sh" \
  || bad "the workflow builds its tag list inline — then this file tests nothing"

# A milestone still declared XFAIL means the line is not ready; the gate exists so that a tag cannot
# publish it anyway.
if [ "$(grep -c "steps.milestones.outputs.publishable == 'true'" "$WORKFLOW")" -ge 3 ]; then
  ok "login, push and digest are gated on the milestones being met"
else
  bad "a publish step is not gated on publishable"
fi

grep -q "startsWith(github.ref, 'refs/tags/v') || inputs.publish" "$WORKFLOW" \
  && ok "publishing happens only from a v* tag or an explicit dispatch" \
  || bad "the publish condition changed: a push to main may now publish"

# A `paths:` filter on the push trigger also applies to TAG pushes: GitHub evaluates it against the
# tagged commit, so tagging a release whose commit only touched docs would skip the workflow
# entirely — no build, no publish, no `latest`, and nothing anywhere saying why. A release that
# quietly publishes nothing is worse than a pipeline that runs a few minutes too often, so the push
# trigger carries no filter. Checked by text, so this test needs nothing installed but a shell.
PUSH_BLOCK=$(awk '/^  push:/ {inside = 1; next} /^  [a-z_]+:/ {inside = 0} inside' "$WORKFLOW")
case "$PUSH_BLOCK" in
  *paths:*) bad "the push trigger has a paths filter: a docs-only release tag would publish nothing" ;;
  *)        ok  "the push trigger has no paths filter, so a release tag always builds" ;;
esac

echo "==> the base image is pinned by digest, and the pin is consistent"

# This repository asks deployments to pin digests. Building itself on a mutable tag would be the
# same mistake one level up, and the one place nobody would look for it.
DOCKERFILE="$REPO_ROOT/Dockerfile"
DIGESTS="$REPO_ROOT/kong-base-digests.env"

grep -qE '^FROM kong:\$\{KONG_VERSION\}-ubuntu@\$\{KONG_DIGEST\}' "$DOCKERFILE" \
  && ok "the base image is referenced by digest" \
  || bad "the Dockerfile builds on a mutable tag"

# The default has to match the file, or a bare `docker build` silently uses a different base than
# CI does — which is the kind of difference that only shows up in production.
DEFAULT_VERSION=$(grep -oE '^ARG KONG_VERSION=.*' "$DOCKERFILE" | cut -d= -f2)
DEFAULT_DIGEST=$(grep -oE '^ARG KONG_DIGEST=.*' "$DOCKERFILE" | cut -d= -f2-)
FILE_DIGEST=$(grep -E "^${DEFAULT_VERSION}=" "$DIGESTS" | cut -d= -f2-)
[ -n "$FILE_DIGEST" ] && [ "$DEFAULT_DIGEST" = "$FILE_DIGEST" ] \
  && ok "the default digest matches kong-base-digests.env for $DEFAULT_VERSION" \
  || bad "the default KONG_DIGEST does not match the entry for $DEFAULT_VERSION"

# Every line CI builds needs an entry, or that build falls back to the default digest and quietly
# builds the wrong base.
for v in $(grep -oE "kong: '[0-9.]+'" "$WORKFLOW" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | sort -u); do
  if grep -qE "^${v}=sha256:" "$DIGESTS"; then
    ok "Kong $v has a pinned base digest"
  else
    bad "Kong $v is built in CI but has no entry in kong-base-digests.env"
  fi
done

echo "==> the image that is published is the image that was tested"

# Building a second time to publish is not the same as publishing what passed. With a warm cache it
# usually produces identical bits — usually is not a property you can rely on for an artefact that
# guards authentication.
grep -q "docker push" "$WORKFLOW" \
  && ok "the publish step pushes an image rather than building one" \
  || bad "nothing in the workflow pushes a built image"

if [ "$(grep -c "push: true" "$WORKFLOW")" = "0" ]; then
  ok "no second build runs with push: true"
else
  bad "a second build-push-action publishes — that is a rebuild, not the tested image"
fi

echo "==> a tag produces a release, and only jobs that publish can publish"

# A tag that ships images and leaves no readable trace is how a registry fills with versions nobody
# can map back to a change.
grep -qE "gh (release edit|api \"repos)" "$WORKFLOW" \
  && ok "a v* tag creates or updates a GitHub release" \
  || bad "nothing creates a release: a tag would publish images and say nothing"

# Reading the digest field without `println` prints the whole default description instead, and the
# first real tag recorded three lines of prose where a digest belonged — in notes people copy into
# deployments.
#
# Comments are stripped before matching. The first version of this check searched the whole file,
# and the comment in the workflow explaining the mistake contained the very string it forbade, so the
# check failed against a correct workflow. Same shape as quoting a footer in the rule that bans it:
# a pattern does not know whether it is being used or being described.
if sed 's/#.*//' "$WORKFLOW" | grep -q "Manifest\.Digest}}" \
   && ! sed 's/#.*//' "$WORKFLOW" | grep -q "println \.Manifest\.Digest"; then
  bad "a digest is read without println — that prints a description, not a digest"
else
  ok "digests are read with println, and checked to start with sha256:"
fi

grep -q "release-notes.sh" "$WORKFLOW" \
  && ok "the release body comes from CHANGELOG.md, not from a second description" \
  || bad "the release body is written somewhere other than the changelog"

# Least privilege, and it is checkable: the workflow-level grant must not include packages, so a
# test suite cannot hold a token that writes to the registry.
awk '/^permissions:/{f=1;next} /^[a-z]/{f=0} f' "$WORKFLOW" | grep -q "packages:" \
  && bad "packages: write is granted workflow-wide — the test jobs inherit it" \
  || ok "registry write is granted per job, not to everything"

echo "==> every action is pinned to a commit, not to a moving tag"

# Invariant 1 says pinned versions, never latest — and a major tag is `latest` with extra steps:
# whoever owns the action can move v4 to different code, and it runs here with a token that can
# write to the registry.
unpinned=$(grep -rhoE "uses: [a-zA-Z0-9/_.-]+@[^ ]+" "$REPO_ROOT/.github/workflows/" \
  | grep -vE "@[a-f0-9]{40}$" | sort -u | head -5)
if [ -z "$unpinned" ]; then
  ok "all actions are pinned by SHA"
else
  bad "actions pinned to a moving reference:"
  printf '%s\n' "$unpinned" | sed 's/^/         /'
fi

# Pinning without a way to update is staleness wearing a security badge.
[ -f "$REPO_ROOT/.github/dependabot.yml" ] \
  && grep -q "github-actions" "$REPO_ROOT/.github/dependabot.yml" \
  && ok "dependabot keeps those pins moving" \
  || bad "nothing updates the pinned actions: pinned and forgotten is its own risk"

echo "==> the backlog check runs on the changes it guards"

# A gate that does not run on the change it guards is decoration. The roadmap is generated from the
# backlog and from the milestone tests, so a pull request touching ANY of those must reach the
# check — including a docs-only edit, which the image workflow filters out by path.
BACKLOG_WF="$REPO_ROOT/.github/workflows/backlog.yml"
if [ -f "$BACKLOG_WF" ]; then
  for input in docs/backlog.md docs/roadmap.md tests/milestones scripts/backlog.py; do
    if grep -qF -- "$input" "$BACKLOG_WF"; then
      ok "a change under ${input} triggers the backlog check"
    else
      bad "${input} feeds the roadmap but does not trigger the backlog check"
    fi
  done
else
  bad "no .github/workflows/backlog.yml: the backlog check runs nowhere of its own"
fi

[ "$fails" -eq 0 ] && { echo "OK: publishing policy"; exit 0; }
echo "RED: $fails policy check(s) failed"; exit 1
