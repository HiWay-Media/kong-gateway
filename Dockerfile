# HiWay Media Kong Gateway — the image that previously had no recipe.
#
# The Kong 2.0.3 image this replaces was never built from a Dockerfile: `docker history` showed
# two `docker commit` layers on top of the official kong:2.0.3-ubuntu. Somebody shelled into a
# container, installed the plugins by hand and committed. Only one tag ever existed, with no
# history, and its base layer fetched Kong from bintray — shut down in 2021. Nobody could rebuild
# it. This file closes that gap.
#
# KONG_VERSION is an ARG because plugin versions differ per Kong major: 3.0 removed BasePlugin and
# made PRIORITY/VERSION mandatory. The matrix in .github/workflows/image.yml builds both lines from
# the same tree — that is how we measure the distance to 3.x without touching production.

ARG KONG_VERSION=2.8.5
# The base is pinned by digest, not by tag — the same rule this image asks of the deployments that
# run it. A tag can be repushed by its publisher; a digest cannot. The value comes from
# kong-base-digests.env, which is where the mapping from version to digest is kept and refreshed
# deliberately; the default below matches the default KONG_VERSION so a bare `docker build` is
# pinned too.
#
# Docker cannot choose a FROM conditionally, so the digest arrives as an argument. It is checked
# against the file by tests/policy.sh, because an argument that nobody verifies is a default waiting
# to go stale.
ARG KONG_DIGEST=sha256:a2b02d517849d74f861cf001ac72e1775549bcac0e95d85ed45593390d516a5b
FROM kong:${KONG_VERSION}-ubuntu@${KONG_DIGEST}

ARG KONG_VERSION
# Which OIDC implementation this image carries. Empty means "pick by Kong major": kong-oidc below
# 3.0, oidcify from 3.0 up, since kong-oidc cannot run there at all.
#
# The point of making it a variant rather than a rule is the 2.x line: `2.8.5` reproduces what runs
# today, bit for bit, while `2.8.5-oidcify` is the same Kong with a MAINTAINED OIDC plugin. That is
# a migration that can be tested and rolled back one image tag at a time, instead of being bundled
# into the jump to Kong 3.
ARG OIDC_PROVIDER=
USER root

# Every rock is pinned to an explicit rockspec URL rather than `luarocks install <name> <version>`.
# That is not stylistic — it is required:
#
#   The luarocks shipped inside kong:2.8.5 CANNOT PARSE the luarocks.org manifest any more.
#   The index outgrew the Lua 5.1 limit and the build dies with
#   "main function has more than 65536 constants". Resolving anything through the manifest — a
#   package or its dependencies — fails. Pinned rockspec URLs bypass the index entirely.
#
# So dependencies are installed explicitly, in order, with --deps-mode=none. A genuinely missing
# dependency is caught by tests/smoke.sh, which loads every module rather than trusting the install.
#
#   lua-resty-jwt / lua-resty-cookie   pulled in by kong-oidc; present in the production image,
#                                      absent from the kong:2.8.5 base
#   lua-resty-openidc  1.7.2-1         kong-oidc's engine
#   kong-oidc          1.1.0-0         nokia/kong-oidc. No longer published on LuaRocks under that
#                                      name, so it is installed from the repo's own v1.1.0 tag.
#                                      ⛔ Uses BasePlugin: incompatible with Kong 3.x.
#   jwt-keycloak       1.1.0-1         gbbirkisson, upstream archived
#   kong-path-allow    0.1-3 / 0.2-0   seifchen, Apache 2.0. 0.1-3 is the Kong < 3.0 line,
#                                      0.2-0 the Kong >= 3.0 one — picked at build time.

ARG RS=https://luarocks.org/manifests

# oidcify replaces kong-oidc on Kong >= 3.x. It is not a Lua rock: it is a Go binary that Kong runs
# as an external plugin server (KONG_PLUGINSERVER_*), which is a real change in operating model —
# one more process, and authentication stops if it dies.
#
# It was chosen over forking kong-oidc because every Lua fork on offer is already dead: nokia/
# kong-oidc is archived and its README says not to use it in production, and revomatico/kong-oidc,
# the best-known 3.x fork, is archived too. oidcify is maintained (releases roughly monthly) and
# Apache-2.0, but it carries one maintainer: that is a known risk, taken with eyes open, not a
# guarantee bought.
#
# Version and checksums are pinned per architecture: a release asset can be replaced upstream, and
# this one lands on the authentication path.
ARG OIDCIFY_VERSION=1.3.10
ARG OIDCIFY_SHA256_AMD64=af24422b5437939ba8a42381ae08e07cf46491a2c2ecc64facc79282313c155b
ARG OIDCIFY_SHA256_ARM64=e4f70ae8bd594bff2667a8bd8f9d4f654aa6509ecd7979faba21e29b824d152b
ARG TARGETARCH

