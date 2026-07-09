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
  # U10 amended this: local bridge auth is now expected. The invariant is "no Proton ACCOUNT credential on the host" —
  # the Bridge's own generated password lives in a 0600 root file read via passwordeval, never inline in msmtprc (F4).
  assert_ok "msmtprc: bridge auth via passwordeval, no inline cleartext password (U8)" \
            inst_exec "$VM" sh -c 'grep -q "^passwordeval " /etc/msmtprc && ! grep -qE "^password[[:space:]]" /etc/msmtprc'
  # The Bridge rejects a MAIL FROM the authenticated account does not own, and msmtp's `auto_from off` makes this the
  # envelope sender — so a `from` that differs from `user` silently breaks every send after login (review F1).
  assert_ok "msmtprc sender equals the authenticated Proton address (U10)" \
            inst_exec "$VM" sh -c '[ "$(awk "/^from /{print \$2}" /etc/msmtprc)" = "$(awk "/^user /{print \$2}" /etc/msmtprc)" ]'
  # `msmtp --pretend` may evaluate passwordeval (unverified); before the operator's init the passfile is absent, so
  # running it then could fail spuriously. Exercise it only once the credential exists (review F3).
  if inst_exec "$VM" test -f /etc/msmtp-bridge.pass 2>/dev/null; then
    assert_ok "msmtp config parses with the bridge credential present" inst_exec "$VM" sh -c 'msmtp --pretend >/dev/null 2>&1'
  else skip "msmtp --pretend deferred: the bridge passfile does not exist until the operator's interactive init"; fi
  assert_ok "bridge quadlet installed, owned by the non-root forge-bridge user (U10)" \
            inst_exec "$VM" sh -c 'f=/home/forge-bridge/.config/containers/systemd/bridge.container; [ -f "$f" ] && [ "$(stat -c %U "$f")" = forge-bridge ]'
  assert_ok "forge-bridge linger enabled — a nologin user cannot run systemctl --user without it (U10)" \
            inst_exec "$VM" sh -c 'loginctl show-user forge-bridge -p Linger 2>/dev/null | grep -qx Linger=yes'
  assert_ok "bridge publishes LOOPBACK only, never 0.0.0.0 (U10)" \
            inst_exec "$VM" sh -c 'f=/home/forge-bridge/.config/containers/systemd/bridge.container; grep -q "PublishPort=127\.0\.0\.1:" "$f" && ! grep -q "PublishPort=0\.0\.0\.0:" "$f"'
  # Real SMTP delivery cannot be verified without the operator's one-time INTERACTIVE Proton login (the image has no
  # headless path), so a "spool drains" assert would false-fail. Check the bind address only if the bridge is actually up.
  if inst_exec "$VM" sh -c 'ss -ltn 2>/dev/null | grep -q ":1025 "' 2>/dev/null; then
    assert_ok "bridge SMTP bound to 127.0.0.1 specifically, not 0.0.0.0 (U10)" \
              inst_exec "$VM" sh -c 'ss -ltn | grep ":1025 " | grep -q "127\.0\.0\.1:1025"'
  else skip "live bridge SMTP bind + delivery deferred to the operator's one-time interactive Proton login"; fi
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
    # NB: the two controls above run in `default`, which U12's forge-scoped policy does NOT cover — so they are
    # attributable to U9's HOST drop alone. The asserts below run in ns `forge` and isolate the k8s layer (review F5).
    assert_ok "baseline egress NetworkPolicy present (U12)" \
              inst_exec "$VM" sh -c 'kubectl -n forge get networkpolicy baseline-egress >/dev/null 2>&1'
    assert_ok "baseline-covered pod CAN still reach an allowed external IP — baseline is not over-blocking (U12)" \
              inst_exec "$VM" sh -c "kubectl -n forge run u12pos --rm -i --restart=Never --image=$IMG -- sh -c 'nc -w5 1.1.1.1 80 </dev/null'"
    # A probe LABELLED as forgejo is selected by U14's strict egress policy and EXCLUDED by this baseline (NotIn). U9
    # never blocks 1.1.1.1, so this drop is attributable to the k8s layer alone — proving both that U14's restriction
    # is enforced and that the additive union with the permissive baseline did NOT materialise (review F1).
    assert_fails "forgejo-labelled pod CANNOT reach an arbitrary external IP — U14's strict egress survives the additive baseline (U12)" \
                 inst_exec "$VM" sh -c "kubectl -n forge run u12np --rm -i --restart=Never --labels app.kubernetes.io/name=forgejo --image=$IMG -- sh -c 'nc -w5 1.1.1.1 80 </dev/null'"
    # The whole exclusion hinges on the chart labelling its pods. A future chart bump emitting an unlabelled
    # Forgejo pod would silently re-open the additive-union hazard AND invalidate the synthetic probe above, together
    # and invisibly. Guard the invariant at its source: the real Deployment's pod template must carry the label (R1/L3).
    assert_ok "the real Forgejo pod template carries the label the baseline exclusion depends on (U12)" \
              inst_exec "$VM" sh -c "[ \"\$(kubectl -n forge get deployment forgejo -o jsonpath='{.spec.template.metadata.labels.app\.kubernetes\.io/name}' 2>/dev/null)\" = forgejo ]"
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
