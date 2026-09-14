# Publishing

Images go to `ghcr.io/hiway-media/kong-gateway`.

```
ghcr.io/hiway-media/kong-gateway:2.8.5          # the line, moves with each release
ghcr.io/hiway-media/kong-gateway:2.8.5-v1.1.0   # one release, never repushed
ghcr.io/hiway-media/kong-gateway:latest         # the last release of the designated line
```

`latest` is published only from an annotated `v*` tag, only for the Kong line named by `LATEST_LINE`
in the workflow, and never from a pre-release such as `v1.1.0-rc.1`. Which line carries it is a
decision, not a side effect of matrix ordering: two lines both claiming `latest` is how a
`docker pull` silently changes major version.

Those rules live in `scripts/publish-tags.sh` rather than in a YAML expression, because
`tests/policy.sh` can then exercise them. What an image is published **as** cannot be checked after
the fact by pulling it: a wrong tag looks exactly like a right one until somebody deploys it.

Publishing happens only from an annotated `v*` tag, or from a manual `workflow_dispatch` that asks
for it. A push to `main` builds and tests but publishes nothing: `latest` should mean *the last
release*, not *the last commit somebody landed*.

Nothing is pushed before [the smoke test](building.md#what-the-smoke-test-checks) passes.

A tag also does not publish every line of the build matrix. The publish steps are gated on
`publishable`, which `tests/run.sh` reports per Kong version and which is false while **any**
milestone is still declared `XFAIL`. So tagging today publishes `2.8.5` and deliberately skips
`3.9.3`: an image whose own tests say two of its three plugins have no Kong 3.x replacement must not
be reachable by a `docker pull` that looks like a release. See [Milestones](milestones.md).

## Pin the digest

!!! danger "Pin the digest in your job specs, never the tag"
    A tag is a mutable pointer. Anyone — or any pipeline — can repush it, and deployments that
    follow the tag will pick up whatever is behind it at their next pull. A workload configured to
    always pull, on a scheduler that replaces instances one at a time without automatic rollback,
    will then replace healthy instances with broken ones and stay there.

    A digest cannot be moved. Pin it.

The publish job prints the digest to use:

```bash
docker buildx imagetools inspect ghcr.io/hiway-media/kong-gateway:2.8.5 \
  --format '{{println .Manifest.Digest}}'
```

## Before the first deployment

!!! warning "Check that your nodes can pull from GHCR"
    GHCR packages are private by default. Verify that every node that may schedule this workload —
    including any short-lived or auto-scaled ones — can `docker pull` without credentials.

    If the package stays private, the options are registry credentials in the workload definition,
    or mirroring the image into a registry the nodes already authenticate against. Either is fine;
    discovering the problem during a rollout is not.

## Verify against the baseline

Before replacing a running image, check that the new one is functionally equivalent to what it
replaces. The extracted sources in `reference/baseline-2.0.3/` exist for exactly this: diff them
against what the build installs, so an upgrade does not silently start from a different base.