RUN set -eux; \
    apt-get update; \
    # curl: kong:3.9.3-ubuntu ships no downloader at all, and LuaRocks 3.12.2 does not say so —
    # it dies inside download_with_mirrors with "attempt to concatenate local 'name' (a nil value)".
    apt-get install -y --no-install-recommends git unzip curl; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    KONG_MAJOR="${KONG_VERSION%%.*}"; \
    if [ "$KONG_MAJOR" -ge 3 ]; then \
        OIDC="${OIDC_PROVIDER:-oidcify}"; \
    else \
        OIDC="${OIDC_PROVIDER:-kong-oidc}"; \
    fi; \
    if [ "$KONG_MAJOR" -ge 3 ] && [ "$OIDC" = kong-oidc ]; then \
        echo "kong-oidc uses BasePlugin, removed in Kong 3.0: it cannot run on $KONG_VERSION" >&2; \
        exit 1; \
    fi; \
    echo "$OIDC" > /usr/local/share/kong-gateway-oidc-provider; \
    if [ "$KONG_MAJOR" -ge 3 ]; then \
        luarocks install --deps-mode=none "${RS}/seifchen/kong-path-allow-0.2-0.rockspec"; \
    elif [ "$OIDC" = oidcify ]; then \
        luarocks install --deps-mode=none "${RS}/cdbattags/lua-resty-jwt-0.2.2-0.rockspec"; \
        luarocks install --deps-mode=none "${RS}/gbbirkisson/kong-plugin-jwt-keycloak-1.1.0-1.rockspec"; \
        luarocks install --deps-mode=none "${RS}/seifchen/kong-path-allow-0.1-3.rockspec"; \
    else \
        luarocks install --deps-mode=none "${RS}/cdbattags/lua-resty-jwt-0.2.2-0.rockspec"; \
        luarocks install --deps-mode=none "${RS}/utix/lua-resty-cookie-0.1.0-1.rockspec"; \
        luarocks install --deps-mode=none "${RS}/hanszandbelt/lua-resty-openidc-1.7.2-1.rockspec"; \
        luarocks install --deps-mode=none \
            "https://raw.githubusercontent.com/nokia/kong-oidc/v1.1.0/kong-oidc-1.1.0-0.rockspec"; \
        luarocks install --deps-mode=none "${RS}/gbbirkisson/kong-plugin-jwt-keycloak-1.1.0-1.rockspec"; \
        luarocks install --deps-mode=none "${RS}/seifchen/kong-path-allow-0.1-3.rockspec"; \
    fi

RUN set -eux; \
    OIDC="$(cat /usr/local/share/kong-gateway-oidc-provider)"; \
    if [ "$OIDC" != oidcify ]; then exit 0; fi; \
    ARCH="${TARGETARCH:-amd64}"; \
    case "$ARCH" in \
        amd64) SHA="$OIDCIFY_SHA256_AMD64" ;; \
        arm64) SHA="$OIDCIFY_SHA256_ARM64" ;; \
        *) echo "oidcify: no pinned checksum for architecture $ARCH" >&2; exit 1 ;; \
    esac; \
    TGZ="oidcify_${OIDCIFY_VERSION}_linux_${ARCH}.tar.gz"; \
    curl -fsSL -o /tmp/oidcify.tgz \
        "https://github.com/hanlaur/oidcify/releases/download/v${OIDCIFY_VERSION}/${TGZ}"; \
    echo "${SHA}  /tmp/oidcify.tgz" | sha256sum -c -; \
    mkdir -p /tmp/oidcify; \
    tar -xzf /tmp/oidcify.tgz --strip-components=1 -C /tmp/oidcify; \
    install -m 0755 /tmp/oidcify/oidcify /usr/local/bin/oidcify; \
    install -D -m 0644 /tmp/oidcify/LICENSE /usr/local/share/oidcify/LICENSE; \
    rm -rf /tmp/oidcify /tmp/oidcify.tgz; \
    /usr/local/bin/oidcify -dump >/dev/null; \
    KONG_MAJOR="${KONG_VERSION%%.*}"; \
    if [ "$KONG_MAJOR" -lt 3 ]; then \
        # Kong 2.8's plugin-server loader searches /usr/local/kong/lib for the protobuf definitions,
        # but the image ships them in /usr/local/kong/include. Without this copy Kong 2.8 does not
        # start at all with a Go plugin: "module load error: pluginsocket.proto", then
        # "google/protobuf/descriptor.proto". It is a path bug in a Kong line that will get no more
        # releases, so it is worked around here rather than waited on.
        cp -r /usr/local/kong/include/. /usr/local/kong/lib/; \
    fi

# ⚠️ The >= 3 branch still has no replacement for jwt-keycloak, so a 3.x build FAILS its smoke test
# even with oidcify in place. That is intentional — a red build tells the truth better than an image
# claiming to be ready.
#
# oidcify is not loaded by being present: Kong must be told to run it. These belong in the runtime
# environment, not in the image, because setting them on a 2.x image would stop Kong from starting:
#
#   KONG_PLUGINS=bundled,oidcify,kong-path-allow
#   KONG_PLUGINSERVER_NAMES=oidcify
#   KONG_PLUGINSERVER_OIDCIFY_QUERY_CMD="/usr/local/bin/oidcify -dump"
#   KONG_PLUGINSERVER_OIDCIFY_START_CMD="/usr/local/bin/oidcify"

USER kong
