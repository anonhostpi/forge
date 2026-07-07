#!/usr/bin/env bash
# see anonhostpi/forge#4
# Prove render-cloudinit.py: renders + substitutes all placeholders, rejects the placeholder pubkey and a
# non-40-char SHA, and ESCAPES a shell/YAML metachar so the output stays valid YAML (no injection break-out).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"; cd "$ROOT" || exit 1
R="$HERE/render-cloudinit.py"
rc=0
sha40="$(printf 'a%.0s' $(seq 1 40))"
base() { export REPO_URL="https://github.com/anonhostpi/forge.git" REF="$sha40" \
         TARBALL_URL="https://example.invalid/t.tgz" TARBALL_SHA256="deadbeef" \
         DEPLOY_PUBKEY="ssh-ed25519 AAAArealkey ci-deploy@forge"; }
valid_yaml() { python3 -c 'import yaml,sys; yaml.safe_load(sys.stdin.read())'; }

base
if out="$(python3 "$R" 2>/dev/null)" && ! grep -qE '\{\{[A-Z0-9_]+\}\}' <<<"$out"; then echo "PASS: renders, all placeholders substituted"; else echo "FAIL: happy render"; rc=1; fi

base; DEPLOY_PUBKEY="ssh-ed25519 AAAAC3REPLACEwithCIdeployPUBLICkey ci-deploy@forge"
if python3 "$R" >/dev/null 2>&1; then echo "FAIL: placeholder pubkey not rejected"; rc=1; else echo "PASS: placeholder pubkey rejected"; fi

base; REF="abc123"
if python3 "$R" >/dev/null 2>&1; then echo "FAIL: non-40-char SHA not rejected"; rc=1; else echo "PASS: non-40-char SHA rejected"; fi

base; REPO_URL='https://x/"$(touch /pwned)"`id`.git'
if out="$(python3 "$R" 2>/dev/null)" && valid_yaml <<<"$out" && ! grep -qE '\{\{[A-Z0-9_]+\}\}' <<<"$out"; then
  echo "PASS: shell/YAML metachar escaped, output still valid YAML"; else echo "FAIL: escaping break-out"; rc=1; fi

[ "$rc" = 0 ] && echo "render selftest OK — renders, rejects, escapes" || echo "render selftest BROKEN"
exit "$rc"
