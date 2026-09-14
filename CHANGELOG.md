# Changelog — kong-gateway

Every significant change to this repository is recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versioning
follows [Semantic Versioning](https://semver.org/).

- **Added** → new features, documents, tests
- **Changed** → changes to existing behaviour or structure (not breaking)
- **Fixed** → corrections
- **Removed** → removals
- **Security** → security fixes or notes

> **Rule: every commit is a tagged release.** For each change: (1) record the entries in a new
> `[X.Y.Z] - YYYY-MM-DD` section; (2) commit; (3) create the annotated tag
> (`git tag -a vX.Y.Z -m "Release X.Y.Z"`); (4) pushing branch and tag is up to the maintainer
> (`git push origin main --follow-tags`). Bump `minor` for substantial additions, `patch` for fixes
> and updates to existing content.
>
> ⚠️ A `v*` tag reaching GitHub triggers the publish workflow. It only publishes the Kong lines
> whose milestones are all met — see [Publishing](docs/publishing.md).

---

## [Unreleased]

_(empty — work in progress only; every commit becomes a tagged release)_

## [1.13.0] - 2026-09-14

### Fixed
- **The logo was invisible on the published site.** It was drawn with `stroke="currentColor"`, and
  both the theme and a README embed it through an `<img>` tag — where there is no inherited colour
  to take, so `currentColor` resolves to black. On a header that is black in both light and dark
  mode, that is a logo nobody can see. It had been rendered and looked at once, standalone on a
  white page: the single context where the bug does not show.
- Colours are explicit now, in three files: `logo.svg` white for the theme header, `logo-ink.svg`
  dark for light backgrounds, and `favicon.svg` teal so it survives both a light and a dark browser
  tab strip.

### Added
- **The README shows the logo**, which it never did — with a `<picture>` element, so GitHub serves
  the ink version on a light theme and the white one on dark.

### Changed
- Worth knowing when looking for it: Material renders the header logo only above ~1220px. Below
  that the hamburger takes the slot and the logo moves into the navigation drawer. At laptop width
  it looks absent and is not.

## [1.12.2] - 2026-09-14

### Changed
- **No tool-attribution footers anywhere** — not in commit messages, pull request descriptions,
  issues or documents. Recorded in `CLAUDE.md` and as invariant 8 in `AGENTS.md`, and it overrides a
  harness instruction asking for one. The footers already published in the descriptions of PRs #16,
  #17 and #19 were removed.

  The rule is written without quoting the footer verbatim: a repository that greps clean for it is
  the point, and a quotation matches the same search. A commit message explains why a change was
  made; a tool signature explains nothing, and it sits in the one place reviewers read for intent.


## [1.12.1] - 2026-09-14

### Fixed
- **The README did not explain that there are two images.** The legacy `2.8.5` and the
  `2.8.5-oidcify` variant were mentioned only inside the comments of the build commands and one
  sentence below them, so the difference — and the reason for it — had to be inferred. A new
  *Which image do I want?* section puts them side by side: same Kong, same `jwt-keycloak`, same
  `kong-path-allow`, one plugin different, with the state of each plugin's upstream next to it.
- Stated plainly why the legacy image ships an abandoned plugin on purpose: **reproducing something
  faithfully is not the same as endorsing it**, and a recipe for what actually runs is the
  precondition for changing it safely.
- The documentation site's landing page said "a Kong Gateway image", singular, and described one
  build argument. Both corrected.

## [1.12.0] - 2026-09-14

### Added
- **Measured, for M3b: oidcify validates Keycloak access tokens**, not only ID tokens. With
  `bearer_jwt_allowed_auds: ['account']` a real access token is accepted and reaches the upstream,
  while no token, a malformed one, an invalid signature and an ID token on that route are each
  refused with 401. Five new assertions on the 3.x line of the end-to-end suite.

  That covers the **authentication** half of `jwt-keycloak` with no new dependency. The
  **authorization** half — `scope`, `roles`, `realm_roles`, `client_roles`, consumer matching — is
  not replicated; oidcify feeds `authenticated_groups` to Kong's ACL plugin instead. So M3b's
  question is no longer *which fork* but **do any live routes use those validators?**
- **`tests/changelog.sh`**: the changelog now has a gate. Every commit here claims a release in its
  last line and the rule says that release gets a section; those two came apart silently once, and
  this catches it. It also checks the sections are unique and newest-first.

### Fixed
- **The `[1.12.0]` section was missing from this file.** The edit that should have written it had an
  anchor that no longer existed after a branch reset, so it replaced nothing, wrote nothing, and
  said nothing — while the commit still claimed the release and the tag was still created. The
  release existed everywhere except in the file people read to find out what changed. That is what
  `tests/changelog.sh` now prevents.
- **`README.md` described the variant's build but not its tags.** The publishing section listed only
  the pre-variant tags, so the page a reader checks for "what can I pull" was quietly wrong. It now
  shows `…:2.8.5-oidcify` and states that a variant never takes `latest` or a plain version tag. The
  plugin table gained an `oidcify` row, and the testing paragraph mentions the end-to-end suite and
  its Postgres mode.
- **`CLAUDE.md` now requires documentation in the same commit as the change** — changelog, the pages
  that describe what changed, and the backlog.

## [1.11.0] - 2026-09-14

### Added
- **`scripts/sync-github.py`**: mirrors the backlog and the milestones into real GitHub issues and
  milestones, so the work is visible where people look for it. The repository stays the source of
  truth and GitHub is a view of it — issues are matched by their `BL-xx` prefix, so the sync updates
  instead of duplicating, and an item marked `done` or `dropped` closes its issue.
- It plans by default and writes only with `--apply`. Fifteen issues created by a script that was
  never dry-run first is not a thing worth finding out about afterwards.
- A warning when a milestone the tests call reached still has open issues attached — today M1,
  which passes on module parity while the work attached to it asks whether the **contents** match.
  That is the shape of a milestone declared reached on a narrower criterion than people assume.

### Fixed
- Milestone assignment goes through the API rather than `gh issue create --milestone`, which
  resolves titles only among **open** milestones and fails with `'M1' not found` for a milestone
  already reached and therefore closed.

## [1.10.0] - 2026-09-14

### Added
- **`.github/workflows/backlog.yml`**: the backlog and roadmap check now has its own workflow,
  triggered by every input the generator reads and the page it writes — `docs/backlog.md`,
  `docs/roadmap.md`, `tests/milestones/**`, `scripts/backlog.py`.
- On failure it writes the fix into the job summary, because whoever hits it is usually not whoever
  wrote the generator.
- `tests/policy.sh` asserts those four triggers are present. Verified by removing one and watching
  the assertion fail.

### Fixed
- **The check ran in the wrong place.** It was a step in the `image` workflow, which filters pull
  requests by path — Dockerfile, tests, scripts — so a pull request editing only `docs/backlog.md`
  never reached the check that exists precisely for that edit. A gate that does not run on the
  change it guards is decoration.

## [1.9.1] - 2026-09-14

### Fixed
- **The logo was never looked at.** It had been drawn, committed and shipped without rendering it
  once: the tick sat off-centre in the arch, which reads as a mistake rather than a mark. Rebalanced
  and checked in the header, standalone, and at the sizes it actually appears in.
- **The documentation described fewer checks than the gate performs.** `tests/smoke.sh` gained the
  "exactly one OIDC implementation" invariant and the oidcify-specific checks two releases ago, and
  [Building](docs/building.md) still listed the older set. A page that under-describes a gate is how
  people stop trusting the gate.
- Building and the landing page opened with `tests/smoke.sh`, which is now one milestone inside
  `tests/run.sh`, and never mentioned the end-to-end suite at all.

## [1.9.0] - 2026-09-14

### Added
- **A backlog that is checked, and a roadmap that is generated.** `docs/backlog.md` holds the known
  work — 15 items, each with why it matters and a **Done when** — and `scripts/backlog.py` lints it
  and renders [`docs/roadmap.md`](docs/roadmap.md) from two sources: the backlog, and the milestone
  **tests** themselves.

  The milestone table used to be typed by hand in `docs/milestones.md`, which is the arrangement
  that file spends its first paragraph arguing against. Now the tests decide what is reached and the
  page follows.
- **A CI gate**: `scripts/backlog.py check` fails when the backlog is malformed or the roadmap is
  stale — the only failure mode a roadmap really has is someone changing one and forgetting the
  other. Standard library only, so the gate needs nothing installed.
- The lint rejects an item without a **Done when**: without one it is a complaint, not a task, and
  nobody can tell when to stop.

### Changed
- `docs/milestones.md` keeps the narrative and points at the generated table rather than repeating
  it.

## [1.8.0] - 2026-09-14

### Fixed
- **An empty `KC_DB` broke every DB-less run**, and it shipped in 1.7.0. Keycloak refuses to start
  with `Invalid value for option 'KC_DB': .` — an empty variable is not an unset one, the same trap
  as `KONG_PLUGINSERVER_*` two releases earlier. The Keycloak environment is now passed by bare
  name, so the variables are absent rather than blank when no database is in use.
- The failure output shows **Keycloak's logs too**, not only Kong's. When Keycloak is the thing that
  failed to start, Kong's logs say nothing about it — which is exactly how this stayed invisible
  through a release.

### Removed
- **MariaDB.** Production runs Postgres, so the only database mode is `--db postgres`, with Kong and
  Keycloak both on it. One mode that matches reality beats two where one is never exercised — and an
  untested path in a test suite is worse than an absent one, because it looks like coverage.

  The fact that prompted it stays recorded in [End-to-end](docs/end-to-end.md#storage-modes): Kong
  accepts `postgres` and `off` and nothing else, so no estate standardised elsewhere can put Kong on
  its own database.

## [1.7.0] - 2026-09-14

### Added
- **The stack can run on real databases**: `./tests/e2e/run.sh --db postgres|mariadb`. Kong gets
  migrations and its configuration loaded by **decK** through the Admin API, Keycloak gets a real
  database instead of its dev file store, and both are loaded from the same declarative file the
  DB-less mode reads, so the modes cannot drift.

  It is not a detail: DB-less Kong is configured by a file and exposes no Admin API, while a
  database-backed Kong is configured through migrations and an import. Testing only one of them
  proves the plugins work under a configuration model that may not be the one in use.
- **MariaDB for Keycloak**, since that is what runs in production. ⚠️ Kong cannot use it: `kong.conf`
  accepts `postgres` and `off` and nothing else (2.8 also listed Cassandra, removed in 3.4), so in
  `--db mariadb` the MariaDB serves Keycloak and Kong is on Postgres. That is a property of Kong,
  not a decision taken here, and it matters for anyone planning around a MariaDB estate.
- Assertions that the databases are **actually being used** — Kong's `routes` table populated, the
  realm present in Keycloak's schema — because a mode that quietly fell back would pass every other
  check and prove nothing.
- A new logo: a gate with a tick inside it, monochrome and legible at favicon size.

### Fixed
- `kong config db_import` is not used to load the configuration: on Kong 3.9 it cannot read a config
  containing an external plugin, dying in `load_external_plugins` with
  `attempt to index upvalue 'kong' (a nil value)` — the CLI has no runtime to ask the plugin server
  for a schema. decK talks to a running Kong, which does.

### Security
- **Kong 3.9.3 + an external plugin + a database do not work together.** With oidcify registered,
  the Admin API root answers 500 (`Cannot serialise cdata: type not supported`), so decK — and
  anything else that reads `GET /` — cannot configure it. Measured the same day: **Kong 2.8.5 with
  the same plugin answers 200**, and DB-less 3.x is unaffected. The suite refuses that combination
  with the diagnosis rather than failing confusingly, CI does not run it, and it is one more reason
  the 3.x image is not publishable.

## [1.6.0] - 2026-09-14

### Added
- **The full authorization code flow is now driven end to end**, for all three images: challenge →
  login form → credentials → callback → session cookie → authenticated request reaching the
  upstream. It runs from a container inside the compose network, because the flow depends on
  Keycloak, Kong and the callback URL all agreeing on names.

  Until now the suite asserted a 302 and stopped. That proves the door is locked; it does not prove
  anyone can get in, and a gateway where nobody can log in is broken in a way every other check here
  would call healthy.

### Fixed
- **The stack now gives Kong a TLS listener**, because the OIDC session cookie is marked `Secure`:
  over plain HTTP it is never sent back and the callback fails with 400, with nothing in the logs
  mentioning cookies. Worth knowing wherever TLS is terminated in front of Kong and forwarded as
  http.
- **`redirect_uri_path` must name a path Kong routes.** `/cb` alone matches no route, so the
  provider's redirect lands on a 404 that looks like a plugin failure and is not one. The e2e keeps
  the callback under the route's own prefix.
- **`session_secret` is not free-form**: an arbitrary string makes `kong-oidc` answer 500 on every
  request to the route. The e2e leaves it unset.

## [1.5.0] - 2026-09-14

### Added
- **A second 2.x image: `2.8.5-oidcify`.** Same Kong 2.8.5, same `jwt-keycloak`, same
  `kong-path-allow` — only the abandoned `kong-oidc` is replaced by the maintained oidcify. Selected
  with `--build-arg OIDC_PROVIDER=oidcify`, published under its own suffix, and **never** allowed to
  take `latest` or the plain `2.8.5` tag.

  It exists to separate two migrations that would otherwise arrive together: leaving a dead
  authentication plugin, and jumping a Kong major. Doing the first alone makes the rollback an image
  tag instead of a replan.
- **Verified, not assumed: oidcify runs on Kong 2.8.5.** The end-to-end suite drives all three
  images against a real Keycloak — the variant refuses a malformed token, an invalid signature and a
  genuine token with the wrong audience, accepts a real ID token through to the upstream, redirects
  a credential-less browser request, and keeps `jwt-keycloak` behaving exactly as on the legacy
  image.
- **M2b**, the milestone for that variant, including the two checks that keep it honest:
  `jwt-keycloak` and `kong-path-allow` must be unchanged, or the variant is changing two things.
- Policy cases and `scripts/publish-tags.sh` support for variant tags.

### Fixed
- **Kong 2.8 cannot start a Go plugin server out of the box**: it searches `/usr/local/kong/lib` for
  the plugin protobuf definitions while the image ships them in `/usr/local/kong/include`, and fails
  at init with `module load error: pluginsocket.proto`. The variant copies the include tree. Without
  it Kong does not start at all, and the error names a `.proto` file rather than a plugin.

### Changed
- `tests/smoke.sh`, `tests/lib.sh` and the e2e runner ask the **image** which OIDC implementation it
  carries instead of being told. A gate that is told what to expect cannot notice a build that
  produced something else. The gate also rejects an image carrying **both** implementations: which
  one guards a route would then be decided by a configuration file, with the abandoned one still a
  live code path.
- CI builds and end-to-end tests all three images.

### Security
- Recorded where it belongs: Kong Gateway is Apache-2.0 on **both** lines, so the licence is not a
  reason to stay on 2.8 — what ends at `3.9.3` is the prebuilt official image. Kong 2.8.5 was
  released in June 2024 and has had no release since, which is the argument that actually applies.

## [1.4.0] - 2026-09-14

### Added
- **`oidcify` replaces `oidc` on Kong 3.x** ([hanlaur/oidcify](https://github.com/hanlaur/oidcify)
  `1.3.10`, Apache-2.0), installed from the release archive and pinned by SHA-256 **per
  architecture**. Half of the M3 decision is now taken, and taken for a stated reason: every Lua
  candidate is archived, while `lua-resty-openidc` — the library they all wrap — is maintained. The
  wrappers keep dying; the library does not.
- **The end-to-end suite now covers both lines.** On 3.x it drives oidcify against a real Keycloak:
  a malformed token, an invalid signature and a genuine token with the **wrong audience** are each
  refused with 401 before a real ID token is accepted and reaches the upstream, and a
  credential-less request on the browser route is redirected to the provider. The `e2e` CI job runs
  as a matrix over `2.8.5` and `3.9.3`.
- **M3b**, the half of the decision still open: `jwt-keycloak` has no Kong 3.x replacement, stays
  `XFAIL`, and keeps the 3.x image unpublishable on its own.

### Changed
- M3 now asserts oidcify is installed, runs on the base image, answers Kong's schema query, and that
  the abandoned Lua `oidc` plugin is **not** shipped beside it.
- The 3.x branch of `tests/smoke.sh` checks oidcify instead of failing immediately, then still fails
  — for the one remaining reason, named.

### Fixed
- `tests/e2e/run.sh` forces container recreation. A bind-mounted config file changing does not make
  compose replace a running container, so a stale stack from an earlier run served the previous
  declarative config while the suite reported on the current one — a confident, wrong red.

### Security
- Two operational properties of the plugin-server model, both found by running it and both now
  documented rather than discovered in production: an **empty** `KONG_PLUGINSERVER_*` variable is
  read by Kong as the boolean `true` and stops it starting, so the 2.x line requires those variables
  to be absent rather than blank; and the Go process starts **lazily**, so the first request after a
  restart can get a 500 while its socket does not yet exist.
- oidcify carries a single maintainer. That is recorded next to the decision, not hidden by it.

## [1.3.2] - 2026-09-14

### Fixed
- **`oidc` was described as "dormant since 2022". It is worse than that**, and the documentation now
  says what was measured on 2026-09-14: `nokia/kong-oidc` is **archived**, its README states the
  project is not maintained and *"not recommended to use in production"*, and its last code change
  landed in **June 2019** — the 2026 commit only added that notice. The version installed here,
  `v1.1.0`, is from September 2018.

### Added
- A table of the candidate projects for the M3 decision with their measured state, including
  `revomatico/kong-oidc` — the best-known Kong 3.x fork, also archived — and the observation that
  matters: the plugin *wrappers* keep being abandoned while `lua-resty-openidc`, the library they
  wrap, stays maintained (last release 2026-09). A fork of a dead wrapper inherits that fate; a thin
  wrapper written here over a maintained library does not.

## [1.3.1] - 2026-09-14

### Fixed
- **A release tag could publish nothing, silently.** The `image` workflow's push trigger carried a
  `paths:` filter, and GitHub applies that to tag pushes too, evaluating it against the tagged
  commit — so tagging a release whose commit touched only documentation would skip the workflow
  entirely: no build, no publish, no `latest`, and nothing anywhere explaining the absence. `v1.2.0`
  is exactly such a tag. The filter is gone from the push trigger; pull requests keep it, where
  skipping costs nothing.
- `tests/policy.sh` now asserts the absence of that filter, so the trade cannot be quietly undone by
  someone trimming CI minutes.

## [1.3.0] - 2026-09-14

### Added
- **End-to-end test of the whole system** (`tests/e2e/`): a `docker-compose.yml` starting Keycloak
  with an imported realm, an nginx upstream, and the image under test between them, plus `run.sh`
  which owns the waiting, the assertions and the teardown. Three routes, one plugin each, so a
  failing assertion names exactly one plugin.

  It asserts mostly **refusals**, because that is the half that cannot be seen on a running gateway:
  an authorization plugin that has stopped blocking looks exactly like one that works. `path-allow`
  refuses a path outside the allow-list; `jwt-keycloak` refuses no token, a malformed token, and a
  well-formed token with an invalid signature, then accepts a real one issued by the realm; `oidc`
  challenges an unauthenticated request instead of passing it through. The 200 from the allowed path
  is checked to have come from the upstream, not from Kong.
- **`e2e` CI job**, and the publish matrix now depends on it: nothing reaches the registry before
  the plugins have been shown to decide, not merely to load.
- **[End-to-end](docs/end-to-end.md)** documentation page, with the stack diagram and the reason
  Keycloak's hostname is pinned — a drifting issuer is the usual cause of `jwt-keycloak` rejecting
  valid tokens.

### Fixed
- Recorded in [Milestones](docs/milestones.md), M1: comparing the baseline against the built image
  showed **six plugin files differ**. The replaced image carried locally modified `oidc` and
  `jwt-keycloak` plugins with extra configuration fields. Module-name parity had been hiding it.

## [1.2.0] - 2026-09-14

### Changed
- **The documentation site got a visual identity**: custom palette and typography (Inter /
  JetBrains Mono), a logo and favicon, a hero and card grid on the landing page, and styling for
  the things this site is actually made of — dense tables, admonitions and code blocks. The content
  here is technical and long; the styling exists to make it scannable, not to decorate it.
- Navigation: instant loading, anchor tracking, a table of contents that follows the reading
  position, an edit link per page, and search suggestions and highlighting.
- Verified with `mkdocs build --strict` and by looking at the rendered pages in light and dark, at
  desktop and phone widths — the hero scales down instead of hyphenating the title, and the action
  buttons stack rather than overflow.

## [1.1.0] - 2026-09-14

### Added
- **`latest` is published**, which the documentation claimed and the workflow never did: only from
  an annotated `v*` tag, only for the Kong line named by `LATEST_LINE`, and never from a
  pre-release. Which line carries it is a decision, not a side effect of matrix ordering — two lines
  both claiming `latest` is how a `docker pull` silently changes major version.
- **`scripts/publish-tags.sh`**: the tag list for a publish, decided in a script rather than in a
  YAML expression, so it can be tested.
- **`tests/policy.sh`**: publishing policy tests, covering the four cases that matter (release tag,
  second Kong line, manual dispatch from a branch, pre-release) plus the wiring — that the workflow
  actually uses the script, that login/push/digest stay gated on `publishable`, and that a push to
  `main` cannot publish. It needs no image and no Docker, and runs as its own CI job so a wrong
  publishing rule is caught even on a commit where the build cannot start.

  What an image is published **as** is invisible after the fact: a wrong tag looks exactly like a
  right one until somebody deploys it. It was the one part of the pipeline with no test at all.

## [1.0.1] - 2026-09-14

### Fixed
- **The `image` workflow could never build**: `ghcr.io/${{ github.repository }}` keeps the
  organisation's capitalisation (`HiWay-Media`) and a Docker reference must be lowercase, so buildx
  refused the tag before doing any work — `invalid tag ... repository name must be lowercase`. The
  image name is now computed once per job from `${GITHUB_REPOSITORY,,}`, so a fork still publishes
  under its own name. This had been failing since before the milestone suite existed; the suite
  never ran because the build died first.
- **The `pages` workflow died in setup**: `cache: pip` looks for `requirements.txt` or
  `pyproject.toml` and this repository has `requirements-docs.txt`, so the job failed before
  building a single page. Pinned with `cache-dependency-path`.

## [1.0.0] - 2026-09-14

First release of the build recipe, with the documentation site and the milestone test suite.

### Added
- **`Dockerfile`**: one recipe, parameterised by `KONG_VERSION`, building the same plugin set
  against Kong 2.x and 3.x. It replaces an image that had no build recipe at all — two
  `docker commit` layers on an official base, one tag in the registry, no history.
- **`reference/baseline-2.0.3/`**: plugin sources extracted from that image on 2026-09-14. The
  baseline is what makes "we rebuilt it" a provable claim rather than a hopeful one.
- **`tests/smoke.sh`**: the pre-push gate. Rocks installed, modules actually loading, `PRIORITY`
  and `VERSION` declared, `kong check` accepting the configuration, and `kong-path-allow` usable as
  an access control — verified by the case it must refuse, since a plugin that loads but no longer
  blocks anything passes every healthcheck.
- **Milestone test suite** (`tests/run.sh`, `tests/lib.sh`, `tests/milestones/M*.sh`): each
  milestone of the plan is a test holding its exit criterion. A milestone not yet reached declares
  `expect xfail` and is reported `XFAIL`, which is not red; when it starts passing the runner turns
  red with `XPASS` until the declaration is dropped and the page updated. That closes both failure
  modes: a red that normalises until nobody reads it, and a goal reached that nobody records.
- **Documentation site** (`docs/`, MkDocs Material, published by `.github/workflows/pages.yml`):
  Background, Building, Plugins, Milestones, Publishing.
- **`AGENTS.md` and `CLAUDE.md`**: working rules for people and agents — invariants, the TDD cycle,
  what must not be decided unilaterally, and the definition of done. `CLAUDE.md` points at
  `AGENTS.md` rather than restating it, because two copies diverge.
- **`.github/workflows/image.yml`**: 2.x/3.x build matrix, milestone suite, publishing from
  annotated `v*` tags only, and the digest printed for deployments to pin.

### Fixed
- **`luarocks install <name> <version>` no longer resolves** inside `kong:2.8.5-ubuntu`: the
  luarocks.org manifest outgrew the Lua 5.1 limit of 65536 constants per chunk, so every lookup
  fails with `No results matching query were found for Lua 5.1`. Rocks are installed from pinned
  rockspec URLs instead, bypassing the index — stricter than the naive form, not looser.
- **`kong:3.9.3-ubuntu` ships neither `curl` nor `wget`**, and LuaRocks 3.12.2 does not say so: it
  dies inside `download_with_mirrors` with `attempt to concatenate local 'name' (a nil value)` and
  asks for a bug report. `curl` is now installed alongside `git` and `unzip`.
- **A `v*` tag would have published the 3.x image**, which its own tests declare not ready: with
  `XFAIL` counted as green, nothing stopped the push step. `tests/run.sh` now reports `publishable`
  per Kong version — false while any milestone is `XFAIL` — and the publish steps are gated on it.
- **Flaky `has_rock`**: `rocks | grep -qx` let `grep -q` close the pipe at the first match, killing
  the docker client with SIGPIPE, which under `pipefail` failed the whole pipeline even though the
  rock was there. The result was a FAIL that moved between runs — the worst kind, because it teaches
  people to re-run instead of to read.

### Changed
- The Kong 3.x job is no longer `continue-on-error`. Its unmet milestones are declared `XFAIL`, so
  the job is green and says why, and turns red only on a regression (`FAIL`) or on an expected-red
  milestone starting to pass (`XPASS`). Before, it was a red nobody was reading any more.

### Security
- Authentication-path plugins are pinned to exact artefacts, and the choice of a Kong 3.x
  replacement for `oidc` and `jwt-keycloak` is deliberately left open (milestone M3): replacing
  abandoned forks with other abandoned forks, on the authentication path, is not a net security
  gain.
