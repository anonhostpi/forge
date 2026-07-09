#!/usr/bin/env bash
# see anonhostpi/forge#14 — validate the plaintext k8s manifests (kubeconform schema check) AND forbid a `kind: Secret`
# in a plaintext deploy/manifests/*.yaml (secrets ride *.sops.yaml only — review F3). Skips *.sops.yaml (encrypted, not
# parseable) and *.example.yaml (templates).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"; cd "$ROOT" || exit 1
shopt -s nullglob
fail=0
for f in deploy/manifests/*.yaml; do
  case "$f" in *.sops.yaml | *.example.yaml) continue ;; esac
  if grep -Eq "^kind:[[:space:]]*[\"']?Secret" "$f"; then   # tolerate a quoted scalar: kind: \"Secret\" (review F#4)
    echo "FAIL: $f is a plaintext kind:Secret — secrets must be SOPS-encrypted (*.sops.yaml), not plaintext (F3)"; fail=1
  fi
  kubeconform -strict -summary -kubernetes-version 1.31.0 "$f" || fail=1
done
[ "$fail" = 0 ] && echo "k8s-lint OK — manifests valid, no plaintext Secret" || exit 1
