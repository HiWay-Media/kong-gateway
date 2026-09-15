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

The table lives in the [Roadmap](roadmap.md), generated from these tests. It used to be kept here by
hand, which is exactly the arrangement this file spends its first paragraph arguing against.

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

!!! warning "It compares contents now, with six declared exceptions"
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

    Since 2026-09-15 M1 compares **contents**, with those six files listed as declared exceptions
    and the reason for each. A seventh file drifting fails it; so does one of the six ceasing to
    differ. What the exceptions are, and how to find out whether the running configuration depends
    on them, is in [Migrating](migrating.md) — including the one that fails silently: the modified
    `oidc` injects `X-Access-Token` and `X-ID-Token`, the upstream rock does not, and a service
    reading either simply stops receiving it.

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

## M2b — The 2.x variant carries a maintained OIDC implementation

**Exit criterion.** On the `oidcify` build of the 2.x line: the binary is installed and answers
Kong's schema query, the protobuf definitions are where Kong 2.8 looks for them, the abandoned
`kong-oidc` is **not** shipped beside it, and `jwt-keycloak` and `kong-path-allow` are unchanged.

**Verified on 2026-09-14: `PASS`**, with the end-to-end suite driving it against a real Keycloak.

This milestone exists to separate two migrations that would otherwise arrive together: getting off
an abandoned OIDC plugin, and jumping a Kong major. The variant does the first alone. The last two
checks are the ones that keep it honest — if `jwt-keycloak` went missing, the variant would be
changing two things and the rollback story would be gone.

⚠️ It also proves something that was not obvious: **Kong 2.8 can run a Go plugin server**, once the
protobuf path bug is worked around. Without that copy Kong does not start at all, and the error
names a `.proto` file rather than anything to do with plugins.

## M3 — Replacement chosen for `oidc` on Kong 3.x

**Exit criterion.** On a Kong >= 3.0 image the `oidcify` binary is installed, runs on that base image
and answers Kong's schema query — and the abandoned Lua `oidc` plugin is **not** shipped next to it.

**Decided on 2026-09-14: [oidcify](https://github.com/hanlaur/oidcify) `1.3.10`**, pinned by SHA-256
per architecture. `PASS`.

The decision was not between good options. Every Lua candidate was already dead: `nokia/kong-oidc` is
archived with a README saying not to use it in production, and `revomatico/kong-oidc` — the
best-known Kong 3.x fork — is archived too. What is *not* dead is `lua-resty-openidc`, the library
both of them wrap. The wrappers keep being abandoned; the library does not.

oidcify is maintained and Apache-2.0, and it is a different kind of thing: a Go binary Kong runs as
an external plugin server. That is one more process, a cold start on the first request, and a single
maintainer. Those costs are listed in [Plugins](plugins.md#oidcify-the-kong-3x-replacement-for-oidc)
rather than buried here, because they are what a future reader will need when deciding whether to
keep it.

What makes this a decision rather than a hope: the [end-to-end suite](end-to-end.md) drives it with a
real identity provider on the 3.x line, and asserts that it refuses a malformed token, an invalid
signature and a genuine token with the wrong audience before it accepts a real one.

## M3b — Replacement chosen for `jwt-keycloak` on Kong 3.x

**Exit criterion.** A `jwt-keycloak` handler exists on a Kong >= 3.0 image, from whatever rock
provides it.

**Still open, and `XFAIL` on purpose.** `gbbirkisson/kong-plugin-jwt-keycloak` is archived; the
[Platformatory fork](https://github.com/Platformatory/kong-plugin-jwt-keycloak) claims 3.x support
but is small and lightly used — 4 stars, last pushed July 2024 — which is worth knowing before it
goes on an authentication path.

### What was measured, and what it leaves open

On 2026-09-14, with a real Keycloak: **oidcify validates access tokens as well as ID tokens**.
Configure `bearer_jwt_allowed_auds: ['account']` — the audience Keycloak puts on an access token —
and the suite shows the full set of outcomes on the 3.x line:

| Request | Result |
|---|---|
| no token | 401 |
| malformed token | 401 |
| well-formed token, invalid signature | 401 |
| genuine access token from the realm | **200**, reaching the upstream |
| ID token on the access-token route | 401 (the audiences are not interchangeable) |

That is the **authentication** half of `jwt-keycloak`, covered with no new dependency. What remains
is the **authorization** half: `jwt-keycloak` also validates `scope`, `roles`, `realm_roles` and
`client_roles`, and can match a claim onto a Kong consumer. oidcify does not replicate those; it maps
a groups claim into `authenticated_groups` for Kong's bundled ACL plugin — a different shape, not a
missing one.

**And the replacement mechanism now works, measured the same way.** The end-to-end suite asserts,
on the 3.x line, that a group alice belongs to lets her through and a group she does not belong to
refuses her — oidcify putting the token's groups into `authenticated_groups`, Kong's bundled ACL
plugin deciding. So the authorization half has a working equivalent; what it does not have is a
mapping from the roles a live configuration uses onto groups.

⚠️ So the open question is no longer *which fork to adopt*, nor even *can this be done without one*,
but **do any live routes use those validators, and do their roles map onto groups?** If none do, this milestone closes by consolidation — no second plugin, nothing new on
the authentication path to be abandoned in two years. If some do, the choice is between an ACL-based
equivalent and a fork, and it is worth making with the roles in front of you.

It is a question about the running configuration, so it stays with whoever operates it. Nothing here
will be decided by inertia.

## M4 — 3.x image publishable

**Exit criterion:** the same gate as M2, on a Kong >= 3.0 image. `XFAIL` today: `oidc` is settled
(M3) but `jwt-keycloak` is not (M3b), and the gate refuses to call the image publishable while one
of its authentication plugins has no replacement. The publish steps read that, so a release tag
publishes the 2.x line and skips 3.x without anyone having to remember.

On Kong 3.x a handler without `VERSION` does not load. On 2.x it does — which is exactly why a
missing one went unnoticed for years.

Entirely dependent on M3b — and there is now a second thing to settle before 3.x can ship with a
database: Kong 3.9.3's Admin API root answers 500 when an external plugin is registered, so decK
cannot configure it. DB-less 3.x is unaffected, and Kong 2.8.5 with the same plugin is fine. See
[End-to-end](end-to-end.md#storage-modes).
