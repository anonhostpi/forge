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
  assert_ok "root SSH login disabled (U6)" inst_exec "$VM" sh -c 'sshd -T 2>/dev/null | grep -qx "permitrootlogin no"'
  assert_ok "forge-deploy has NOPASSWD sudo (U6)"   inst_exec "$VM" sh -c 'sudo -l -U forge-deploy 2>/dev/null | grep -q NOPASSWD'
  assert_ok "rp_filter loose for flannel (U6)"      inst_exec "$VM" sh -c '[ "$(sysctl -n net.ipv4.conf.all.rp_filter)" = 2 ]'
  assert_ok "unattended-upgrades security-only, no auto-reboot (U7)" inst_exec "$VM" sh -c 'grep -Eq "Automatic-Reboot \"false\"" /etc/apt/apt.conf.d/50unattended-upgrades'
  assert_ok "fail2ban active + sshd jail up (U7)"   inst_exec "$VM" sh -c 'systemctl is-active fail2ban | grep -qx active && fail2ban-client status sshd >/dev/null 2>&1'
  assert_ok "fail2ban systemd backend, not dead file backend (U7)" inst_exec "$VM" sh -c 'grep -Eq "backend *= *systemd" /etc/fail2ban/jail.local'
  assert_ok "auditd running + forge ruleset loaded (U7)" inst_exec "$VM" sh -c 'systemctl is-active auditd | grep -qx active && auditctl -l 2>/dev/null | grep -q identity'
  assert_ok "podman + rootless forge-bridge, subuid distinct from forge-deploy (U7)" inst_exec "$VM" sh -c 'command -v podman >/dev/null && b="$(awk -F: "/^forge-bridge:/{print \$2}" /etc/subuid)"; d="$(awk -F: "/^forge-deploy:/{print \$2}" /etc/subuid)"; [ -n "$b" ] && [ "$b" != "$d" ]'
  assert_ok "sendmail resolves to the msmtpq queue wrapper (U8)" inst_exec "$VM" sh -c 'readlink -f "$(command -v sendmail)" | grep -q forge-sendmail'
  assert_ok "msmtprc valid + NO host SMTP secret (U8)"           inst_exec "$VM" sh -c 'msmtp --pretend >/dev/null 2>&1 && ! grep -qiE "password|^auth +on" /etc/msmtprc'
  assert_ok "msmtpq flush timer enabled (U8)"                    inst_exec "$VM" sh -c 'systemctl is-enabled msmtpq-flush.timer | grep -qx enabled'
  assert_ok "pre-Bridge mail SPOOLS, not lost (U8)"              inst_exec "$VM" sh -c 'printf "To: root\nSubject: t\n\nx\n" | sendmail root >/dev/null 2>&1; ls /var/spool/msmtpq 2>/dev/null | grep -q .'
  assert_ok "forge nft table present, INPUT default-drop (U9)"   inst_exec "$VM" sh -c 'nft list table inet forge 2>/dev/null | grep -q "hook input" && nft list table inet forge | grep -Eq "policy drop"'
  assert_ok "external 6443 not in the INPUT allow-set (U9)"      inst_exec "$VM" sh -c '! nft list table inet forge | grep -Eq "dport \{[^}]*6443"'
  # This textual assert is the SUBSTANTIVE metadata check in incus; the pod nc->169.254.169.254 negative below is
  # vacuous off-Hetzner (nothing listens there regardless), so it needs real Hetzner or an injected listener (review F2).
  assert_ok "FORWARD pod->metadata drop rule present (U9)"       inst_exec "$VM" sh -c 'nft list table inet forge | grep -Eq "169\.254\.169\.254 drop"'
  assert_ok "forge firewall re-assert timer enabled (U9)"        inst_exec "$VM" sh -c 'systemctl is-enabled forge-firewall.timer | grep -qx enabled'
  if inst_exec "$VM" test -x /usr/local/bin/kubectl 2>/dev/null; then
    assert_ok "k3s node Ready (U11)" inst_exec "$VM" sh -c 'kubectl get nodes | grep -qw Ready'
    assert_ok "CoreDNS Ready — INPUT allows pod->apiserver, firewall didn't brick the cluster (U9)" \
              inst_exec "$VM" sh -c 'kubectl -n kube-system wait --for=condition=ready pod -l k8s-app=kube-dns --timeout=90s >/dev/null 2>&1'
    # Bracket the metadata block with a raw TCP-connect probe (nc): same pinned image, same protocol depth
    # (TCP:80, no DNS / no HTTP redirect / no TLS), differ ONLY in destination IP — so a broken-egress cluster
    # fails the positive too, and only "metadata specifically dropped" passes the negative (R2/2, R3/F2, R4/F1).
    IMG=busybox:1.37.0
    assert_ok    "pod CAN reach an allowed external IP over TCP:80 — positive control (U12)" \
                 inst_exec "$VM" sh -c "kubectl run pos --rm -i --restart=Never --image=$IMG -- sh -c 'nc -w5 1.1.1.1 80 </dev/null'"
    assert_fails "pod CANNOT reach metadata 169.254.169.254 over TCP:80 — egress dropped, negative control (U9) (U12)" \
                 inst_exec "$VM" sh -c "kubectl run neg --rm -i --restart=Never --image=$IMG -- sh -c 'nc -w5 169.254.169.254 80 </dev/null'"
    # U13 Postgres — requires the deploy flow (U4 SSH-push of the workload + Secret) to have run. Persistence: a sentinel
    # row written on the clean deploy must survive the DIRTY-substrate reboot via the local-path PVC (review F2).
    assert_ok "Postgres pod Ready (U13)" \
              inst_exec "$VM" sh -c 'kubectl -n forge wait --for=condition=ready pod -l app=forgejo-postgres --timeout=120s >/dev/null 2>&1'
    # Write the sentinel ONCE, guarded by a VM-side marker that survives the reboot. On the post-replay re-grade this is
    # a NO-OP, so the assert below READS ONLY — a wiped PVC (postgres re-initdb's, table gone) then FAILS it. The prior
    # form re-inserted the row immediately before reading it: a tautology that proved nothing (review F#3).
    inst_exec "$VM" sh -c 'test -f /var/lib/forge-e2e-persist || { kubectl -n forge exec statefulset/forgejo-postgres -- psql -U forgejo -c "CREATE TABLE forge_persist(tok text); INSERT INTO forge_persist VALUES('"'"'forge-sentinel'"'"');" && touch /var/lib/forge-e2e-persist; }' >/dev/null 2>&1 || true
    assert_ok "Postgres data persists across dirty reboot — original sentinel survives, read-only re-grade (U13)" \
              inst_exec "$VM" sh -c "kubectl -n forge exec statefulset/forgejo-postgres -- psql -U forgejo -tAc 'SELECT tok FROM forge_persist' | grep -qx forge-sentinel"
    assert_ok "Postgres backup CronJob present (U13)" \
              inst_exec "$VM" sh -c 'kubectl -n forge get cronjob forgejo-postgres-backup >/dev/null 2>&1'
    # U14 Forgejo. The bundled-subchart guard is a direct regression test for the spec's worst trap: forgejo-helm v12
    # ships postgresql-ha + redis-cluster ENABLED, which would silently replace U13's Postgres (review F1).
    assert_ok "Forgejo pod Ready (U14)" \
              inst_exec "$VM" sh -c 'kubectl -n forge wait --for=condition=ready pod -l app.kubernetes.io/name=forgejo --timeout=300s >/dev/null 2>&1'
    assert_ok "no bundled Postgres/Redis — Forgejo uses U13's external DB (U14)" \
              inst_exec "$VM" sh -c '! kubectl -n forge get statefulset,deployment -o name 2>/dev/null | grep -Eiq "postgresql|redis"'
    assert_ok "Forgejo serves HTTP 200 on :80 (U14)" \
              inst_exec "$VM" sh -c '[ "$(curl -s -o /dev/null -w %{http_code} --max-time 20 http://127.0.0.1/)" = 200 ]'
    assert_ok "git-SSH answers on :2222 (U14)" \
              inst_exec "$VM" sh -c 'ssh-keyscan -T 10 -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-'
    # A rotating host key is indistinguishable from a MITM to every git client — the /data PVC must keep it stable.
    # `rollout restart` + `rollout status` tracks the NEW ReplicaSet. (delete-pod then `wait -l` would return
    # "no matching resources found" INSTANTLY if the replacement isn't created yet, then a fixed sleep could leave the
    # key unread -> a spurious FAILURE. A test that can false-fail is a test-quality defect. Review R1/1.)
    assert_ok "git-SSH host key STABLE across a pod restart (U14)" \
              inst_exec "$VM" sh -c 'k1=$(ssh-keyscan -T 10 -p 2222 127.0.0.1 2>/dev/null | sort); [ -n "$k1" ] || exit 1; kubectl -n forge rollout restart deployment/forgejo >/dev/null 2>&1 || exit 1; kubectl -n forge rollout status deployment/forgejo --timeout=300s >/dev/null 2>&1 || exit 1; k2=$(ssh-keyscan -T 10 -p 2222 127.0.0.1 2>/dev/null | sort); [ -n "$k2" ] && [ "$k1" = "$k2" ]'
  else skip "kubectl absent (U11 pending) — k3s / firewall / metadata / postgres / forgejo asserts deferred"; fi
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
