#!/usr/bin/env bash
# Block until a reviewable change appears on a PR, then print what changed and
# exit. Drives the `reviewer` skill's in-session watch loop: after a review the
# agent spawns this as a background task; when it returns, the agent
# re-reviews/responds and re-arms it. Detects new commits, new (non-bot)
# reviews/comments/replies, a draft being marked ready, and the PR closing.
#
#   watch-pr.sh <owner/repo> <pr> <last_head_sha> <since_iso> <bot_slug> [--was-draft]
#   watch-pr.sh --issue [--exclude=<url,url,...>] <owner/repo> <issue> "" <since_iso> <slug>
#
# last_head_sha is a FULL 40-character lowercase SHA, or empty. Anything else is
# rejected as bad-args rather than compared — see the check below for why an
# abbreviated one is worse than no baseline at all.
#
# bot_slug is the App slug WITHOUT the [bot] suffix. Both forms are excluded:
# gh pr view (GraphQL) reports a Bot author's login as `<slug>`, while gh api
# (REST) reports `<slug>[bot]` — so the bot never wakes itself.
#
# --was-draft arms the draft->ready check. Pass it when watching a PR you are
# deliberately NOT reviewing because it is still a draft; without it a ready
# transition is ignored, which is right for a PR already under review (it cannot
# go back to draft mid-review in any way that should re-trigger one).
#
# Prints exactly one result line, then exits 0:
#   result=COMMITS new_head=<sha> activity=0|1 now=<iso>  # author pushed
#   result=ACTIVITY activity=1 now=<iso>                  # review/comment/reply, not the bot's
#   result=READY new_head=<sha> activity=0|1 now=<iso>    # draft marked ready — only with --was-draft
#   result=CLOSED state=MERGED|CLOSED                     # PR finished — stop watching
#   result=IDLE now=<iso>                                 # nothing within the window — re-arm
#   result=ERROR reason=<source> now=<iso>                # the watch itself is broken — do NOT re-arm
#
# A bad argument reports `result=ERROR reason=bad-args` and still exits 0, rather
# than dying silently: a caller reads a MISSING result line as "killed", so a typo
# would otherwise imitate the vanished watch this script exists to make legible. A
# malformed POLL_CURVE still dies at source time via `_poll_die` — that one is a
# caller bug caught before the loop, and predates this contract.
#
# ERROR is not IDLE. IDLE means the PR was quiet; ERROR means one source failed
# for FAIL_MAX ticks AND at least FAIL_MIN_SECONDS of awake time, so the watch
# cannot see. Both callers stop and tell the operator what to check (gh auth, the
# number/repo pair) rather than re-arming into the same failure. Short outages —
# a wifi hiccup, the reconnect after a lid opens — are ridden out.
#
# `activity=1` on a COMMITS or READY result means comments or replies landed in
# the same burst. The primary result names what to do first; the flag says there
# is also unread conversation. Ignoring it loses those replies for good, because
# the agent re-arms with since_iso set to now.
#
# Reads with the dev's own gh auth (not the short-lived bot token) so a long watch —
# including across laptop sleep — doesn't expire its credential mid-poll.
#
# Every watch traces its own life — a line per tick, per signal, and at exit — to
# `${TMPDIR:-/tmp}/dnbg-watch/<script>-<pid>.log`, for diagnosing a watch that stops
# without printing a result. ON BY DEFAULT, because the failure it catches is
# intermittent: a knob nobody thought to set beforehand captures nothing.
# `WATCH_LOG=<path>` redirects it, `WATCH_LOG=off` disables it. See "Tracing a watch
# that vanishes" in lib-poll.sh for how to read one, and why a *missing* line is the
# most informative outcome.
set -euo pipefail
unset GH_TOKEN   # use the dev's own (non-expiring) gh auth for the long poll

# ⚠️ CAPTURED BEFORE THE FLAG SHIFTS BELOW, and read by lib-poll.sh's START trace.
# lib-poll captures `$*` at source time, which is *after* those shifts, so without
# this an issue watch traces as a bare `o/r 56` — indistinguishable from a PR watch
# on PR 56, and with no record of which PRs were excluded. The trace is the only
# evidence a killed watch leaves, so the arguments most likely to be wrong on a
# re-arm are exactly the ones it must not drop.
_poll_argv="$*"

