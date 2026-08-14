#!/usr/bin/env bash
# Block until a reviewable change appears on a PR, then print what changed and
# exit. Drives the `reviewer` skill's in-session watch loop: after a review the
# agent spawns this as a background task; when it returns, the agent
# re-reviews/responds and re-arms it. Detects new commits, new (non-bot)
# reviews/comments/replies, a draft being marked ready, and the PR closing.
#
#   watch-pr.sh <owner/repo> <pr> <last_head_sha> <since_iso> <bot_slug> \
#     [--was-draft] [--last-verdict=<sha>]
#   watch-pr.sh --issue [--exclude=<url,url,...>] <owner/repo> <issue> "" <since_iso> <slug>
#
# last_head_sha is a FULL 40-character lowercase SHA, or empty. Anything else is
# rejected as bad-args rather than compared — see the check below for why an
# abbreviated one is worse than no baseline at all.
#
# --last-verdict=<sha> makes verdict detection LEVEL-triggered, the way the head
# comparison already is. Commits are detected by comparing state (`last_head_sha`
# against what GitHub reports), so a push during a gap in watching is still seen
# on the next poll; reviews are counted against `since_iso`, so a verdict posted
# while no watch was running — or before the `since_iso` a re-arm was given — is
# invisible for good, and the watch then reports IDLE, which reads as a quiet PR.
# A missed push self-heals; a missed verdict does not.
#
# The value is the SHA the CALLER last handled a verdict for: empty (`--last-verdict=`)
# means none, and is the right value on a first arm. Each poll reads the standing
# verdict; if it is attached to the current HEAD and its SHA is not the one passed
# in, the watch wakes regardless of `since_iso`. So a verdict can only be lost by
# the caller saying it already handled that one — which is what the reported
# `verdict_sha=` field is for. Re-arm with it, or the next watch wakes on the same
# verdict immediately, forever.
#
# Omitting the flag leaves verdict detection edge-triggered, as before.
#
# Two things it deliberately does not cover, both of which the edge trigger still
# catches whenever a watch is actually running: a second verdict at the SAME SHA
# (an APPROVED reversed to CHANGES_REQUESTED without a push), and a verdict left
# behind by a push, which is stale by construction and needs a fresh review anyway.
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
# Prints a summary of the activity it saw as one compact JSON object per line,
# then — where a round is there to be read — the call that reads it in full, then
# exactly one result line, then exits 0:
#   {"kind":"review|comment|inline","author":…,"at":…}
#   ── next ──
#   "<dir>/pr-round.sh" <owner/repo> <pr> <since-sha> <since-iso> <slug>
#   result=COMMITS new_head=<sha> activity=0|1 now=<iso>  # author pushed
#   result=ACTIVITY activity=1 now=<iso>                  # review/comment/reply, not the bot's
#   result=READY new_head=<sha> activity=0|1 now=<iso>    # draft marked ready — only with --was-draft
#   result=CLOSED state=MERGED|CLOSED                     # PR finished — stop watching
#   result=IDLE now=<iso>                                 # nothing within the window — re-arm
#   result=ERROR reason=<source> now=<iso>                # the watch itself is broken — do NOT re-arm
#
# COMMITS, ACTIVITY and READY carry `verdict_sha=<sha> verdict=<state>` before
# `now=` when the level-triggered check above fired. The SHA is the value to
# re-arm `--last-verdict` with; absent means that check did not fire, so carry the
# previous value forward. Those three are also the results that print `── next ──`,
# because they are the ones with a round behind them.
#
# No bodies here — this signals, `pr-round.sh` delivers. What a wake needs is
# whether to act and on what; the text, the unresolved threads and the diff are
# one call away and only that call has all three. A watcher that printed bodies
# looked complete while carrying neither the threads nor the diff, so a caller
# could act on it and be wrong — and one that ran pr-round.sh anyway paid for
# every body twice.
#
# `verdict=` IS A BRANCHING HINT AND MUST NOT REPLACE THE `pr-verdict.sh` READ.
# It reports the standing verdict as of this poll, which is not the question a
# caller about to act on an approval is asking — that one has to be re-read
# against the HEAD being merged. Its value is picking the branch before fetching.
#
# A bad argument reports `result=ERROR reason=bad-args` and still exits 0, rather
# than dying silently: a caller reads a MISSING result line as "killed", so a typo
# would otherwise imitate the vanished watch this script exists to make legible. A
# malformed POLL_CURVE still dies at source time via `_poll_die` — that one is a
# caller bug caught before the loop.
#
# ERROR is not IDLE. IDLE means the PR was quiet; ERROR means one source failed
# for FAIL_MAX ticks AND at least FAIL_MIN_SECONDS of awake time, so the watch
# cannot see. Both callers stop and tell the operator what to check (gh auth, the
# number/repo pair) rather than re-arming into the same failure. Short outages —
# a wifi hiccup, the reconnect after a lid opens — are ridden out.
#
# `activity=1` on a COMMITS or READY result means comments or replies landed in
# the same burst, and the JSON lines above the result line say what landed and
# from whom — read them together with the `── next ──` call, which is what
# fetches the text. The primary result names what to do first; ignoring the rest
# loses those replies for good, because the agent re-arms with since_iso set to
# now.
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

