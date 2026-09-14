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
