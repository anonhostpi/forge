#!/usr/bin/env bash
# see anonhostpi/forge#3
set -uo pipefail
: "${INCUS:=incus}"

incus_available() { command -v "$INCUS" >/dev/null 2>&1; }

vm_launch() { "$INCUS" launch "$2" "$1" --vm -c limits.cpu=2 -c limits.memory=4GiB; }  # --vm: k3s + sysctl hardening need a real kernel
ct_launch() { "$INCUS" launch "$2" "$1"; }

inst_exists()        { "$INCUS" info "$1" >/dev/null 2>&1; }
inst_delete()        { if inst_exists "$1"; then "$INCUS" delete -f "$1"; fi; }
inst_exec()          { local n="$1"; shift; "$INCUS" exec "$n" -- "$@"; }
inst_push_userdata() { "$INCUS" config set "$1" user.user-data - < "$2"; }
inst_snapshot()      { "$INCUS" snapshot "$1" "$2"; }
inst_restore()       { "$INCUS" restore "$1" "$2"; }

wait_cloud_init() {
  local n="$1" t="${2:-600}" s=0 st
  while [ "$s" -lt "$t" ]; do
    st="$(inst_exec "$n" cloud-init status 2>/dev/null || true)"
    case "$st" in
      *"status: done"*)  return 0 ;;
      *"status: error"*) return 1 ;;
    esac
    sleep 5; s=$((s+5))
  done
  return 1
}
