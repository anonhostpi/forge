#!/usr/bin/env bash
# see anonhostpi/forge#3
# usage: e2e.sh <clean|dirty> [image]   — set HARNESS_GATE=1 in CI (incus required; all-skip fails)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib/assert.sh"; . "$HERE/lib/incus.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SUBSTRATE="${1:-clean}"; IMAGE="${2:-images:ubuntu/24.04/cloud}"; VM="forge-e2e-$SUBSTRATE"

# In gate mode a missing prerequisite is a FAILURE, not a skip — the gate must not false-green (finding 4).
missing() { if [ "$HARNESS_GATE" = 1 ]; then fail "$1"; else skip "$1"; fi; report; exit $?; }
incus_available                     || missing "incus unavailable (gate needs a KVM runner — forge#3 nested-KVM RISK)"
[ -f "$REPO_ROOT/cloud-init.yml" ]  || missing "cloud-init.yml absent — nothing to grade (U5 must land before the gate runs)"

trap 'inst_delete "$VM"' EXIT
echo "== E2E ($SUBSTRATE) =="
vm_create "$VM" "$IMAGE" "$REPO_ROOT/cloud-init.yml" || { fail "vm create"; report; exit $?; }
if wait_cloud_init "$VM" 600; then pass "cloud-init reached status=done (first install)"; else fail "cloud-init did not finish"; report; exit $?; fi

# The assertions that grade a deployed seed. Each is guarded and SKIPs until its owning unit lands;
# a skipped assert cannot false-green the gate — HARNESS_GATE=1 fails an all-skip run (finding 4).
grade_end_state() {
  assert_ok "sshd actually listening on :22 (U6)" inst_exec "$VM" sh -c 'ss -ltn | grep -Eq "[:.]22 "'
  if inst_exec "$VM" test -x /usr/local/bin/kubectl 2>/dev/null; then
    assert_ok "k3s node Ready (U11)" inst_exec "$VM" sh -c 'kubectl get nodes | grep -qw Ready'
    # Bracket the metadata block with ONE pod image: it CAN reach an allowed external IP but NOT metadata,
    # so image-pull / scheduling / DNS failures fail BOTH and cannot spuriously pass the negative (finding 6).
    assert_ok    "pod CAN reach an allowed external IP (positive control)" \
                 inst_exec "$VM" sh -c 'kubectl run pos --rm -i --restart=Never --image=busybox -- ping -c1 -W3 1.1.1.1'
    assert_fails "pod CANNOT reach metadata 169.254.169.254 — egress dropped (U9/U12 negative control)" \
                 inst_exec "$VM" sh -c 'kubectl run neg --rm -i --restart=Never --image=busybox -- wget -T5 -qO- http://169.254.169.254/'
  else skip "kubectl absent (U11 pending) — k3s / firewall / metadata asserts deferred"; fi
  skip "Forgejo HTTP 200 + git-SSH clone (U14 pending)"
  skip "CI->seed:22 SSH-push deploy exercised end-to-end (U4 pending)"
  skip "user-data secret scrub-on-boot asserted (U3/U4 pending)"
}
grade_end_state

if [ "$SUBSTRATE" = dirty ]; then
  # Upgrade path: snapshot the deployed box, re-apply the deploy on the populated system, re-grade (finding 3).
  inst_snapshot "$VM" deployed
  inst_replay "$VM"
  if wait_cloud_init "$VM" 600; then pass "cloud-init re-apply on populated box (idempotent replay)"; else fail "re-apply failed (non-idempotent)"; fi
  grade_end_state
  skip "N-1 (previous-release) upgrade compat (pending a prior release to restore)"
fi
report; exit $?