# Captured before the flag shifts below, and read by lib-poll.sh's START trace.
# lib-poll captures `$*` at source time, which is *after* those shifts, so without
# this the trace records only what survived them — no `--issue`, no `--exclude`, and
# so no way to tell an issue watch from a PR watch on the same number. The trace is
# the only evidence a killed watch leaves, so the arguments most likely to be wrong
# on a re-arm are exactly the ones it must not drop.
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

# Trailing flags, in any order, and anything unrecognised is refused.
#
# The refusal is the point: the alternative is a flag that silently does
# nothing. Reading a trailing flag by position instead honours `--was-draft
# --last-verdict=<sha>` in one order and drops half of it in the other, depending only
# on how they were typed. Both are wake paths, and a wake path that fails quietly is
# the class of bug `--exclude`'s valueless form is refused to avoid.
#
# `shift` is bounded by `$#` because the two `${n:?}` above only guarantee two
# arguments: `shift 5` on a three-argument call fails, which under `set -e` kills the
# watch with no result line at all — the vanished-watch case this script must not fake.
shift $(( $# < 5 ? $# : 5 ))
WAS_DRAFT=0; LAST_VERDICT=""; HAVE_LAST_VERDICT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --was-draft)       WAS_DRAFT=1 ;;
    --last-verdict=*)  LAST_VERDICT="${1#--last-verdict=}"; HAVE_LAST_VERDICT=1 ;;
    *)                 bad_flag=1 ;;
  esac
  shift
done

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
# --exclude, a short SHA, an empty slug); a quiet failure of the wake path is the one
# thing this mode must never do.
EXCLUDE_LINES=$(printf '%s' "$EXCLUDE" | tr ',' '\n' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true)

# The poll curve, the awake clock, FAIL_MAX and WINDOW all come from here. This
# script's own default window is the shared 6h: unlike git-workflow's watchers
# (where a timeout means "something's wrong — wake once, don't re-spawn"), IDLE
# here is routine, since a quiet PR is expected and the agent simply re-arms.
# shellcheck source=./lib-poll.sh
. "$(dirname "$0")/lib-poll.sh"

