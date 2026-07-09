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
  if grep -Eq "^kind:[[:space:]]*[\"']?Secret" "$f"; then   # tolerate a quoted scalar: kind: "Secret" (U13 review F#4)
    echo "FAIL: $f is a plaintext kind:Secret — secrets must be SOPS-encrypted (*.sops.yaml), not plaintext (F3)"; fail=1
  fi
  # A HelmChart CRD's `valuesContent` is plaintext YAML, so a secret smuggled there slips past the kind:Secret guard
  # entirely (U14 review F1/F10). Anchor on the secret-ish KEY NAME at line start: this cannot false-positive on a
  # legitimate `key: password` (key name is `key`) or `- name: GITEA__mailer__PASSWD` (key name is `name`).
  # Match a key whose NAME ENDS in a secret word (so `GITEA__mailer__PASSWD: plaintext` and a bare `token:` are both
  # caught), while `key: password` and `- name: GITEA__mailer__PASSWD` are NOT (their key names are `key`/`name`) —
  # review R1/3 widened this from the original literal list.
  if grep -Eqi "^[[:space:]]*[a-z0-9_.-]*(password|passwd|secret_key|internal_token|token)[[:space:]]*:[[:space:]]*[^[:space:]]" "$f"; then
    echo "FAIL: $f assigns a secret-ish key inline — secrets must ride existingSecret/secretKeyRef, never plaintext values (F10)"; fail=1
  fi
  # helm.cattle.io/v1 HelmChart is a CRD with no built-in schema, so it needs -ignore-missing-schemas (review F2). Apply
  # that ONLY to files declaring a CRD kind — a blanket ignore would silently PASS a typo'd standard kind like
  # `kind: NetwrokPolicy`; everything else stays fully strict and still catches typos (review R1/2).
  if grep -Eq '^kind:[[:space:]]*HelmChart' "$f"; then
    kubeconform -strict -summary -ignore-missing-schemas -kubernetes-version 1.31.0 "$f" || fail=1
  else
    kubeconform -strict -summary -kubernetes-version 1.31.0 "$f" || fail=1
  fi
done
[ "$fail" = 0 ] && echo "k8s-lint OK — manifests valid, no plaintext Secret" || exit 1
