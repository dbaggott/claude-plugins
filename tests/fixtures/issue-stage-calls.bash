# shellcheck shell=bash
# Names each forge call issue-stage.sh's run makes, so a recording and its replay
# agree on which answer goes with which call. Sourced by capture-issue-stage.sh,
# which records under these keys, and by tests/issue-stage.bats, whose `gh` stub
# serves them.
#
# A key is `<source>:<owner/repo>#<n>` for an issue, `<source>:<url>` for a PR.
# A call this does not recognise is `unknown:` plus its arguments, which no
# fixture holds, so the replay fails it rather than guessing.
issue_stage_call_key() {  # <gh argument...>
  local all="$*" owner="" repo="" n="" a
  for a in "$@"; do
    case "$a" in
      owner=*) owner="${a#owner=}" ;;
      repo=*)  repo="${a#repo=}" ;;
      n=*)     n="${a#n=}" ;;
    esac
  done
  case "$all" in
    "api graphql"*"state body }"*)        echo "stage:$owner/$repo#$n" ;;
    "api graphql"*"parent { url state }"*) echo "project:$owner/$repo#$n" ;;
    "api graphql"*"subIssues(first: 100)"*) echo "set:$owner/$repo#$n" ;;
    "api graphql"*"body createdAt"*)       echo "claim:$owner/$repo#$n" ;;
    "issue view "*"closedByPullRequestsReferences"*)
      # gh issue view <n> --repo <repo> --json closedByPullRequestsReferences
      echo "closing:$5#$3" ;;
    "api repos/"*"/timeline"*)
      a="${2#repos/}"; echo "timeline:${a%%/issues/*}#$(cut -d/ -f4 <<<"$a")" ;;
    "search prs "*)
      a=$(grep -oE 'https://github.com/[^ ]+/issues/[0-9]+' <<<"$all")
      a="${a#https://github.com/}"; echo "search:${a%%/issues/*}#${a##*/}" ;;
    "pr view "*)                           echo "prview:$3" ;;
    *)                                     echo "unknown:$all" ;;
  esac
}
