# kong-gateway

Reproducible Kong Gateway images carrying three plugins Kong does not bundle: **OIDC**,
**JWT-Keycloak** and **path-allow**. Full documentation: [docs/](docs/index.md).

---

## Which image do I want?

One `Dockerfile` builds **two published images**, and the difference between them is one plugin:

| | `2.8.5` | `2.8.5-oidcify` |
|---|---|---|
| Kong | 2.8.5 | 2.8.5 — **the same** |
| OIDC | [`nokia/kong-oidc`](https://github.com/nokia/kong-oidc) `1.1.0` | **[`oidcify`](https://github.com/hanlaur/oidcify) `1.3.10`** |
| …its upstream | ⛔ archived; its README says not to use it in production; last code change June 2019 | ✅ maintained, releases roughly monthly, Apache-2.0 |
| …what it is | a Lua plugin, in-process | a Go binary Kong runs as an external plugin server |
| `jwt-keycloak` | `1.1.0-1` | `1.1.0-1` — **unchanged** |
| `kong-path-allow` | `0.1-3` | `0.1-3` — **unchanged** |
| What it is for | reproducing what runs today, bit for bit | getting off the abandoned OIDC plugin |

**`2.8.5` is the legacy image.** It exists so that the thing currently in production can be rebuilt
from a recipe instead of from a `docker commit` nobody can account for. It carries a plugin whose
authors have publicly abandoned it, and that is deliberate: reproducing something faithfully is not
the same as endorsing it.

**`2.8.5-oidcify` is the way off it.** Same Kong, same `jwt-keycloak`, same `kong-path-allow` — only
the OIDC plugin is replaced. That is the whole point: it separates two migrations that would
otherwise arrive together, leaving an abandoned plugin and jumping a Kong major. Doing the first
alone makes a rollback **one image tag**, not a replan.

Both are driven through a real Keycloak by the [end-to-end suite](docs/end-to-end.md), including a
full browser login, so "the variant works" is a measurement rather than a hope.

A third line, **`3.9.3`**, builds from the same tree and is **not publishable yet**: `jwt-keycloak`
has no Kong 3.x replacement, so its tests declare that outstanding and the publish step skips it on
its own. See [the open decision](#-the-open-decision).

## Why this repository exists

The image this replaces was never built from a Dockerfile. `docker history` showed two
`docker commit` layers on top of the official `kong:2.0.3-ubuntu`: somebody shelled into a
container, installed the plugins by hand and committed the result. The registry held **a single
tag**, with no history behind it.

So it was an image nobody could rebuild — and its base layer fetched Kong from **bintray**, shut
down in 2021, so the upstream was not reproducible either.

The plugin sources were recovered by extracting them from that image on 2026-09-14 and live in
[`reference/baseline-2.0.3/`](reference/baseline-2.0.3/). That is the baseline: it is what proves
this Dockerfile produces what was actually running.

## What is inside

| Plugin | Origin | In the 2.0.3 image | For Kong ≥ 3.0 |
|---|---|---|---|
| `kong-path-allow` | [seifchen](https://github.com/seifchen/kong-path-allow), Apache 2.0, public on LuaRocks | `0.1-3` | ✅ **`0.2-0`**, published for the 3.x line |
| `oidc` | [nokia/kong-oidc](https://github.com/nokia/kong-oidc) | `1.1.0-0`, in the `2.8.5` image only | ⛔ cannot run — replaced by `oidcify` |
| `jwt-keycloak` | [gbbirkisson](https://github.com/gbbirkisson/kong-plugin-jwt-keycloak), archived | `1.1.0-1` | ⚠️ [Platformatory](https://github.com/Platformatory/kong-plugin-jwt-keycloak) fork, to evaluate |
| `lua-resty-openidc` | dependency of `kong-oidc` | `1.7.2-1` | not used — oidcify carries its own |
| `oidcify` | [hanlaur/oidcify](https://github.com/hanlaur/oidcify), Apache-2.0 | — | ✅ `1.3.10`, a Go plugin server — used by `2.8.5-oidcify` and by the whole 3.x line |

## Build

`KONG_VERSION` picks the Kong line; `OIDC_PROVIDER` picks the OIDC plugin. Everything else is shared.

```bash
# The legacy image: what runs today, rebuilt from a recipe
docker build --build-arg KONG_VERSION=2.8.5 -t kong-gateway:2.8.5 .

# The variant: same Kong, same jwt-keycloak, maintained OIDC plugin
docker build --build-arg KONG_VERSION=2.8.5 --build-arg OIDC_PROVIDER=oidcify \
  -t kong-gateway:2.8.5-oidcify .

# The 3.x line, where kong-oidc cannot run at all
docker build --build-arg KONG_VERSION=3.9.3 -t kong-gateway:3.9.3 .

./tests/run.sh kong-gateway:2.8.5 2.8.5              # milestones, including the pre-push gate
./tests/e2e/run.sh kong-gateway:2.8.5-oidcify 2.8.5  # the whole system, with a real Keycloak
```

CI builds and tests all three from every commit.

Both Kong lines are Apache-2.0: the licence is not what forces staying on 2.8. What ends at `3.9.3`
is the prebuilt official image. 2.8.5 was released in June 2024 and has had no release since.

On an arm64 workstation the `kong:*-ubuntu` base images have no native manifest: use
`--platform linux/amd64` for the build and `DOCKER_PLATFORM=linux/amd64` in front of the tests.
Without it the error is `no match for platform in manifest`, which does not say so.

## Milestones and tests

Each phase of the plan has a test holding its exit criterion: `tests/milestones/M*.sh`. A milestone
not reached yet is declared `expect xfail` — its test fails **on purpose** and the runner records
`XFAIL`, not red. When it starts passing, the runner goes red (`XPASS`) until the declaration is
dropped and the document updated. That closes both gaps: reds that normalise, and goals reached
that nobody records.

Beyond the image, `tests/e2e/` starts the whole system — a real Keycloak, an upstream, and the image
between them — and drives the full login round trip. It runs DB-less or on Postgres
(`--db postgres`), because how Kong is configured differs between the two.

State lives in [docs/milestones.md](docs/milestones.md) and the generated
[roadmap](docs/roadmap.md); known work in [docs/backlog.md](docs/backlog.md); working rules, for
people and agents, in [AGENTS.md](AGENTS.md).

## ⛔ The open decision

**The 3.x build does not pass yet, and that is declared.** `oidc` is settled — oidcify replaces it,
and the end-to-end suite proves it refuses and accepts the right things (milestone `M3`, green).
`jwt-keycloak` still has no chosen replacement (milestone `M3b`, `XFAIL`), so the 3.x image stays
unpublishable and a release tag skips that line by itself.

A goal declared missing is better than an image that claims to be ready and is not. Once the
decision is made — which fork, or whether to consolidate both plugins into one — the line is added,
the test turns `XPASS`, and it stays red until `docs/milestones.md` records which fork was chosen and why.

⚠️ Replacing abandoned forks with **other** abandoned forks, on the authentication path, is not a
net security gain. It is a decision to take with eyes open, not one to drift into.

## Publishing

Only from an annotated `v*` tag (or an explicit manual dispatch). A push to `main` builds and tests
without publishing: `latest` must mean *the last release*, not *the last commit*.

```
ghcr.io/hiway-media/kong-gateway:2.8.5                  # the line, moves with each release
ghcr.io/hiway-media/kong-gateway:2.8.5-v1.1.0           # one release, never repushed
ghcr.io/hiway-media/kong-gateway:latest                 # the last release of the designated line
ghcr.io/hiway-media/kong-gateway:2.8.5-oidcify          # the variant: same Kong, maintained OIDC
ghcr.io/hiway-media/kong-gateway:2.8.5-oidcify-v1.1.0   # one release of the variant
```

`latest` is published only from a `v*` release tag, for one Kong line only, and never from a
pre-release. A **variant never takes `latest` or a plain version tag**: `2.8.5` must keep meaning the
image that reproduces what runs today, and no publish may move a deployment onto a different
authentication plugin. The rules live in `scripts/publish-tags.sh` and are tested by
`tests/policy.sh`.

⚠️ **Deployments must pin the digest, not the tag.** A tag can be repushed underneath a running
workload; a digest cannot. CI prints the digest to use.
