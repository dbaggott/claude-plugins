#!/usr/bin/env bash
# Who holds an issue's claim, or claim it.
#
#   claim-issue.sh <owner/repo> <n>
#   claim-issue.sh <owner/repo> <n> --claim [--label=<assigned:…>] [--stamp=<version>]
#
# Without `--claim`, the own-claim test from `issue-workflow`'s
# `references/resolving.md`. Exactly one result line, then exit 0:
#   result=UNCLAIMED claim=none at=none
#   result=OWN       claim=<id> at=<iso> assignees=<login,…> labels=<label,…|none>
#   result=FOREIGN   claim=<id|none> at=<iso|none> assignees=<login,…|none> labels=<label,…|none>
#   result=ERROR     reason=bad-args|unsupported-forge|not-found|issue-query|issue-query-shape now=<iso>
#
# An issue is claimed when it has an assignee or any `assigned:*` label. The
# claim is then the latest line, across its comments, that opens with
# `Claimed by`, and its id is what that line carries in parentheses. OWN needs
# that id to equal this session's (`${CLAUDE_CODE_SESSION_ID:0:8}`); every other
# claimed state is FOREIGN, and `claim=none` there means the claim carries no id
# a session could have written: marks applied by hand, a claim predating ids, or
# one made where no session id was exported. `assignees` and `labels` (the
# `assigned:*` ones) say who holds a claim with no id, since a teammate assigned
# by hand and an agent session's id-less claim read the same otherwise.
#
# With `--claim`, the three marks: the label (created if the repo lacks it), the
# operator as assignee, and the claim comment carrying this session's id, with
# the version stamp on a line of its own when `--stamp` names one. The label
# defaults to `assigned:agent-session` and must sit in the `assigned:` namespace.
#   result=OK claim=<id|none> url=<comment-url>
#   result=ERROR reason=bad-args|unsupported-forge|claim-write now=<iso>
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail
unset GH_TOKEN

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

REPO="${1:-}"; N="${2:-}"
[ "$#" -ge 2 ] || fail bad-args
shift 2
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$N" in ''|*[!0-9]*) fail bad-args ;; esac

CLAIM=0; LABEL="assigned:agent-session"; STAMP=""
for a in "$@"; do
  case "$a" in
    --claim)   CLAIM=1 ;;
    --label=*) LABEL="${a#--label=}" ;;
    --stamp=*) STAMP="${a#--stamp=}" ;;
    *) fail bad-args ;;
  esac
done
case "$LABEL" in assigned:) fail bad-args ;; assigned:*) ;; *) fail bad-args ;; esac
case "$STAMP" in *[!0-9A-Za-z.+-]*) fail bad-args ;; esac

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

SID="${CLAUDE_CODE_SESSION_ID:-}"; SID="${SID:0:8}"

if [ "$CLAIM" = 1 ]; then
  BODY="Claimed by an agent session (${SID:-id unavailable})."
  [ -z "$STAMP" ] || BODY="$BODY
<!-- dnbg-workflow $STAMP -->"
  gh label create "$LABEL" --repo "$REPO" --color BFD4F2 \
    --description "Claimed by an agent session" --force >/dev/null 2>&1 || fail claim-write
  gh issue edit "$N" --repo "$REPO" --add-assignee "@me" --add-label "$LABEL" \
    >/dev/null 2>&1 || fail claim-write
  URL=$(gh issue comment "$N" --repo "$REPO" --body "$BODY" 2>/dev/null | tail -1) || fail claim-write
  case "$URL" in https://*) ;; *) fail claim-write ;; esac
  echo "result=OK claim=${SID:-none} url=$URL"
  exit 0
fi

OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

# The newest page of comments is the one a live claim is on: the test reads the
# latest claim line, and an issue's claims arrive after its discussion starts.
# shellcheck disable=SC2016  # GraphQL variables, bound by the flags below.
Q='query($owner:String!, $repo:String!, $n:Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $n) {
      assignees(first: 20) { nodes { login } }
      labels(first: 100) { nodes { name } }
      comments(last: 100) { nodes { body createdAt } }
    }
  }
}'

RAW=$(gh api graphql -f query="$Q" -f owner="$OWNER" -f repo="$NAME" -F n="$N" 2>/dev/null) || true
[ -n "$RAW" ] || fail issue-query
printf '%s' "$RAW" | jq -e '.errors // [] | any(.type == "NOT_FOUND")' >/dev/null 2>&1 && fail not-found

# One line out: `<claimed 0|1>|<id or empty>|<at or empty>|<assignees>|<labels>`. A separator that is
# not whitespace, since `read` folds adjacent whitespace ones and an empty id
# would shift the timestamp into its place. An id of "id unavailable" is the
# comment saying it has none.
OUT=$(printf '%s' "$RAW" | jq -r '
  .data.repository.issue as $i
  | if $i == null then error("no issue") else . end
  | (($i.assignees.nodes | length) > 0
     or ($i.labels.nodes | any(.name | startswith("assigned:")))) as $claimed
  | [ $i.comments.nodes[] as $c
      | $c.body | split("\n")[] | sub("\r$"; "")
      | select(test("^claimed by"; "i"))
      | { at: $c.createdAt,
          id: ((capture("\\((?<id>[^)]*)\\)").id // "") | if . == "id unavailable" then "" else . end) } ]
  | last as $latest
  | [ (if $claimed then 1 else 0 end), ($latest.id // ""), ($latest.at // ""),
      ($i.assignees.nodes | map(.login) | join(",")),
      ($i.labels.nodes | map(.name | select(startswith("assigned:"))) | join(",")) ]
  | map(tostring | gsub("\\|"; "")) | join("|")' 2>/dev/null) \
  || fail issue-query-shape

IFS='|' read -r CLAIMED ID AT WHO LABELS <<<"$OUT"
HOLDERS="assignees=${WHO:-none} labels=${LABELS:-none}"

if [ "$CLAIMED" = 0 ]; then
  echo "result=UNCLAIMED claim=none at=none"
elif [ -n "$ID" ] && [ -n "$SID" ] && [ "$ID" = "$SID" ]; then
  echo "result=OWN claim=$ID at=$AT $HOLDERS"
else
  echo "result=FOREIGN claim=${ID:-none} at=${AT:-none} $HOLDERS"
fi
