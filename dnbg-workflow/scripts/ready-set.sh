#!/usr/bin/env bash
# Which of a tracking issue's sub-issues may be dispatched now, as one
# forge-neutral object.
#
#   ready-set.sh <owner/repo> <parent> --slug=<reviewer login>
#
# Prints the object, then exactly one result line, then exits 0:
#   {"parent":{"url":…,"number":…,"spec_review":true|false,
#              "verdict":"READY"|"CHANGES REQUESTED"|null,
#              "verdict_mode":"design"|"spec"|"set"|null,
#              "verdict_current":true|false|null,"verdict_url":…|null},
#    "ready":[{"url":…,"number":…,"title":…}],
#    "waiting":[{"url":…,"number":…,"title":…,
#                "reasons":["blocked"|"claimed"|"no-ready-verdict"|"design-not-ready",…],
#                "blocked_by":["<blocker url>",…],
#                "assignees":[…],"claim_labels":[…]}]}
#   result=OK now=<iso> children=<count> open=<count> ready=<count>
#   result=ERROR reason=bad-args|unsupported-forge|not-found|issue-query|issue-query-shape|set-overflow now=<iso>
#
# A child is ready when it is open, every issue blocking it was closed as
# completed, it has no assignee and no `assigned:*` label, and — when the
# project uses spec review — the latest spec or set review verdict on it and on
# the parent both read READY. `blocked_by` lists the blockers that are not
# cleared: open, or closed as not planned or as a duplicate, since the work they
# stood for was never built. `waiting` holds every other open child with each
# reason it is held; closed children appear in neither list, only in the counts.
# Both lists keep the parent's sub-issue order.
#
# A verdict is a comment by `<slug>` or `<slug>[bot]` whose first line is
# `**Spec review…, round <n>: READY**` or `**Set review…, round <n>: …**`, with
# READY or CHANGES REQUESTED. The project uses spec review when the parent
# carries one. The parent's are read from its oldest and newest comments, since
# the design review sits among the first; a child's from its newest, where the
# latest round sits. A child with no verdict there is `no-ready-verdict`.
#
# `verdict_mode`, `verdict_current` and `verdict_url` describe the parent's
# latest verdict, null without one: its mode from the first line (`(design
# mode)`, or `Set review`), whether it was made against the body as it stands,
# and its comment. Current means the value after the comment's first
# `lastEditedAt` is the body's `lastEditedAt`, `null` matching a body never
# edited; a round naming none is not current. One query reads both, so an edit
# between two reads cannot pair a new body with an old round.
#
# `set-overflow` means a page came back short of its total — sub-issues,
# blockers, assignees or labels — so a claim or a blocker could be missing and
# the child would read as ready; or the parent has verdicts but too many
# comments to tell which is latest. `issue-query-shape` is a payload that did
# not parse, or a null node such as an issue the token cannot see.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail
unset GH_TOKEN

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

REPO=""; N=""; SLUG=""
for arg in "$@"; do
  case "$arg" in
    --slug=*) SLUG="${arg#--slug=}" ;;
    --*) fail bad-args ;;
    *) if [ -z "$REPO" ]; then REPO="$arg"
       elif [ -z "$N" ]; then N="$arg"
       else fail bad-args; fi ;;
  esac
done
[ -n "$SLUG" ] || fail bad-args
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$N" in ''|*[!0-9]*) fail bad-args ;; esac

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

# GitHub caps a parent at 100 sub-issues, so one page holds any set.
# shellcheck disable=SC2016  # GraphQL variables, bound by the flags below.
Q='query($owner:String!, $repo:String!, $n:Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $n) {
      url number lastEditedAt
      oldest: comments(first: 100) { nodes { author { login } body url } }
      newest: comments(last: 100) { totalCount nodes { author { login } body url } }
      subIssues(first: 100) {
        totalCount
        nodes {
          url number title state
          assignees(first: 20) { totalCount nodes { login } }
          labels(first: 100) { totalCount nodes { name } }
          blockedBy(first: 50) { totalCount nodes { url state stateReason } }
          comments(last: 100) { nodes { author { login } body } }
        }
      }
    }
  }
}'

