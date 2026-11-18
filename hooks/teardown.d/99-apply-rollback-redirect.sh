#!/bin/bash
#
# Applies the rollback flagged by boot-sel.d/10-record-boot-attempt.sh, if any
# Syncs the log and dismounts the ESP
# Reboots if a change was applied, otherwise returns to allow normal ZBM kexec()

ZBM_AUTO_ROLLBACK_REDIRECT_FLAG="/run/zbm-auto/rollback-redirect"
source /usr/local/lib/zbm-auto-log.sh 2>/dev/null || exit 0
do_reboot=0

# If we are rolling back
if [ -f "${ZBM_AUTO_ROLLBACK_REDIRECT_FLAG}" ]; then
  rollback_be="$(cat "${ZBM_AUTO_ROLLBACK_REDIRECT_FLAG}")"
  rm -f "${ZBM_AUTO_ROLLBACK_REDIRECT_FLAG}"

  if [ -z "${rollback_be}" ]; then
    zbm_auto_log "99-apply-rollback-redirect: empty rollback-redirect flag, nothing to do"
  else
    pool="${ZBM_SELECTED_BE%%/*}"

    # zfsbootmenu-core.sh's functions call back into kmsg-log-lib.sh's
    # zdebug/zinfo/zerror -- source it first or those calls fail as
    # missing commands.
    if source /lib/kmsg-log-lib.sh 2>/dev/null && source /lib/zfsbootmenu-core.sh 2>/dev/null; then
      set_rw_pool "${pool}" \
        || zbm_auto_log "99-apply-rollback-redirect: set_rw_pool ${pool} failed, bootfs redirect will likely fail"
    else
      zbm_auto_log "99-apply-rollback-redirect: could not source zfsbootmenu-core.sh, skipping set_rw_pool, bootfs redirect will likely fail"
    fi

    if zpool set bootfs="${rollback_be}" "${pool}"; then
      zbm_auto_log "99-apply-rollback-redirect: redirected bootfs ${ZBM_SELECTED_BE} -> ${rollback_be}, rebooting now to pick it up immediately"
      do_reboot=1
    else
      zbm_auto_log "99-apply-rollback-redirect: failed to set bootfs=${rollback_be} on pool ${pool}, letting this boot proceed instead of reboot-looping on a change that can't be applied"
    fi
  fi
fi

# Log cleanup
sync
if grep -q " ${ZBM_AUTO_ESP_MOUNT} " /proc/mounts 2>/dev/null; then
  umount "${ZBM_AUTO_ESP_MOUNT}" 2>/dev/null \
    || zbm_auto_log "99-apply-rollback-redirect: umount ${ZBM_AUTO_ESP_MOUNT} failed, this boot's log may not survive a forced reset"
fi

# Reboot if we applied a config change
if [ "${do_reboot}" -eq 1 ]; then
  exec reboot
fi
