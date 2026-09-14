# Background

## The image had no recipe

The Kong image this repository replaces ran in production for roughly six years. It was never built
from a `Dockerfile`.

`docker history` on it showed this at the top:

```
1b520e53d541 | kong docker-start | 80.8MB | 4 years ago
<missing>     | kong docker-start |  1.63MB | 6 years ago
```

Two `docker commit` layers on top of the official `kong:2.0.3-ubuntu`. Somebody had started a
container, installed the plugins by hand, and committed the result. The registry held **a single
tag**, with no history and no predecessor.

Three consequences followed from that, none of them visible until someone went looking:

- **Nobody could rebuild it.** Not "it would be inconvenient" — there was no recipe to follow. The
  only artefacts were the binary image in the registry and whatever copies sat in the local Docker
  storage of the nodes running it.
- **The base layer was already unbuildable.** It fetched Kong from bintray, which shut down in 2021.
  Even the upstream half could not be reproduced.
- **The exact plugin versions were unknown.** Nothing recorded them. They had to be read back out of
  the running artefact.

A mutable tag on a single unreproducible image is a failure waiting for a trigger. Any repush, any
registry cleanup, any node rescheduled onto a fresh host, and the only good copy is gone — with no
way to make another.

## What was recovered

The plugin sources were extracted from the image and are kept verbatim in
[`reference/baseline-2.0.3/`](https://github.com/HiWay-Media/kong-gateway/tree/main/reference/baseline-2.0.3).
They are the baseline: what this build produces should be functionally identical to what was running,
and that directory is what makes the comparison possible.

Reading the rock metadata back out also answered questions that had been open:

| Rock | Version found |
|---|---|
| `kong-oidc` | `1.1.0-0` |
| `kong-plugin-jwt-keycloak` | `1.1.0-1` |
| `kong-path-allow` | `0.1-3` |
| `lua-resty-openidc` | `1.7.2-1` |
| `lua-resty-jwt` | `0.2.2-0` |

It also corrected a belief that had survived unchallenged: **`kong-path-allow` was assumed to be an
in-house plugin** with no upstream, something that would need rewriting for Kong 3.x. Its rockspec
says otherwise — it is [`seifchen/kong-path-allow`](https://github.com/seifchen/kong-path-allow),
public on LuaRocks under Apache 2.0, and version `0.2-0` was published specifically for Kong 3.x.

That single fact moved the plugin from "rewrite" to "version bump", and cut the list of genuinely
unresolved plugins from three to two.

## What this does not fix

The two remaining plugins are still the hard part, and this repository does not make them easier —
it only makes the work possible. See [Plugins](plugins.md).
