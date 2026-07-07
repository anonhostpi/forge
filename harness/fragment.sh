#!/usr/bin/env bash
# see anonhostpi/forge#3
# usage: fragment.sh <fragment-name> [image]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib/assert.sh"; . "$HERE/lib/incus.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
FRAG="${1:?usage: fragment.sh <fragment-name> [image]}"; IMAGE="${2:-images:ubuntu/24.04}"
safe="$(printf '%s' "$FRAG" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' - | sed 's/-\{1,\}/-/g; s/^-//; s/-$//')"
CT="forge-frag-$safe"

incus_available || { skip "incus unavailable"; report; exit $?; }
[ -f "$REPO_ROOT/write_files/$FRAG" ] || { skip "fragment $FRAG absent (owning unit pending)"; report; exit $?; }
# Fragments apply BY setup.sh's convention (a write_files entry may be data, not +x) — never assume executable
# (review R1/8). Deferred until U5 defines setup.sh with an --only <fragment> selector (see README open items).
[ -x "$REPO_ROOT/setup.sh" ] || { skip "setup.sh absent — U5 defines how a fragment applies; cannot exercise $FRAG yet"; report; exit $?; }

trap 'inst_delete "$CT"' EXIT
ct_launch "$CT" "$IMAGE" || { fail "container launch ($CT)"; report; exit $?; }
sleep 2
"$INCUS" file push -r "$REPO_ROOT/write_files" "$CT/root/"
"$INCUS" file push "$REPO_ROOT/setup.sh" "$CT/root/setup.sh"
assert_ok "fragment $FRAG applies via setup.sh" inst_exec "$CT" sh -c "cd /root && bash setup.sh --only '$FRAG'"
report; exit $?
