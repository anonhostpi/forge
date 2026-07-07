#!/usr/bin/env bash
# see anonhostpi/forge#5
# CI-side SSH-push deploy (the AGE_KEY-using half of the Q5 security decision). Decrypt scope:cluster SOPS
# manifests in-runner, load the deploy SSH key into ssh-agent from STDIN (never on disk — review F3), SSH to
# forge-deploy@seed:22, pipe plaintext to `sudo k3s kubectl apply -f -`. apiserver 6443 is NEVER contacted.
# Hooks (SSH_CMD/SOPS_CMD/MANIFEST_DIR/SECRETS_FILE) exist only so the selftest can inject mocks + fixtures.
set -euo pipefail

: "${AGE_KEY:?AGE_KEY required}" "${SEED_IP:?SEED_IP required}"
SSH_CMD="${SSH_CMD:-ssh}"
SOPS_CMD="${SOPS_CMD:-sops}"
MANIFEST_DIR="${MANIFEST_DIR:-deploy/manifests}"          # scope:cluster SOPS-encrypted k8s manifests (U13/U14 add real ones)
SECRETS_FILE="${SECRETS_FILE:-secrets/seed.sops.yaml}"
export SOPS_AGE_KEY="$AGE_KEY"

shopt -s nullglob
manifests=("$MANIFEST_DIR"/*.sops.yaml)                   # scope:cluster ONLY; the ci-only deploy_ssh key is NEVER in this stream (F6)
if [ ${#manifests[@]} -eq 0 ]; then
  echo "no scope:cluster manifests in $MANIFEST_DIR yet (U13/U14 add them); nothing to deploy"
  exit 0
fi

# Deploy SSH key -> ssh-agent from STDIN; never a disk file. The agent dies on exit (trap), and no key path exists to leak.
eval "$(ssh-agent -s)" >/dev/null
trap 'ssh-agent -k >/dev/null 2>&1 || true' EXIT
"$SOPS_CMD" -d --extract '["deploy_ssh"]["private"]' "$SECRETS_FILE" | ssh-add - 2>/dev/null

# The manifest stream = ONLY in-repo SOPS-decrypted content, ZERO workflow-context interpolation (F8) — root kubectl can't become RCE.
stream() { local f; for f in "${manifests[@]}"; do "$SOPS_CMD" -d "$f"; echo "---"; done; }

# pipefail (F4): a decrypt failure must not be masked by ssh's exit; the remote kubectl exit propagates back through ssh.
# accept-new: first-contact host-key window is a tracked risk (#25). partial-apply is re-run-recoverable, not atomic (F4).
stream | "$SSH_CMD" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
  "forge-deploy@${SEED_IP}" 'sudo k3s kubectl apply -f -'
echo "deploy applied"