# --issue switches what is watched, not how: the curve, the awake clock and the
# failure counting are the same code either way (lib-poll.sh), which is why this
# is a mode rather than a sibling script. What separates a mode from a sibling is
# whether the *result* means something different — watch-merge.sh is a sibling
# because MERGED/DIRTY/BLOCKED are not COMMITS/ACTIVITY with a different label.
#
# --exclude=<csv> lists PR URLs already triaged as not-resolving, which issue mode
# subtracts from its wake set. Only the `=` form is accepted: a two-token
# `--exclude <csv>` would need `shift 2`, which dies under `set -e` when the value
# is missing — no result line at all, imitating the killed watch the tracing exists
# to keep legible. The bare form is rejected as bad-args below instead.
ISSUE_MODE=0; EXCLUDE=""; bad_flag=0
while :; do
  case "${1:-}" in
    --issue)     ISSUE_MODE=1; shift ;;
    --exclude=*) EXCLUDE="${1#--exclude=}"; shift ;;
    --exclude)   bad_flag=1; break ;;
    *)           break ;;
  esac
done
REPO="${1:?owner/repo}"; PR="${2:?pr or issue number}"
LAST_HEAD="${3:-}"; SINCE="${4:-1970-01-01T00:00:00Z}"; SLUG="${5:-}"
WAS_DRAFT=0; [ "${6:-}" = "--was-draft" ] && WAS_DRAFT=1

# One pattern per line, which is what `grep -vxF` consumes. Built once: the set is
# fixed for the life of the watch, and re-splitting it every tick would spend the
# work on every poll of a six-hour window.
#
# ⚠️ EACH ENTRY IS TRIMMED, AND WITHOUT THAT THE WHOLE FLAG FAILS OPEN. `grep -vxF`
# matches whole lines literally, so ` https://…/pull/200` — the shape a human or an
# agent writes after a comma — can never equal the URL the poll produces, and the entry
# is silently ignored. The result is exactly the hot loop `--exclude` exists to prevent,
# with no diagnostic: the caller passed the PR, the watch wakes on it anyway. Every
# other malformed argument on this path is refused loudly (`bad-args` for a valueless
# --exclude, a short SHA, an empty slug); a quiet failure of the wake path is the class
# of bug this mode was broadened to remove, so it must not be reintroduced by the fix.
EXCLUDE_LINES=$(printf '%s' "$EXCLUDE" | tr ',' '\n' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true)

# The poll curve, the awake clock, FAIL_MAX and WINDOW all come from here. This
# script's own default window is the shared 6h: unlike git-workflow's watchers
# (where a timeout means "something's wrong — wake once, don't re-spawn"), IDLE
# here is routine, since a quiet PR is expected and the agent simply re-arms.
# shellcheck source=./lib-poll.sh
. "$(dirname "$0")/lib-poll.sh"

# ⚠️ AN EMPTY SLUG IS FATAL ON THE PR PATH RATHER THAN A DEFAULT. `mine` reduces to
# `. == "" or . == "[bot]"`, which matches no login at all — so the watch stops
# excluding its own activity and wakes on its OWN review, which is precisely the
# self-triggering loop the fifth argument exists to prevent. Both callers document a
# bail on a blank slug, but documentation is not enforcement, and this failure is
# invisible: the watch looks healthy and simply reports its own posts as news.
#
# PR path only — `--issue` mode never reads the slug.

# ⚠️ AN ABBREVIATED `<last_head>` IS A SILENT FALSE POSITIVE, NOT A CONVENIENCE. It is
# compared as a string against the 40-character `headRefOid` GitHub returns, so a short
# SHA can never equal it: the first tick reports COMMITS naming a push that never
# happened. Observed live — two watches armed with 7-character SHAs both returned
# COMMITS within seconds, each naming the full SHA as `new_head`. `reviewer` routes that
# into re-reviewing a delta that does not exist, and `git-workflow` reads it as the
# author having pushed; neither can tell it from a real push.
#
# Rejected rather than prefix-matched: every caller can obtain the full value from
# `gh pr view --json headRefOid`, and accepting abbreviations would make a genuine
# mismatch indistinguishable from a truncation. Uppercase hex is rejected for exactly
# the reason it looks harmless to allow — GitHub returns lowercase, so an uppercase SHA
# would pass a case-insensitive check and then mismatch on every single tick.
#
# Empty is NOT rejected: it self-heals from the first observed HEAD (see the loop), and
# `--issue` mode passes it on purpose.
# ⚠️ THE HEX CLASS IS ENUMERATED, NOT A RANGE, AND `a-f` IS THE REASON. Bracket ranges
# are matched in COLLATION order, which under bash 3.2 — stock macOS, and what
# `env bash` finds on a machine with no Homebrew bash — interleaves case in a UTF-8
# locale: `a-f` spans `a A b B … f F`, so `[!0-9a-f]` does not match `A` and the
# uppercase rejection silently becomes a no-op. Bash 4.3's `globasciiranges` fixes it
# and 5.x defaults it on, which is why CI (ubuntu, bash 5.x) would never show this.
# The length test below is unaffected — no locale touches `${#LAST_HEAD}`.
bad_head=0
case $LAST_HEAD in
  '') ;;
  *[!0123456789abcdef]*) bad_head=1 ;;
  *) [ "${#LAST_HEAD}" = 40 ] || bad_head=1 ;;
