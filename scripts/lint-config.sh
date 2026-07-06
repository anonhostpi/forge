#!/usr/bin/env bash
# see anonhostpi/forge#2
# Config-lint gate: encrypted-at-rest + no-cleartext-secrets + scope tags + schema shape.
# CONFIG_GATE=1 (CI): a missing validator tool FAILS; dev default: it SKIPs (staged like the U2 harness).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
GATE="${CONFIG_GATE:-0}"; fails=0
FAIL() { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }
OK()   { printf 'ok   %s\n' "$1"; }
SKIP() { if [ "$GATE" = 1 ]; then FAIL "$1 (required in gate mode)"; else printf 'skip %s\n' "$1"; fi; }

# 1. Encrypted-at-rest: every file the .sops.yaml rules cover must actually be SOPS-encrypted.
shopt -s nullglob
for f in "$ROOT"/secrets/*.sops.y*ml "$ROOT"/config/topology.sops.y*ml; do
  if grep -q 'ENC\[' "$f" && grep -q '^sops:' "$f"; then OK "encrypted-at-rest: ${f#"$ROOT"/}"
  else FAIL "PLAINTEXT where SOPS-encryption is required: ${f#"$ROOT"/}"; fi
done
shopt -u nullglob

# 2. No cleartext secrets: config/seed.yaml must carry no secret-shaped keys.
if grep -Eiq '(password|secret|token|private[_-]?key)[[:space:]]*:' "$ROOT/config/seed.yaml"; then
  FAIL "config/seed.yaml has a secret-shaped key (belongs in secrets/seed.sops.yaml)"
else OK "config/seed.yaml carries no secret-shaped keys"; fi

# 3. Scope tags: every secret group carries a ci-only|cluster scope tag (the U4 filter contract).
if grep -q 'scope: ci-only' "$ROOT/secrets/seed.example.yaml" && grep -q 'scope: cluster' "$ROOT/secrets/seed.example.yaml"; then
  OK "secrets example carries ci-only + cluster scope tags"
else FAIL "secrets example missing scope tags (U4 filter contract)"; fi

# 4. Schema shape — needs a yaml + jsonschema validator. Tool-gated (SKIP dev, FAIL in gate mode).
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml, jsonschema' 2>/dev/null; then
  if python3 "$HERE/validate-schema.py" "$ROOT"; then OK "schema shape (seed + topology.example + secrets.example)"
  else FAIL "schema shape validation"; fi
else SKIP "schema shape validation (needs python3 + pyyaml + jsonschema)"; fi

printf -- '-- config-lint -- fails=%d gate=%s\n' "$fails" "$GATE"
[ "$fails" -eq 0 ]
