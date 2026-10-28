#!/usr/bin/env bash
# Who holds an issue's claim, or claim it.
#
#   claim-issue.sh <owner/repo> <n> [--as=<role>]
#   claim-issue.sh <owner/repo> <n> --claim [--as=<role>] [--label=<assigned:…>] [--stamp=<version>]
#   claim-issue.sh <owner/repo> <n> --release [--as=<role>] [--label=<assigned:…>]
#
# Without `--claim`, the own-claim test from `issue-workflow`'s
# `references/claiming.md`. Exactly one result line, then exit 0:
#   result=UNCLAIMED claim=none at=none
#   result=OWN       claim=<id> at=<iso> assignees=<login,…> labels=<label,…|none>
#   result=FOREIGN   claim=<id|none> at=<iso|none> assignees=<login,…|none> labels=<label,…|none>
#   result=ERROR     reason=bad-args|unsupported-forge|not-found|issue-query|issue-query-shape|role now=<iso>
#
# An issue is claimed when it has an assignee or any `assigned:*` label. The
# claim is then the latest line, across its comments, that opens with
# `Claimed by`, and its id is what that line carries in parentheses, unless a
# `Released by` line comes after it, which leaves no claim. OWN needs
# that id to equal this session's (`${CLAUDE_CODE_SESSION_ID:0:8}`); every other
# claimed state is FOREIGN, and `claim=none` there means the claim carries no id
# a session could have written: marks applied by hand, a claim predating ids, or
# one made where no session id was exported. `assignees` and `labels` (the
# `assigned:*` ones) say who holds a claim with no id, since a teammate assigned
# by hand and an agent session's id-less claim read the same otherwise.
# With `--as`, the OWN and FOREIGN lines end with `operator=<login>`, the
# resolver's operator answer, for the caller to compare `assignees` against.
#
# With `--claim`, the three marks: the label (created if the repo lacks it), the
# operator as assignee, and the claim comment carrying this session's id, with
# the version stamp on a line of its own when `--stamp` names one. The label
# defaults to `assigned:agent-session` and must sit in the `assigned:` namespace.
#   result=OK claim=<id|none> url=<comment-url>
#   result=ERROR reason=bad-args|unsupported-forge|claim-write|role now=<iso>
#
# With `--release`, the read above first: anything but OWN refuses with
# `not-own` and writes nothing. Then it removes the claim's label (`--label`, as
# for `--claim`) and the operator as assignee, and posts `Released by an agent
# session (<id>).` The read then reports UNCLAIMED, or FOREIGN claim=none while
# another holder's marks remain.
#   result=OK url=<comment-url>
#   result=ERROR reason=bad-args|unsupported-forge|not-own|claim-write|role|<a read's reason> now=<iso>
# `claim-write` there means a mark may still be in place.
#
# `--as=<role>` makes the writes under that role, through one `as-role.sh` call: the
# label and the comment post as the role's App (or as the operator, when the
# role falls back), and the assignee is the operator's login from the resolver,
# since an App cannot be assigned and `@me` would name whichever credential is
# in place. The OK line then ends with `as=<login>`, plus `fallback=unconfigured`
# when the role ran as the operator. `role` means the resolver refused; its
# stderr says why, and no mark was written.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB. https://github.com/dbaggott/claude-plugins/issues/149
# replaces the constant below with host detection; the output above is not
# GitHub-shaped.
set -euo pipefail
unset GH_TOKEN

# shellcheck source=./lib-role.sh
. "$(dirname "$0")/lib-role.sh"

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
fail() { echo "result=ERROR reason=$1 now=$(now_iso)"; exit 0; }

REPO="${1:-}"; N="${2:-}"
[ "$#" -ge 2 ] || fail bad-args
shift 2
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$N" in ''|*[!0-9]*) fail bad-args ;; esac

CLAIM=0; RELEASE=0; LABEL="assigned:agent-session"; STAMP=""; AS=""
for a in "$@"; do
  case "$a" in
    --claim)   CLAIM=1 ;;
    --release) RELEASE=1 ;;
    --as=?*)   AS="${a#--as=}" ;;
    --label=*) LABEL="${a#--label=}" ;;
    --stamp=*) STAMP="${a#--stamp=}" ;;
    *) fail bad-args ;;
  esac
done
[ "$RELEASE" = 0 ] || { [ "$CLAIM" = 0 ] && [ -z "$STAMP" ]; } || fail bad-args
case "$LABEL" in assigned:) fail bad-args ;; assigned:*) ;; *) fail bad-args ;; esac
case "$STAMP" in *[!0-9A-Za-z.+-]*) fail bad-args ;; esac

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

SID="${CLAUDE_CODE_SESSION_ID:-}"; SID="${SID:0:8}"