# The activity filters, shared with pr-round.sh so both emit the same objects.
# shellcheck source=./lib-activity.sh
. "$(dirname "$0")/lib-activity.sh"

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
# happened, with the full SHA as `new_head`. `reviewer` routes that into re-reviewing a
# delta that does not exist, and `git-workflow` reads it as the author having pushed;
# neither can tell it from a real push.
#
# Rejected rather than prefix-matched: every caller can obtain the full value from
# `gh pr view --json headRefOid`, and accepting abbreviations would make a genuine
# mismatch indistinguishable from a truncation. Uppercase hex is rejected for exactly
# the reason it looks harmless to allow — GitHub returns lowercase, so an uppercase SHA
# would pass a case-insensitive check and then mismatch on every single tick.
#
# Empty is NOT rejected: it self-heals from the first observed HEAD (see the loop), and
# `--issue` mode passes it on purpose. `--last-verdict=` is empty for the same kind of
# reason — the caller has handled no verdict yet — which is why both go through one
# check rather than each growing its own.
#
# The hex class is enumerated rather than a range, and `a-f` is the reason. Bracket ranges
# are matched in COLLATION order, which under bash 3.2 — stock macOS, and what
# `env bash` finds on a machine with no Homebrew bash — interleaves case in a UTF-8
# locale: `a-f` spans `a A b B … f F`, so `[!0-9a-f]` does not match `A` and the
# uppercase rejection silently becomes a no-op. Bash 4.3's `globasciiranges` fixes it
# and 5.x defaults it on, which is why CI (ubuntu, bash 5.x) would never show this.
# The length test is unaffected — no locale touches `${#1}`.
sha_ok() {  # a full 40-character lowercase SHA, or empty
  case $1 in
    '') return 0 ;;
    *[!0123456789abcdef]*) return 1 ;;
    *) [ "${#1}" = 40 ] ;;
  esac
}
bad_head=0
sha_ok "$LAST_HEAD" || bad_head=1
sha_ok "$LAST_VERDICT" || bad_flag=1

# `--exclude` outside `--issue` is refused rather than ignored. Nothing on the PR path
# reads it, so accepting it would take an argument whose entire purpose is suppressing
# wakes and silently not suppress anything — and the caller has no way to tell, since a
# quiet PR and a disregarded exclusion produce the same IDLE. Same reasoning as the
# valueless form above: on this path an argument that cannot do its job is bad-args.
[ "$ISSUE_MODE" = 0 ] && [ -n "$EXCLUDE" ] && bad_flag=1

# ...and `--last-verdict` inside it, for the mirror-image reason: an issue has no
# reviews and no HEAD, so nothing on that path could ever read the baseline. Accepting
# it would take an argument whose whole purpose is guaranteeing a wake and guarantee
# nothing, and the caller sees the same IDLE either way.
[ "$ISSUE_MODE" = 1 ] && [ "$HAVE_LAST_VERDICT" = 1 ] && bad_flag=1

if [ "$bad_flag" = 1 ] || { [ "$ISSUE_MODE" = 0 ] && { [ -z "$SLUG" ] || [ "$bad_head" = 1 ]; }; }; then
  # A result line, not `_poll_die`, and the difference matters here more than
  # anywhere. Callers branch on `result=`, and `reviewer`'s only handler for a
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
# That burst is what watching an author looks like, and the default is sized for
# it. A reviewer's round is the opposite shape: one write. Its verdict and every
# inline comment filed with it share a timestamp, and the two sources below expose
# them on the same tick — measured, not deduced. Watching a reviewer therefore
# needs settle only to cover skew between those sources, which is why
# `git-workflow`'s spawn passes its own value instead of inheriting this one.
# That reading is of an agent reviewer. A human filing comments over several
# minutes is a burst like any author's, and a settle sized for skew alone reports
# it as one wake per write; each write is newer than the re-arm point, so that
# costs extra rounds rather than the loss described above.
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

