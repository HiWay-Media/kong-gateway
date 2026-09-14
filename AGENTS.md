# AGENTS.md — how work is done in this repository

Single source of truth for anyone working here, human or agent. `CLAUDE.md` points at this file:
the rules are written once, because two copies diverge and then nobody knows which one applies.

## What this repository is

The build recipe for a Kong Gateway image carrying three non-bundled plugins. It exists because the
image it replaces **was never built from a Dockerfile**: `docker history` showed two `docker commit`
layers on top of an official base, a single tag in the registry, and no history behind it. The full
account is in [docs/background.md](docs/background.md); the plan and its state are in
[docs/milestones.md](docs/milestones.md).

The work here is not "upgrade Kong". It is **making the image rebuildable and provable**. An image
that builds but whose contents nobody can account for is the starting point, not the finish line.

## Map

| Path | What it holds |
|---|---|
| `Dockerfile` | The recipe. `ARG KONG_VERSION` picks the Kong line, `ARG OIDC_PROVIDER` the OIDC implementation |
| `reference/baseline-2.0.3/` | Plugin sources extracted from the image being replaced. **Baseline, read-only** |
| `tests/smoke.sh` | The pre-push gate: what must be true before an image may be published |
| `tests/lib.sh` | Helpers and the result protocol (`PASS`/`FAIL`/`XFAIL`/`XPASS`/`SKIP`) |
| `tests/milestones/M*.sh` | One file per milestone: the milestone itself, in executable form |
| `tests/run.sh` | Runner and summary (also writes the GitHub Actions step summary) |
| `tests/policy.sh` | Publishing policy tests: which tags a release produces. Needs no image and no Docker |
| `tests/e2e/` | The system test: Keycloak, an upstream, and the image between them. `run.sh` owns the waiting and the teardown |
| `scripts/publish-tags.sh` | Decides the tag list for a publish — in a script so the policy test can exercise it |
| `docs/` | The published documentation site (MkDocs) |
| `docs/backlog.md` | Known work, with the reason attached. One section per item, parsed |
| `docs/roadmap.md` | **Generated.** Milestone state from the tests, plus the open backlog |
| `scripts/backlog.py` | Lints the backlog and renders the roadmap (`lint`, `render`, `check`) |
| `scripts/sync-github.py` | Mirrors backlog and milestones into GitHub issues and milestones (`--apply`) |
| `.github/workflows/image.yml` | 2.x/3.x build matrix, tests, and publishing from tags only |
| `plugins/` | Empty: for a plugin written in-house, should one ever be needed |

## Commands

```bash
docker build --build-arg KONG_VERSION=2.8.5 -t kong-gateway:2.8.5 .
./tests/run.sh kong-gateway:2.8.5 2.8.5
./tests/e2e/run.sh kong-gateway:2.8.5 2.8.5
```

Three images come out of this tree: `2.8.5` (what runs today), `2.8.5-oidcify` (the same Kong with a
maintained OIDC plugin, built with `--build-arg OIDC_PROVIDER=oidcify`), and `3.9.3`. The tests ask
each image which implementation it carries rather than being told, so a build that produced the
wrong one is caught instead of described.

The `kong:*-ubuntu` base images are amd64-only, so an arm64 workstation needs
`--platform linux/amd64` on the build and `DOCKER_PLATFORM=linux/amd64` in front of the tests.
Without it the error is `no match for platform in manifest`, which does not say so.

Verified on 2026-09-14: `2.8.5` → `PASS` on M0, M1, M2; `3.9.3` → `PASS` on M0, `XFAIL` on M3 and
M4 (both expected). Two traps met while actually building are written up in
[docs/milestones.md](docs/milestones.md), M0 — both surface as errors that say nothing about the cause, so
if a build fails incomprehensibly, read that before investigating from scratch.

## The TDD cycle

A milestone is not a line in a document someone will remember to update. It is a test.

1. **Declared red.** A milestone not yet reached has its test marked `expect xfail`. The test
   fails, and the runner records `XFAIL` — which is not red. It is declared, outstanding work.
2. **Work happens** on the `Dockerfile` until the test genuinely passes.
3. **XPASS.** The moment it does, the runner goes **red** with
   `milestone REACHED: drop expect xfail and update docs/milestones.md`.
4. **Green.** Drop `expect xfail`, update `docs/milestones.md`, and from then on a regression on that
   milestone is a real `FAIL`.

