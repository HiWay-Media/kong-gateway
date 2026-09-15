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

**Done when:** the live configuration has been checked against those field names, and the decision to
port or drop the modifications is recorded. Then M1 can compare contents instead of module names.

## BL-06 — Add OCI labels and build provenance

**Priority:** medium · **Status:** open · **Milestone:** -

No `org.opencontainers.image.source`/`revision`/`version`, so GHCR does not link the package to the
repository and a digest does not say which commit produced it. No SBOM or provenance attestation
either, on an image that sits on the authentication path.

**Done when:** labels are set from the build, and `provenance`/`sbom` are enabled on the publish step.

## BL-07 — Remove build tooling from the published image

**Priority:** medium · **Status:** open · **Milestone:** -

`git`, `unzip` and `curl` stay in the final image. Extra surface on an authentication gateway, for
tools only the build needs.

**Done when:** they are purged in the same layer, or the plugins are installed in a builder stage.

## BL-08 — Warm up the oidcify plugin server on start

**Priority:** medium · **Status:** open · **Milestone:** -

Kong starts the Go plugin server lazily, so the first request after a restart can get a 500 while its
socket does not exist yet. Brief, self-correcting, and visible to whoever arrives first.

**Done when:** whatever starts the container issues a warm-up request before traffic reaches it, or
the behaviour is accepted in writing.

## BL-09 — Scope `packages: write` to the job that publishes

**Priority:** medium · **Status:** open · **Milestone:** -

The permission is set workflow-wide, so the `policy` and `e2e` jobs inherit registry write access
they never use.

**Done when:** the permission is declared on the `build` job only.

## BL-10 — Pin GitHub Actions by SHA

**Priority:** medium · **Status:** open · **Milestone:** -

Actions are pinned by major tag (`@v4`), while invariant 1 of `AGENTS.md` demands exact versions
everywhere. The same class of mutable reference the repository warns about, applied to itself.

**Done when:** actions are pinned by commit SHA, with a policy for updating them.

## BL-11 — Review oidcify's maintenance once a quarter

**Priority:** medium · **Status:** open · **Milestone:** -

One maintainer, 24 stars. Alive today is not safe forever, and the failure mode is silence: the
project simply stops, as `kong-oidc` did for seven years before saying so.

**Done when:** a recurring check exists, and its result is recorded next to the M3 decision.

## BL-12 — Exclude `scripts/` and `docs/` from the build context

**Priority:** low · **Status:** open · **Milestone:** -

`.dockerignore` does not list them, so they are shipped to the daemon on every build for no reason.

**Done when:** `.dockerignore` covers them.

## BL-13 — `plugins/` exists only on disk

**Priority:** low · **Status:** open · **Milestone:** -

Git does not track empty directories, so the folder `AGENTS.md` describes is absent from a fresh
clone.

**Done when:** a `.gitkeep` is added, or the reference is removed.

## BL-14 — Document where `lua-resty-jwt` and `lua-resty-cookie` come from

**Priority:** low · **Status:** open · **Milestone:** -

Both are installed from third-party LuaRocks manifests (`cdbattags`, `utix`) without the provenance
note the other plugins get.

**Done when:** `docs/plugins.md` states their origin and why those manifests.

## BL-15 — CODEOWNERS and branch protection

**Priority:** low · **Status:** open · **Milestone:** -

Nothing records who reviews changes to a repository that publishes authentication images.

**Done when:** a CODEOWNERS file exists and the protection rules are described in `AGENTS.md`.
