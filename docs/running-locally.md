# Running it locally

```bash
scripts/run-local.sh up
```

That builds the image if it is not there, starts Kong with a real Keycloak and an upstream behind it,
and **leaves it running**. The end-to-end suite starts the same stack, asserts against it and tears
it down — right for a test, useless for looking at something.

```
scripts/run-local.sh up [--db postgres] [--variant oidcify] [--kong 2.8.5]
scripts/run-local.sh status | logs [service] | token [access|id] | down
```

Nothing tears the stack down on its own. `scripts/run-local.sh down` when you are finished.

## What is up

| | |
|---|---|
| Proxy | <http://127.0.0.1:18000> |
| Keycloak | <http://127.0.0.1:18080> — admin / admin |
| User | `alice` / `alice-password`, realm `kong` |

Routes depend on the image, and the script prints the list it actually started with:

| Route | Plugin | Line |
|---|---|---|
| `/open/allowed`, `/open/secret` | `kong-path-allow` | all |
| `/jwt` | `jwt-keycloak` | 2.x |
| `/oidc` | `oidc` or `oidcify` — browser flow | all |
| `/api` | `oidcify`, refusals rather than redirects | the oidcify variant and 3.x |
| `/api-access` | `oidcify` validating **access** tokens | 3.x |

## The thing worth trying first

```bash
curl -i http://127.0.0.1:18000/open/allowed   # 200, reaches the upstream
curl -i http://127.0.0.1:18000/open/secret    # 403, kong-path-allow refuses it
```

The second one is the interesting request. `kong-path-allow` is an authorization control, and an
authorization control that has stopped refusing looks exactly like one that works: the process is up,
the plugin is loaded, healthchecks are green, and everything gets through.

With a real token from the realm:

```bash
TOKEN=$(scripts/run-local.sh token access)
curl -i -H "Authorization: Bearer $TOKEN" http://127.0.0.1:18000/jwt/anything
```

`token access` is what `jwt-keycloak` validates; `token id` is what `oidcify` validates by default.
Sending the wrong one is an easy way to spend an hour on a 401 that is behaving correctly.

## Watching it decide

```bash
scripts/run-local.sh logs kong
```

On the oidcify variant the first request that touches the plugin also starts the Go plugin server,
so the very first one can answer 500 while its socket does not exist yet. It is brief, it is
self-correcting, and it is in the logs.

## One stack, two callers

`scripts/run-local.sh` and the end-to-end suite share `tests/e2e/stack.sh`, which decides which
declarative config, plugin list and storage mode belong together. That is deliberate: a second copy
of that mapping would drift, and the first sign of it would be a test passing against a stack nobody
else runs.

!!! warning "Kong 3.x with a database cannot be configured"
    `--db postgres` together with a 3.x image is refused, with the reason printed. Kong 3.9.3's
    Admin API root answers 500 when an external plugin is registered, so decK cannot configure it.
    See [Storage modes](end-to-end.md#storage-modes).
