# Backlog

Everything known to be worth doing, with the reason attached. One item per section; the metadata
line is parsed by `scripts/backlog.py`, which lints it and regenerates the
[Roadmap](roadmap.md) — so an item cannot be added here, or quietly finished, without the roadmap
following.

Fields: **priority** `high|medium|low` · **status** `open|doing|done|dropped` · **milestone** the
milestone it unblocks, or `-`.

---

## BL-01 — Decide what replaces jwt-keycloak on Kong 3.x

**Priority:** high · **Status:** open · **Milestone:** M3b

The upstream is archived; the only non-archived fork has 4 stars and was last pushed in July 2024.
It is on the authentication path, and it is the single thing keeping the 3.x image unpublishable.

⚠️ **Measured on 2026-09-14, and it narrows the question.** oidcify validates Keycloak **access**
tokens too, not only ID tokens: with `bearer_jwt_allowed_auds: ['account']` a real access token is
accepted, while no token, a malformed one, an invalid signature and a wrong audience are each
refused with 401. The end-to-end suite asserts all five on the 3.x line.

So the **authentication** half needs no fork. What is left is the **authorization** half:
jwt-keycloak also validates `scope`, `roles`, `realm_roles` and `client_roles`, and can map a claim
onto a Kong consumer; oidcify instead maps a groups claim into `authenticated_groups` for Kong's ACL
plugin.

The question is no longer *which fork* but: **do any live routes use those validators?** If none do,
this closes by consolidation with no new dependency on the authentication path. That is a question
about the running configuration, which only its owner can answer.

**The replacement mechanism is now proven**, not just plausible: the end-to-end suite asserts that
oidcify + Kong's ACL plugin authorizes by group in both directions on the 3.x line. What is missing
is the mapping from the roles a live configuration uses onto Keycloak groups.

**Done when:** the live Kong configuration has been checked for `scope`/`roles`/`realm_roles`/
`client_roles`/`consumer_match` on jwt-keycloak, and either those routes have an ACL-based
equivalent or the plugin is dropped — with the reasoning written in `docs/milestones.md`.

## BL-02 — Kong 3.9.3 Admin API returns 500 with an external plugin registered

**Priority:** high · **Status:** open · **Milestone:** M4

`GET /` answers `Cannot serialise cdata: type not supported` when oidcify is registered, so decK —
and anything else reading that endpoint — cannot configure a database-backed Kong 3.9.3. Kong 2.8.5
with the same plugin answers 200, and DB-less 3.x is unaffected.

**Done when:** either upstream fixes it, or the 3.x line is committed to DB-less and that is stated
where deployments are described.

## BL-03 — Pin the base image by digest, not by tag

**Priority:** high · **Status:** done · **Milestone:** -

`FROM kong:${KONG_VERSION}-ubuntu` is a mutable tag. This repository insists deployments pin digests
and then rests on a tag one level up: reproducibility stops exactly where it is asserted most loudly.

**Done when:** the Dockerfile pins `kong@sha256:…` per line, with the human-readable tag in a comment.

✅ **Done 2026-09-15.** `kong-base-digests.env` holds the mapping; `ARG KONG_DIGEST` defaults to the
entry for the default version, so a bare `docker build` is pinned too; CI and `scripts/run-local.sh`
pass the entry for the line they build; and `tests/policy.sh` checks the default still matches the
file and that every line CI builds has an entry. A wrong digest fails the build outright — verified
by passing one.

## BL-04 — Publish the image that was tested, not a rebuild of it

**Priority:** high · **Status:** done · **Milestone:** -

The publish step runs `build-push-action` a second time. With a warm cache it usually produces the
same bits — usually is not a guarantee, and the tests certify bits that may not be the ones pushed.

**Done when:** the image is built once and pushed by digest, or the workflow proves the two digests
match before pushing.

✅ **Done 2026-09-15.** The publish step is `docker tag` plus `docker push` of the image the
milestones and the end-to-end suite ran against; the second `build-push-action` is gone, and
`tests/policy.sh` fails if one comes back.

## BL-05 — Decide whether to carry the production plugin modifications forward

**Priority:** high · **Status:** open · **Milestone:** M1

Six files differ between `reference/baseline-2.0.3/` and the upstream rocks: the replaced image
carried locally modified `oidc` and `jwt-keycloak` plugins, with extra config fields
(`internal_request_headers`, `redirect_after_authentication_failed_uri`, `timeout`). A configuration
using any of them would be **rejected** by the new image.

**Measured 2026-09-15**, and one risk is worse than this item described. The modifications are: an
`oidc` `timeout` field, `jwt-keycloak`'s `internal_request_headers` and
`redirect_after_authentication_failed_uri` — all of which make Kong **refuse** a configuration that
uses them, loudly — and the `oidc` handler injecting **`X-Access-Token` and `X-ID-Token`** into every
authenticated request, which the upstream rock does not. A service reading either header stops
receiving it with **no error anywhere**.

`scripts/check-live-config.sh <kong-admin-url>` answers the configuration half against a running
Kong. The header half has to be answered in the services:
`grep -ril 'X-ID-Token\|X-Access-Token'`. M1 now compares file contents with the six differences
declared, so a seventh cannot appear unnoticed.

**Done when:** the check has been run against each zone, the services have been grepped for those
two headers, and the decision to port or drop each modification is recorded in
`docs/migrating.md`.

## BL-06 — Add OCI labels and build provenance

**Priority:** medium · **Status:** done · **Milestone:** -

