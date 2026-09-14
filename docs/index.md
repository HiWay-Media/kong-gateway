---
hide:
  - navigation
---

<div class="kg-hero" markdown>
<span class="kg-kicker">Reproducible by construction</span>

# kong-gateway

A Kong Gateway image carrying three plugins Kong does not bundle — **OIDC**, **JWT-Keycloak** and
**path-allow** — built from one `Dockerfile`, checked by a test suite that refuses to let a broken
image be published, and pinned to exact artefacts from end to end.

<div class="kg-actions">
<a class="kg-primary" href="building/">Build it</a>
<a class="kg-ghost" href="background/">Why it exists</a>
<a class="kg-ghost" href="milestones/">Where it stands</a>
</div>
</div>

```bash
docker build --build-arg KONG_VERSION=2.8.5 -t kong-gateway:2.8.5 .
./tests/run.sh kong-gateway:2.8.5 2.8.5
```

## What this is

One `Dockerfile`, parameterised by Kong version, building the same plugin set against more than one
Kong major — plus a gate that runs before anything is published.

It replaces an image that had **no build recipe at all**: two `docker commit` layers on top of an
official base, one tag in the registry, no history behind it. [Background](background.md) covers
what that cost and how the sources were recovered.

<div class="grid cards" markdown>

-   :material-history:{ .lg .middle } **Background**

    ---

    An image built by `docker commit`, a base layer fetching Kong from a service shut down in 2021,
    and what it takes to get back to a recipe.

    [:octicons-arrow-right-24: Read it](background.md)

-   :material-hammer-wrench:{ .lg .middle } **Building**

    ---

    How to build both Kong lines from one tree — and the LuaRocks trap that makes the obvious
    Dockerfile fail with an error that says nothing.

    [:octicons-arrow-right-24: Build it](building.md)

-   :material-puzzle:{ .lg .middle } **Plugins**

    ---

    What each plugin does, which version is pinned, where Kong 3.x breaks it, and one matching
    quirk worth checking your configuration against.

    [:octicons-arrow-right-24: Inspect them](plugins.md)

-   :material-lan-connect:{ .lg .middle } **End-to-end**

    ---

    The whole system running: Keycloak issuing real tokens, an upstream to protect, and the image
    between them — asserting mostly what must be refused.

    [:octicons-arrow-right-24: Run it](end-to-end.md)

-   :material-flag-checkered:{ .lg .middle } **Milestones**

    ---

    Every phase of the plan is a test holding its exit criterion. What is reached, what is
    declared outstanding, and what that blocks.

    [:octicons-arrow-right-24: See the state](milestones.md)

-   :material-package-up:{ .lg .middle } **Publishing**

    ---

    Which tags a release produces, why `latest` names exactly one line, and why deployments pin the
    digest instead.

    [:octicons-arrow-right-24: Publish safely](publishing.md)

-   :material-shield-check:{ .lg .middle } **The open decision**

    ---

    Two of the three plugins have no chosen Kong 3.x replacement. They sit on the authentication
    path, so the choice is deliberately left visible rather than made by drift.

    [:octicons-arrow-right-24: The decision](plugins.md#the-open-decision)

</div>

## Two things worth knowing up front

!!! warning "The Kong 3.x build is not publishable, and says so"
    It is not broken — it is honest. Two of the three plugins have no chosen Kong 3.x replacement,
    so the 3.x milestones are declared `XFAIL` and the publish step is gated on them. A release tag
    publishes the 2.x line and skips 3.x without anyone having to remember.

!!! danger "Pin the digest, not the tag"
    A tag can be repushed underneath a running deployment; a digest cannot. The publish workflow
    prints the digest to use. See [Publishing](publishing.md#pin-the-digest).
