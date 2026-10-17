#!/usr/bin/env bash
# Which stage of the project flow an issue is at, and the prompt that moves it on.
# A lookup: it claims nothing and writes nothing.
#
#   issue-stage.sh <owner/repo> <n> [--slug=<reviewer login>]
#
# Exactly one result line, then exit 0:
#   result=OK kind=tracking|child|plain stage=<stage> next=<prompt-id> evidence=<key=value ...>
#   result=ERROR reason=bad-args|unsupported-forge|not-found|issue-query|issue-query-shape|set-overflow now=<iso>
#
# `kind` is `child` when the issue has an open parent (issue-project.sh), else
# `tracking` when it is a tracking issue, else `plain`. Stages, first match wins:
#
#   any       closed         the issue is closed
#   child     in-project     next is the parent's prompt; evidence names the
#                            parent and its stage
#   tracking  orchestrating  the parent or any open child carries a claim
#             closeout       every child closed
#             ready          no open child lacks a READY verdict (ready-set.sh's
#                            no-ready-verdict / design-not-ready)
#             set-review     some open child does
#             accepted       no children; a decision-log row whose Entry opens
#                            `Design accepted:` and whose State is not proposed
#             design-review  no children, no such row; a spec verdict exists
#             design-draft   none of the above
#   plain     in-progress    a claim, or an open PR that closes the issue
#             ready          a READY spec verdict, or none
#             spec-review    a verdict that is not READY
#
# Prompt ids: review-spec, decompose, orchestrate, resolve, merge-closeout
# (closeout with an open closing PR on the parent; without one it is orchestrate),
# none (closed), unknown (below).
#
# `evidence` carries what decided the stage: claim=own|foreign|none,
# children=<n> open=<n>, verdict=READY|CHANGES-REQUESTED|none|unknown-verdict,
# acceptance_row=yes|no, prs=<url,...|none>, parent=<url> parent_stage=<stage>.
#
# The verdicts are the reviewer bot's, so `--slug` names it; absent, it is read
# from the reviewer config as orchestrate's multi-issue.md does. With neither, a
# stage that turns on a verdict prints `stage=unknown next=unknown` with
# `verdict=unknown-verdict`, rather than reading an unreadable verdict as none.
#
# `issue-query` also covers a PR source that failed (pr-sources.sh), since a PR
# it could not see may be the one that puts the issue in progress.
#
# orchestrate's "On start" recomputes much of this and may adopt the script; it
# does not yet.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail
unset GH_TOKEN

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

REPO=""; N=""; SLUG=""; SLUG_GIVEN=0
for arg in "$@"; do
  case "$arg" in
    --slug=*) SLUG="${arg#--slug=}"; SLUG_GIVEN=1 ;;
    --*) fail bad-args ;;
    *) if [ -z "$REPO" ]; then REPO="$arg"
       elif [ -z "$N" ]; then N="$arg"
       else fail bad-args; fi ;;
  esac
done
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$N" in ''|*[!0-9]*) fail bad-args ;; esac

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

if [ "$SLUG_GIVEN" = 0 ]; then
  CONF="${DNBG_REVIEWER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dnbg/reviewer}/config.json"
  SLUG=$(jq -r '.slug // empty' "$CONF" 2>/dev/null) || SLUG=""
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

say() {  # <kind> <stage> <next> <evidence>
  echo "result=OK kind=$1 stage=$2 next=$3 evidence=$4"; exit 0
}
# A sub-script's ERROR line carries a reason from the vocabulary above; anything
# else it says is not an answer this script can read.
passthrough() {  # <result line>
  case "$1" in
    "result=ERROR reason="*) local r="${1#result=ERROR reason=}"; fail "${r%% *}" ;;
    *) fail issue-query-shape ;;
  esac
}

# shellcheck disable=SC2016  # GraphQL variables, bound by the flags below.
Q='query($owner:String!, $repo:String!, $n:Int!) {
  repository(owner: $owner, name: $repo) { issue(number: $n) { state body } }
}'
RAW=$(gh api graphql -f query="$Q" -f owner="$OWNER" -f repo="$NAME" -F n="$N" 2>/dev/null) || true
# Stdout is parsed regardless of exit status: an unresolvable issue or repo
# answers a null node plus a NOT_FOUND error, and `gh` exits 1 on it.
[ -n "$RAW" ] || fail issue-query
ISSUE=$(printf '%s' "$RAW" | jq -c '.data.repository.issue // empty' 2>/dev/null) \
  || fail issue-query-shape
if [ -z "$ISSUE" ]; then
  printf '%s' "$RAW" | jq -e 'any(.errors[]?; .type == "NOT_FOUND")' >/dev/null 2>&1 \
    && fail not-found
  fail issue-query