# What set `activity=1`, straight from the payloads the poll already made — as a
# summary. Who posted what kind of thing, where, and when; not the text.
#
# Reads the LAST SUCCESSFUL poll's payloads, which is what the unreachable-gh path
# has when it reports a burst it can no longer confirm quiet — the best available
# answer there, and exact everywhere else. The filters come from lib-activity.sh
# rather than being spelled here, so pr-round.sh emits the same objects and this
# emits that shape minus the body.
emit_activity() {
  [ "$saw_activity" = 1 ] || return 0
  { echo "${J:-}"    | jq -c --arg s "$SINCE" --arg slug "$SLUG" "$ACTIVITY_JQ_REVIEWS" 2>/dev/null || true
    echo "${RAWC:-}" | jq -c --arg s "$SINCE" --arg slug "$SLUG" "$ACTIVITY_JQ_INLINE"  2>/dev/null || true
  } | jq -c "$ACTIVITY_JQ_SUMMARY" 2>/dev/null || true
}

# The call that reads this round in full, with every argument already filled in.
#
# This watch holds the whole tuple pr-round.sh takes, so a caller reassembling it
# by hand is copying state across a boundary that did not need one — and a caller
# who never learns the script exists hand-rolls the round instead. A printed
# command is reachable from the wake itself; a prose pointer in another file is
# not, and loses outright to any instruction to batch reads.
#
# `<since-sha>` stays the SHA the caller last handled even on COMMITS: the new
# head is what they have *not* handled, so it is the far end of the delta, not
# the near one. Blank renders as a literal `""` — pr-round.sh takes that as "no
# round handled yet, send the full diff", and takes a missing argument as
# bad-args, so the quotes are what keeps the printed command runnable.
emit_next() {
  printf '── next ──\n'
  printf '"%s/pr-round.sh" %s %s %s %s %s\n' \
    "$(cd "$(dirname "$0")" && pwd)" "$REPO" "$PR" "${LAST_HEAD:-\"\"}" "$SINCE" "$SLUG"
}

# Report the accumulated burst. Defined once because two paths reach it — the
# quiet-period exit below, and the unreachable-gh path at the top of the loop,
# which must not silently drop a burst it can no longer confirm quiet.
report_burst() {
  emit_activity
  emit_next
  if [ "$saw_commits" = 1 ]; then
    echo "result=COMMITS new_head=$new_head activity=$saw_activity$(verdict_field) now=$(poll_now_iso)"
  else
    echo "result=ACTIVITY activity=1$(verdict_field) now=$(poll_now_iso)"
  fi
  exit 0
}

# The SHA to re-arm `--last-verdict` with and the state standing at it, printed
# only when the level-triggered check fired. Absent rather than empty on every
# other result: an empty field would be indistinguishable from "no verdict
# handled", and a caller reading it back would discard the baseline it already
# holds and wake on that same verdict next arm.
verdict_field() {
  [ -n "$verdict_sha" ] && printf ' verdict_sha=%s verdict=%s' "$verdict_sha" "$verdict_state" || true
}

