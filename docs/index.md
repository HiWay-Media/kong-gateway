# kong-gateway

A reproducible Kong Gateway image carrying three non-bundled plugins: **OIDC**, **JWT-Keycloak** and
**path-allow**.

```bash
docker build --build-arg KONG_VERSION=2.8.5 -t kong-gateway:2.8.5 .
./tests/smoke.sh kong-gateway:2.8.5 2.8.5
```

## What this is

One `Dockerfile`, parameterised by Kong version, that builds the same plugin set against more than
one Kong major — plus a smoke test that refuses to let a broken image be published.

It replaces an image that had **no build recipe at all**. That is the whole point, and
[Background](background.md) explains what was wrong and how the sources were recovered.

## Start here

| | |
|---|---|
| [Background](background.md) | Why this repository exists: an image built by `docker commit`, and what it cost |
| [Building](building.md) | How to build, and the LuaRocks trap that makes naive builds fail |
| [Plugins](plugins.md) | What each plugin is, which version, and where Kong 3.x breaks it |
| [Publishing](publishing.md) | GHCR tags, digest pinning, and pull access |

## Two things worth knowing up front

!!! warning "The Kong 3.x build is expected to fail"
    It is not broken — it is honest. Two of the three plugins have no chosen Kong 3.x replacement
    yet, so the 3.x build fails its smoke test by design. See
    [The open decision](plugins.md#the-open-decision).

!!! danger "Pin the digest, not the tag"
    A tag can be repushed underneath a running deployment; a digest cannot. The publish workflow
    prints the digest to use. See [Publishing](publishing.md#pin-the-digest).
