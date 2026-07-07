#!/usr/bin/env bash
# see anonhostpi/forge#6
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"
FRAG_DIR="${SETUP_FRAG_DIR:-$ROOT/write_files}"
ONLY=""; PHASE="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --only)  ONLY="${2:?}"; shift 2 ;;
    --phase) PHASE="${2:?}"; shift 2 ;;
    *) echo "usage: setup.sh [--only <NN-name>] [--phase boot|full|all]" >&2; exit 2 ;;
  esac
done

run_fragment() {
  local f="$1"
  [ -x "$f" ] || { echo "fragment not executable (fragments are scripts, not data): ${f#"$ROOT"/}" >&2; return 1; }
  echo ">> ${f#"$ROOT"/}"
  "$f"
}
# a fragment declares its phase via a `# phase: boot|full` header; default full (needs the U4-pushed config).
frag_phase() { grep -m1 -oE '# phase:[[:space:]]*(boot|full)' "$1" 2>/dev/null | grep -oE '(boot|full)$' || echo full; }

if [ -n "$ONLY" ]; then
  f="$FRAG_DIR/$ONLY"
  [ -f "$f" ] || { echo "no such fragment: $ONLY" >&2; exit 1; }
  run_fragment "$f"; exit $?
fi

[ -d "$FRAG_DIR" ] || { echo "no $FRAG_DIR — nothing to apply"; exit 0; }
shopt -s nullglob
matched=0
for f in "$FRAG_DIR"/*; do
  [ -f "$f" ] || continue
  fp="$(frag_phase "$f")"
  if [ "$PHASE" != all ] && [ "$fp" != "$PHASE" ]; then echo "-- skip ${f#"$ROOT"/} (phase=$fp != $PHASE)"; continue; fi
  run_fragment "$f"; matched=1
done
[ "$matched" = 1 ] || echo "no fragments matched (phase=$PHASE)"
