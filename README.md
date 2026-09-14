# kong-gateway

A reproducible Kong Gateway image carrying three non-bundled plugins: **OIDC**, **JWT-Keycloak**
and **path-allow**. Full documentation: [docs/](docs/index.md).

---

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
| `oidc` | [nokia/kong-oidc](https://github.com/nokia/kong-oidc) | `1.1.0-0` | ✅ replaced by **[oidcify](https://github.com/hanlaur/oidcify)** `1.3.10` — a Go plugin server, not a rock |
| `jwt-keycloak` | [gbbirkisson](https://github.com/gbbirkisson/kong-plugin-jwt-keycloak), archived | `1.1.0-1` | ⚠️ [Platformatory](https://github.com/Platformatory/kong-plugin-jwt-keycloak) fork, to evaluate |
| `lua-resty-openidc` | dependency of `kong-oidc` | `1.7.2-1` | not used — oidcify carries its own |
| `oidcify` | [hanlaur/oidcify](https://github.com/hanlaur/oidcify), Apache-2.0 | — | ✅ `1.3.10`, a Go plugin server. Also available on the 2.x line as the `-oidcify` variant |

## Build

```bash
# What runs today
docker build --build-arg KONG_VERSION=2.8.5 -t kong-gateway:2.8.5 .

# Same Kong, same jwt-keycloak, maintained OIDC plugin instead of the abandoned one
docker build --build-arg KONG_VERSION=2.8.5 --build-arg OIDC_PROVIDER=oidcify \
  -t kong-gateway:2.8.5-oidcify .

./tests/run.sh kong-gateway:2.8.5 2.8.5
./tests/e2e/run.sh kong-gateway:2.8.5-oidcify 2.8.5
```

CI builds **three images** from the same tree: `2.8.5` as it runs today, `2.8.5-oidcify` (the same
Kong with a maintained OIDC plugin), and `3.9.3`. The variant exists to separate two migrations that
would otherwise arrive together — leaving an abandoned plugin, and jumping a Kong major.

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
