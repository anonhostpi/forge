#!/usr/bin/env bash
# see anonhostpi/forge#10
# Parse-check the forge firewall ruleset (the crux U9 could not validate at authoring — review F1). Renders via the
# SAME write_files/render-firewall.sh the box uses at boot (lint==boot by construction, review R2/1), then `nft -c -f`
# (no apply). nft -c needs netlink -> run as root (the CI job uses sudo).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"; cd "$ROOT" || exit 1
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
bash write_files/render-firewall.sh > "$tmp"
nft -c -f "$tmp"
echo "firewall-lint OK — the shared-rendered forge ruleset parses"
