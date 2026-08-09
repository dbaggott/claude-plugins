#!/usr/bin/env bash
# Shared polling primitives for the watchers in this directory. Sourced, never
# executed — `watch-pr.sh` and `watch-merge.sh` both `.` this file.
#
# Two things live here because both watchers need them and neither can own them:
# the poll-interval curve, and the awake clock.
#
# ## The awake clock
#
# Every duration here — the curve's position and the window — is measured in
# laptop-open seconds, not wall-clock. A watch that spent the night suspended has
# not been watching, and charging it for that time is wrong in both directions:
# it retires the window without the watch ever having looked, and it comes back
# at the 5-minute cap at exactly the moment the operator has returned and is
# about to act. `poll_nap` detects a suspend as overshoot on its own sleep and
# banks it in `_poll_suspended`, which every elapsed calculation subtracts.
#
# ## The curve
#
# A watch is most valuable early. A PR merges, a review lands, or a PR shows up
# for review usually within minutes, and nearly always inside the first hour or
# so; after that the odds flatten and a fast poll stops buying anything. So the
# interval is a piecewise-linear function of how long the watch has been quiet,
# given as breakpoints rather than as a state machine:
#
#   POLL_CURVE="<awake-seconds>:<interval-seconds> ..."
#
# Between breakpoints the interval is linearly interpolated; past the last one it
# is flat. The default, and what each breakpoint is buying:
#
#   0s     -> 10s    the first minutes, where most events land
#   30m    -> 30s
#   1h30m  -> 60s    a minute or better across the whole likely window
#   2h+    -> 300s   the cap — nobody waits more than 5 minutes for a wake
#
# Expressing it as a pure function of elapsed time (`poll_interval_at`) is what
# makes it testable without running a watch: there is no accumulated per-tick
# state to seed, and retuning is a one-line diff rather than a re-derivation.
# `tests/lib-poll.bats` pins both the breakpoints and the two properties that
# outlive any particular shape — never slower than 60s inside the first 90
# minutes, never slower than the cap ever.

# INTERVAL pins the curve flat at one value. Kept as its own knob because a test
# wants a fixed rate, and writing `POLL_CURVE=0:1` in every test would couple
# each of them to the curve's syntax for no benefit.
# `-` not `:-` on purpose: an explicitly empty POLL_CURVE is a caller bug, and
# quietly serving the default would hide it for the life of the watch.
POLL_CURVE=${POLL_CURVE-"0:10 1800:30 5400:60 7200:300"}
[ -n "${INTERVAL:-}" ] && POLL_CURVE="0:${INTERVAL}"

# Consecutive failed ticks of one source before a watch declares itself broken.
# Counted in TICKS, not elapsed time: ticks are elastic, so an elapsed threshold
# alone would mean something different at the floor than at the cap.
FAIL_MAX=${FAIL_MAX:-10}

# ...but ticks alone are not enough either, because a failure resets the curve to
# the floor. Ten ticks at a 10s floor is 100 seconds, so a two-minute wifi hiccup
# would end a six-hour watch and report it as broken.
#
# That is not hypothetical: waking from suspend also resets to the floor, so
# lid-open-and-reconnect is precisely a fast blind streak. A watch must ride that
# out. Both conditions have to hold — enough ticks AND enough awake time — before
# a transient source is called broken.
FAIL_MIN_SECONDS=${FAIL_MIN_SECONDS:-180}

# For sources whose failures are transient by nature (a network call). A shape
# break is NOT one of these: the payload will not start parsing on its own, so
# waiting three minutes to say so only delays the report. Those keep the plain
# FAIL_MAX check at their call site.
poll_broken() {   # $1 = consecutive failures, $2 = awake seconds when the streak began
  [ "$1" -ge "$FAIL_MAX" ] || return 1
  [ $(( $(poll_awake) - $2 )) -ge "$FAIL_MIN_SECONDS" ]
}

# How long a watch runs before reporting that nothing happened. Awake seconds —
# see the header. Callers differ on what a timeout *means* (routine for the
# reviewer's watch, a problem for the author's), so only the number lives here.
WINDOW=${WINDOW:-21600}

# A nap that overshoots by more than this is read as a machine suspend rather
# than a busy scheduler. Generous on purpose: over-counting a loaded machine's
# late wake as suspend costs a few seconds of clock, while under-counting a real
# suspend costs the whole window.
POLL_SUSPEND_SLACK=${POLL_SUSPEND_SLACK:-30}

_poll_die() { echo "watch: $*" >&2; exit 1; }

