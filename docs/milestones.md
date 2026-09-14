# Milestones

The real state is not this document: it is `./tests/run.sh`. Every milestone here has a file in
`tests/milestones/` holding its exit criterion in executable form. If the two disagree, the test is
right — and the document is updated in the same commit.

Runner results:

| Result | Meaning |
|---|---|
| `PASS` | Milestone reached, and still holding |
| `FAIL` | **Red.** A milestone that had been reached has regressed |
| `XFAIL` | Milestone declared not reached yet. Not red: declared, outstanding work |
| `XPASS` | **Red.** It now passes: drop `expect xfail` and update this page |
| `SKIP` | Not applicable to this Kong major |

## State

| | Milestone | Test | State |
|---|---|---|---|
| **M0** | Reproducible recipe | `M0-reproducible-recipe.sh` | 🟢 `PASS` (2.8.5 and 3.9.3) |
| **M1** | Parity with the extracted baseline | `M1-parity-with-baseline.sh` | 🟢 `PASS` — 14 of 14 modules |
| **M2** | 2.x image publishable | `M2-publishable-2x.sh` | 🟢 `PASS` |
| **M3** | Replacement chosen for `oidc` and `jwt-keycloak` on 3.x | `M3-replacement-chosen-3x.sh` | 🟡 `XFAIL` — open decision |
| **M4** | 3.x image publishable | `M4-publishable-3x.sh` | 🟡 `XFAIL` — depends on M3 |

An unmet milestone also blocks publishing: `tests/run.sh` reports `publishable` per Kong version,
false while any milestone is `XFAIL`, and the workflow's publish steps are gated on it. A `v*` tag
therefore publishes the 2.x line and skips the 3.x one, without anyone having to remember to.

---

## M0 — Reproducible recipe

**Exit criterion.** The build completes, the image contains the Kong version it declares,
`kong-path-allow` is installed as a rock, and the default process does not run as root.

**Verified on 2026-09-14** for `2.8.5` and `3.9.3` (amd64 builds emulated on Apple Silicon): `PASS`.

Two broken things surfaced only by actually building the image. Both are worth recording, because
both present with an error that says nothing about what happened:

1. **`luarocks install <name> <version>` no longer works** inside `kong:2.8.5-ubuntu`: the
   luarocks.org manifest outgrew the Lua 5.1 limit of 65536 constants per chunk
   (`main function has more than 65536 constants`), and resolution ends in
   `No results matching query were found for Lua 5.1`. Hence the Dockerfile installs from **pinned
   rockspec URLs**, bypassing the index. That is not a style choice; it is the only form that works.
2. **`kong:3.9.3-ubuntu` ships neither `curl` nor `wget`.** LuaRocks 3.12.2 does not say so: it dies
   inside `download_with_mirrors` with `attempt to concatenate local 'name' (a nil value)` and asks
   you to file a bug. `curl` is therefore installed explicitly alongside `git` and `unzip`.

Neither would have been visible by reading the Dockerfile. That was the condition of the image this
repository replaces: it looked fine because nobody had ever rebuilt it.

## M1 — Parity with the extracted baseline

**Exit criterion.** Every `.lua` module present in `reference/baseline-2.0.3/` also exists in the
built image. Without that comparison, "rebuilding the image" only means "building an image": the
baseline is the only evidence of what was actually running.

The test runs on Kong < 3.0 only — on 3.x the plugin set is different by definition.

!!! warning "Module parity is not source parity, and the sources differ"
    M1 compares which modules exist, not what is in them. Comparing the contents on 2026-09-14
    showed **six files differ** from the baseline: `oidc/handler.lua`, `oidc/schema.lua`,
    `oidc/utils.lua`, `jwt-keycloak/handler.lua`, `jwt-keycloak/schema.lua` and
    `jwt-keycloak/validators/roles.lua`. `kong-path-allow` matches exactly.

    The differences are not cosmetic. The image being replaced carried **locally modified** plugins:
    its `jwt-keycloak` schema accepts `internal_request_headers` and
    `redirect_after_authentication_failed_uri`, and its handler can read a token payload left behind
    by another plugin; its `oidc` schema accepts a `timeout`. None of that exists in the upstream
    rocks this Dockerfile installs.

    So a configuration using any of those fields would be **rejected** by this image, and a request
    path that depended on that behaviour would change. Before this image replaces anything, the
    running configuration has to be checked against those field names — and a decision made about
    whether to carry the modifications forward or drop them deliberately.

    Turning M1 into a content comparison would make it fail today. That is the honest state; the
    test is left as it is only until that decision is recorded here.

## M2 — 2.x image publishable

**Exit criterion:** `tests/smoke.sh` passes. The milestone calls the gate rather than restating it —
two copies of the same check drift, and then neither can be trusted to describe the image.

The gate checks that the rocks are installed, that every schema and handler **actually loads**
(installing a rock only proves a file was copied), that `PRIORITY` is declared, that `kong check`
accepts a configuration with all plugins enabled, and that `kong-path-allow` exposes a usable
`access()`.

That last one is the one that matters. `kong-path-allow` is an **authorization** control, and an
authorization control is verified by the case it must refuse. A plugin that loads but no longer
blocks anything passes every healthcheck and is invisible to whoever pulls the image.

## M3 — Replacement chosen for `oidc` and `jwt-keycloak` on Kong 3.x

**Exit criterion.** On a Kong >= 3.0 image, `kong/plugins/oidc/handler.lua` and
`kong/plugins/jwt-keycloak/handler.lua` exist, whatever rock provides them.

**This is the repository's open decision, and it is `XFAIL` on purpose.**

- `nokia/kong-oidc` is **archived**, and its README states it is not maintained and not
  recommended in production. Last code change: June 2019. It also uses `BasePlugin`, removed in
  Kong 3.0.
- `gbbirkisson/kong-plugin-jwt-keycloak` is archived; the
  [Platformatory](https://github.com/Platformatory/kong-plugin-jwt-keycloak) fork exists and is
  worth evaluating.

⚠️ Replacing abandoned forks with **other** abandoned forks, on the authentication path, is not a
net security gain. Three options remain on the table, and the third should not be dismissed by
inertia: adopt a maintained fork, consolidate both plugins into one written in-house (`plugins/` is
empty for exactly that), or move the function out of Kong altogether.

Once decided, the line goes into the `Dockerfile`, the test turns `XPASS` — that is, red — and stays
red until this file records **which** fork was chosen and **why**.

## M4 — 3.x image publishable

**Exit criterion:** the same gate as M2, on a Kong >= 3.0 image. `XFAIL` today: without replacements
for `oidc` and `jwt-keycloak` the gate refuses to call it publishable, which is correct.

On Kong 3.x a handler without `VERSION` does not load. On 2.x it does — which is exactly why a
missing one went unnoticed for years.

Entirely dependent on M3.
