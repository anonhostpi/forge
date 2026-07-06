#!/usr/bin/env bash
# Assertion library for the forge test harness.  # #3
# Sourced by harness drivers. Tracks pass/fail/skip; report() exits non-zero on any failure.
set -uo pipefail

_ASSERT_PASS=0; _ASSERT_FAIL=0; _ASSERT_SKIP=0

_col() { case "$1" in pass) printf '\033[32m';; fail) printf '\033[31m';; skip) printf '\033[33m';; esac; }
_rst() { printf '\033[0m'; }

pass() { _ASSERT_PASS=$((_ASSERT_PASS+1)); printf '%sPASS%s %s\n' "$(_col pass)" "$(_rst)" "$1"; }
fail() { _ASSERT_FAIL=$((_ASSERT_FAIL+1)); printf '%sFAIL%s %s\n' "$(_col fail)" "$(_rst)" "$1"; }
skip() { _ASSERT_SKIP=$((_ASSERT_SKIP+1)); printf '%sSKIP%s %s\n' "$(_col skip)" "$(_rst)" "$1"; }

# assert_ok "<desc>" <cmd...>     — command must exit 0
assert_ok()    { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d (cmd: $*)"; fi; }
# assert_fails "<desc>" <cmd...>  — command must exit non-zero (the NEGATIVE-control primitive)
assert_fails() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d (expected failure, got success)"; else pass "$d"; fi; }
# assert_eq "<desc>" <expected> <actual>
assert_eq()    { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (want=[$2] got=[$3])"; fi; }
# assert_contains "<desc>" <haystack> <needle>
assert_contains() { case "$2" in *"$3"*) pass "$1";; *) fail "$1 (missing [$3])";; esac; }

report() {
  printf '\n-- harness report -- pass=%d fail=%d skip=%d\n' "$_ASSERT_PASS" "$_ASSERT_FAIL" "$_ASSERT_SKIP"
  [ "$_ASSERT_FAIL" -eq 0 ]
}