NOW=$(now_iso)
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

# Shape first, so a payload that stopped parsing is never reported as a set too
# large to read.
printf '%s' "$ISSUE" | jq -e '
  def page: (.totalCount | type) == "number" and (.nodes | type) == "array"
            and all(.nodes[]; type == "object");
  def list: (.nodes | type) == "array" and all(.nodes[]; type == "object");
  (.oldest | list) and (.newest | page) and (.subIssues | page)
  and all(.subIssues.nodes[];
          (.assignees | page) and (.labels | page) and (.blockedBy | page)
          and (.comments | list))' \
  >/dev/null 2>&1 || fail issue-query-shape
printf '%s' "$ISSUE" | jq -e '
  def full: (.nodes | length) == .totalCount;
  (.subIssues | full)
  and all(.subIssues.nodes[]; (.assignees | full) and (.labels | full) and (.blockedBy | full))' \
  >/dev/null 2>&1 || fail set-overflow

OUT=$(printf '%s' "$ISSUE" | jq -c --arg slug "$SLUG" '
  # Each verdict comment, with its first line parsed as `head`.
  def verdicts: [ .nodes[]
    | select(.author != null and (.author.login == $slug or .author.login == ($slug + "[bot]")))
    | . + { head: (.body // "" | split("\n")[0] | rtrimstr("\r")
                   | capture("^\\*\\*(?<k>Spec|Set) review(?<m>[^*]*), round [0-9]+: (?<v>READY|CHANGES REQUESTED)\\*\\*")) } ];
  def watermark: (.body // "") | split("lastEditedAt")
    | if length < 2 then null
      else [.[1] | capture("^`?[`:\\s]*(?<t>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|null\\b)")]
           | first | .t? end;
  def cleared: .state == "CLOSED" and (.stateReason == null or .stateReason == "COMPLETED");
  (.oldest | verdicts) as $first | (.newest | verdicts) as $last
  | if ($last | length) == 0 and ($first | length) > 0 and .newest.totalCount > 200
    then "overflow" else
    (($first + $last) | length > 0) as $spec
    | (if ($last | length) > 0 then $last | last else $first | last end) as $pr
    | ($pr.head.v? // null) as $pv
    | (.lastEditedAt // "null") as $edited
    | [ .subIssues.nodes[] | select(.state == "OPEN")
        | { url, number, title,
            blocked_by: [ .blockedBy.nodes[] | select(cleared | not) | .url ],
            assignees: [ .assignees.nodes[].login ],
            claim_labels: [ .labels.nodes[].name | select(startswith("assigned:")) ],
            verdict: (.comments | verdicts | last | .head.v?) }
        | .reasons = ( [ if (.blocked_by | length) > 0 then "blocked" else empty end,
                         if (.assignees + .claim_labels | length) > 0 then "claimed" else empty end,
                         if $spec and .verdict != "READY" then "no-ready-verdict" else empty end,
                         if $spec and $pv != "READY" then "design-not-ready" else empty end ] )
      ] as $open
    | { parent: { url, number, spec_review: $spec, verdict: $pv,
                  verdict_mode: (if $pr == null then null elif $pr.head.k == "Set" then "set"
                                 elif ($pr.head.m | test("design mode")) then "design" else "spec" end),
                  verdict_current: (if $pr == null then null
                                    else ($pr | watermark) as $w | $w != null and $w == $edited end),
                  verdict_url: ($pr.url? // null) },
        ready: [ $open[] | select(.reasons == []) | {url, number, title} ],
        waiting: [ $open[] | select(.reasons != []) | del(.verdict) ],
        children: (.subIssues.nodes | length) }
    end' 2>/dev/null) || fail issue-query-shape
[ "$OUT" != '"overflow"' ] || fail set-overflow

printf '%s\n' "$OUT" | jq -c 'del(.children)'
printf '%s' "$OUT" | jq -r --arg now "$NOW" '
  "result=OK now=\($now) children=\(.children) open=\((.ready + .waiting) | length) ready=\(.ready | length)"'
