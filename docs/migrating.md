# Migrating off the replaced image

The image this repository builds installs the plugins from their **upstream rocks**. The image it
replaces carried **locally modified** copies. Six files differ, and the differences are not cosmetic:

| File | What the modification adds |
|---|---|
| `oidc/schema.lua` | a `timeout` config field |
| `oidc/utils.lua` | passes `timeout` through; adds header injectors |
| `oidc/handler.lua` | injects **`X-Access-Token`** and **`X-ID-Token`** into every authenticated request |
| `jwt-keycloak/schema.lua` | `internal_request_headers`, `redirect_after_authentication_failed_uri` |
| `jwt-keycloak/handler.lua` | implements both, reading a token another plugin left in `kong.ctx.shared` |
| `jwt-keycloak/validators/roles.lua` | logging only — no behaviour change |

## Two risks, and they fail very differently

**A rejected configuration.** A route using `internal_request_headers`,
`redirect_after_authentication_failed_uri` or the `oidc` `timeout` is refused by an image built from
the upstream rocks. Kong does not start. Loud, immediate, and easy to catch before a rollout.

!!! danger "Headers that simply stop arriving"
    The modified `oidc` plugin injects `X-Access-Token` and `X-ID-Token` into every authenticated
    request. The upstream rock does not. If a service behind the gateway reads either header, it
    stops receiving it — **with no error at the gateway, and none in Kong's logs**. Nothing fails;
    the request arrives without the identity the service expected, and what happens next depends
    entirely on how that service handles the absence.

    This is the one a test in this repository cannot find, because it lives in the services, not in
    the gateway.

## Answering it

Against a running Kong — read-only, GETs only:

```bash
scripts/check-live-config.sh http://<kong-admin-host>:8001
```

Or take a copy first, which is worth doing anyway:

```bash
scripts/dump-config.sh http://<kong-admin-host>:8001 ~/private-repo/kong-config/<zone>
scripts/check-live-config.sh ~/private-repo/kong-config/<zone>/plugins.json
```

!!! danger "The dump does not belong in this repository"
    A gateway's configuration names upstream hosts and services; this repository is public, and a
    file that lands here is public the moment it is pushed. `dump-config.sh` **refuses** to write
    inside it — that refusal is the point, not an inconvenience to work around.

    Fields whose names suggest a secret are redacted, and anything left that looks like a credential
    is reported. The scrub matches field *names*: a key pasted into a header transformation or a
    URL is invisible to it, so read the dump before committing it even privately.

## Why take a copy at all

The configuration of the gateway being replaced lives in a database and nowhere else — not in git,
not in the deployment manifests, which carry only the plugin list. So today nobody can diff two
zones, review a change before it is applied, or restore anything without a database backup.

A dump per zone makes all three possible, and it is the prerequisite for answering the questions
above for more than one zone at a time.

It reports which plugins are configured, whether any route uses a field only the modified plugins
accept, and whether `jwt-keycloak` is enforcing roles or scopes (which is what decides whether the
Kong 3.x line needs a replacement plugin at all — see [M3b](milestones.md#m3b-replacement-chosen-for-jwt-keycloak-on-kong-3x)).
It exits non-zero when something would be rejected, so it can gate a rollout.

For the header question, which it cannot see, grep the services behind the gateway:

```bash
grep -ril 'X-ID-Token\|X-Access-Token' <service sources>
```

## What the milestone checks

[M1](milestones.md#m1-parity-with-the-extracted-baseline) compares the **contents** of every baseline
module against the built image, with those six files listed as declared exceptions. A seventh file
drifting fails it — and so does one of the six ceasing to differ, which would mean the modification
had arrived upstream or been vendored here. Either is news.
