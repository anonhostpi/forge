#!/usr/bin/env bash
# see anonhostpi/forge#3
# usage: e2e.sh <clean|dirty> [image]   — set HARNESS_GATE=1 in CI (incus required; all-skip / missing-required fails)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib/assert.sh"; . "$HERE/lib/incus.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SUBSTRATE="${1:-clean}"; IMAGE="${2:-images:ubuntu/24.04/cloud}"
case "$SUBSTRATE" in clean|dirty) ;; *) echo "usage: e2e.sh <clean|dirty> [image]" >&2; exit 2 ;; esac
VM="forge-e2e-$SUBSTRATE"

# In gate mode a missing prerequisite is a FAILURE, not a skip — the gate must not false-green (review R1/4).
missing() { if [ "$HARNESS_GATE" = 1 ]; then fail "$1"; else skip "$1"; fi; report; exit $?; }
incus_available                     || missing "incus unavailable (gate needs a KVM runner — forge#3 nested-KVM RISK)"
[ -f "$REPO_ROOT/cloud-init.yml" ]  || missing "cloud-init.yml absent — nothing to grade (U5 must land before the gate runs)"

trap 'inst_delete "$VM"' EXIT
echo "== E2E ($SUBSTRATE) =="
vm_create "$VM" "$IMAGE" "$REPO_ROOT/cloud-init.yml" || { fail "vm create"; report; exit $?; }
if wait_cloud_init "$VM" 600; then pass "cloud-init reached status=done (first install)"; else fail "cloud-init did not finish"; report; exit $?; fi

# Grade a deployed seed. Each assert is staged (SKIPs until its owning unit lands); a run that skips a
# unit named in HARNESS_REQUIRE FAILS in gate mode, so a staged skip cannot false-green that unit (review R2/1,3).
grade_end_state() {
  assert_ok "sshd actually listening on :22 (U6)" inst_exec "$VM" sh -c 'ss -ltn | grep -Eq "[:.]22 "'
  assert_ok "root SSH login disabled (U6)"          inst_exec "$VM" sh -c 'sshd -T 2>/dev/null | grep -qx "permitrootlogin no"'
  assert_ok "forge-deploy has NOPASSWD sudo (U6)"   inst_exec "$VM" sh -c 'sudo -l -U forge-deploy 2>/dev/null | grep -q NOPASSWD'
  assert_ok "rp_filter loose for flannel (U6)"      inst_exec "$VM" sh -c '[ "$(sysctl -n net.ipv4.conf.all.rp_filter)" = 2 ]'
  if inst_exec "$VM" test -x /usr/local/bin/kubectl 2>/dev/null; then
    assert_ok "k3s node Ready (U11)" inst_exec "$VM" sh -c 'kubectl get nodes | grep -qw Ready'
    # Bracket the metadata block with a raw TCP-connect probe (nc): same pinned image, same protocol depth
    # (TCP:80, no DNS / no HTTP redirect / no TLS), differ ONLY in destination IP — so a broken-egress cluster
    # fails the positive too, and only "metadata specifically dropped" passes the negative (R2/2, R3/F2, R4/F1).
    IMG=busybox:1.37.0
    assert_ok    "pod CAN reach an allowed external IP over TCP:80 — positive control (U12)" \
                 inst_exec "$VM" sh -c "kubectl run pos --rm -i --restart=Never --image=$IMG -- sh -c 'nc -w5 1.1.1.1 80 </dev/null'"
    assert_fails "pod CANNOT reach metadata 169.254.169.254 over TCP:80 — egress dropped, negative control (U9) (U12)" \
                 inst_exec "$VM" sh -c "kubectl run neg --rm -i --restart=Never --image=$IMG -- sh -c 'nc -w5 169.254.169.254 80 </dev/null'"
  else skip "kubectl absent (U11 pending) — k3s / firewall / metadata asserts deferred"; fi
  skip "Forgejo HTTP 200 + git-SSH clone (U14 pending)"
  skip "CI->seed:22 SSH-push deploy exercised end-to-end (U4 pending)"
  skip "user-data secret scrub-on-boot asserted (U3/U4 pending)"
}
grade_end_state

if [ "$SUBSTRATE" = dirty ]; then
  # Idempotent-replay upgrade path: re-apply the deploy on the populated box and re-grade (review R1/3).
  inst_replay "$VM"
  if wait_cloud_init "$VM" 600; then pass "cloud-init re-apply on populated box — idempotent replay (U5)"; else fail "re-apply failed (non-idempotent)"; fi
  grade_end_state
  skip "N-1 (previous-release) upgrade compat — pending a prior-release golden image to restore"
fi
report; exit $?
