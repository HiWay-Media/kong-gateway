#!/usr/bin/env bash
# M2 — The 2.x image is publishable: the plugins do not merely exist, they work.
#
# The exit criterion is exactly the pre-push gate, tests/smoke.sh: nothing is published unless that
# passes. The milestone calls it rather than restating it — two copies of the same check drift, and
# then neither can be trusted to describe the image.
source "$(dirname "$0")/../lib.sh"

milestone M2 "Kong 2.x image is publishable (pre-push gate)"
expect pass
only_major lt 3

check "the tests/smoke.sh gate passes" smoke
