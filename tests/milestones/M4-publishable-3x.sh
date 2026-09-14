#!/usr/bin/env bash
# M4 — The 3.x image is publishable. It depends on M3: without replacements for oidc and
# jwt-keycloak the same gate that covers 2.x refuses to call it publishable, and rightly so.
#
# On Kong 3.x a handler without VERSION does not load. On 2.x it does — which is exactly why a
# missing one went unnoticed for years.
source "$(dirname "$0")/../lib.sh"

milestone M4 "Kong 3.x image is publishable"
expect xfail
only_major ge 3

check "the tests/smoke.sh gate also passes on Kong $KONG_VERSION" smoke
