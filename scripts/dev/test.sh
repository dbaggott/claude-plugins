#!/usr/bin/env bash
#
# Runs the bats suite locally the way CI does, with a result an agent can read
# without piping it anywhere. The full TAP output goes to a temporary file;
# stdout carries the plan line, each failure with its diagnostics, each skipped
# test, any bats warning or error, the slowest tests with the run's wall time,
# the junit report's path as `report=<path>`, the TAP file's as `tap=<path>`,
# and bats' exit status as `status=<n>`, last. The script exits with that status.
#
# The timing is on stdout so that the PR adding a slow test sees it in its own
# run: a suite's time grows one unremarkable test at a time, and nothing else
# in the loop shows the number to whoever is adding the next one.
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
report=$(mktemp -d "${tmp%/}/bats-report.XXXXXX") || exit 1
started=$(date +%s)
npx --yes bats@1.13.0 --report-formatter junit --output "$report" \
  ${jobs[@]+"${jobs[@]}"} "$@" >"$tap" 2>&1
status=$?
wall=$(( $(date +%s) - started ))

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
# The junit report is where a test's file and its time are, which the TAP line
# does not carry. The sum is the suite's cost whatever `-j` was; the wall time
# is what the run waited. bats escapes the five XML entities in a test's name.
if [ -f "$report/report.xml" ]; then
  awk '
    /<testcase / {
      match($0, /classname="[^"]*"/); file = substr($0, RSTART + 11, RLENGTH - 12)
      sub(/.*\//, "", file)
      match($0, / name="[^"]*"/); name = substr($0, RSTART + 7, RLENGTH - 8)
      match($0, / time="[^"]*"/); t = substr($0, RSTART + 7, RLENGTH - 8)
      gsub(/&quot;/, "\"", name); gsub(/&#39;/, "\047", name)
      gsub(/&lt;/, "<", name); gsub(/&gt;/, ">", name); gsub(/&amp;/, "\\&", name)
      printf "%d\t%s\t%s\n", t * 1000, file, name
    }' "$report/report.xml" | sort -rn | awk -F '\t' -v wall="$wall" '
    NR == 1  { print "slowest tests:" }
    NR <= 10 { printf "  %6dms  %s  %s\n", $1, $2, $3 }
             { s += $1 }
    END      { if (NR) printf "tests_time=%ds wall=%ds\n", s / 1000, wall }'
fi
echo "report=$report/report.xml"
echo "tap=$tap"
echo "status=$status"
exit "$status"
