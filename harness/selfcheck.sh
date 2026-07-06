#!/usr/bin/env bash
# see anonhostpi/forge#3
# Negative-control self-check: prove the assertion library DETECTS failure, incl. gate-mode teeth.
# A green harness that can never fail is worthless (spec #3 finding 8; review R2/5). Needs no incus.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/lib/assert.sh"
L=". \"$LIB\";"
rc_all=0

expect() { # <want 0|1> <desc> <script>
  bash -c "$3" >/dev/null 2>&1; local got=$?
  if { [ "$1" = 0 ] && [ "$got" = 0 ]; } || { [ "$1" != 0 ] && [ "$got" != 0 ]; }; then
    echo "PASS: $2"
  else echo "FAIL: $2 (want rc $1, got $got)"; rc_all=1; fi
}

echo "== harness self-check =="
expect 1 "injected failure fails report()"            "$L assert_eq bad 1 2; report"
expect 0 "assert_fails(false) => pass"                "$L assert_fails d false; report"
expect 1 "assert_fails(true) => fail"                 "$L assert_fails d true; report"
expect 0 "clean run => zero"                          "$L assert_ok d true; report"
expect 1 "gate mode: all-skip => fail"                "export HARNESS_GATE=1; $L skip x; report"
expect 0 "gate mode: one pass => zero"                "export HARNESS_GATE=1; $L assert_ok d true; report"
expect 1 "gate mode: required token skipped => fail"  "export HARNESS_GATE=1 HARNESS_REQUIRE=U6; $L assert_ok 'd (U9)' true; report"
expect 0 "gate mode: required token passed => zero"   "export HARNESS_GATE=1 HARNESS_REQUIRE=U6; $L assert_ok 'd (U6)' true; report"

[ "$rc_all" -eq 0 ] && echo "self-check OK — pass/fail detection and gate-mode teeth verified" || echo "self-check BROKEN"
exit "$rc_all"
