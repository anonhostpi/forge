#!/usr/bin/env bash
# see anonhostpi/forge#3
set -uo pipefail

HARNESS_PASS=0; HARNESS_FAIL=0; HARNESS_SKIP=0
HARNESS_GATE="${HARNESS_GATE:-0}"          # 1 in CI: a run that verifies nothing FAILS
HARNESS_REQUIRE="${HARNESS_REQUIRE:-}"     # gate: space-list of tokens that MUST appear in a PASS line, else FAIL
HARNESS_PASSED=""                          # accumulated PASS descriptions, for the require check

hcol() { case "$1" in pass) printf '\033[32m';; fail) printf '\033[31m';; skip) printf '\033[33m';; esac; }
hrst() { printf '\033[0m'; }

pass() { HARNESS_PASS=$((HARNESS_PASS+1)); HARNESS_PASSED="$HARNESS_PASSED|$1"; printf '%sPASS%s %s\n' "$(hcol pass)" "$(hrst)" "$1"; }
fail() { HARNESS_FAIL=$((HARNESS_FAIL+1)); printf '%sFAIL%s %s\n' "$(hcol fail)" "$(hrst)" "$1"; }
skip() { HARNESS_SKIP=$((HARNESS_SKIP+1)); printf '%sSKIP%s %s\n' "$(hcol skip)" "$(hrst)" "$1"; }

assert_ok()       { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d (cmd: $*)"; fi; }
assert_fails()    { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d (expected failure, got success)"; else pass "$d"; fi; }
assert_eq()       { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (want=[$2] got=[$3])"; fi; }
assert_contains() { case "$2" in *"$3"*) pass "$1";; *) fail "$1 (missing [$3])";; esac; }

report() {
  printf '\n-- harness report -- pass=%d fail=%d skip=%d gate=%s\n' \
    "$HARNESS_PASS" "$HARNESS_FAIL" "$HARNESS_SKIP" "$HARNESS_GATE"
  [ "$HARNESS_FAIL" -eq 0 ] || return 1
  [ "$HARNESS_GATE" = 1 ] || return 0
  if [ "$HARNESS_PASS" -eq 0 ]; then
    printf 'GATE FAIL: nothing verified (%d skipped) — a gate run must assert something\n' "$HARNESS_SKIP"; return 1
  fi
  local tok
  for tok in $HARNESS_REQUIRE; do
    case "$HARNESS_PASSED" in
      *"$tok"*) ;;
      *) printf 'GATE FAIL: required assertion [%s] did not pass (skipped or absent)\n' "$tok"; return 1 ;;
    esac
  done
  return 0
}
