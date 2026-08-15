#!/usr/bin/env bash
# Find every PR that might resolve an issue. Three sources, because each misses
# something the others catch — and the gaps are not hypothetical: a real pair (a
# PR closing an issue in one repo, its infrastructure sibling in another) is
# found by exactly one of the first two.
#
#   pr-sources.sh <owner/repo> <issue>
#
# Prints the deduped union as one URL per line, then a result line, then exits 0:
#   <url>
#   ...
#   result=OK count=<n> closing=<s> search=<s> timeline=<s>
#
#   result=ERROR reason=bad-args      # nothing was queried
#   result=ERROR reason=all-sources   # every source failed; the URL list is empty
#                                     # because nothing could see, not because
#                                     # nothing is linked
#
# Each `<s>` is one of the SAME three values, meaning the same thing for every
# source — `ok`, `fail` (the request did not come back), or `shape` (it came back
# and stopped parsing). One vocabulary across all three on purpose: a caller
# matching a per-source enumeration is one field it has never seen away from
# reading a dead source as a live one, which is the exact confusion the fields
# exist to remove.
#
# The distinction is worth keeping rather than collapsing to `fail`: a request
# failure is transient by nature and worth retrying, while a payload that stopped
# parsing will not start on its own.
#
# ⚠️ A PARTIAL FAILURE STILL PRINTS `result=OK`, WITH THE FAILING SOURCE NAMED.
# Discovery is a union, so one live source is a real (if narrower) answer and
# suppressing it would be worse than reporting it. The per-source fields are what
# make "no PRs found" distinguishable from "no PRs found by the sources that
# worked" — a caller that ignores them and reports an empty set as "nothing links
# this issue" is making the claim this contract exists to prevent.
#
# All three can only find what the author linked. A sibling PR whose body never
# mentions the issue is invisible to every method here — there is nothing to
# discover. `git-workflow`'s "Multi-repo changes" requires that mention for this
# reason.
#
# Runs under your own auth, not the reviewer bot's. `GH_TOKEN` is unset below.
# The reviewer App requests no `issues` scope at all, so a bot token cannot touch
# a genuine issue: `gh api repos/<repo>/issues/<n>` answers `403 Resource not
# accessible by integration`. `pull_requests: write` covers conversation comments
# on a *PR*, a different resource, which is what makes this look like it should
# work. Unsetting here rather than asking each caller to remember `env -u
# GH_TOKEN` is the point of the script: `reviewer` mints a bot token inside the
# same call as each write, so a call that also reaches the issue would fail.
set -euo pipefail
unset GH_TOKEN

REPO="${1:-}"; ISSUE="${2:-}"

if [ -z "$REPO" ] || [ -z "$ISSUE" ] || [ "$#" -gt 2 ] || [ "${REPO%/*}" = "$REPO" ]; then
  echo "result=ERROR reason=bad-args"
  exit 0
fi
OWNER="${REPO%%/*}"

# 1. Closing references — only PRs carrying a closing keyword. The narrowest
#    source by construction: `git-workflow`'s multi-repo rule has exactly ONE
#    sibling close the issue and the rest merely reference it, so this source sees
#    a fraction of the set.
closing=ok
closing_urls=""
if J=$(gh issue view "$ISSUE" --repo "$REPO" --json closedByPullRequestsReferences 2>/dev/null); then
  closing_urls=$(echo "$J" | jq -r '(.closedByPullRequestsReferences // [])[] | .url // empty' 2>/dev/null) \
    || { closing=shape; closing_urls=""; }
else
  closing=fail
fi

# 2. Timeline cross-references — anything that MENTIONS the issue, any repo,
#    keyword or not. Authoritative, and immediate (no search-index lag).
#
#    `--slurp` is load-bearing. `--paginate` alone emits each page as a
#    SEPARATE top-level JSON array, so the concatenation is not valid JSON and jq
#    rejects the whole thing the moment an issue exceeds one page — the failure
#    would arrive only on a busy issue, which is exactly where a cross-reference
#    is most likely to be waiting. Hence `.[][]`.
#
#    And pagination itself is load-bearing. The timeline is ordered OLDEST
#    FIRST with no sort parameter to invert it, so on an issue past 100 events
#    every new cross-reference lands on the LAST page.
#
#    Fetch and parse are separated so a parse failure is not reported as "no
#    cross-references" — the fail-closed-and-silent shape this whole file exists
#    to keep out of prose.
timeline=ok
xref_urls=""
if RAWT=$(gh api "repos/$REPO/issues/$ISSUE/timeline" --paginate --slurp 2>/dev/null); then
  xref_urls=$(echo "$RAWT" | jq -r '.[][]
        | select(.event == "cross-referenced")
        | select(.source.issue.pull_request != null)
        | .source.issue.html_url' 2>/dev/null) || { timeline=shape; xref_urls=""; }
else
  timeline=fail
fi

# 3. Text search, scoped to the OWNER — catches a sibling before the timeline
#    event registers, and PRs that reference the issue in prose.
#
#    Scoped to `--owner`, never `--repo`. The case this source exists for is a
#    pair spanning two repos, and `--repo` can only ever return siblings in the
#    same one — it silently drops the half you most need. Over-inclusion (an
#    unrelated repo of the same owner mentioning the issue) is the safe
#    direction; judge relevance from the PR, don't narrow the query.
search=ok
search_urls=""
if RAWS=$(gh search prs --owner "$OWNER" "https://github.com/$REPO/issues/$ISSUE" \
            --json url --limit 100 2>/dev/null); then
  search_urls=$(echo "$RAWS" | jq -r '.[] | .url // empty' 2>/dev/null) \
    || { search=shape; search_urls=""; }
else
  search=fail
fi

if [ "$closing" != ok ] && [ "$timeline" != ok ] && [ "$search" != ok ]; then
  echo "result=ERROR reason=all-sources"
  exit 0
fi

# `sort -u` is OUTSIDE the jq programs above: `gh --jq` applies per page, so a
# jq-side `unique` would only dedupe within a page. `|| true` because grep exits
# 1 on no match, which under `set -e` would kill the run on the ordinary empty
# case.
urls=$(printf '%s\n%s\n%s\n' "$closing_urls" "$xref_urls" "$search_urls" \
         | grep -v '^[[:space:]]*$' | sort -u || true)

[ -n "$urls" ] && printf '%s\n' "$urls"
echo "result=OK count=$(printf '%s' "$urls" | grep -c . || true) closing=$closing search=$search timeline=$timeline"