fi
STATE=$(printf '%s' "$ISSUE" | jq -r '.state | strings') || fail issue-query-shape
ACCEPTED=$(printf '%s' "$ISSUE" | jq -r '
  [ (.body // "") | split("\n")[] | sub("\r$"; "") | select(startswith("|"))
    | split("|") | map(gsub("^\\s+|\\s+$"; ""))
    | select((.[4] // "" | startswith("Design accepted:")) and .[5] != "proposed") ]
  | if length > 0 then "yes" else "no" end') || fail issue-query-shape

PROJECT=$("$HERE/issue-project.sh" "$REPO" "$N")
case "$PROJECT" in "result=OK "*) ;; *) passthrough "$PROJECT" ;; esac
PARENT=$(sed -n 's/.* parent=\([^ ]*\).*/\1/p' <<<"$PROJECT")
TRACKING=$(sed -n 's/.* tracking=\([^ ]*\).*/\1/p' <<<"$PROJECT")

if [ "$PARENT" != none ]; then KIND=child
elif [ "$TRACKING" = yes ]; then KIND=tracking
else KIND=plain; fi

[ "$STATE" != CLOSED ] || say "$KIND" closed none "state=closed"

if [ "$KIND" = child ]; then
  case "$PARENT" in
    https://github.com/*/*/issues/*) ;;
    *) fail issue-query-shape ;;
  esac
  P_PATH="${PARENT#https://github.com/}"
  P_REPO="${P_PATH%/issues/*}"; P_N="${P_PATH##*/}"
  UP=$("$0" "$P_REPO" "$P_N" "--slug=$SLUG")
  case "$UP" in "result=OK "*) ;; *) passthrough "$UP" ;; esac
  P_STAGE=$(sed -n 's/.* stage=\([^ ]*\).*/\1/p' <<<"$UP")
  P_NEXT=$(sed -n 's/.* next=\([^ ]*\).*/\1/p' <<<"$UP")
  say child in-project "$P_NEXT" "parent=$PARENT parent_stage=$P_STAGE"
fi

CLAIM_LINE=$("$HERE/claim-issue.sh" "$REPO" "$N")
case "$CLAIM_LINE" in
  result=OWN*) CLAIM=own ;;
  result=FOREIGN*) CLAIM=foreign ;;
  result=UNCLAIMED*) CLAIM=none ;;
  *) passthrough "$CLAIM_LINE" ;;
esac

# Sets PRS to the open PRs that close the issue. Every source has to answer: a PR
# one of them missed may be the one that matters. A `relevance=unknown` PR is not
# one, since the closing source answered without listing it. Not run in a
# subshell, so that `fail` ends the script.
closing_prs() {
  local out line url state urls=""
  out=$("$HERE/pr-sources.sh" "$REPO" "$N")
  line=$(tail -1 <<<"$out")
  case "$line" in
    "result=OK "*"closing=ok search=ok timeline=ok") ;;
    *) fail issue-query ;;
  esac
  while read -r url; do
    [ -n "$url" ] || continue
    state=$(gh pr view "$url" --json state --jq .state 2>/dev/null) || fail issue-query
    [ "$state" != OPEN ] || urls="${urls:+$urls,}$url"
  done < <(sed -n 's/^\(https:[^ ]*\) relevance=closes$/\1/p' <<<"$out")
  PRS="${urls:-none}"
}

# ready-set.sh needs a login to match verdicts against. Without one it still
# answers the claims and counts; `-` cannot be a GitHub login, so it matches no
# comment, and every verdict-dependent stage below reads unknown instead.
SET=$("$HERE/ready-set.sh" "$REPO" "$N" "--slug=${SLUG:--}")
SET_LINE=$(tail -1 <<<"$SET")
case "$SET_LINE" in "result=OK "*) ;; *) passthrough "$SET_LINE" ;; esac
SET_OBJ=$(head -1 <<<"$SET")
read -r CHILDREN OPEN CHILD_CLAIMED VERDICT_HELD VERDICT < <(printf '%s' "$SET_OBJ" | jq -r '
  [ ($SET_LINE | capture("children=(?<c>[0-9]+)").c),
    ($SET_LINE | capture("open=(?<o>[0-9]+)").o),
    (any(.waiting[]; .reasons | index("claimed")) | tostring),
    (any(.waiting[]; .reasons | (index("no-ready-verdict") or index("design-not-ready"))) | tostring),
    (.parent.verdict // "none" | gsub(" "; "-")) ] | join(" ")' --arg SET_LINE "$SET_LINE") \
  || fail issue-query-shape
[ -n "$SLUG" ] || VERDICT=unknown-verdict

if [ "$KIND" = tracking ]; then
  COUNTS="children=$CHILDREN open=$OPEN"
  if [ "$CLAIM" != none ] || [ "$CHILD_CLAIMED" = true ]; then
    say tracking orchestrating orchestrate "claim=$CLAIM $COUNTS"
  fi
  if [ "$CHILDREN" -gt 0 ] && [ "$OPEN" -eq 0 ]; then
    closing_prs
    if [ "$PRS" = none ]; then say tracking closeout orchestrate "$COUNTS prs=none"
    else say tracking closeout merge-closeout "$COUNTS prs=$PRS"; fi
  fi
  if [ "$CHILDREN" -gt 0 ]; then
    [ -n "$SLUG" ] || say tracking unknown unknown "$COUNTS verdict=unknown-verdict"
    [ "$VERDICT_HELD" = false ] || say tracking set-review review-spec "$COUNTS verdict=$VERDICT"
    say tracking ready orchestrate "$COUNTS verdict=$VERDICT"
  fi
  [ "$ACCEPTED" = no ] || say tracking accepted decompose "children=0 acceptance_row=yes"
  [ -n "$SLUG" ] || say tracking unknown unknown "children=0 acceptance_row=no verdict=unknown-verdict"
  [ "$VERDICT" != none ] || say tracking design-draft review-spec "children=0 acceptance_row=no verdict=none"
  say tracking design-review review-spec "children=0 acceptance_row=no verdict=$VERDICT"
fi

closing_prs
if [ "$CLAIM" != none ] || [ "$PRS" != none ]; then
  say plain in-progress resolve "claim=$CLAIM prs=$PRS"
fi
case "$VERDICT" in
  unknown-verdict) say plain unknown unknown "claim=none prs=none verdict=$VERDICT" ;;
  READY|none) say plain ready resolve "claim=none prs=none verdict=$VERDICT" ;;
  *) say plain spec-review review-spec "claim=none prs=none verdict=$VERDICT" ;;
esac
