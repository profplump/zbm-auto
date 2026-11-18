#!/bin/bash
#
# Records this boot's attempt count for ZBM_SELECTED_BE in EFI NVRAM, and
# flags a rollback redirect for teardown.d/99-apply-rollback-redirect.sh
# if the attempt threshold is exceeded

ZBM_AUTO_ATTEMPT_FAIL_THRESHOLD=2
# Shared with teardown.d/99-apply-rollback-redirect.sh -- keep the two in sync.
ZBM_AUTO_ROLLBACK_REDIRECT_FLAG="/run/zbm-auto/rollback-redirect"

source /usr/local/lib/zbm-auto-log.sh 2>/dev/null || exit 0
source /usr/local/lib/zbm-auto-efivar.sh 2>/dev/null || { zbm_auto_log "10-record-boot-attempt: could not source zbm-auto-efivar.sh, giving up"; exit 0; }
# zfsbootmenu-core.sh's own functions (mount_efivarfs among them) call back
# into kmsg-log-lib.sh's zdebug/zinfo/zerror -- source it first or those
# calls fail as missing commands.
source /lib/kmsg-log-lib.sh 2>/dev/null || { zbm_auto_log "10-record-boot-attempt: could not source kmsg-log-lib.sh, giving up"; exit 0; }
source /lib/zfsbootmenu-core.sh 2>/dev/null || { zbm_auto_log "10-record-boot-attempt: could not source zfsbootmenu-core.sh, giving up"; exit 0; }
mount_efivarfs rw || { zbm_auto_log "10-record-boot-attempt: mount_efivarfs rw failed (non-EFI system?), giving up"; exit 0; }

be_guid="$(zfs get -H -o value guid "${ZBM_SELECTED_BE:-}" 2>/dev/null)"
if [ -z "${be_guid}" ]; then
  zbm_auto_log "10-record-boot-attempt: empty be_guid for ZBM_SELECTED_BE=[${ZBM_SELECTED_BE:-}], nothing recorded this boot"
  mount_efivarfs ro
  exit 0
fi

prev_attempt="$(zbm_efivar_read "${be_guid}")"
[[ "${prev_attempt}" =~ ^[0-9]+$ ]] || prev_attempt=0
attempt=$(( prev_attempt + 1 ))

if zbm_efivar_write "${be_guid}" "${attempt}"; then
  # Verify the write actually took -- catches firmware NVRAM quirks
  # (full/ignored writes, silent truncation) that `efivar` itself won't
  # report as a failure.
  readback="$(zbm_efivar_read "${be_guid}")"
  if [ -z "${readback}" ]; then
    zbm_auto_log "10-record-boot-attempt: ZBM.${be_guid} verify failed: var does not exist after write"
  elif [[ ! "${readback}" =~ ^[0-9]+$ ]]; then
    zbm_auto_log "10-record-boot-attempt: ZBM.${be_guid} verify failed: read back [${readback}], not an integer"
  elif [ "${readback}" -le "${prev_attempt}" ]; then
    zbm_auto_log "10-record-boot-attempt: ZBM.${be_guid} verify failed: read back ${readback}, not greater than starting value ${prev_attempt}"
  fi
else
  zbm_auto_log "10-record-boot-attempt: write to ZBM.${be_guid} failed"
fi

zbm_efivar_write "ATTEMPT" "time=$(zbm_now), be=${ZBM_SELECTED_BE:-}, guid=${be_guid}" \
  || zbm_auto_log "10-record-boot-attempt: write to ZBM.ATTEMPT failed"

zbm_auto_log "10-record-boot-attempt: ${ZBM_SELECTED_BE:-} guid=${be_guid} attempt=${attempt}"

# Logged unconditionally, not just on failure -- a missing/stale
# ZBM.ROLLBACK means the whole rollback mechanism is silently inert,
# worth an admin noticing long before it's ever needed.
rollback_guid="$(zbm_efivar_read "ROLLBACK")"
rollback_be=""
if [ -z "${rollback_guid}" ]; then
  zbm_auto_log "10-record-boot-attempt: ZBM.ROLLBACK not set -- rollback fallback is inactive until the post-boot success tool runs"
else
  while IFS=$'\t' read -r _name _guid; do
    if [ "${_guid}" = "${rollback_guid}" ]; then
      rollback_be="${_name}"
      break
    fi
  done <<<"$(zfs list -H -o name,guid -t filesystem)"
  unset _name _guid

  if [ -z "${rollback_be}" ]; then
    zbm_auto_log "10-record-boot-attempt: ZBM.ROLLBACK guid ${rollback_guid} matches no filesystem -- rollback fallback is inactive"
  fi
fi

if [ "${attempt}" -ge "${ZBM_AUTO_ATTEMPT_FAIL_THRESHOLD}" ] && [ -n "${rollback_be}" ]; then
  zbm_auto_log "10-record-boot-attempt: attempt=${attempt} >= threshold ${ZBM_AUTO_ATTEMPT_FAIL_THRESHOLD}, rollback candidate is ${rollback_be} (guid ${rollback_guid})"
  if [ "${rollback_be}" != "${ZBM_SELECTED_BE}" ]; then
    printf '%s\n' "${rollback_be}" > "${ZBM_AUTO_ROLLBACK_REDIRECT_FLAG}" \
      && zbm_auto_log "10-record-boot-attempt: flagged bootfs redirect ${ZBM_SELECTED_BE} -> ${rollback_be} for teardown.d/99-apply-rollback-redirect.sh" \
      || zbm_auto_log "10-record-boot-attempt: failed to write rollback-redirect flag file"
  fi
fi

mount_efivarfs ro