Step 3 looks like a nuisance and is the point of the whole mechanism: it stops a goal being reached
without anyone noticing, and stops a red staying red until it fades into the background. The 3.x
build, "expected to fail" with nothing tracking it, was already halfway to that.

### Adding backlog work

Add a section to `docs/backlog.md` — id, title, the metadata line, why it matters, and a
**Done when** — then regenerate:

```bash
python3 scripts/backlog.py render   # rewrites docs/roadmap.md
python3 scripts/backlog.py check    # what CI runs
```

An item without a *Done when* is a complaint, not a task: nobody can tell when to stop. The lint
rejects it. The roadmap is generated from the milestone **tests** and this file, so it cannot
disagree with either — and CI fails if it was not regenerated.

To make the same work visible on GitHub:

```bash
python3 scripts/sync-github.py           # show what would change
python3 scripts/sync-github.py --apply   # create and update issues and milestones
```

The repository stays the source of truth and GitHub is a view of it: issues are matched by their
`BL-xx` prefix, so the sync updates rather than duplicates, and an item marked `done` or `dropped`
closes its issue. Editing an issue body on GitHub is pointless — the next sync overwrites it, which
is deliberate: an issue tracker that disagrees with the repository is worse than an empty one,
because people trust it.

### Adding a milestone

A numbered file in `tests/milestones/` stating the exit criterion as observable `check`s:

```bash
source "$(dirname "$0")/../lib.sh"
milestone M5 "A title that states the exit criterion, not the activity"
expect xfail          # or: pass, once it is reached
only_major ge 3       # optional: skip rather than pretend to pass
check "what must be true" has_rock something
```

Then add it to `docs/milestones.md` under the same identifier.

## Invariants — not negotiable without saying so in the commit

1. **Pinned versions, never `latest`.** Rocks, base image, published tags alike. An artefact that
   moves under your feet cannot be reasoned about after the fact.
2. **Deployments pin the digest, not the tag.** A tag can be repushed underneath a running
   workload; a digest cannot. CI prints the digest to use.
3. **Publishing happens only from an annotated `v*` tag** (or an explicit dispatch). `latest` must
   mean *the last release*, not *the last commit*, and it names one line only — the one in
   `LATEST_LINE`. Changing the tag rules means changing `scripts/publish-tags.sh` and its cases in
   `tests/policy.sh`, never the workflow alone.
4. **A red test is not made green by deleting it, loosening it, or appending `|| true`.** Either the
   cause is fixed, or it is declared `expect xfail` with the reason written in the file.
5. **`reference/` is read-only.** It is the evidence of what was running. If the comparison against
   the baseline fails, the `Dockerfile` is wrong, not the baseline.
6. **Authorization controls are tested by what they refuse.** `kong-path-allow` decides which paths
   are permitted: a test that only proves the module loads would pass even if it stopped blocking
   anything. This holds for any plugin on the auth path.
7. **No secrets in the repository or in image layers.** Registry credentials come from the workflow.
8. **No tool-attribution footers** — not in commits, pull request descriptions, issues or
   documents, and not quoted verbatim when writing the rule itself. A commit message explains why a
   change was made; a tool signature explains nothing.
9. **A variant never takes a plain tag.** `2.8.5` means the image that reproduces production, and
   `latest` follows the default line only: a deployment must never be moved onto a different
   authentication plugin by a publish. `tests/policy.sh` asserts it.

## Open decisions — do not close them by drift

On Kong >= 3.0, `oidc` is settled: oidcify, a maintained Go plugin server, with its trade-offs
written up in [docs/plugins.md](docs/plugins.md). `jwt-keycloak` (gbbirkisson, archived) still has
none. It sits on the **authentication path**: swapping abandoned forks for other abandoned forks is
not a net security gain.

An agent does not pick the fork on behalf of whoever operates the service. It may gather the
candidates, diff them against `reference/`, report how maintained each one is — and leave the
decision written up in `docs/milestones.md` (M3) for the person who has to sign it.

## Definition of done

A change is done when the 2.x build passes, `./tests/run.sh` reports no `FAIL` and no `XPASS`, any
behaviour change is written into `docs/milestones.md`, and the commit says **why** — not what: the what
is already in the diff.

If something was not verified (build not run, tests not executed, plugin not exercised), say so
explicitly. An unverified "should work" is exactly the image this repository replaces: it looks
fine right up to the moment it is needed.
