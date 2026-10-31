#!/usr/bin/env bash
# Put a PR into the GitHub stack its base PR is in, or read the stack a PR is in.
# A stack is what makes GitHub rebase the PRs above a merged one and lets one
# merge land every open PR below the merged one (`orchestrate`'s stacked mode).
#
#   stack-prs.sh <owner/repo> <pr> --onto=<base pr>   form: add <pr> above <base pr>
#   stack-prs.sh <owner/repo> <pr>                    read: the stack <pr> is in
#
# Exactly one result line, then exit 0.
#
# Form:
#   result=OK stack=<n>
#   result=ERROR reason=bad-args|unsupported-forge|stack-read|not-top|pr-view|not-default-base|stack-create|stack-add
# <pr> joins the stack <base pr> is in, above it. A <pr> already in a stack is
# OK with that stack: a re-run after a crash forms nothing twice. GitHub stacks
# are linear, so a <base pr> that is not the open top of its stack is `not-top`
# with nothing written: a second PR based on the same branch stays on the manual
# path. When <base pr> is in no stack, the stack is created from [<base pr>,
# <pr>] if <base pr> targets the default branch; `not-default-base` with nothing
# written when it targets another branch, since that chain was never stacked and
# stacking its top would leave the stack's trunk a branch the merge deletes.
# `stack-create` and `stack-add` are the forge refusing the write, the add after
# one retry when it answered 409 (another request was editing the stack;
# STACK_RETRY_WAIT seconds between the two, default 5). Run it as the author:
# `as-role.sh author <owner/repo> -- stack-prs.sh …` puts the role's token in
# GH_TOKEN, which this script leaves in place.
#
# Read:
#   result=OK stack=<n|none> below=<pr,…|none> above=<pr,…|none>
#   result=ERROR reason=bad-args|unsupported-forge|stack-read
# `below` and `above` are the OPEN PRs under and over <pr> in its stack, bottom
# to top. Merged and closed PRs stay in a stack on GitHub and are left out here:
# a merge of <pr> lands exactly `below` with it, and `above` is what GitHub
# rebases after it. A PR in no stack answers an empty list, observed, not a 404.
# Reads run under the caller's own auth.
#
# A stack's number is drawn from the repo's issue and PR sequence, so it can
# equal a PR number; nothing here treats it as one.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail

fail() { echo "result=ERROR reason=$1"; exit 0; }

REPO="${1:-}"; PR="${2:-}"
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || fail bad-args
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$PR" in ''|*[!0-9]*) fail bad-args ;; esac
BASE=""
if [ "$#" -eq 3 ]; then
  case "$3" in --onto=*) BASE="${3#--onto=}" ;; *) fail bad-args ;; esac
  case "$BASE" in ''|*[!0-9]*) fail bad-args ;; esac
  [ "$BASE" != "$PR" ] || fail bad-args
fi

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

# The stack a PR is in, as `{number, pull_requests}`, or nothing for none. A
# failed or unparseable read exits 1: "in no stack" and "could not read" must
# not collapse into each other.
stack_of() {  # <pr>
  local raw
  raw=$(gh api "repos/$REPO/stacks?pull_request=$1" 2>/dev/null) || return 1
  printf '%s' "$raw" | jq -c 'if type == "array" then (.[0] // empty) | {number, pull_requests}
                             else error("not a list") end' 2>/dev/null
}

if [ -z "$BASE" ]; then
  STACK=$(stack_of "$PR") || fail stack-read
  [ -n "$STACK" ] || { echo "result=OK stack=none below=none above=none"; exit 0; }
  LINE=$(printf '%s' "$STACK" | jq -r --argjson pr "$PR" '
    (.pull_requests | map(.number)) as $all
    | ($all | index($pr)) as $i
    | if $i == null then error("pr not in stack") else . end
    | [.pull_requests[] | select(.state == "open" and .merged_at == null) | .number] as $open
    | def side(f): ([$open[] | select(f)] | if length == 0 then "none" else map(tostring) | join(",") end);
      "stack=\(.number) below=\(side(. as $n | ($all | index($n)) < $i)) above=\(side(. as $n | ($all | index($n)) > $i))"' \
    2>/dev/null) || fail stack-read
  echo "result=OK $LINE"
  exit 0
fi

OWN=$(stack_of "$PR") || fail stack-read
if [ -n "$OWN" ]; then
  echo "result=OK stack=$(printf '%s' "$OWN" | jq -r '.number')"; exit 0
fi
STACK=$(stack_of "$BASE") || fail stack-read
if [ -n "$STACK" ]; then
  N=$(printf '%s' "$STACK" | jq -r '.number')
  TOP=$(printf '%s' "$STACK" | jq -r '[.pull_requests[] | select(.state == "open" and .merged_at == null) | .number] | last // empty')
  [ "$TOP" = "$BASE" ] || fail not-top
  # One retry on 409: the stack was being edited by another request, which
  # finishes on its own. Any other refusal is final.
  for attempt in 1 2; do
    if OUT=$(gh api -X POST "repos/$REPO/stacks/$N/add" -F "pull_requests[]=$PR" 2>&1); then
      echo "result=OK stack=$N"; exit 0
    fi
    case "$OUT" in
      *"HTTP 409"*|*'"status":"409"'*) [ "$attempt" -eq 1 ] && sleep "${STACK_RETRY_WAIT:-5}" ;;
      *) break ;;
    esac
  done
  fail stack-add
fi

BASE_REF=$(gh pr view "$BASE" --repo "$REPO" --json baseRefName --jq '.baseRefName // empty' 2>/dev/null) \
  && [ -n "$BASE_REF" ] || fail pr-view
DEFAULT=$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name // empty' 2>/dev/null) \
  && [ -n "$DEFAULT" ] || fail pr-view
[ "$BASE_REF" = "$DEFAULT" ] || fail not-default-base
N=$(gh api -X POST "repos/$REPO/stacks" -F "pull_requests[]=$BASE" -F "pull_requests[]=$PR" \
      --jq '.number' 2>/dev/null) && [ -n "$N" ] || fail stack-create
echo "result=OK stack=$N"
