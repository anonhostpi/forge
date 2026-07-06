#!/usr/bin/env bash
# Fast fragment loop — apply one write_files/NN-name fragment in a system-container.  # #3
# usage: fragment.sh <fragment-name> [image]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib/assert.sh"; . "$HERE/lib/incus.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
FRAG="${1:?usage: fragment.sh <fragment-name> [image]}"; IMAGE="${2:-images:ubuntu/24.04}"
CT="forge-frag-$(printf '%s' "$FRAG" | tr -c 'a-z0-9' - )"

incus_available || { skip "incus unavailable"; report; exit $?; }
FRAGFILE="$REPO_ROOT/write_files/$FRAG"
[ -f "$FRAGFILE" ] || { skip "fragment $FRAG absent (owning unit pending)"; report; exit $?; }

trap 'inst_delete "$CT"' EXIT
ct_launch "$CT" "$IMAGE"; sleep 2
"$INCUS" file push "$FRAGFILE" "$CT/tmp/$FRAG"
assert_ok "fragment $FRAG applies cleanly" inst_exec "$CT" sh -c "chmod +x /tmp/$FRAG && /tmp/$FRAG"
report; exit $?