# ## Tracing a watch that vanishes (on by default)
#
# Every watch records its own life: one line per tick, one per signal, one at exit.
# Traces land in `${TMPDIR:-/tmp}/dnbg-watch/<script>-<pid>.log` and are swept after
# three days. `WATCH_LOG=<path>` redirects it; `WATCH_LOG=off` turns it off, after
# which every function below is an immediate return and nothing is spent.
#
# ⚠️ IT EXISTS BECAUSE A VANISHED WATCH LEAVES NO EVIDENCE ANYWHERE ELSE, which is
# not obvious until you go looking for it. A background task reported as killed
# has an EMPTY output file, because a watch writes its one result line at exit and
# a watch that was killed never reached it. macOS keeps nothing either: the
# unified log does not record ordinary process signals or exits, and dtrace's
# `proc:::signal-send` — the only probe that names WHO signalled WHOM — needs SIP
# disabled. So a watch that stopped could not be diagnosed after the fact at all.
#
# Three records partition the causes, and the third is an absence:
#
#   SIGNAL=<name>   something asked it to stop, and the name says what kind
#   EXIT code=<n>   it stopped itself — a `set -e` death, or a normal result
#   neither         SIGKILL, or the process group went down underneath it
#
# The absence only means anything against a heartbeat, which is why the tick line
# earns its place: without one, "the watch died silently" and "the watch was never
# running" produce identical logs.
#
# ⚠️ ON BY DEFAULT, AND THAT IS THE WHOLE POINT — an opt-in knob is off exactly when
# it matters. The failure this traces is intermittent and unreproducible: it has
# happened four times, never on demand, and nobody knows in advance which watch will
# be the one that dies. A knob somebody has to remember to set BEFORE a random
# failure captures nothing, so the feature would ship and never once fire.
#
# `WATCH_LOG=off` opts out. Any other value is an explicit path.
#
# Defaulting also covers every caller for free, including the six spawn sites in the
# skills and any written later — wiring the knob into those instead would leave each
# new spawn site silently opted out again.
_poll_trace_default() {
  local dir="${TMPDIR:-/tmp}/dnbg-watch"
  mkdir -p "$dir" 2>/dev/null || return 1
  # Best-effort sweep, so unattended tracing cannot grow without bound. Failures are
  # ignored: housekeeping must never be the reason a watch does not start.
  find "$dir" -name '*.log' -mtime +3 -delete 2>/dev/null || true
  printf '%s/%s-%s.log' "$dir" "$(basename "${0%.sh}")" "$$"
}

_poll_trace_defaulted=0
if [ "${WATCH_LOG:-}" = off ]; then
  WATCH_LOG=""
elif [ -z "${WATCH_LOG:-}" ]; then
  WATCH_LOG=$(_poll_trace_default) || WATCH_LOG=""
  _poll_trace_defaulted=1
fi

# ⚠️ THE LIVE PARENT, NOT `$PPID`. Bash captures `$PPID` once at startup and never
# refreshes it, so after the parent dies it still names the dead one — exactly the
# case worth detecting. A watch reparented to 1 was ORPHANED, which is a different
# failure from being killed and is otherwise indistinguishable in the log.
_poll_parent() {
  local p
  p=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')
  printf '%s(%s)' "$(ps -o comm= -p "${p:-0}" 2>/dev/null | tr -d ' ')" "${p:-?}"
}

# Never fails the watch: a trace that cannot be written is worth less than the
# watch, so an unwritable path is swallowed rather than killing the run under
# `set -e`.
poll_log() {
  [ -n "$WATCH_LOG" ] || return 0
  printf '%s pid=%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$*" >> "$WATCH_LOG" 2>/dev/null || true
}

# Log, then re-raise with the default disposition so the exit status still encodes
# the signal. Clearing the trap first is what keeps the re-raise from re-entering
# this handler.
_poll_on_signal() {
  poll_log "SIGNAL=$1 parent=$(_poll_parent)"
  # Take the nap's `sleep` down first. Re-raising kills this shell, and the child
  # would outlive it by up to a whole interval — 300s at the cap. Harmless in
  # itself, but leaving a stray process behind is a poor look for the one code path
  # whose entire job is to make a death legible.
  # ⚠️ `|| true` IS LOAD-BEARING, NOT TIDINESS. `kill` here follows the final `&&`,
  # which `set -e` does NOT exempt, and both watchers run under `set -euo pipefail`.
  # The nap child is often already gone — `wait` reaps it a moment before
  # `_poll_napper` is cleared — so the kill fails, the handler aborts before the
  # re-raise, and the death is recorded as an ordinary exit. That is a FALSE trace
  # (a SIGNAL line and an EXIT line together, contradicting the table, with the
  # status no longer naming the signal), which costs strictly more than the stray
  # `sleep` the reap was added to prevent.
  if [ -n "${_poll_napper:-}" ]; then kill "$_poll_napper" 2>/dev/null || true; fi
  trap - "$1"
  kill -s "$1" $$
}