AS_ROLE="$(dirname "$0")/as-role.sh"
# Ask the resolver, in this shell so a refusal exits the script: ANSWER holds
# its OK line with a space at each end, for field() to read.
ask() {  # <as-role args…>
  ANSWER=$("$AS_ROLE" "$@") || fail role
  case "$ANSWER" in result=OK\ *) ANSWER=" ${ANSWER#result=OK} " ;; *) fail role ;; esac
}
field() {  # <key> — from ANSWER
  local v="${ANSWER#* "$1"=}"
  printf '%s' "${v%% *}"
}
# The three marks, in one process so a role mints once for all of them. The
# last line out is `url=<comment-url>`; any failed write exits 3.
write_marks() {  # <repo> <n> <label> <assignee> <body>
  gh label create "$3" --repo "$1" --color BFD4F2 \
    --description "Claimed by an agent session" --force >/dev/null 2>&1 || exit 3
  gh issue edit "$2" --repo "$1" --add-assignee "$4" --add-label "$3" >/dev/null 2>&1 || exit 3
  local url; url=$(gh issue comment "$2" --repo "$1" --body "$5" 2>/dev/null | tail -1) || exit 3
  echo "url=$url"
}

# The release: the label and the assignee off, then the comment. The same
# output and exit as write_marks.
release_marks() {  # <repo> <n> <label> <assignee> <body>
  gh issue edit "$2" --repo "$1" --remove-assignee "$4" --remove-label "$3" >/dev/null 2>&1 || exit 3
  local url; url=$(gh issue comment "$2" --repo "$1" --body "$5" 2>/dev/null | tail -1) || exit 3
  echo "url=$url"
}

# Runs one of the mark functions, under the role when `--as` names one, and
# sets URL and TAIL from its output, or fails. ASSIGNEE is the operator's login
# under a role, else `@me`.
ASSIGNEE="@me"; RUN=()
as_role() {
  [ -n "$AS" ] || return 0
  ask --operator "$REPO"; ASSIGNEE=$(field login)
  RUN=("$AS_ROLE" "$AS" "$REPO" --)
}
run_marks() {  # <function> <args…>
  local fn="$1"; shift
  # The resolver's own line, `as-role.sh: result=…`, comes on stderr; it is
  # read here, and anything else there (a mint's permission warning) passes on.
  local rc=0 out line refused=0
  out=$(${RUN[@]+"${RUN[@]}"} bash -c "$(declare -f "$fn"); $fn \"\$@\"" _ "$@" 2>&1) || rc=$?
  URL=""; TAIL=""
  while IFS= read -r line; do
    case "$line" in
      url=*) URL="${line#url=}" ;;
      "as-role.sh: result=OK "*) TAIL=$(role_as_tail "$line") ;;
      "as-role.sh: result=ERROR "*) refused=1 ;;
      '') ;;
      *) printf '%s\n' "$line" >&2 ;;
    esac
  done <<<"$out"
  [ "$refused" = 0 ] || fail role
  [ "$rc" -eq 0 ] || fail claim-write
  case "$URL" in https://*) ;; *) fail claim-write ;; esac
}

if [ "$CLAIM" = 1 ]; then
  as_role
  BODY="Claimed by an agent session (${SID:-id unavailable})."
  [ -z "$STAMP" ] || BODY="$BODY
<!-- dnbg-workflow $STAMP -->"
  run_marks write_marks "$REPO" "$N" "$LABEL" "$ASSIGNEE" "$BODY"
  echo "result=OK claim=${SID:-none} url=$URL$TAIL"
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
      | select(test("^(claimed|released) by"; "i"))
      | if test("^released by"; "i") then { at: "", id: "" } else
          { at: $c.createdAt,
            id: ((capture("\\((?<id>[^)]*)\\)").id // "") | if . == "id unavailable" then "" else . end) }
        end ]
  | last as $latest
  | [ (if $claimed then 1 else 0 end), ($latest.id // ""), ($latest.at // ""),
      ($i.assignees.nodes | map(.login) | join(",")),
      ($i.labels.nodes | map(.name | select(startswith("assigned:"))) | join(",")) ]
  | map(tostring | gsub("\\|"; "")) | join("|")' 2>/dev/null) \
  || fail issue-query-shape

IFS='|' read -r CLAIMED ID AT WHO LABELS <<<"$OUT"
HOLDERS="assignees=${WHO:-none} labels=${LABELS:-none}"
OWN=0
[ "$CLAIMED" = 1 ] && [ -n "$ID" ] && [ -n "$SID" ] && [ "$ID" = "$SID" ] && OWN=1

if [ "$RELEASE" = 1 ]; then
  [ "$OWN" = 1 ] || fail not-own
  as_role
  run_marks release_marks "$REPO" "$N" "$LABEL" "$ASSIGNEE" "Released by an agent session ($SID)."
  echo "result=OK url=$URL$TAIL"
  exit 0
fi

if [ -n "$AS" ] && [ "$CLAIMED" = 1 ]; then
  ask --operator "$REPO"; HOLDERS="$HOLDERS operator=$(field login)"
fi

if [ "$CLAIMED" = 0 ]; then
  echo "result=UNCLAIMED claim=none at=none"
elif [ "$OWN" = 1 ]; then
  echo "result=OWN claim=$ID at=$AT $HOLDERS"
else
  echo "result=FOREIGN claim=${ID:-none} at=${AT:-none} $HOLDERS"
fi
