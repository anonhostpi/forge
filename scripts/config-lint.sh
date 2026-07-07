#!/usr/bin/env bash
# see anonhostpi/forge#2
# CONFIG_GATE=1 (CI): a missing sops/validator FAILS; dev default: SKIP the tool-gated checks.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="${LINT_ROOT:-$(cd "$HERE/.." && pwd)}"
GATE="${CONFIG_GATE:-0}"; fails=0
FAIL() { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }
OK()   { printf 'ok   %s\n' "$1"; }
SKIP() { if [ "$GATE" = 1 ]; then FAIL "$1 (required in gate mode)"; else printf 'skip %s\n' "$1"; fi; }

secret_shape='(password|secret|token|private[_-]?key|bridge_password)[[:space:]]*:'
is_example() { case "$1" in *.example.yaml|*.example.yml) return 0;; *) return 1;; esac; }

# 1. If any REAL encrypted secret is committed, the .sops.yaml recipient must not be the shipped placeholder
#    (a placeholder is fine while only examples exist — nothing is encrypted to it yet).
real_secret="$(find "$ROOT/secrets" -type f \( -name '*.sops.yaml' -o -name '*.sops.yml' \) 2>/dev/null | head -1)"
if [ -n "$real_secret" ] && grep -Eq 'age1[a-z0-9]*(replace|00000)' "$ROOT/.sops.yaml"; then
  FAIL ".sops.yaml has a placeholder age recipient but real encrypted secrets exist — replace it"
else OK ".sops.yaml recipient (no real secrets yet, or recipient set)"; fi

# 2. Coverage keyed to LOCATION, not filename: every non-example file in the secret area must be sops-encrypted.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  is_example "$f" && { OK "example plaintext allowed: ${f#"$ROOT"/}"; continue; }
  if command -v sops >/dev/null 2>&1; then
    if sops --verify "$f" >/dev/null 2>&1; then OK "sops --verify: ${f#"$ROOT"/}"; else FAIL "NOT sops-encrypted (or MAC invalid): ${f#"$ROOT"/}"; fi
  elif grep -Eiq "$secret_shape" "$f" && ! grep -q 'ENC\[' "$f"; then
    FAIL "PLAINTEXT secret-shaped file in the secret area: ${f#"$ROOT"/}"
  else SKIP "true sops --verify of ${f#"$ROOT"/} (sops not installed)"; fi
done < <(
  find "$ROOT/secrets" -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null
  find "$ROOT/config" -type f \( -name 'topology*.yaml' -o -name 'topology*.yml' \) 2>/dev/null
)

# 3. No secret-shaped key in ANY cleartext config file (not .sops, not .example).
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.sops.yaml|*.sops.yml|*.example.yaml|*.example.yml) continue;; esac
  if grep -Eiq "$secret_shape" "$f"; then FAIL "secret-shaped key in cleartext ${f#"$ROOT"/}"; else OK "no secret-shaped key: ${f#"$ROOT"/}"; fi
done < <(find "$ROOT/config" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null)

# 4. scope is a DATA key on every secret group (the U4 filter contract; comments are unreadable to yaml.safe_load).
if grep -q 'scope: ci-only' "$ROOT/secrets/seed.example.yaml" && grep -q 'scope: cluster' "$ROOT/secrets/seed.example.yaml"; then
  OK "secrets example carries ci-only + cluster scope data keys"
else FAIL "secrets example missing scope data keys (U4 filter contract)"; fi

# 5. Schema shape.
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml, jsonschema' 2>/dev/null; then
  if python3 "$HERE/validate-schema.py" "$ROOT"; then OK "schema shape"; else FAIL "schema shape validation"; fi
else SKIP "schema shape validation (needs python3 + pyyaml + jsonschema)"; fi

printf -- '-- config-lint -- fails=%d gate=%s\n' "$fails" "$GATE"
[ "$fails" -eq 0 ]
