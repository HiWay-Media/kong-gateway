# End-to-end

```bash
./tests/e2e/run.sh kong-gateway:2.8.5 2.8.5
```

The smoke test proves the plugins **load**. That is not the same as proving they **decide**.

An authorization plugin that has stopped blocking looks exactly like one that is working: the
process is up, the module is loaded, the configuration is accepted, every healthcheck is green, and
requests that should be refused sail through. Nothing short of driving real traffic through the
gateway can tell those two states apart.

So this suite starts the whole system — a real identity provider, a real upstream, and the image
under test between them — and asserts mostly what must be **refused**.

## The stack

```
                    ┌──────────────┐
  curl ────────────▶│     kong     │──────────▶ ┌──────────┐
  (host, :18000)    │ image under  │            │ upstream │  nginx, answers 200 and
                    │     test     │            └──────────┘  echoes the path it got
                    └──────┬───────┘
                           │ fetches realm keys, validates issuer
                           ▼
                    ┌──────────────┐
                    │   keycloak   │◀────────── curl asks for a token as alice
                    │ realm: kong  │            (host, :18080)
                    └──────────────┘
```

Three routes, one plugin each, so a failing assertion names exactly one plugin:

| Route | Plugin | Configured with |
|---|---|---|
| `/open` | `kong-path-allow` | `allow_paths: ['/allowed']` |
| `/jwt` | `jwt-keycloak` | `allowed_iss: ['http://keycloak:8080/realms/kong']` |
| `/oidc` | `oidc` | the realm's discovery document and a confidential client |

!!! note "Why `KC_HOSTNAME` is fixed"
    Keycloak derives the token issuer from the request host unless told otherwise, so a token
    fetched from the host (`localhost:18080`) would carry a different issuer than the one Kong
    expects. `jwt-keycloak` matches `allowed_iss` exactly and fetches the realm keys from that same
    URL: a drifting issuer is the usual reason this plugin rejects perfectly valid tokens.

## What it asserts

**`kong-path-allow`** — an allowed path reaches the upstream; a path outside the list is refused
with 403; and the 200 is checked to have come from the upstream rather than from Kong itself,
because "allowed" is only meaningful if the request actually went somewhere.

**`jwt-keycloak`** — refusals first: no token, a malformed token, and a well-formed token with an
invalid signature are each refused with 401. That third case is the one worth having: a plugin that
decodes without verifying passes the first two. Then a real token, obtained from the realm by
password grant, is accepted with 200.

**`oidc` / `oidcify`** — an unauthenticated request is redirected to the identity provider's
authorization endpoint rather than passed through, **and then the whole round trip is driven**:

```
1. an unauthenticated request is challenged
2. the identity provider serves a login form
3. alice logs in
4. the gateway exchanges the code and issues a session
5. the authenticated request reaches the upstream
```

A 302 proves the door is locked. It does not prove anyone can get in — and a gateway where nobody
can log in is broken in a way every other test here would call healthy. The round trip runs for all
three images, driven by a container with curl **inside** the compose network, because the flow
depends on names agreeing: Keycloak issues tokens for `http://keycloak:8080`, Kong expects that
issuer, and the callback has to reach a URL both can resolve.

!!! warning "The flow only completes over TLS"
    The OIDC session cookie is marked `Secure`, so over plain HTTP it is never sent back and the
    callback fails with **400** — with nothing in the logs pointing at cookies. The stack therefore
    gives Kong a TLS listener (`0.0.0.0:8443 ssl`, self-signed in DB-less mode) and the in-network
    browser accepts that certificate. In production this is a non-issue, provided TLS is not
    terminated in a way that leaves Kong serving the flow over http.

!!! warning "The callback must be a path Kong routes"
    With `kong-oidc`, `redirect_uri_path: /cb` sends the provider to a URL matching no route: the
    redirect lands on a **404** that looks like a plugin failure and is not one. Keeping the
    callback under the route's own prefix (`/oidc/cb`) is what makes the flow completable.

!!! warning "`session_secret` is not free-form"
    Setting it to an arbitrary string makes `kong-oidc` answer **500** on every request to the
    route — the underlying session library requires a key of a specific length. Unset is safer than
    wrong here, and the e2e leaves it unset for exactly that reason.

## The 3.x line is a different system

`run.sh` picks the declarative config and the plugin list from the Kong version, because the two
lines are no longer the same stack:

| | Kong 2.x | Kong 3.x |
|---|---|---|
| OIDC | `oidc` (Lua, in-process) | `oidcify` (Go, external plugin server) |
| JWT | `jwt-keycloak` | **nothing** — no replacement chosen (M3b) |
| Routes | `/open`, `/jwt`, `/oidc` | `/open`, `/api`, `/oidc` |

On 3.x the refusals are asserted against `/api`, which sets `redirect_unauthenticated: false`: an API
route must answer **401**, not bounce a machine client into a browser flow. `/oidc` keeps the default
and is used to assert the redirect. The absence of a `/jwt` route is deliberate — writing one anyway
would be the first step to forgetting that the decision is still open.

!!! warning "The first request pays for a cold start"
    Kong starts the Go plugin server lazily, on the first request that touches the plugin, and
    anything arriving before its socket exists gets a 500. The suite waits that out explicitly rather
    than hiding it behind a retry, because it is a real property of this plugin model: after a
    restart, the first user through the door can see a 500.

## Running it

`tests/e2e/run.sh` owns the lifecycle: it starts the stack, waits for the realm and the proxy to
answer (rather than sleeping a guessed number of seconds — Kong under emulation and Keycloak
importing a realm take wildly different times on different machines), runs the assertions, prints
Kong's last 40 log lines if anything failed, and tears everything down on the way out, including on
failure.

On an arm64 workstation the Kong image runs under emulation: set `DOCKER_PLATFORM=linux/amd64`.

In CI this runs as its own job, once per Kong line, and the publish matrix depends on it: nothing
reaches the registry before the plugins have been shown to decide.
