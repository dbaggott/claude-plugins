#!/usr/bin/env bash
#
# The only `gh` an eval run can reach. It serves one fixture issue, answers the
# rest of the pickup flow's reads with "nothing there", and records every call
# to a JSON-lines log that `run.sh` grades from. Reads of the issue reflect the
# comments, assignees and labels the log says were written, so an agent that
# checks its own claim or comment finds it.
#
# Each log line is {kind: read|write|unmodelled, cmd: "<noun> <verb>", args, body}.
#
# Environment (set by the wrapper `run.sh` writes, not by the agent):
#   EVAL_ISSUE_JSON  the fixture issue; its `_`-prefixed keys are never served
#   EVAL_GH_LOG      the call log, appended to
#
# Modelled: issue view/list/edit/comment, label create, pr list/create,
# search prs, and GET-only api: user, the issue, its comments and its timeline.
# Anything else, an api write included, is logged as
# `unmodelled` and exits 1, so a path the stub does not know about fails the run
# with the call named instead of being answered with something plausible.
#
# Kept to bash 3.2, the `bash` a stock macOS PATH resolves.

set -euo pipefail

: "${EVAL_ISSUE_JSON:?}" "${EVAL_GH_LOG:?}"

ISSUE_URL=$(jq -r .url "$EVAL_ISSUE_JSON")
ISSUE_PATH="repos/${ISSUE_URL#https://github.com/}"

log() {
  local kind=$1 body=${2-}
  jq -cn --arg kind "$kind" --arg cmd "$CMD" --arg body "$body" \
    '{kind: $kind, cmd: $cmd, args: $ARGS.positional, body: $body}' \
    --args -- ${ARGV[@]+"${ARGV[@]}"} >> "$EVAL_GH_LOG"
}

unmodelled() {
  log unmodelled
  echo "gh stub: unmodelled call: gh ${ARGV[*]}" >&2
  exit 1
}

ARGV=("$@")
CMD=""

# Flags the modelled commands take a value for. Anything else is positional.
JSON_FIELDS="" JQ="" BODY="" BODY_FILE="" PAGINATE_SLURP=0 METHOD=GET API_FIELDS=0
POSITIONAL=()
VALUE_FLAGS=" --json -q --jq -b --body -F --body-file -R --repo -t --title -B --base -H --head -l --label
  --add-label --remove-label -a --assignee --add-assignee --remove-assignee -c --color --description
  -s --state -L --limit --owner -X --method -f --raw-field --field --input "
while [ "$#" -gt 0 ]; do
  case "$VALUE_FLAGS" in
    *[[:space:]]"$1"[[:space:]]*) [ "$#" -ge 2 ] || unmodelled ;;
  esac
  case "$1" in
    --json) JSON_FIELDS=$2; shift 2 ;;
    --json=*) JSON_FIELDS=${1#--json=}; shift ;;
    -q|--jq) JQ=$2; shift 2 ;;
    --jq=*) JQ=${1#--jq=}; shift ;;
    -b|--body) BODY=$2; shift 2 ;;
    --body=*) BODY=${1#--body=}; shift ;;
    -F|--body-file) BODY_FILE=$2; shift 2 ;;
    --body-file=*) BODY_FILE=${1#--body-file=}; shift ;;
    --slurp) PAGINATE_SLURP=1; shift ;;
    -X|--method) METHOD=$2; shift 2 ;;
    -f|--raw-field|--field|--input) API_FIELDS=1; shift 2 ;;
    -R|--repo|-t|--title|-B|--base|-H|--head|-l|--label|--add-label|--remove-label \
      |-a|--assignee|--add-assignee|--remove-assignee|-c|--color|--description \
      |-s|--state|-L|--limit|--owner)
      shift 2 ;;
    -*) shift ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
[ "${#POSITIONAL[@]}" -ge 2 ] || unmodelled
CMD="${POSITIONAL[0]} ${POSITIONAL[1]}"
if [ "${POSITIONAL[0]}" = api ]; then
  # `/user` and `user?per_page=100` are the same endpoint as `user`.
  endpoint=${POSITIONAL[1]#/}
  CMD="api ${endpoint%%\?*}"
fi

read_body() {
  if [ -n "$BODY_FILE" ]; then
    if [ "$BODY_FILE" = - ]; then BODY=$(cat); else BODY=$(cat "$BODY_FILE"); fi
  fi
}

# gh applies --jq to its JSON output and prints strings raw.
emit() {
  if [ -n "$JQ" ]; then jq -r "$JQ"; else cat; fi
}

# The fixture without its `_` keys, plus what the log says was written to it.
served_issue() {
  jq --slurpfile log "$EVAL_GH_LOG" '
    def flag_values($f): . as $a
      | [range(0; length) as $i
         | if $a[$i] == $f then $a[$i + 1]
           elif ($a[$i] | startswith($f + "=")) then $a[$i] | ltrimstr($f + "=")
           else empty end]
      | map(select(. != null) | split(",")[]);
    ($log | map(select(.cmd == "issue edit") | .args)) as $edits
    | with_entries(select(.key | startswith("_") | not))
    | .comments += [$log[] | select(.cmd == "issue comment") | {author: {login: "eval-operator"}, body}]
    | .assignees = ([.assignees[].login]
        + [$edits[] | flag_values("--add-assignee")[] | if . == "@me" then "eval-operator" else . end]
        | unique | map({login: .}))
    | .labels = ([.labels[].name] + [$edits[] | flag_values("--add-label")[]] | unique | map({name: .}))
  ' "$EVAL_ISSUE_JSON"
}

# gh --paginate --slurp wraps the pages in an outer array; one page here.
paged() {
  if [ "$PAGINATE_SLURP" = 1 ]; then jq -c '[.]'; else cat; fi
}

case "$CMD" in
  "issue view")
    log read
    if [ -n "$JSON_FIELDS" ]; then
      served_issue | jq --arg f "$JSON_FIELDS" '. as $i | ($f | split(",")) | map({(.): $i[.]}) | add' | emit
    else
      served_issue | jq -r '"title:\t\(.title)\nstate:\t\(.state)\nurl:\t\(.url)\n--\n\(.body)"'
    fi
    ;;
  "issue list"|"pr list"|"search prs")
    log read
    echo '[]' | emit
    ;;
  "api user")
    log read
    echo '{"login":"eval-operator"}' | emit
    ;;
  "api "*)
    if [ "$API_FIELDS" = 1 ] || [ -n "$BODY_FILE" ] || [ "$METHOD" != GET ]; then unmodelled; fi
    case "$CMD" in
      "api $ISSUE_PATH")
        log read
        served_issue | jq '{number, title, body, state: (.state | ascii_downcase), html_url: .url,
                            assignees, labels, comments: (.comments | length)}' | emit ;;
      "api $ISSUE_PATH/comments")
        log read
        served_issue | jq '[.comments[] | {body, user: .author}]' | paged | emit ;;
      "api $ISSUE_PATH/timeline")
        log read
        echo '[]' | paged | emit ;;
      *) unmodelled ;;
    esac
    ;;
  "issue comment")
    read_body
    log write "$BODY"
    echo "$ISSUE_URL#issuecomment-1"
    ;;
  "issue edit")
    read_body
    log write "$BODY"
    echo "$ISSUE_URL"
    ;;
  "label create")
    log write
    ;;
  "pr create")
    read_body
    log write "$BODY"
    echo "${ISSUE_URL%/issues/*}/pull/2"
    ;;
  *) unmodelled ;;
esac
