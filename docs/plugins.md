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

⛔ **It cannot run on Kong 3.x.** It extends `BasePlugin`, which Kong 3.0 removed. The upstream issue
asking for 3.x support has been open and unanswered since 2022, and the rock is no longer published
on LuaRocks under that name — this build installs it from the repository's own `v1.1.0` tag.

## jwt-keycloak

Validates Keycloak-issued access tokens. Reads its own priority from an environment variable at load
time, which is why the smoke test needs a `kong` stub to require it.

⚠️ **The upstream repository is archived.** The author stopped maintaining it and invited forks. A
[Platformatory fork](https://github.com/Platformatory/kong-plugin-jwt-keycloak) claims Kong 3.x
support.

## The open decision

The Kong 3.x build installs only `kong-path-allow` and then **fails its smoke test on purpose**.

`oidc` and `jwt-keycloak` have no chosen replacement. Both candidate paths are forks of abandoned
projects, and both sit on the **authentication** path.

!!! danger "Replacing dead forks with other dead forks is not a security gain"
    It moves the debt rather than settling it. The work is real either way — but it should be chosen
    deliberately, with the tradeoff stated, not drifted into because an upgrade needed a green build.

A worthwhile question to settle first: if the two plugins overlap in what they actually do across
your routes, consolidating on one is cheaper than porting both.

Until that decision is made, the red 3.x build is the correct output. A build that fails tells the
truth better than an image that claims to be ready.
