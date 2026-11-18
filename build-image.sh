#!/bin/sh
set -eu

# Find our path
cd "$(dirname "$(readlink -f "$0")")"

# Build IDs, so we can tell what is actually installed
{ od -An -N4 -tx1 /dev/urandom | tr -d ' \n'; echo; } > lib/zbm-auto-build-id

# Docker would probably work too
exec podman build -t localhost/zbm-auto-builder:latest "$@" .
