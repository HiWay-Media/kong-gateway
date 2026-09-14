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
