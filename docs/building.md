# Building

```bash
docker build --build-arg KONG_VERSION=2.8.5 -t kong-gateway:2.8.5 .
./tests/smoke.sh kong-gateway:2.8.5 2.8.5
```

On an arm64 workstation the base image is amd64-only, so build and test under emulation:

```bash
docker build --platform linux/amd64 --build-arg KONG_VERSION=2.8.5 -t kong-gateway:2.8.5 .
DOCKER_PLATFORM=linux/amd64 ./tests/smoke.sh kong-gateway:2.8.5 2.8.5
```

`KONG_VERSION` selects both the base image and the plugin set, so one tree builds several Kong
majors. A second argument, `OIDC_PROVIDER`, selects the OIDC implementation — which is what makes
the variant below possible.

## Three images from one tree

| Build | OIDC | Why it exists |
|---|---|---|
| `KONG_VERSION=2.8.5` | `kong-oidc` (Lua) | Reproduces what runs today, bit for bit |
| `KONG_VERSION=2.8.5 OIDC_PROVIDER=oidcify` | `oidcify` (Go) | Same Kong, same `jwt-keycloak`, **maintained** OIDC |
| `KONG_VERSION=3.9.3` | `oidcify` (Go) | `kong-oidc` cannot run on 3.x at all |

```bash
docker build --build-arg KONG_VERSION=2.8.5 --build-arg OIDC_PROVIDER=oidcify \
  -t kong-gateway:2.8.5-oidcify .
./tests/e2e/run.sh kong-gateway:2.8.5-oidcify 2.8.5
```

The variant exists to separate two migrations that would otherwise arrive together: getting off an
abandoned OIDC plugin, and jumping a Kong major. It does the first alone — same Kong 2.8.5, same
`jwt-keycloak`, same `kong-path-allow`, one plugin swapped — so a rollback is a tag, not a replan.
The end-to-end suite runs against all three.

!!! note "Both Kong lines are open source — that is not what changes at 3.x"
    Kong Gateway is Apache-2.0 on both lines; nothing about the licence forces staying on 2.8.5.
    What ends is the **prebuilt official image**: Docker Hub's `kong` library has tags up to
    `3.9.3` and nothing for `3.10` or later. And 2.8.5 is not standing still by choice — it was
    released in June 2024 and has had no release since, while 3.9.3 was released in June 2026.

!!! warning "Kong 2.8 cannot start a Go plugin out of the box"
    It looks for the plugin-server protobuf definitions in `/usr/local/kong/lib`, and the image
    ships them in `/usr/local/kong/include`. Without a copy, Kong 2.8 fails at init with
    `module load error: pluginsocket.proto` — and then, once that is fixed,
    `google/protobuf/descriptor.proto`. The Dockerfile copies the whole include tree for the 2.x
    variant. It is a path bug in a line that will get no further releases, so it is worked around
    rather than waited on.

## ⚠️ The LuaRocks trap

The obvious Dockerfile does not work:

```dockerfile
RUN luarocks install kong-oidc 1.1.0-0     # fails
```

```
Warning: Failed searching manifest: Failed loading manifest for https://luarocks.org:
  main function has more than 65536 constants
Error: No results matching query were found for Lua 5.1.
```

The LuaRocks client shipped inside older Kong images **can no longer parse the luarocks.org
manifest**. The public index outgrew the Lua 5.1 limit on constants per chunk, so loading it aborts.
Every lookup that goes through the manifest fails — the package you asked for, and each of its
dependencies.

This is worth naming plainly: it is not a transient outage, and it does not get better. An old
toolchain quietly loses the ability to reach the modern package index, and the first symptom is that
a build which "should obviously work" does not.

The fix is to bypass the index and install from pinned rockspec URLs:

```dockerfile
RUN luarocks install --deps-mode=none \
      "https://luarocks.org/manifests/seifchen/kong-path-allow-0.1-3.rockspec"
```

`--deps-mode=none` is required for the same reason: dependency resolution would go back through the
manifest. So dependencies are installed explicitly, in order, and their correctness is checked at
test time rather than at build time.

This is stricter than the naive form, not looser: every rock is pinned to one exact artefact, and a
rock that moves upstream cannot move under the build.

## Milestones

`tests/smoke.sh` answers one question: may this image be published? The milestone suite answers the
wider one — how far along the plan this image is:

```bash
./tests/run.sh kong-gateway:2.8.5 2.8.5
```

Each file in `tests/milestones/` holds one exit criterion. A milestone not reached yet is declared
`expect xfail`: it fails on purpose and is reported as `XFAIL`, not as a failure. When it starts
passing the runner goes red (`XPASS`) until the declaration is dropped and [`milestones.md`](milestones.md) updated,
so that neither a normalised red nor an unrecorded green can sit there unnoticed.

## Beyond the image

The smoke test and the milestones inspect an image. [End-to-end](end-to-end.md) runs the whole
system — Keycloak, an upstream, and the image between them — and asserts what the plugins refuse.

## What the smoke test checks

`tests/smoke.sh` runs before anything is published. It is deliberately not a healthcheck.

- **rocks are installed** — the shallowest check, and the least meaningful on its own
- **modules load** — installing a rock proves a file was copied; requiring the module proves its
  dependencies actually resolved, which is precisely what `--deps-mode=none` does not verify at
  build time
- **`PRIORITY` and `VERSION` are declared** — Kong 3.0 refuses to load a plugin without `VERSION`;
  Kong 2.x does not, which is exactly how a missing one goes unnoticed for years
- **Kong accepts the configuration** with all plugins enabled
- **`kong-path-allow` is usable as an access control**

!!! note "Handlers need a stub"
    Plugin handlers touch the `kong` global at module scope, so a bare `require` outside the Kong
    runtime fails for reasons that say nothing about the image. The test injects a minimal stub. That
    is the honest harness: it still proves the file parses and its requires resolve, without
    pretending to be a running gateway.

!!! warning "An authorization control is tested by what it refuses"
    `kong-path-allow` decides which paths are permitted. A plugin that loads but no longer blocks
    anything passes every healthcheck and every positive test. Any test added here for it must keep
    asserting the negative case.
