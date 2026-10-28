#!/usr/bin/env bash
#
# Runs the bats suite locally the way CI does, with a result an agent can read
# without piping it anywhere. The full TAP output goes to a temporary file;
# stdout carries the plan line, each failure with its diagnostics, each skipped
# test, any bats warning or error, the file's path as `tap=<path>`, and bats'
# exit status as `status=<n>`, last. The script exits with that status.
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
# test line. A line that is not TAP at all is an error from bats or npx, such
# as a target that does not exist, and is printed too.
awk '
  /^1\.\./                { print; next }
  /^not ok /              { infail = 1; print; next }
  /^ok .* # skip/         { infail = 0; print; next }
  /^ok /                  { infail = 0; next }
  /^# bats warning/       { print; next }
  /^#/                    { if (infail) print; next }
  { print }
' "$tap"
echo "tap=$tap"
echo "status=$status"
exit "$status"
