# Plugins

Three plugins beyond `bundled`. None ships with Kong.

| Plugin | Upstream | Pinned | Kong ≥ 3.0 |
|---|---|---|---|
| `kong-path-allow` | [seifchen/kong-path-allow](https://github.com/seifchen/kong-path-allow), Apache 2.0, on LuaRocks | `0.1-3` | ✅ bump to **`0.2-0`**, published for the 3.x line |
| `oidc` | [nokia/kong-oidc](https://github.com/nokia/kong-oidc) | `1.1.0-0` | ✅ replaced by **[oidcify](https://github.com/hanlaur/oidcify)** `1.3.10` |
| `jwt-keycloak` | [gbbirkisson/kong-plugin-jwt-keycloak](https://github.com/gbbirkisson/kong-plugin-jwt-keycloak) | `1.1.0-1` | ⚠️ fork only |

Supporting rocks, with where each comes from — the same question the plugins above get answered,
because a dependency on the authentication path deserves it too:

| Rock | Published by | Why it is here |
|---|---|---|
| `lua-resty-openidc 1.7.2-1` | [`hanszandbelt`](https://luarocks.org/modules/hanszandbelt/lua-resty-openidc) | the OIDC engine `kong-oidc` wraps; maintained upstream |
| `lua-resty-jwt 0.2.2-0` | [`cdbattags`](https://luarocks.org/modules/cdbattags/lua-resty-jwt) | JWT parsing for both auth plugins. The original author's line is dormant; this fork is the one LuaRocks serves |
| `lua-resty-cookie 0.1.0-1` | [`utix`](https://luarocks.org/modules/utix/lua-resty-cookie) | session cookies for `kong-oidc` |

Each is pinned to an exact rockspec URL, so none can move under a build.

## kong-path-allow

An allow/deny list over request paths, with optional regex matching. Small — a handler and a schema.

`0.1-3` is the Kong `< 3.0` line and `0.2-0` the Kong `>= 3.0` one; the Dockerfile picks by major.
Its porting cost is a version bump.

!!! warning "Matching is prefix-anchored, not full-match"
    The handler matches with `ngx.re.find(...)` and accepts when the match starts at position 1. It
    does not anchor the end. So an entry of `/public` also permits `/publicsecret`.

    For a deny list that errs safe. For an **allow** list it errs the other way, and it is worth
    checking real configurations against it rather than assuming intent.

    Anchor the **end** where a full match is what you mean — `/public$`. The start cannot be
    anchored: `allow_paths` uses Kong's path typedef, which rejects any value not beginning with a
    slash, so `^/public$` is refused when the configuration loads. (This page recommended exactly
    that until a test tried it and Kong would not start.) The end-anchored form is asserted in the
    end-to-end suite, in both directions.

## oidc

[nokia/kong-oidc](https://github.com/nokia/kong-oidc), built on `lua-resty-openidc`.

⛔ **Upstream declared it dead, and the repository is archived.** On 2026-05-18 the only commit in
seven years added this to the README:

> This project is not maintaned anymore. It is not recommended to use this project in production.

The repository is archived (read-only) and the last functional change landed in **June 2019**. The
released version this image installs, `v1.1.0`, is from **September 2018**.

⛔ **It also cannot run on Kong 3.x.** It extends `BasePlugin`, which Kong 3.0 removed. The rock is
no longer published on LuaRocks under that name, so this build installs it from the repository's own
`v1.1.0` tag.

!!! note "The engine underneath is alive"
    `lua-resty-openidc`, which does the actual OIDC work, is maintained — last released in 2026. It
    is the Kong-plugin wrapper around it that was abandoned, which is what makes "write the wrapper
    ourselves" a real option rather than a heroic one.

## oidcify — the Kong 3.x replacement for oidc

[hanlaur/oidcify](https://github.com/hanlaur/oidcify) `1.3.10`, Apache-2.0. Chosen because every Lua
candidate was already dead, and because the thing that keeps dying is the *wrapper*, not the library:
`lua-resty-openidc` is maintained and was released this month, while two successive Kong plugins
around it have been archived.

It is **not a Lua rock**. It is a Go binary built on Kong's Plugin Development Kit, which Kong starts
as an external plugin server. The image installs it at `/usr/local/bin/oidcify`, pinned by version
and SHA-256 per architecture; the runtime has to be told to use it:

```bash
KONG_PLUGINS=bundled,oidcify,kong-path-allow
KONG_PLUGINSERVER_NAMES=oidcify
KONG_PLUGINSERVER_OIDCIFY_QUERY_CMD="/usr/local/bin/oidcify -dump"
KONG_PLUGINSERVER_OIDCIFY_START_CMD="/usr/local/bin/oidcify"
```

!!! warning "An empty `KONG_PLUGINSERVER_*` is not an unset one"
    Kong reads an empty value as the boolean `true` and refuses to start:
    `pluginserver_oidcify_start_cmd is not a string: 'true'`. On the 2.x line these variables must be
    **absent**, not blank — which is why the compose file passes them through by bare name rather
    than defaulting them to `""`.

!!! danger "On Kong 3.9.3, an external plugin breaks the Admin API root"
    With oidcify registered, `GET /` on Kong 3.9.3's Admin API answers 500 —
    `Cannot serialise cdata: type not supported` — so decK, and anything else that reads that
    endpoint, cannot configure a database-backed Kong. Kong **2.8.5** with the same plugin answers
    200, and DB-less 3.x is unaffected. It is worth knowing before planning a 3.x migration that
    also keeps a database.

!!! warning "The browser flow needs TLS all the way to Kong"
    oidcify marks its session cookie `Secure`. If Kong serves the flow over plain HTTP — TLS
    terminated somewhere in front and forwarded as http, say — the cookie never comes back and the
    callback answers **400**, with nothing in the logs mentioning cookies. The end-to-end suite gives
    Kong a TLS listener for this reason.

!!! warning "The first request pays for a cold start"
    Kong starts the Go process lazily, on the first request that touches the plugin, and requests
    arriving before its socket exists get **HTTP 500** —
    `connect() to unix:/usr/local/kong/oidcify.socket failed`. It is brief and self-correcting, but
    it is real: after a restart, the first user through the door can see a 500. Worth a warm-up
    request in whatever starts the container.

Three more things to know before this reaches anything real:

- **Bus factor 1.** One maintainer, 24 stars. Alive today, with monthly releases and dependabot —
  not an institutional guarantee. The difference from `kong-oidc` is that this one is maintained
  *now*, not that it is safe forever.
- **The configuration is not compatible.** Field names differ throughout: every route using `oidc`
  is rewritten, not renamed. `redirect_unauthenticated: false` is what turns it from a browser flow
  into an API guard that answers 401.
- **It can stand in for `jwt-keycloak`'s token checks.** Allowing the `account` audience makes it
  validate Keycloak **access** tokens, which is what `jwt-keycloak` does today — measured, and
  asserted in the end-to-end suite. What it does not replicate is the role and scope validation;
  for that it feeds `authenticated_groups` to Kong's ACL plugin. See
  [Milestones, M3b](milestones.md#m3b-replacement-chosen-for-jwt-keycloak-on-kong-3x).
- **Bearer authentication is off until an audience is allowed.** `bearer_jwt_allowed_auds` must list
  the audience of the **ID token** — an access token carries a different one and is refused, which
  the end-to-end test asserts on purpose.

## jwt-keycloak

Validates Keycloak-issued access tokens. Reads its own priority from an environment variable at load
time, which is why the smoke test needs a `kong` stub to require it.

⚠️ **The upstream repository is archived** (last push August 2023). The author stopped maintaining
it and invited forks. A [Platformatory fork](https://github.com/Platformatory/kong-plugin-jwt-keycloak)
claims Kong 3.x support; it is small and lightly used — 4 stars, last pushed July 2024 — which is
worth knowing before it is put on an authentication path.

## The open decision

The Kong 3.x build installs only `kong-path-allow` and then **fails its smoke test on purpose**.

**`oidc` is decided: oidcify** (above). What remains open is `jwt-keycloak`, and it sits on the same
**authentication** path, with the same shape of problem: the upstream is archived and the only
non-archived fork is small and lightly used.

Measured on 2026-09-14, so the decision starts from facts rather than impressions:

| Project | Archived | Last push | Note |
|---|---|---|---|
| [nokia/kong-oidc](https://github.com/nokia/kong-oidc) | **yes** | 2026-05-18 | That push only added "not maintained"; last code change June 2019 |
| [revomatico/kong-oidc](https://github.com/revomatico/kong-oidc) | **yes** | 2024-04-12 | The best-known 3.x fork — also archived |
| [zmartzone/lua-resty-openidc](https://github.com/zmartzone/lua-resty-openidc) | no | 2026-09-05 | The engine both of them wrap. Maintained |
| [gbbirkisson/kong-plugin-jwt-keycloak](https://github.com/gbbirkisson/kong-plugin-jwt-keycloak) | **yes** | 2023-08-14 | Author invited forks |
| [Platformatory/…-jwt-keycloak](https://github.com/Platformatory/kong-plugin-jwt-keycloak) | no | 2024-07-25 | 4 stars, 1 fork |

The pattern is worth naming: the *plugin wrappers* keep being abandoned, while the *library* they
wrap stays maintained. A fork of a dead wrapper inherits the same fate; a thin wrapper written here,
over a maintained library, does not.

!!! danger "Replacing dead forks with other dead forks is not a security gain"
    It moves the debt rather than settling it. The work is real either way — but it should be chosen
    deliberately, with the tradeoff stated, not drifted into because an upgrade needed a green build.

A worthwhile question to settle first, and it is now sharper than it was: oidcify validates bearer
ID tokens itself. If the routes carrying `jwt-keycloak` only need signature, issuer and audience
checks, they may not need a second plugin at all — consolidating on one is cheaper than adopting
another unmaintained fork.

Until that decision is made, the 3.x image stays unpublishable: `M3b` is declared `XFAIL`, the
publish gate reads that, and a release tag skips the 3.x line on its own. A build that refuses to
ship tells the truth better than an image that claims to be ready.
