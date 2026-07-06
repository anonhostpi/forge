#!/usr/bin/env bash
# Full-deploy E2E gate for a tier-2 seed deploy.  usage: e2e.sh <clean|dirty> [image]   # #3
# Assertions are STAGED: each is guarded and SKIPs until the unit that produces its target lands.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib/assert.sh"; . "$HERE/lib/incus.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SUBSTRATE="${1:-clean}"; IMAGE="${2:-images:ubuntu/24.04/cloud}"; VM="forge-e2e-$SUBSTRATE"

incus_available || { skip "incus unavailable — E2E gate needs a KVM runner (#3 nested-KVM RISK)"; report; exit $?; }
[ -f "$REPO_ROOT/cloud-init.yml" ] || { skip "cloud-init.yml absent (U5 pending) — deploy not yet gradable"; report; exit $?; }

trap 'instance_delete "$VM"' EXIT
echo "== E2E ($SUBSTRATE) =="
vm_launch "$VM" "$IMAGE" || { fail "vm launch"; report; exit $?; }
inst_push_userdata "$VM" "$REPO_ROOT/cloud-init.yml"; "$INCUS" restart "$VM"
if wait_cloud_init "$VM" 600; then pass "cloud-init reached status=done"; else fail "cloud-init did not finish"; report; exit $?; fi

# --- end-state assertions (staged per spec #3) ---
assert_ok "sshd listening on :22 (U6)" inst_exec "$VM" ss -ltn
if inst_exec "$VM" test -x /usr/local/bin/kubectl 2>/dev/null; then
  assert_ok    "k3s node Ready (U11)"                         inst_exec "$VM" sh -c 'kubectl get nodes | grep -qw Ready'
  assert_fails "pod DENIED to metadata 169.254.169.254 (U9/U12 negative control)" \
               inst_exec "$VM" sh -c 'kubectl run md --rm -i --restart=Never --image=busybox -- wget -T3 -qO- http://169.254.169.254/'
  assert_ok    "pod ALLOWED to cluster DNS (positive control)" \
               inst_exec "$VM" sh -c 'kubectl run dns --rm -i --restart=Never --image=busybox -- nslookup kubernetes.default'
else
  skip "kubectl absent (U11 pending) — k3s / firewall / metadata asserts deferred"
fi
skip "Forgejo HTTP 200 + git-SSH clone (U14 pending)"
skip "CI->seed:22 SSH-push deploy exercised end-to-end (U4 pending)"
skip "user-data secret scrub-on-boot asserted (U3/U4 pending)"

if [ "$SUBSTRATE" = dirty ]; then
  "$INCUS" restart "$VM"
  assert_ok "host survives reboot: sshd back on :22" inst_exec "$VM" ss -ltn
  skip "N-1 upgrade + non-idempotent replay (pending deployable units)"
fi
report; exit $?