# Guarded INSIDE rather than at the call site: the arguments to `poll_log` are
# expanded before it runs, so an unguarded tick line would fork `ps` twice per
# poll for a log nobody asked for.
_poll_log_tick() {
  [ -n "$WATCH_LOG" ] || return 0
  poll_log "tick interval=${1}s awake=$(poll_awake)s quiet=$(poll_quiet)s parent=$(_poll_parent)"
}

# Installed only while tracing: these traps change the exit path, which is not
# something to carry on the default path in exchange for nothing.
poll_trace_init() {
  [ -n "$WATCH_LOG" ] || return 0
  # ⚠️ ONE UNGUARDED WRITE, FIRST. `poll_log` swallows per-line failures, which is
  # right — a trace is worth less than the watch — but swallowing the FIRST one
  # turns a mistyped path into the most misleading outcome this feature has. A
  # `WATCH_LOG` under a directory that does not exist writes nothing at all, not
  # even START, and no file is exactly row three of the table above: killed before
  # its first tick. That reading is confidently wrong, and the path is typed by
  # hand, at the moment something has just gone wrong, by someone already primed to
  # expect a silent death.
  # ⚠️ `2>/dev/null` FIRST, BEFORE THE APPEND. Redirections are applied left to right,
  # so writing it the other way round attempts `>>` while stderr is still the
  # caller's — bash prints its own `Permission denied` there before the suppression
  # is in effect. Now that tracing defaults on, this line is reached by every watch
  # on the machine, and the branch below deliberately carries on without dying: a raw
  # error on the stderr of a watch that then runs perfectly normally is a confusing
  # thing to hand somebody, especially on the one script whose stderr gets read when
  # they are already trying to work out why a watch misbehaved.
  if ! : 2>/dev/null >> "$WATCH_LOG"; then
    # ⚠️ LOUD FOR A PATH THE CALLER TYPED, SILENT FOR THE DEFAULT, and the asymmetry
    # is the point. An explicit path that cannot be written is a caller error, and
    # swallowing it produces the most misleading outcome this feature has: no file at
    # all, which the table above reads as row three. The default path is nobody's
    # request, so it must never take down a watch that was otherwise doing its job —
    # now that tracing is on by default, dying here would turn an unwritable TMPDIR
    # into every watch failing to start.
    [ "$_poll_trace_defaulted" = 1 ] || _poll_die "WATCH_LOG=$WATCH_LOG is not writable"
    WATCH_LOG=""
    return 0
  fi
  local s
  for s in TERM INT HUP QUIT PIPE USR1 USR2; do
    # SC2064 expands $s at install time deliberately — the handler has to know
    # which signal it is standing in for, and a deferred expansion would read the
    # loop variable's final value in every trap.
    # shellcheck disable=SC2064
    trap "_poll_on_signal $s" "$s"
  done
  # `$?` here is the pending exit status, so a `set -e` death is recorded with the
  # status that caused it rather than as a clean finish.
  # shellcheck disable=SC2064
  trap 'poll_log "EXIT code=$?"' EXIT
  poll_log "START script=$(basename "$0") parent=$(_poll_parent) window=${WINDOW}s curve=${POLL_CURVE}"
}

