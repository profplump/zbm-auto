#!/bin/bash
# vim: softtabstop=2 shiftwidth=2 expandtab
#
# One-step build: (re)builds the local image from Dockerfile, then runs
# this directory's config/hooks through the pinned upstream
# zbm-builder.sh (see zfsbootmenu/, a submodule), writing build products
# to ./build. With no arguments this is the whole build; anything passed
# here is forwarded as extra arguments to the container's build-init.sh /
# generate-zbm (see build-init.sh -h inside the image, or CODE.md).
#
# Needs zfsbootmenu/ checked out: `git submodule update --init`.

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

./build-image.sh

mkdir -p build

exec ./zfsbootmenu/zbm-builder.sh \
  -b . \
  -i localhost/zbm-auto-builder:latest \
  -O -v -O "$(readlink -f build):/output" \
  -- -o /output "$@"
