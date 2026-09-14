# Plugins

Three plugins beyond `bundled`. None ships with Kong.

| Plugin | Upstream | Pinned | Kong ≥ 3.0 |
|---|---|---|---|
| `kong-path-allow` | [seifchen/kong-path-allow](https://github.com/seifchen/kong-path-allow), Apache 2.0, on LuaRocks | `0.1-3` | ✅ bump to **`0.2-0`**, published for the 3.x line |
| `oidc` | [nokia/kong-oidc](https://github.com/nokia/kong-oidc) | `1.1.0-0` | ⛔ **none** |
| `jwt-keycloak` | [gbbirkisson/kong-plugin-jwt-keycloak](https://github.com/gbbirkisson/kong-plugin-jwt-keycloak) | `1.1.0-1` | ⚠️ fork only |

Supporting rocks: `lua-resty-openidc 1.7.2-1`, `lua-resty-jwt 0.2.2-0`, `lua-resty-cookie 0.1.0-1`.

## kong-path-allow

An allow/deny list over request paths, with optional regex matching. Small — a handler and a schema.

`0.1-3` is the Kong `< 3.0` line and `0.2-0` the Kong `>= 3.0` one; the Dockerfile picks by major.
Its porting cost is a version bump.

!!! warning "Matching is prefix-anchored, not full-match"
    The handler matches with `ngx.re.find(...)` and accepts when the match starts at position 1. It
    does not anchor the end. So an entry of `/public` also permits `/publicsecret`.

    For a deny list that errs safe. For an **allow** list it errs the other way, and it is worth
    checking real configurations against it rather than assuming intent. Anchor patterns explicitly
    (`^/public$`) where a full match is what you mean.

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

## jwt-keycloak

Validates Keycloak-issued access tokens. Reads its own priority from an environment variable at load
time, which is why the smoke test needs a `kong` stub to require it.

⚠️ **The upstream repository is archived** (last push August 2023). The author stopped maintaining
it and invited forks. A [Platformatory fork](https://github.com/Platformatory/kong-plugin-jwt-keycloak)
claims Kong 3.x support; it is small and lightly used — 4 stars, last pushed July 2024 — which is
worth knowing before it is put on an authentication path.

## The open decision

The Kong 3.x build installs only `kong-path-allow` and then **fails its smoke test on purpose**.

`oidc` and `jwt-keycloak` have no chosen replacement. Both candidate paths are forks of abandoned
projects, and both sit on the **authentication** path.

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

A worthwhile question to settle first: if the two plugins overlap in what they actually do across
your routes, consolidating on one is cheaper than porting both.

Until that decision is made, the red 3.x build is the correct output. A build that fails tells the
truth better than an image that claims to be ready.
