#!/usr/bin/env bash
# Negative-control self-check: prove the assertion library actually DETECTS failure.  # #3
# A green harness that can never fail is worthless (spec #3, finding 8). Needs no incus.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/lib/assert.sh"
rc_all=0

run() { bash -c ". \"$LIB\"; $1; report" >/dev/null 2>&1; }

echo "== harness self-check =="

# 1) A run containing a real failure MUST report non-zero.
if run 'assert_eq "injected-bad" 1 2'; then echo "FAIL: injected failure did not fail report()"; rc_all=1
else echo "PASS: injected failure => report() non-zero"; fi

# 2) assert_fails treats a FAILING command as a PASS (the negative-control primitive).
if run 'assert_fails "false-must-fail" false'; then echo "PASS: assert_fails(false) => report() zero"
else echo "FAIL: assert_fails(false) unexpectedly failed report()"; rc_all=1; fi

# 3) assert_fails treats a SUCCEEDING command as a FAIL (guards the negative control itself).
if run 'assert_fails "true-should-be-flagged" true'; then echo "FAIL: assert_fails(true) did not flag"; rc_all=1
else echo "PASS: assert_fails(true) => report() non-zero"; fi

# 4) A clean run MUST report zero.
if run 'assert_ok "true-ok" true'; then echo "PASS: clean run => report() zero"
else echo "FAIL: clean run unexpectedly failed report()"; rc_all=1; fi

[ "$rc_all" -eq 0 ] && echo "self-check OK — the harness can distinguish pass from fail" || echo "self-check BROKEN"
exit "$rc_all"
