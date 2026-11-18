# Shared helpers for reading/writing our EFI NVRAM vars through `efivar`
ZBM_AUTO_EFI_VENDOR_UUID="f8d6e8d4-b7ab-4ff8-9657-24b15cf51ebe"

# arg1: var name (without the vendor-UUID/"ZBM." prefix), arg2: value to write
# returns: efivar's exit code
zbm_efivar_write() {
  local name tmp rc
  name="${ZBM_AUTO_EFI_VENDOR_UUID}-ZBM.$1"
  tmp="$(mktemp)"
  printf '%s' "$2" > "${tmp}"
  efivar -n "${name}" -w -f "${tmp}" -A 0x7 2>/dev/null
  rc=$?
  rm -f "${tmp}"
  return "${rc}"
}

# arg1: var name (without the vendor-UUID/"ZBM." prefix)
# Parses efivar -p's dump format
zbm_efivar_read() {
  local dump line ascii value
  dump="$(efivar -n "${ZBM_AUTO_EFI_VENDOR_UUID}-ZBM.$1" -p 2>/dev/null)" || return 0
  value=""
  while IFS= read -r line; do
    case "$line" in
      *'|'*'|'*)
        ascii="${line#*|}"
        ascii="${ascii%|*}"
        value+="${ascii}"
        ;;
    esac
  done <<< "${dump}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

# prints: current UTC time as ISO8601, or "unknown" if unavailable
zbm_now() {
  TZ=UTC0 printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || printf 'unknown'
}
