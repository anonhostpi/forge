#!/usr/bin/env bash
# see anonhostpi/forge#2
# Negative control: prove config-lint REJECTS a plaintext secret / cleartext secret-key / placeholder-recipient,
# and PASSES a clean tree. A lint that can't fail is worthless (mirrors the U2 harness selfcheck).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REAL="$(cd "$HERE/.." && pwd)"
LINT="$HERE/config-lint.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -r "$REAL/.sops.yaml" "$REAL/config" "$REAL/secrets" "$tmp/"
run() { LINT_ROOT="$tmp" CONFIG_GATE=0 "$LINT" >/dev/null 2>&1; }
rc=0
expect_fail() { if run; then echo "FAIL: $1 NOT rejected"; rc=1; else echo "PASS: $1 rejected"; fi; }
expect_pass() { if run; then echo "PASS: $1"; else echo "FAIL: $1 wrongly rejected"; rc=1; fi; }

expect_pass "clean tree passes"

printf 'forgejo:\n  admin_password: hunter2\n' > "$tmp/secrets/seed.yaml"
expect_fail "misnamed plaintext secret in secret area (secrets/seed.yaml)"
rm -f "$tmp/secrets/seed.yaml"

printf 'api_token: abc\n' >> "$tmp/config/seed.yaml"
expect_fail "secret-shaped key in a cleartext config file"
cp "$REAL/config/seed.yaml" "$tmp/config/seed.yaml"

printf 'sops:\n  mac: x\nforgejo:\n  admin_password: ENC[AES256_GCM,data:zz]\n' > "$tmp/secrets/real.sops.yaml"
expect_fail "placeholder recipient while real encrypted secrets exist"
rm -f "$tmp/secrets/real.sops.yaml"

[ "$rc" -eq 0 ] && echo "config-lint selftest OK — the lint bites" || echo "config-lint selftest BROKEN"
exit "$rc"
