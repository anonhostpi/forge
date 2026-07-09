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

[ -d "$MANIFEST_DIR" ] || { echo "MANIFEST_DIR '$MANIFEST_DIR' does not exist — misconfigured path (review F-2)" >&2; exit 1; }
shopt -s nullglob
# Two globs (U13 F3): plaintext NON-secret workloads (*.yaml, excluding *.sops.yaml + *.example.yaml templates) and
# SOPS-encrypted secrets (*.sops.yaml). k8s-lint forbids a `kind: Secret` in a plaintext *.yaml.
plain=(); for f in "$MANIFEST_DIR"/*.yaml; do case "$f" in *.sops.yaml|*.example.yaml) ;; *) plain+=("$f") ;; esac; done
enc=("$MANIFEST_DIR"/*.sops.yaml)
if [ ${#plain[@]} -eq 0 ] && [ ${#enc[@]} -eq 0 ]; then
  echo "no manifests in $MANIFEST_DIR yet (U13/U14 add them); nothing to deploy"   # dir exists but empty = intentional
  exit 0
fi

# Deploy SSH key -> ssh-agent from STDIN; never a disk file. The agent dies on exit (trap), and no key path exists to leak.
eval "$(ssh-agent -s)" >/dev/null
trap 'ssh-agent -k >/dev/null 2>&1 || true' EXIT
"$SOPS_CMD" -d --extract '["deploy_ssh"]["private"]' "$SECRETS_FILE" | ssh-add - 2>/dev/null

# The manifest stream = ONLY in-repo content (plaintext workloads + SOPS-decrypted secrets), ZERO workflow-context
# interpolation — root kubectl can't become RCE (F8, restated for the plaintext path). `kubectl apply -f -` streams
# documents IN ORDER and does NOT kind-reorder, so plaintext files apply in NN-prefix (glob-sorted) order — an EXPLICIT
# contract: `00-namespace.yaml` first, then workloads (review F#1: a namespaced object applied before its Namespace
# errors and aborts the whole deploy; alphabetical filenames are NOT an ordering contract). Secrets stream LAST: the
# StatefulSet pod CreateContainerConfigError-retries until its Secret in the same batch lands — self-heals (U13 F3).
stream() {
  local f
  for f in "${plain[@]}"; do cat "$f"; echo "---"; done
  for f in "${enc[@]}"; do "$SOPS_CMD" -d "$f"; echo "---"; done
}

# pipefail (F4): a decrypt failure must not be masked by ssh's exit; the remote kubectl exit propagates back through ssh.
# accept-new: first-contact host-key window is a tracked risk (#25). partial-apply is re-run-recoverable, not atomic (F4).
stream | "$SSH_CMD" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
  "forge-deploy@${SEED_IP}" 'sudo k3s kubectl apply -f -'
echo "deploy applied"
