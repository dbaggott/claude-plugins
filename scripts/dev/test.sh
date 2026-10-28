#!/usr/bin/env bash
#
# Runs the bats suite locally the way CI does, with a result an agent can read
# without piping it anywhere. The full TAP output goes to a temporary file;
# stdout carries the plan line, each failure with its diagnostics, any bats
# warning, the file's path as `tap=<path>`, and bats' exit status as
# `status=<n>`, last. The script exits with that status.
#
# Usage: scripts/dev/test.sh [bats target...]    (default: the repo's tests/)

set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
[ $# -gt 0 ] || set -- "$root/tests"

# `-j` needs GNU parallel, and with any other `parallel` (moreutils ships one)
# bats runs no tests at all.
jobs=()
if parallel --version 2>/dev/null | grep -q 'GNU parallel'; then
  jobs=(-j 8)
fi

tmp=${TMPDIR:-/tmp}
tap=$(mktemp "${tmp%/}/bats-tap.XXXXXX") || exit 1
npx --yes bats@1.13.0 ${jobs[@]+"${jobs[@]}"} "$@" >"$tap" 2>&1
status=$?

# A failure's diagnostics are the `#` lines between its `not ok` and the next
# test line.
awk '
  /^1\.\./                { print; next }
  /^not ok /              { infail = 1; print; next }
  /^ok /                  { infail = 0; next }
  /^# bats warning/       { print; next }
  infail && /^#/          { print }
' "$tap"
echo "tap=$tap"
echo "status=$status"
exit "$status"