esac

# `--exclude` outside `--issue` is refused rather than ignored. Nothing on the PR path
# reads it, so accepting it would take an argument whose entire purpose is suppressing
# wakes and silently not suppress anything — and the caller has no way to tell, since a
# quiet PR and a disregarded exclusion produce the same IDLE. Same reasoning as the
# valueless form above: on this path an argument that cannot do its job is bad-args.
[ "$ISSUE_MODE" = 0 ] && [ -n "$EXCLUDE" ] && bad_flag=1

if [ "$bad_flag" = 1 ] || { [ "$ISSUE_MODE" = 0 ] && { [ -z "$SLUG" ] || [ "$bad_head" = 1 ]; }; }; then
  # ⚠️ A RESULT LINE, NOT `_poll_die`, AND THE DIFFERENCE MATTERS HERE MORE THAN
  # ANYWHERE. Callers branch on `result=`, and `reviewer`'s only handler for a
  # MISSING one reads it as "the task was killed — do not assume quiet, re-read
  # HEAD". So exiting 1 silently would make a plain typo in the fifth argument
  # present as exactly the vanished watch this script's tracing exists to make
  # legible: the one diagnosis we are trying to keep trustworthy, wrong at the
  # first opportunity. ERROR is the honest code — the watch cannot see — and its
  # handler already says don't re-arm, check the arguments.
  echo "result=ERROR reason=bad-args now=$(poll_now_iso)"
  exit 0
fi

# Settle window. An author's round is a burst — reply to three threads, then push
# the fix — but a webhook-driven bot sees one event per action while this sees
# whichever it polls into first. Returning on that first sighting is not merely
# mis-ordered, it is lossy: the agent re-arms with `since_iso` set to now, so
# replies made before the wake but never read are filtered out permanently rather
# than deferred to the next wake.
#
# So once something changes, keep polling until SETTLE seconds pass with nothing
# further, and report the whole burst at once. SETTLE_MAX caps it so an author
# who keeps working can't hold the watch open indefinitely.
#
# Deliberately wall-clock, not awake time, and the only duration here that is.
# SETTLE exists to coalesce one author's burst of actions; a machine that
# suspended mid-burst has ended it by definition, so releasing immediately on
# wake is right. Charging it awake-seconds would hold a hours-old burst back
# waiting for quiet that already happened.
SETTLE=${SETTLE:-45}
SETTLE_MAX=${SETTLE_MAX:-300}

fails_primary=0; fails_comments=0; fails_shape=0
fails_timeline=0; fails_timeline_shape=0; fails_timeline_since=0
# When each transient streak began, in awake seconds — poll_broken needs both a
# tick count and a duration, so a fast blind streak at the floor (a wifi hiccup,
# or the reconnect right after a lid opens) can't end a long watch.
fails_primary_since=0; fails_comments_since=0
poll_init

# A burst in hand outranks ERROR: the observed activity is real, and reporting
# ERROR instead would send the caller to re-arm straight back into the failure
# while silently dropping what was already seen. Same invariant the idle path
# enforces.
report_error() {
  [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] && report_burst
  echo "result=ERROR reason=$1 now=$(poll_now_iso)"
  exit 0
}

