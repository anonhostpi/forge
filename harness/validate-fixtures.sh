#!/usr/bin/env bash
# see anonhostpi/forge#3
# Validate the harness fixture secrets against U1's schema so fixtures cannot drift from the real contract.
# Staged: SKIPs (declared open item) until U1 (#2) ships config/schema; the validator is wired in then.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib/assert.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SCHEMA="$REPO_ROOT/config/schema"          # U1 (#2) owns this
FIXTURES="$HERE/fixtures"

[ -d "$FIXTURES" ] || { skip "no fixtures dir"; report; exit $?; }
[ -e "$SCHEMA" ]   || { skip "U1 schema absent (#2 pending) — fixture-vs-schema validation deferred (declared open item)"; report; exit $?; }
skip "open item (#3): wire cue-vet / jsonschema over fixtures once U1's schema shape is fixed"
report; exit $?