# What the burst contained. `obs_*` track the last values already accounted for,
# so a *second* push or reply during the window registers as new and extends it
# rather than re-reporting the same one forever.
saw_commits=0; saw_activity=0; new_head=""; verdict_sha=""; verdict_state=""
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
  # failure at 1, so it can never reach FAIL_MAX and the watch idles out.
  #
  # That is the fail-closed-and-silent shape, stated here once for the whole file.
  # A parse failure folded into a default — `|| echo 0`, a swallowed `jq` — reads as
  # "nothing new": `gh` keeps succeeding, the watch looks perfectly healthy, and
  # whatever it can no longer see goes unreported. Every fetch/parse split below is
  # there to avoid it, and points back here rather than restating it.
  #
  # Guarded, not bare: an unguarded assignment dies under `set -e` with no
  # `result=` line at all, which is the same blindness in a louder costume.
  # ⚠️ IT MUST PROVE THE FIELDS ARE THERE, NOT ONLY THAT THE PAYLOAD PARSES. `// empty`
  # establishes only the second: an error body like `{"message":"Not Found"}` is
  # well-formed JSON, so it passes the gate with `fails_shape=0` and `STATE=""` —
  # matching neither MERGED nor CLOSED — and the watch runs its whole window against
  # that, reporting IDLE on a PR that has already closed. Hence the emptiness tests.
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

    # The second source exists because `closedByPullRequestsReferences` lists only
    # PRs carrying a closing keyword. It is the narrower half by construction, and the `reviewer` skill
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
    # looking perfectly healthy — the fail-closed-and-silent shape the shape gate
    # above states, reached from the other end of the ordering.
    #
    # The cost this accepts is one request per 100 timeline events per tick. Unlike the
    # comments endpoint there is no `direction=desc` escape, so it scales with the
    # issue's total history rather than with what is new. Tolerable because the curve
    # leaves the 10s floor within half an hour, and because a wait that cannot see is
    # worth more requests than one that can't be trusted.
    #
    # Split fetch from parse for the reason above: folded together, a parse failure
    # reads as "no cross-references" and the watch goes blind silently.
    #
    # Fetch and parse are counted separately, because `poll_broken` in lib-poll.sh
    # grades them differently: a network call is transient by nature and earns the
    # FAIL_MIN_SECONDS grace, while a payload that stopped parsing gets the plain
    # FAIL_MAX check. The primary payload honours that split via `fails_shape`; the
    # inline comments block below folds the two into one counter, which is why the
    # split is spelled out here rather than assumed.
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
  # commit branch below and is assigned only inside it, so without this an empty
  # `<last_head>` is a closed loop: the gate never opens, a push goes undetected for
  # the whole window, and the watch reports IDLE on a PR that has moved. Self-healing
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
  #
  # COUNTED WITH THE FILTER THAT EMITS, NOT A MATCHING COPY OF IT. `emit_activity`
  # reports what this counts, so a predicate that drifted between the two would print
  # `activity=1` above an empty payload — and a caller now told the payload IS the
  # conversation reads that as nothing landed, then re-arms with `since_iso` set to
  # now and loses it for good. Wrapping the shared filter makes them one expression
  # rather than two that agree today.
  NEW=$(echo "$J" | jq --arg s "$SINCE" --arg slug "$SLUG" "[ $ACTIVITY_JQ_REVIEWS ] | length")
  # New inline review-comments (thread replies) after SINCE, not by the bot.
  # Split the fetch from the parse so a failure is not read as "no new replies" —
  # the fail-closed-and-silent shape the shape gate above states.
  #
  # ⚠️ THE ENDPOINT'S DEFAULTS ARE UNUSABLE HERE, AND THE ORDER IS WHY. It caps at
  # 30 per page and returns OLDEST FIRST, so on a PR that has accumulated more than
  # 30 inline comments every page-one result is old news and each new reply lands on
  # the LAST page. Left at the defaults, `NEWC` is computed over nothing but history:
  # it never rises, no reply ever registers, and the watch idles out looking
  # perfectly healthy — the same shape reached by a different route, and a busy PR
  # with several reviewers is exactly where it bites.
  #
  # Newest first, which is what makes one request enough. Paging through the whole
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
    if NEWC=$(echo "$RAWC" | jq --arg s "$SINCE" --arg slug "$SLUG" \
                "[ $ACTIVITY_JQ_INLINE ] | length" 2>/dev/null)
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
  # `obs_*` are safe as counts only because `settle_until` is never cleared. The
  # strictly-greater tests below are a ratchet: once `obs_new` has risen, an item
  # arriving at or below that mark — a delete-and-replace nets to the same total —
  # does not register. That is harmless today, and the reason is two lines away rather
  # than local: raising `obs_*` always sets `changed=1`, which arms `settle_until`, and
  # nothing ever sets it back to 0 — so the idle-out below is disabled and a report is
  # already guaranteed. And the report carries the replacement regardless of what the
  # counts did, because `emit_activity` re-filters the whole payload against `$SINCE`
  # rather than emitting a per-tick delta.
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

  # The standing verdict, compared against what the caller says it handled — the
  # level-triggered half described at the top of this file. `$SINCE` is not consulted,
  # which is the whole point: this is what survives a window where no watch was running.
  #
  # ⚠️ THE BOT'S OWN VERDICTS ARE EXCLUDED, AND WITHOUT THAT THIS WAKES `reviewer` ON ITS
  # OWN REVIEW — the self-triggering loop the `<bot_slug>` argument exists to prevent,
  # arriving through the one check that ignores `$SINCE` and so cannot age out of it.
  # The exclusion is a no-op on the author side, where the slug is the author's own login
  # and GitHub does not let an author verdict their own PR.
  #
  # `COMMENTED` is not a verdict and must stay out of the set: a reviewer answering a
  # thread posts one, so counting it would wake on every exchange. `DISMISSED` is in it
  # because a dismissal genuinely ends the review it dismissed. Same set, same reasoning,
  # as pr-verdict.sh — `tests/coupling.bats` pins the two together.
  #
  # `last`, not "the last APPROVED": an APPROVED followed by a CHANGES_REQUESTED at the
  # same SHA is not an approval, and this must wake on the same event pr-verdict.sh
  # reports. Unguarded jq for the reason the `NEW` query above gives — the shape gate
  # has already proved the payload parses, and `[]?`/`//` cover a missing field.
  if [ "$HAVE_LAST_VERDICT" = 1 ]; then
    # State and SHA in one read: the caller wants to know WHICH verdict stands
    # before it fetches, and the reviews list is already in hand either way.
    #
    # ASSIGNED FIRST, THEN SPLIT, BECAUSE A HEREDOC WOULD SWALLOW THE FAILURE. The
    # jq stays unguarded on purpose (see the `NEW` query above) so a payload-shape
    # change kills the watch loudly; a command substitution feeding `read` via a
    # heredoc discards its exit status instead, leaving both variables empty and this
    # check silently never firing again — fail-closed-and-silent, reached through the
    # one line written to avoid it.
    VLINE=$(echo "$J" | jq -r --arg slug "$SLUG" '
      def mine: . == $slug or . == ($slug + "[bot]");
      [ .reviews[]?
        | select((.author.login | mine | not)
                 and (.state == "APPROVED" or .state == "CHANGES_REQUESTED"
                      or .state == "DISMISSED")) ]
      | last | [(.state // ""), (.commit.oid // "")] | @tsv')
    IFS=$'\t' read -r VSTATE VSHA <<<"$VLINE"
    # At HEAD only. A verdict the author has since pushed past is stale by construction
    # — it needs a fresh review, which arrives as a new verdict at the new HEAD — and
    # waking on it would fire after every push, on feedback the caller already handled.
    if [ -n "$VSHA" ] && [ "$VSHA" = "$HEAD" ] && [ "$VSHA" != "$LAST_VERDICT" ]; then
      # Advancing the baseline is what keeps this from re-firing on every tick for the
      # life of the watch — the same ratchet `obs_*` are, for the same reason.
      saw_activity=1; verdict_sha="$VSHA"; verdict_state="$VSTATE"; LAST_VERDICT="$VSHA"; changed=1
    fi
  fi

  # Draft -> ready. Marking a PR ready is neither a push nor a review nor a
  # comment, so without this the transition is invisible and a deliberately
  # skipped draft would only be noticed on its next push — or never. Pass
  # `--was-draft` when arming the watch on a PR being skipped for that reason.
  #
  # Reported immediately rather than settled: a draft going ready is the signal to
  # start a first review, and nothing else in the burst changes that.
  if [ "$WAS_DRAFT" = 1 ] && [ "$DRAFT" = false ]; then
    emit_activity
    emit_next
    echo "result=READY new_head=$HEAD activity=$saw_activity$(verdict_field) now=$(poll_now_iso)"; exit 0
  fi

  # A draft we are deliberately holding back is not reportable. Without this a
  # push returns COMMITS, which routes the reviewer into a re-review — reviewing
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