No `org.opencontainers.image.source`/`revision`/`version`, so GHCR does not link the package to the
repository and a digest does not say which commit produced it. No SBOM or provenance attestation
either, on an image that sits on the authentication path.

**Done when:** labels are set from the build, and `provenance`/`sbom` are enabled on the publish step.

✅ **Done 2026-09-15, in the part that was in reach.** The image carries the OCI title, description,
source, documentation, licence, revision, created and version labels plus the Kong line, with
revision and version passed by CI — so a digest in a job spec traces back to a commit.

⚠️ Provenance and SBOM attestations are **not** added: they are produced by `buildx --push`, and this
workflow deliberately pushes the image it tested instead of rebuilding it (`BL-04`). Having both
needs a step that attests an already-pushed digest. Said here rather than quietly dropped.

## BL-07 — Remove build tooling from the published image

**Priority:** medium · **Status:** dropped · **Milestone:** -

`git`, `unzip` and `curl` stay in the final image. Extra surface on an authentication gateway, for
tools only the build needs.

**Done when:** they are purged in the same layer, or the plugins are installed in a builder stage.

⛔ **Dropped 2026-09-15 — it cannot be done on this base.** `apt-get purge git unzip curl` takes
`/usr/local/lib/luarocks` with it: the whole rock tree, every plugin, leaving an image where
`kong version` answers and not one plugin exists. With `--auto-remove` apt goes further still and
judges the `kong` package itself orphaned. Measured on real builds, twice.

The extra surface is real and this is not a comfortable answer — but an image whose plugins have
silently vanished is a worse one. The Dockerfile records it where somebody would otherwise try it
again.

## BL-08 — Warm up the oidcify plugin server on start

**Priority:** medium · **Status:** open · **Milestone:** -

Kong starts the Go plugin server lazily, so the first request after a restart can get a 500 while its
socket does not exist yet. Brief, self-correcting, and visible to whoever arrives first.

**Done when:** whatever starts the container issues a warm-up request before traffic reaches it, or
the behaviour is accepted in writing.

## BL-09 — Scope `packages: write` to the job that publishes

**Priority:** medium · **Status:** done · **Milestone:** -

The permission is set workflow-wide, so the `policy` and `e2e` jobs inherit registry write access
they never use.

**Done when:** the permission is declared on the `build` job only.

✅ **Done 2026-09-15.** The workflow-level grant is `contents: read`; `packages: write` belongs to
the build job, `contents: write` to the release job. `tests/policy.sh` fails if a package permission
reappears at workflow level.

## BL-10 — Pin GitHub Actions by SHA

**Priority:** medium · **Status:** done · **Milestone:** -

Actions are pinned by major tag (`@v4`), while invariant 1 of `AGENTS.md` demands exact versions
everywhere. The same class of mutable reference the repository warns about, applied to itself.

**Done when:** actions are pinned by commit SHA, with a policy for updating them.

✅ **Done 2026-09-15.** Every action in every workflow is pinned to a 40-character commit SHA with
the version kept beside it as a comment, and `.github/dependabot.yml` bumps those pins weekly —
pinning without a way to update trades a supply-chain risk for a staleness one and calls it
progress. `tests/policy.sh` fails if any action returns to a moving reference, or if dependabot
stops watching them.

## BL-11 — Review oidcify's maintenance once a quarter

**Priority:** medium · **Status:** open · **Milestone:** -

One maintainer, 24 stars. Alive today is not safe forever, and the failure mode is silence: the
project simply stops, as `kong-oidc` did for seven years before saying so.

**Done when:** a recurring check exists, and its result is recorded next to the M3 decision.

## BL-12 — Exclude `scripts/` and `docs/` from the build context

**Priority:** low · **Status:** done · **Milestone:** -

`.dockerignore` does not list them, so they are shipped to the daemon on every build for no reason.

**Done when:** `.dockerignore` covers them.

✅ **Done 2026-09-15**, in the same change that closed `BL-06` — and marked here only afterwards:
the changelog said done while this file still said open, which is precisely the drift the roadmap
generator exists to prevent and cannot catch, because it reads this file and believes it.

## BL-13 — `plugins/` exists only on disk

**Priority:** low · **Status:** done · **Milestone:** -

Git does not track empty directories, so the folder `AGENTS.md` describes is absent from a fresh
clone.

**Done when:** a `.gitkeep` is added, or the reference is removed.

✅ **Done 2026-09-15.** `plugins/.gitkeep`: the folder now exists in a clone, not only on the
author's disk.

## BL-14 — Document where `lua-resty-jwt` and `lua-resty-cookie` come from

**Priority:** low · **Status:** done · **Milestone:** -

Both are installed from third-party LuaRocks manifests (`cdbattags`, `utix`) without the provenance
note the other plugins get.

**Done when:** `docs/plugins.md` states their origin and why those manifests.

✅ **Done 2026-09-15.** Each supporting rock has its publisher and its reason for being there,
including that `lua-resty-jwt` comes from a fork because the original line is dormant.

## BL-15 — CODEOWNERS and branch protection

**Priority:** low · **Status:** done · **Milestone:** -

Nothing records who reviews changes to a repository that publishes authentication images.

**Done when:** a CODEOWNERS file exists and the protection rules are described in `AGENTS.md`.

✅ **Done 2026-09-15, by half.** `.github/CODEOWNERS` records who reviews what, listing separately
the paths where a mistake is published rather than merely committed.

⚠️ GitHub enforces it only when branch protection requires code-owner review. That is a repository
setting, not a file — so the other half belongs to whoever administers the repository, and no commit
here can supply it.
