#!/usr/bin/env bash
# see anonhostpi/forge#5
# Prove deploy.sh's pipeline WITHOUT real crypto/network (review F7 scopes the selftest to command-shape + no-disk):
# mock ssh/ssh-add/ssh-agent/sops on PATH; assert the decrypted stream reaches `kubectl apply -f -` over ssh, the
# key is loaded from STDIN (no key file), the target is forge-deploy@seed, and 6443 is NEVER contacted.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"; cd "$ROOT" || exit 1
rc=0
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"; mkdir -p "$bin"
sshlog="$tmp/ssh.args"; sshin="$tmp/ssh.stdin"; addlog="$tmp/ssh-add.args"

cat > "$bin/ssh-agent" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "-k" ] && exit 0
echo "SSH_AUTH_SOCK=/dev/null; export SSH_AUTH_SOCK; SSH_AGENT_PID=1; export SSH_AGENT_PID"
EOF
cat > "$bin/ssh-add" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$addlog"          # record args (want exactly "-", i.e. read key from stdin)
cat > /dev/null                 # consume the key from stdin; never write it to disk
EOF
cat > "$bin/ssh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$sshlog" # record args
cat > "$sshin"                  # record stdin (the manifest stream)
EOF
cat > "$bin/sops" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *deploy_ssh*) echo "FAKE-OPENSSH-PRIVATE-KEY"; exit 0;; esac; done
printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: forgejo\n'
EOF
chmod +x "$bin"/*

fdir="$tmp/manifests"; mkdir -p "$fdir"; echo dummy > "$fdir/forgejo.sops.yaml"
printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: forge-plain\n' > "$fdir/workload.yaml"   # U13: a plaintext non-secret workload

PATH="$bin:$PATH" AGE_KEY=fixture SEED_IP=203.0.113.5 \
  MANIFEST_DIR="$fdir" SECRETS_FILE="$tmp/secrets.sops.yaml" \
  bash scripts/deploy.sh >/dev/null 2>&1

grep -q 'kind: Secret' "$sshin" 2>/dev/null && echo "PASS: decrypted secret piped to ssh stdin" || { echo "FAIL: secret not on ssh stdin"; rc=1; }
grep -q 'kind: ConfigMap' "$sshin" 2>/dev/null && echo "PASS: plaintext workload piped to ssh stdin (U13 dual-glob)" || { echo "FAIL: plaintext workload not on ssh stdin"; rc=1; }
grep -q 'sudo k3s kubectl apply -f -' "$sshlog" 2>/dev/null && echo "PASS: remote cmd is sudo k3s kubectl apply -f -" || { echo "FAIL: wrong remote cmd"; rc=1; }
grep -q 'forge-deploy@203.0.113.5' "$sshlog" 2>/dev/null && echo "PASS: targets forge-deploy@seed" || { echo "FAIL: wrong ssh target"; rc=1; }
grep -q 'accept-new' "$sshlog" 2>/dev/null && echo "PASS: host-key accept-new (window tracked #25)" || { echo "FAIL: no accept-new"; rc=1; }
grep -q '6443' "$sshlog" "$sshin" 2>/dev/null && { echo "FAIL: apiserver 6443 contacted"; rc=1; } || echo "PASS: apiserver 6443 never contacted"
[ "$(cat "$addlog" 2>/dev/null)" = "-" ] && echo "PASS: deploy key loaded from stdin (no key file)" || { echo "FAIL: ssh-add not stdin: [$(cat "$addlog" 2>/dev/null)]"; rc=1; }
if grep -rl 'FAKE-OPENSSH-PRIVATE-KEY' "$tmp" 2>/dev/null | grep -qv '/bin/'; then echo "FAIL: key plaintext found on disk"; rc=1; else echo "PASS: no key plaintext left on disk"; fi

if PATH="$bin:$PATH" AGE_KEY=x SEED_IP=203.0.113.5 MANIFEST_DIR="$tmp/nope" SECRETS_FILE="$tmp/s" bash scripts/deploy.sh >/dev/null 2>&1; then
  echo "FAIL: missing MANIFEST_DIR not rejected"; rc=1; else echo "PASS: missing MANIFEST_DIR rejected (misconfig, F-2)"; fi
edir="$tmp/empty"; mkdir -p "$edir"
if PATH="$bin:$PATH" AGE_KEY=x SEED_IP=203.0.113.5 MANIFEST_DIR="$edir" SECRETS_FILE="$tmp/s" bash scripts/deploy.sh >/dev/null 2>&1; then
  echo "PASS: empty MANIFEST_DIR is intentional (exit 0, F-2)"; else echo "FAIL: empty dir should exit 0"; rc=1; fi

[ "$rc" = 0 ] && echo "deploy selftest OK — pipes to :22, loads key from stdin, never touches 6443" || echo "deploy selftest BROKEN"
exit "$rc"
