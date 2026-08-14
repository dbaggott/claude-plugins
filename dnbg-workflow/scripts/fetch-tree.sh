#!/usr/bin/env bash
# Fetch a repo's whole tree at one SHA into a scratch directory, in one API call.
# `reviewer` uses it past ~2 questions of the tree, and for any repo-wide sweep,
# instead of continuing to fetch files one at a time through the contents API.
#
#   fetch-tree.sh <owner/repo> <sha> [dir]
#
# Prints exactly one result line, then exits 0:
#   result=OK dir=<path> files=<n>
#   result=ERROR reason=bad-args|fetch|empty
#
# `dir` defaults to a fresh mktemp -d. An explicit one is created if absent and
# must be empty, so a second fetch cannot silently blend two SHAs into one tree
# that matches neither.
#
# ⚠️ AN EMPTY TREE IS AN ERROR, NOT AN EMPTY ANSWER. This is the whole reason the
# fetch is a script, and the two guards below catch different failures — neither
# is redundant. A bad SHA fails the pipeline (gh 404s, pipefail propagates it)
# and lands on `reason=fetch`. `reason=empty` catches what gets past that: an
# archive with no members, where both sides of the pipe exit 0 and the directory
# is still empty. Either way the caller's next move is typically a repo-wide
# sweep, where zero hits is exactly the answer an absence criterion is looking
# for ("nothing else references it, clean") — so an empty tree reported as OK
# would read as the finding.
#
# The extraction strips the leading `<owner>-<repo>-<sha>/` component GitHub
# wraps every tarball in, so paths under `dir` are repo-relative and a grep's
# output can be read as `path:line` without editing.
set -euo pipefail

REPO="${1:-}"; SHA="${2:-}"; DIR="${3:-}"

# A result line rather than a silent exit 1, matching the other scripts here:
# callers branch on `result=`, so a typo must not present as the vanished-process
# case. The slash check keeps a malformed repo off `reason=fetch`, which the
# skills gloss as "the API could not see" — one code, opposite remedies.
if [ -z "$REPO" ] || [ -z "$SHA" ] || [ "$#" -gt 3 ] || [ "${REPO%/*}" = "$REPO" ]; then
  echo "result=ERROR reason=bad-args"
  exit 0
fi

if [ -z "$DIR" ]; then
  DIR=$(mktemp -d)
else
  mkdir -p "$DIR" || { echo "result=ERROR reason=bad-args"; exit 0; }
  if [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
    echo "result=ERROR reason=bad-args"
    exit 0
  fi
fi

# Piping gh straight into tar avoids landing a second copy on disk. `pipefail` is
# already set, so a 404 from gh fails the pipeline even though tar is what exits
# last — but the empty check below is what the caller actually relies on, since a
# partial or malformed archive can extract nothing while both sides exit 0.
if ! gh api "repos/$REPO/tarball/$SHA" 2>/dev/null \
     | tar xz -C "$DIR" --strip-components=1 2>/dev/null; then
  echo "result=ERROR reason=fetch"
  exit 0
fi

FILES=$(find "$DIR" -type f | wc -l | tr -d ' ')
if [ "$FILES" -eq 0 ]; then
  echo "result=ERROR reason=empty"
  exit 0
fi

echo "result=OK dir=$DIR files=$FILES"
