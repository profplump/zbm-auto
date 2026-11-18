# syntax=docker/dockerfile:1.4
#
# ZFSBootMenu is built on Void Linux
# Add more packages by extending EXTRA_PACKAGES, either here or with
# `--build-arg EXTRA_PACKAGES="efivar foo bar"`.

FROM ghcr.io/zbm-dev/zbm-builder:latest

ARG EXTRA_PACKAGES="efivar"

# Cache-mount the package manager
RUN --mount=type=cache,target=/var/cache/xbps <<-EOF
	set -e
	# xbps demands self-update first
	xbps-install -Suy xbps
	if [ -n "${EXTRA_PACKAGES}" ]; then
		xbps-install -Suy ${EXTRA_PACKAGES}
	fi
EOF

# Source the shell lib dracut will install for our hooks
COPY --chmod=644 lib/zbm-auto-log.sh /usr/local/lib/zbm-auto-log.sh
COPY --chmod=644 lib/zbm-auto-efivar.sh /usr/local/lib/zbm-auto-efivar.sh

# Embed a unique build ID
COPY --chmod=644 lib/zbm-auto-build-id /usr/local/lib/zbm-auto-build-id
