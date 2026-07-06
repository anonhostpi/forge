#!/usr/bin/env bash
# see anonhostpi/forge#3
# usage: smoke.sh <host> [port] [repo]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib/assert.sh"
HOST="${1:-seed}"; PORT="${2:-2222}"; REPO="${3:-forge/smoke.git}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

assert_ok "git clone git@$HOST:$REPO over git-SSH (port $PORT)" \
  env GIT_SSH_COMMAND="ssh -p $PORT -o StrictHostKeyChecking=accept-new" \
  git clone "git@$HOST:$REPO" "$TMP/clone"
report; exit $?
