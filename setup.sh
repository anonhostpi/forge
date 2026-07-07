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

fragment_run() {
  local f="$1"
  [ -x "$f" ] || { echo "fragment not executable (fragments are scripts, not data): ${f#"$ROOT"/}" >&2; return 1; }
  echo ">> ${f#"$ROOT"/}"
  "$f"
}
fragment_phase() { grep -m1 -oE '# phase:[[:space:]]*(boot|full)' "$1" 2>/dev/null | grep -oE '(boot|full)$' || echo full; }

if [ -n "$ONLY" ]; then
  f="$FRAG_DIR/$ONLY"
  [ -f "$f" ] || { echo "no such fragment: $ONLY" >&2; exit 1; }
  fragment_run "$f"; exit $?
fi

[ -d "$FRAG_DIR" ] || { echo "no $FRAG_DIR — nothing to apply"; exit 0; }
shopt -s nullglob
matched=0
for f in "$FRAG_DIR"/[0-9][0-9]-*; do          # NN-name fragments only; README / .gitkeep / non-NN files ignored
  [ -f "$f" ] || continue
  fp="$(fragment_phase "$f")"
  if [ "$PHASE" != all ] && [ "$fp" != "$PHASE" ]; then echo "-- skip ${f#"$ROOT"/} (phase=$fp != $PHASE)"; continue; fi
  fragment_run "$f"; matched=1
done
[ "$matched" = 1 ] || echo "no fragments matched (phase=$PHASE)"