# Breakpoints, split into parallel arrays at source time so a malformed knob
# fails before the watch prints anything — a bad curve is a caller bug, and
# silently falling back to the default would hide it for the life of the watch.
_poll_t=(0); _poll_i=(10)
_poll_parse_curve() {
  local pair t i prev=-1
  local -a parts=() ts=() is=()
  read -r -a parts <<< "$POLL_CURVE"
  [ "${#parts[@]}" -gt 0 ] || _poll_die "POLL_CURVE is empty"
  for pair in "${parts[@]}"; do
    case $pair in
      *:*) ;;
      *) _poll_die "POLL_CURVE entry '$pair' is not <seconds>:<interval>" ;;
    esac
    t=${pair%%:*}; i=${pair##*:}
    case $t in ''|*[!0-9]*) _poll_die "POLL_CURVE offset '$t' is not a non-negative integer" ;; esac
    # ⚠️ OFFSETS MAY BE ZERO, INTERVALS MAY NOT, and the asymmetry is the point: the
    # curve has to start at offset 0, while a zero INTERVAL makes `poll_nap` return
    # at once and turns the watch into a busy loop around `gh`. Measured before this
    # check: 200 naps in 2s, which is the hourly REST budget gone inside a minute and
    # the watch then blind behind rate-limit failures for the rest of its window —
    # while still reporting a perfectly ordinary IDLE. `INTERVAL` is the knob tests
    # and callers reach for, so `INTERVAL=0` is a live typo, not a hypothetical.
    case $i in ''|*[!0-9]*) _poll_die "POLL_CURVE interval '$i' is not a non-negative integer" ;; esac
    [ "$i" -ge 1 ] || _poll_die "POLL_CURVE interval must be at least 1s (got $i) — 0 spins"
    # Strictly increasing, so the interpolation below can never divide by zero
    # and the segment search can never pick a later breakpoint than it meant to.
    [ "$t" -gt "$prev" ] || _poll_die "POLL_CURVE offsets must strictly increase (got $t after $prev)"
    prev=$t
    ts[${#ts[@]}]=$t
    is[${#is[@]}]=$i
  done
  [ "${ts[0]}" = 0 ] || _poll_die "POLL_CURVE must start at offset 0 (got ${ts[0]})"
  _poll_t=("${ts[@]}"); _poll_i=("${is[@]}")
}
_poll_parse_curve

# The curve as a pure function: interval for a given quiet-time, in seconds.
# Public because it is the whole shape of the thing and deserves a test that
# doesn't have to run a watch to reach it.
poll_interval_at() {
  local e=$1 n k t0 t1 i0 i1
  n=${#_poll_t[@]}
  if [ "$e" -le "${_poll_t[0]}" ]; then echo "${_poll_i[0]}"; return 0; fi
  k=1
  while [ "$k" -lt "$n" ]; do
    if [ "$e" -lt "${_poll_t[$k]}" ]; then
      t0=${_poll_t[$((k - 1))]}; t1=${_poll_t[$k]}
      i0=${_poll_i[$((k - 1))]}; i1=${_poll_i[$k]}
      echo $(( i0 + ((i1 - i0) * (e - t0)) / (t1 - t0) ))
      return 0
    fi
    k=$((k + 1))
  done
  echo "${_poll_i[$((n - 1))]}"
}

_poll_start=0; _poll_suspended=0; _poll_baseline=0

# Call once, after the knobs are set and before the loop.
poll_init() { _poll_start=$(date +%s); _poll_suspended=0; _poll_baseline=0; poll_trace_init; }

# Awake seconds since poll_init.
poll_awake() { echo $(( $(date +%s) - _poll_start - _poll_suspended )); }

# Awake seconds since the last poll_reset — the curve's input.
poll_quiet() { echo $(( $(poll_awake) - _poll_baseline )); }

# Back to the floor. Three callers, for three different reasons:
#   - an observed change: the watch just got interesting again;
#   - a failed poll: FAIL_MAX is counted in ticks, so a watch that went blind at
#     the cap would take 10 x 5 minutes to say so;
#   - a detected suspend: waking at the dormant cap is being least responsive
#     exactly when the human has come back.
poll_reset() { _poll_baseline=$(poll_awake); }

poll_interval() { poll_interval_at "$(poll_quiet)"; }

poll_timed_out() { [ "$(poll_awake)" -ge "$WINDOW" ]; }

poll_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Sleep one interval, then reconcile the clock with what actually elapsed.
poll_nap() {
  local iv before after over
  iv=$(poll_interval)
  # Before the sleep, not after: a watch is killed mid-sleep far more often than
  # mid-poll, and a line written afterwards is the one line that would be missing.
  _poll_log_tick "$iv"
  # ⚠️ BACKGROUND `sleep` + `wait`, NOT A FOREGROUND `sleep`, and the trace is the
  # reason. Bash defers a trap until the running foreground command finishes, so a
  # foreground nap swallows a SIGTERM for up to a full interval — five minutes at
  # the cap. Worse, where a SIGKILL follows the TERM, the handler never runs at
  # all and the log shows exactly the silent death the trace was added to rule
  # out, which is a false answer rather than a missing one. `wait` is
  # interruptible, so the handler runs while the signal still means something.
  #
  # Only trapped signals cut `wait` short, and the traps are installed only while
  # tracing — so with WATCH_LOG unset this sleeps precisely as it did before.
  # ⚠️ THIS CLOBBERS `$!` FOR THE CALLER. Neither watcher backgrounds anything, so
  # nothing is broken today — but this is a shared library function, so a future
  # caller that backgrounds a job and reads `$!` after a nap would get the sleep.
  # The pid is kept in `_poll_napper` rather than left in `$!` so the signal
  # handler can reap it, and so that this is stated rather than discovered.
  before=$(date +%s)
  sleep "$iv" &
  _poll_napper=$!
  wait "$_poll_napper" 2>/dev/null || true
  _poll_napper=""
  after=$(date +%s)
  over=$(( after - before - iv ))
  if [ "$over" -gt "$POLL_SUSPEND_SLACK" ]; then
    _poll_suspended=$(( _poll_suspended + over ))
    poll_reset
    poll_log "suspend over=${over}s banked=${_poll_suspended}s"
  fi
  return 0
}
