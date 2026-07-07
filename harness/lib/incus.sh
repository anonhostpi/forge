#!/usr/bin/env bash
# see anonhostpi/forge#3
set -uo pipefail
: "${INCUS:=incus}"

incus_available() { command -v "$INCUS" >/dev/null 2>&1; }

# vm_create <name> <image> <userdata-file> — user-data set BEFORE first start so cloud-init runs it (see forge#3 review R1/1)
vm_create() {
  "$INCUS" init "$2" "$1" --vm -c limits.cpu=2 -c limits.memory=4GiB  # --vm: k3s + sysctl hardening need a real kernel
  "$INCUS" config set "$1" user.user-data - < "$3"
  "$INCUS" start "$1"
}
ct_launch() { "$INCUS" launch "$2" "$1"; }

inst_exists() { "$INCUS" info "$1" >/dev/null 2>&1; }
inst_delete() { if inst_exists "$1"; then "$INCUS" delete -f "$1"; fi; }
inst_exec()   { local n="$1"; shift; "$INCUS" exec "$n" -- "$@"; }
# re-apply cloud-init on an already-provisioned box — the dirty/idempotent-replay path (see forge#3 review R1/3)
inst_replay() { inst_exec "$1" cloud-init clean --logs; "$INCUS" restart "$1"; }

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
