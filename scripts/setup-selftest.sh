#!/usr/bin/env bash
# see anonhostpi/forge#6
# Prove setup.sh: applies fragments in NN order, honors --only, fails fast on a bad fragment, rejects a
# non-executable (data) entry. A bootstrap that can't fail is worthless.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
SETUP="$ROOT/setup.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fdir="$tmp/frags"; mkdir -p "$fdir"      # fragment dir kept separate from the output file
rc=0
mkfrag() { printf '#!/usr/bin/env bash\nset -e\n%s\n' "$2" > "$fdir/$1"; chmod +x "$fdir/$1"; }

mkfrag 10-a 'printf a >> "$OUT"'
mkfrag 20-b 'printf b >> "$OUT"'

OUT="$tmp/order"; : > "$OUT"
if SETUP_FRAG_DIR="$fdir" OUT="$OUT" "$SETUP" >/dev/null 2>&1 && [ "$(cat "$OUT")" = ab ]; then
  echo "PASS: fragments apply in NN order"; else echo "FAIL: order=[$(cat "$OUT" 2>/dev/null)]"; rc=1; fi

OUT="$tmp/only"; : > "$OUT"
if SETUP_FRAG_DIR="$fdir" OUT="$OUT" "$SETUP" --only 20-b >/dev/null 2>&1 && [ "$(cat "$OUT")" = b ]; then
  echo "PASS: --only runs exactly one fragment"; else echo "FAIL: only=[$(cat "$OUT" 2>/dev/null)]"; rc=1; fi

mkfrag 30-fail 'exit 3'
if SETUP_FRAG_DIR="$fdir" OUT="$tmp/x" "$SETUP" >/dev/null 2>&1; then echo "FAIL: a failing fragment did not fail setup.sh"; rc=1
else echo "PASS: fail-fast — a failing fragment fails the run"; fi
rm -f "$fdir/30-fail"

printf 'just data\n' > "$fdir/40-data"   # not executable
if SETUP_FRAG_DIR="$fdir" OUT="$tmp/x" "$SETUP" >/dev/null 2>&1; then echo "FAIL: non-executable fragment not rejected"; rc=1
else echo "PASS: non-executable (data) fragment rejected"; fi

sz=$(wc -c < "$ROOT/cloud-init.yml")   # spec #6 finding 8: enforce the Hetzner ~32 KiB user-data cap
if [ "$sz" -lt 32768 ]; then echo "PASS: cloud-init.yml $sz B < 32 KiB cap"; else echo "FAIL: cloud-init.yml $sz B >= 32768"; rc=1; fi

[ "$rc" = 0 ] && echo "setup.sh selftest OK — it applies, selects, and bites" || echo "setup.sh selftest BROKEN"
exit "$rc"
