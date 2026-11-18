# Shared helpers for the ESP-backed boot log
ZBM_AUTO_ESP_MOUNT="/run/zbm-auto/esp"
ZBM_AUTO_LOG="${ZBM_AUTO_ESP_MOUNT}/boot.log"

# arg*: message to record
# Writes to the log if available; otherwise to stderr
zbm_auto_log() {
  if [ -w "${ZBM_AUTO_LOG}" ] 2>/dev/null; then
    printf '%s\n' "$*" >> "${ZBM_AUTO_LOG}"
  else
    printf '%s\n' "$*" >&2
  fi
}

# prints: device path of the chosen ESP (e.g. /dev/sda1)
# returns: 1 if no candidate is found
zbm_auto_find_esp() {
  local esp_type="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
  local dev ptype fstype partuuid best_uuid best_dev

  best_uuid=""
  best_dev=""

  while read -r dev ptype fstype partuuid; do
    [ -n "${dev}" ] || continue
    [ "${ptype,,}" = "${esp_type}" ] || continue
    [ "${fstype,,}" = "vfat" ] || continue
    [ -n "${partuuid}" ] || continue

    if [ -z "${best_uuid}" ] || [[ "${partuuid,,}" < "${best_uuid}" ]]; then
      best_uuid="${partuuid,,}"
      best_dev="${dev}"
    fi
  done < <( lsblk -rno PATH,PARTTYPE,FSTYPE,PARTUUID 2>/dev/null )

  [ -n "${best_dev}" ] || return 1
  printf '%s\n' "${best_dev}"
}
