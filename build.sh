#!/bin/sh

# One-step build:
# - Builds a local image from Dockerfile
# - Adds config/hooks using upstream's zbm-builder.sh
# - Writes build products to ./build

# Setup
set -eu
cd "$(dirname "$(readlink -f "$0")")"
mkdir -p build

# Fetch zfsbootmenu if it looks empty
if [ ! -e zfsbootmenu/zbm-builder.sh ]; then
  git submodule update --init -- zfsbootmenu
fi

# Stamp a fresh ID into each build
{ od -An -N4 -tx1 /dev/urandom | tr -d ' \n'; echo; } > lib/zbm-auto-build-id

# Build a local image with podman/docker
cmd=$(command -v podman || command -v docker)
"${cmd}" build -t localhost/zbm-auto-builder:latest .

# Apply our automatic rollback overlay
exec ./zfsbootmenu/zbm-builder.sh \
  -b . \
  -i localhost/zbm-auto-builder:latest \
  -O -v -O "$(readlink -f build):/output" \
  -- -o /output "$@"