# Report the accumulated burst. Defined once because two paths reach it — the
# quiet-period exit below, and the unreachable-gh path at the top of the loop,
# which must not silently drop a burst it can no longer confirm quiet.
report_burst() {
  if [ "$saw_commits" = 1 ]; then
    echo "result=COMMITS new_head=$new_head activity=$saw_activity now=$(poll_now_iso)"
  else
    echo "result=ACTIVITY activity=1 now=$(poll_now_iso)"
  fi
  exit 0
}

# What the burst contained. `obs_*` track the last values already accounted for,
# so a *second* push or reply during the window registers as new and extends it
# rather than re-reporting the same one forever.
saw_commits=0; saw_activity=0; new_head=""
obs_head="$LAST_HEAD"; obs_new=0; obs_newc=0
settle_until=0; settle_cap=0
# Initialised here, not left to the per-tick assignment: the unreachable-gh path
# reads it before any successful tick may have run. Today that is safe only
# because `settle_until != 0` implies one has — a coincidence, not a guarantee.
holding_draft=0

# Each jq program defines `mine` (true if a login is the bot, in either API's
# form). $slug/$s are jq vars from --arg, so the program stays single-quoted.

while :; do
  # Tolerate transient gh/network failures — skip the tick rather than dying
  # (set -e would otherwise kill the watch on a blip; an empty value must not
  # be read as a change).
  if [ "$ISSUE_MODE" = 1 ]; then
    poll_ok=0
    J=$(gh issue view "$PR" --repo "$REPO" --json state,closedByPullRequestsReferences 2>/dev/null) && poll_ok=1
  else
    poll_ok=0
    J=$(gh pr view "$PR" --repo "$REPO" --json state,isDraft,headRefOid,reviews,comments 2>/dev/null) && poll_ok=1
  fi
  if [ "$poll_ok" = 0 ]; then
    fails_primary=$(( fails_primary + 1 ))
    # A source that has failed FAIL_MAX ticks running is not a blip. Without
    # this the watch runs out its window and prints the line a genuinely quiet
    # PR prints, so a caller cannot tell a broken watch from a calm one.
    [ "$fails_primary" = 1 ] && fails_primary_since=$(poll_awake)
    poll_broken "$fails_primary" "$fails_primary_since" \
      && report_error "$([ "$ISSUE_MODE" = 1 ] && echo issue-view || echo pr-view)"
    poll_reset
    # Honour the same invariant the report block below documents: never idle out
    # from under an accumulating burst. If the cap has passed while gh is
    # unreachable, report what was already observed rather than spinning — the
    # burst is real even though it can't be confirmed quiet.
    # `holding_draft` carries the last successful tick's value, which is the right
    # one to trust when gh cannot confirm draft status. Without it a held-back
    # draft reports COMMITS here — the case the quiet-period path already
    # excludes — and this is the laptop-sleep path, where the first poll after
    # wake can fail while `date` has already jumped past the cap.
    [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] \
      && [ "$(date +%s)" -ge "$settle_cap" ] && report_burst
    { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out \
      && { echo "result=IDLE now=$(poll_now_iso)"; exit 0; }
    poll_nap; continue
  fi
  fails_primary=0

  # One shape gate for the payload, counted on its own. A parse failure here is
  # not a poll failure: `$J` came from a call that succeeded, so this is a
  # payload-shape change, which is never transient.
  #
  # It needs its own counter because the successful poll above resets
  # `fails_primary` on every iteration — sharing that counter caps a shape
  # failure at 1, so it can never reach FAIL_MAX and the watch idles out exactly
  # as it did when the parse was swallowed with `|| echo 0`.
  #
  # Guarded, not bare: an unguarded assignment dies under `set -e` with no
  # `result=` line at all, which is the same blindness in a louder costume.
  # ⚠️ IT MUST PROVE THE FIELDS ARE THERE, NOT ONLY THAT THE PAYLOAD PARSES. `// empty`
  # alone established the second and was read as establishing the first: an error body
  # like `{"message":"Not Found"}` is well-formed JSON, so it passed the gate with
  # `fails_shape=0` and `STATE=""` — matching neither MERGED nor CLOSED — and the watch
  # ran its entire window against it and reported IDLE on a PR that had already closed.
  # That is exactly the "broken watch indistinguishable from a calm one" this counter
  # exists to prevent, arriving through the gate meant to catch it.
  #
  # `isDraft` is checked on the PR path for the same reason and is not cosmetic: a
  # missing field renders as the string `null`, which equals neither `true` nor
  # `false`, so the READY transition and `holding_draft` both silently stop working.
  # It also lets the unguarded `//` uses further down keep their justification — they
  # need the FIELDS present, which only this establishes.
  shape_ok=1
  STATE=$(echo "$J" | jq -r '.state // empty' 2>/dev/null) || shape_ok=0
  [ -n "${STATE:-}" ] || shape_ok=0
  if [ "$ISSUE_MODE" = 0 ] && [ "$shape_ok" = 1 ]; then
    DRAFT=$(echo "$J" | jq -r 'if .isDraft == null then "" else .isDraft end' 2>/dev/null) || shape_ok=0
    [ -n "${DRAFT:-}" ] || shape_ok=0
  fi
  if [ "$shape_ok" = 1 ]; then
    fails_shape=0
  else
    fails_shape=$(( fails_shape + 1 ))
    [ "$fails_shape" -ge "$FAIL_MAX" ] \
      && report_error "$([ "$ISSUE_MODE" = 1 ] && echo issue-view-shape || echo pr-view-shape)"
    poll_reset
    { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out \
      && { echo "result=IDLE now=$(poll_now_iso)"; exit 0; }
    poll_nap; continue
  fi

  # Issue mode ends here: nothing to settle, no drafts, no head SHA. Wake as soon
  # as a linked PR exists or the issue closes; otherwise fall through to the same
  # curve, failure counting and idle-out as the PR path.
  if [ "$ISSUE_MODE" = 1 ]; then
    if [ "$STATE" = CLOSED ]; then echo "result=CLOSED state=CLOSED"; exit 0; fi

    # ⚠️ TWO SOURCES, BECAUSE `closedByPullRequestsReferences` LISTS ONLY PRs CARRYING A
    # CLOSING KEYWORD. It is the narrower half by construction, and the `reviewer` skill
    # requires the *mention* rather than the keyword — `git-workflow`'s multi-repo rule
    # has exactly one sibling close the issue and the rest merely reference it. Polling
    # the keyword source alone therefore makes the wake condition strictly narrower than
    # the discovery it exists to trigger: a real resolving PR that links the issue in
    # prose never wakes the watch, and the deadline path then presents it as "the issue
    # number is probably wrong" — a diagnosis that cannot be confirmed, because the issue
    # resolves fine. `tests/coupling.bats` pins these against the skill's discovery set.
    #
    # A discovery source this wait deliberately does NOT poll declares itself here, in
    # the form the coupling test reads. Adding a fourth source to the skill's discovery
    # block without either polling it or writing a line like this fails that test — the
    # divergence has to be a decision someone made, not one that accumulated.
    #
    # PR-SOURCE-EXEMPT: gh search prs — it is the only discovery source with index lag,
    # so the timeline above already sees everything it would, sooner: a poll gains
    # nothing from it. Discovery keeps it for the one thing a poll does not need,
    # finding a sibling in a *different* repo, which the reviewer re-runs on wake anyway.
    #
    # The search API's tighter budget is a secondary reason, and smaller than it first
    # looks: 30/min sustains 1800/hr against core's 5000/hr — roughly 3x tighter, not an
    # order of magnitude. One watch at the 10s floor issues 6 polls/min, well inside
    # 30/min; it would take about five concurrent issue waits to threaten the ceiling.
    # Stated precisely because a margin quoted too grimly gets discounted wholesale the
    # first time someone measures it, taking the sound reason above down with it.
    #
    # Lowercase deliberately. An assignment to a name the caller already exported
    # updates the *exported* value, so a generic uppercase internal here would
    # clobber a caller's environment variable — and this script's children are
    # `gh` invocations that read the environment.
    # `// []` rather than a second guard: the shape gate above already proved the
    # payload parses, so a missing or null field is the only realistic gap left
    # here, and it reads as zero linked PRs — correct.
    #
    # Not total in general: `//` substitutes only on null or false, so a
    # wrong-typed field (`true`, a number, a string) still errors or miscounts.
    # Left unguarded deliberately — reaching it needs well-formed JSON carrying a
    # schema-valid field of the wrong type, while every realistic corruption
    # (an HTML error page, a truncated body, empty output) is caught by the gate.
    closing_urls=$(echo "$J" | jq -r '(.closedByPullRequestsReferences // [])[] | .url // empty')

    # ⚠️ `--slurp` IS LOAD-BEARING, NOT TIDINESS. `--paginate` alone emits each page as a
    # SEPARATE top-level JSON array, so the concatenation is not valid JSON and `jq`
    # rejects the whole thing the moment an issue exceeds one page — the failure would
    # arrive only on a busy issue, which is precisely where a cross-reference is most
    # likely to be waiting. `--slurp` wraps the pages into one array, hence `.[][]`.
    #
    # ⚠️ AND PAGINATION ITSELF IS LOAD-BEARING. The timeline is ordered OLDEST FIRST with
    # no sort parameter to invert it, so on an issue past 100 events every new
    # cross-reference lands on the LAST page. Fetching page one only would poll nothing
    # but history: the wake condition could never fire and the watch would idle out
    # looking perfectly healthy — the same fail-closed-and-silent shape the inline
    # comments fetch below documents, reached from the other end of the ordering.
    #
    # The cost this accepts is one request per 100 timeline events per tick. Unlike the
    # comments endpoint there is no `direction=desc` escape, so it scales with the
    # issue's total history rather than with what is new. Tolerable because the curve
    # leaves the 10s floor within half an hour, and because a wait that cannot see is
    # worth more requests than one that can't be trusted.
    #
    # Split fetch from parse for the reason the comments block gives: folded together, a
    # parse failure reads as "no cross-references" and the watch goes blind silently.
    # ⚠️ FETCH AND PARSE ARE COUNTED SEPARATELY, because lib-poll.sh:66-69 says they are
    # different kinds of failure: a network call is transient by nature and earns the
    # FAIL_MIN_SECONDS grace, while a payload that stopped parsing "will not start
    # parsing on its own, so waiting three minutes to say so only delays the report".
    # The primary payload already honours that split via `fails_shape`. The inline
    # comments block below still folds the two into one counter — a pre-existing
    # divergence this change does not widen, and the reason the split is spelled out
    # here rather than assumed.
    if RAWT=$(gh api "repos/$REPO/issues/$PR/timeline" --paginate --slurp 2>/dev/null); then
      fails_timeline=0
      if xref_urls=$(echo "$RAWT" | jq -r '.[][]
            | select(.event == "cross-referenced")
            | select(.source.issue.pull_request != null)
            | .source.issue.html_url' 2>/dev/null)
      then fails_timeline_shape=0
      else
        fails_timeline_shape=$(( fails_timeline_shape + 1 )); xref_urls=""
        [ "$fails_timeline_shape" -ge "$FAIL_MAX" ] && report_error issue-timeline-shape
      fi
    else
      fails_timeline=$(( fails_timeline + 1 )); xref_urls=""
      [ "$fails_timeline" = 1 ] && fails_timeline_since=$(poll_awake)
      poll_broken "$fails_timeline" "$fails_timeline_since" && report_error issue-timeline
    fi
    { [ "$fails_timeline" -gt 0 ] || [ "$fails_timeline_shape" -gt 0 ]; } && poll_reset

    # Union the two sources, then subtract what the caller has already triaged.
    #
    # ⚠️ THE EXCLUSION LIST IS WHAT KEEPS THE BROADENED CONDITION USABLE. A mention-only
    # PR that stays open satisfies the timeline source on EVERY tick, so without it the
    # first triaged-as-irrelevant PR turns the wait into a hot loop that re-wakes the
    # reviewer forever. Keyed by URL rather than number because the whole point of the
    # timeline source is that it spans repos, where numbers collide.
    #
    # `|| true` on both filters: grep exits 1 on no match, which under `set -e` would
    # kill the watch on the ordinary empty case.
    wake=$(printf '%s\n%s\n' "$closing_urls" "$xref_urls" \
             | grep -v '^[[:space:]]*$' | sort -u || true)
    if [ -n "$wake" ] && [ -n "$EXCLUDE_LINES" ]; then
      wake=$(printf '%s\n' "$wake" | grep -vxF "$EXCLUDE_LINES" || true)
    fi
    if [ -n "$wake" ]; then
      echo "result=ACTIVITY activity=1 now=$(poll_now_iso)"; exit 0
    fi
    poll_timed_out && { echo "result=IDLE now=$(poll_now_iso)"; exit 0; }
    poll_nap; continue
  fi
  if [ "$STATE" = MERGED ] || [ "$STATE" = CLOSED ]; then
    echo "result=CLOSED state=$STATE"; exit 0
  fi

  # `DRAFT` comes from the shape gate above, which is where its presence is proved.
  # Note for anyone tempted to write `.isDraft // empty` there: jq's `//` treats
  # `false` as absent, so it would fire exactly when the PR is ready — hence the
  # explicit `== null` test.
  HEAD=$(echo "$J" | jq -r '.headRefOid // empty')

  # ⚠️ ADOPT THE FIRST HEAD WE SEE WHEN THE CALLER GAVE US NONE. `obs_head` gates the
  # commit branch below and is assigned only inside it, so an empty `<last_head>` used
  # to be a closed loop: the gate could never open, a push went undetected for the
  # whole window, and the watch reported IDLE on a PR that had moved. Self-healing
  # here costs one missed detection at most — a push landing between the caller's last
  # look and our first — instead of failing for the life of the watch. That cost is
  # real rather than free: a caller holding a baseline WOULD have caught that push, so
  # an empty `<last_head>` is a fallback, not a convenient default.
  # Deliberately after the shape gate, so a `null` HEAD never becomes one.
  [ -z "$obs_head" ] && [ -n "$HEAD" ] && obs_head="$HEAD"

  # New formal reviews / top-level comments after SINCE, not authored by the bot.
  # `[]?` skips a missing or non-array field, so the shape gate above is the only
  # place a payload change needs counting in practice. It guards the *iteration*,
  # not the elements: `reviews: [1,2]` would still error on `.submittedAt`. Same
  # judgement as the linked-PR count above — unreachable without well-formed JSON
  # of the wrong shape, and not worth a guard the gate already covers.
  NEW=$(echo "$J" | jq --arg s "$SINCE" --arg slug "$SLUG" '
    def mine: . == $slug or . == ($slug + "[bot]");
    [ (.reviews[]?  | select(.submittedAt > $s and (.author.login | mine | not))),
      (.comments[]? | select(.createdAt  > $s and (.author.login | mine | not))) ] | length')
  # New inline review-comments (thread replies) after SINCE, not by the bot.
  # Split the fetch from the parse so a failure is not read as "no new replies".
  # Ending it in `|| echo 0` would make this path fail *closed and silent*:
  # `gh pr view` keeps succeeding, so the watch looks healthy while thread
  # replies never register — partial blindness nothing reported.
  # ⚠️ PAGINATED, AND THE ORDER IS WHY IT HAS TO BE. This endpoint caps at 30 per
  # page and returns OLDEST FIRST, so on a PR that has accumulated more than 30
  # inline comments every page-one result is old news and each new reply lands on
  # the LAST page. Unpaginated, `NEWC` is then computed over nothing but history:
  # it never rises, no reply ever registers, and the watch idles out looking
  # perfectly healthy. That is the same fail-closed-and-silent shape the note
  # above describes, reached by a different route, and a busy PR with several
  # reviewers is exactly where it bites.
  #
  # ⚠️ NEWEST FIRST, WHICH IS WHAT MAKES ONE REQUEST ENOUGH. Paging through the whole
  # thread history would also be correct, but it re-fetches every page on every tick,
  # so its cost scales with the PR's TOTAL comment count rather than with what is
  # new: a PR at ~250 inline comments is 3 requests per tick, and at the 10s floor
  # that is ~1080/hour against a 5000/hour budget — for a watch whose whole job is to
  # notice the handful of comments at the end. `direction=desc` puts those first, so
  # page one always carries everything created after `$SINCE` and the problem stops
  # existing rather than being paged around.
  #
  # The bound this trades for is 100 new comments within a single window, which is
  # not a real burst — and even at the bound it degrades safely: the count saturates
  # rather than resetting, so it still rises and still wakes the watch.
  if RAWC=$(gh api "repos/$REPO/pulls/$PR/comments?per_page=100&sort=created&direction=desc" 2>/dev/null); then
    if NEWC=$(echo "$RAWC" | jq --arg s "$SINCE" --arg slug "$SLUG" '
        def mine: . == $slug or . == ($slug + "[bot]");
        [ .[] | select(.created_at > $s and (.user.login | mine | not)) ] | length' 2>/dev/null)
    then fails_comments=0
    else
      # A jq failure here is a payload-shape change, never transient — the same
      # reason git-workflow's merge watcher deliberately leaves its jq unsilenced.
      fails_comments=$(( fails_comments + 1 )); NEWC="$obs_newc"
    fi
  else
    fails_comments=$(( fails_comments + 1 )); NEWC="$obs_newc"
  fi
  [ "$fails_comments" = 1 ] && fails_comments_since=$(poll_awake)
  if poll_broken "$fails_comments" "$fails_comments_since"; then report_error comments; fi
  [ "$fails_comments" -gt 0 ] && poll_reset

  # Accumulate this tick's deltas, and restart the quiet timer on anything new.
  #
  # ⚠️ `obs_*` ARE SAFE AS COUNTS ONLY BECAUSE `settle_until` IS NEVER CLEARED. The
  # strictly-greater tests below are a ratchet: once `obs_new` has risen, an item
  # arriving at or below that mark — a delete-and-replace nets to the same total —
  # does not register. That is harmless today, and the reason is two lines away rather
  # than local: raising `obs_*` always sets `changed=1`, which arms `settle_until`, and
  # nothing ever sets it back to 0 — so the idle-out below is disabled and a report is
  # already guaranteed. `ACTIVITY` carries no payload, so the caller re-reads everything
  # since `$SINCE` and finds the replacement anyway.
  #
  # Clear `settle_until` anywhere and that stops holding: the watch could then return
  # to a quiet, still-running state carrying a raised high-water mark, and genuinely new
  # items below it would go unreported for the rest of the window. Track identities
  # instead of counts if that day comes — `.id` is on both payloads already.
  changed=0
  if [ -n "$HEAD" ] && [ -n "$obs_head" ] && [ "$HEAD" != "$obs_head" ]; then
    saw_commits=1; new_head="$HEAD"; obs_head="$HEAD"; changed=1
  fi
  if [ "${NEW:-0}" -gt "$obs_new" ];   then saw_activity=1; obs_new="$NEW";   changed=1; fi
  if [ "${NEWC:-0}" -gt "$obs_newc" ]; then saw_activity=1; obs_newc="$NEWC"; changed=1; fi

  # Draft -> ready. Marking a PR ready is neither a push nor a review nor a
  # comment, so without this the transition is invisible and a deliberately
  # skipped draft would only be noticed on its next push — or never. Pass
  # `--was-draft` when arming the watch on a PR being skipped for that reason.
  #
  # Reported immediately rather than settled: a draft going ready is the signal to
  # start a first review, and nothing else in the burst changes that.
  if [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = false ]; then
    echo "result=READY new_head=$HEAD activity=$saw_activity now=$(poll_now_iso)"; exit 0
  fi

  # A draft we are deliberately holding back is not reportable. Without this a
  # push returns COMMITS, which routes the reviewer into Re-reviewing — reviewing
  # the very draft "Don't review a discovered PR that is still a draft" excludes.
  # Keep accumulating; the READY check above is what releases the burst.
  holding_draft=0
  [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = true ] && holding_draft=1

  if [ "$changed" = 1 ]; then
    # Reset-on-change also keeps SETTLE's resolution usable: the quiet-period
    # check runs once per tick, so a backed-off interval would let SETTLE_MAX
    # release bursts that should have settled quietly.
    #
    # It returns to the floor on each change, not for the whole burst — the quiet
    # tail still advances, so from a 10s floor a SETTLE=45 window releases nearer
    # 70s. SETTLE is a lower bound, so that is late rather than wrong.
    poll_reset
    NOW=$(date +%s)
    settle_until=$(( NOW + SETTLE ))
    [ "$settle_cap" = 0 ] && settle_cap=$(( NOW + SETTLE_MAX ))
  fi

  # Report once the burst has been quiet for SETTLE, or the cap forces it.
  if [ "$settle_until" != 0 ] && [ "$holding_draft" = 0 ] \
     && { [ "$(date +%s)" -ge "$settle_until" ] || [ "$(date +%s)" -ge "$settle_cap" ]; }; then
    report_burst
  fi

  # Idle out only when nothing is being withheld — either nothing is mid-settle,
  # or a burst is accumulating behind a held-back draft, which has no release
  # short of the draft going ready and would otherwise never time out.
  { [ "$settle_until" = 0 ] || [ "$holding_draft" = 1 ]; } && poll_timed_out \
    && { echo "result=IDLE now=$(poll_now_iso)"; exit 0; }
  # No poll_reset on a quiet tick: the curve is a function of how long it has
  # been since something happened, so quiet is exactly what widens it.
  poll_nap
done
