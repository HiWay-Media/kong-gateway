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
FROM kong:${KONG_VERSION}-ubuntu

ARG KONG_VERSION
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

RUN set -eux; \
    apt-get update; \
    # curl: kong:3.9.3-ubuntu ships no downloader at all, and LuaRocks 3.12.2 does not say so —
    # it dies inside download_with_mirrors with "attempt to concatenate local 'name' (a nil value)".
    apt-get install -y --no-install-recommends git unzip curl; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    KONG_MAJOR="${KONG_VERSION%%.*}"; \
    if [ "$KONG_MAJOR" -ge 3 ]; then \
        luarocks install --deps-mode=none "${RS}/seifchen/kong-path-allow-0.2-0.rockspec"; \
    else \
        luarocks install --deps-mode=none "${RS}/cdbattags/lua-resty-jwt-0.2.2-0.rockspec"; \
        luarocks install --deps-mode=none "${RS}/utix/lua-resty-cookie-0.1.0-1.rockspec"; \
        luarocks install --deps-mode=none "${RS}/hanszandbelt/lua-resty-openidc-1.7.2-1.rockspec"; \
        luarocks install --deps-mode=none \
            "https://raw.githubusercontent.com/nokia/kong-oidc/v1.1.0/kong-oidc-1.1.0-0.rockspec"; \
        luarocks install --deps-mode=none "${RS}/gbbirkisson/kong-plugin-jwt-keycloak-1.1.0-1.rockspec"; \
        luarocks install --deps-mode=none "${RS}/seifchen/kong-path-allow-0.1-3.rockspec"; \
    fi

# ⚠️ The >= 3 branch deliberately installs only kong-path-allow: oidc and jwt-keycloak have no
# chosen replacement yet. A 3.x build FAILS its smoke test until that decision is made. That is
# intentional — a red build tells the truth better than an image claiming to be ready.

USER kong
