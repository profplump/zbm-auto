#!/bin/bash
#
# Finds & mounts (one) ESP for use in logging
# Rotates last log and marks the new one with the time and our build ID

source /usr/local/lib/zbm-auto-log.sh 2>/dev/null || exit 0

esp_dev="$( zbm_auto_find_esp )" || { zbm_auto_log "10-esp-log-init: no ESP found, boot log disabled this boot"; exit 0; }

mkdir -p "${ZBM_AUTO_ESP_MOUNT}"
mount -o rw "${esp_dev}" "${ZBM_AUTO_ESP_MOUNT}" 2>/dev/null \
  || { zbm_auto_log "10-esp-log-init: mount ${esp_dev} rw failed, boot log disabled this boot"; exit 0; }

if [ -e "${ZBM_AUTO_LOG}" ]; then
  mv -f "${ZBM_AUTO_LOG}" "${ZBM_AUTO_ESP_MOUNT}/boot.last"
fi

{
  # A human-readable breadcrumb only -- pre-boot clock state isn't
  # trustworthy enough to drive any decision off of.
  printf 'zbm-auto boot log -- rotated %s\n' \
    "$( date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown time' )"
  printf 'build: %s\n' \
    "$( cat /usr/local/lib/zbm-auto-build-id 2>/dev/null || echo 'unknown' )"
  printf 'esp: %s\n' "${esp_dev}"
} > "${ZBM_AUTO_LOG}"
