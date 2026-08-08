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
    case $i in ''|*[!0-9]*) _poll_die "POLL_CURVE interval '$i' is not a non-negative integer" ;; esac
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
poll_init() { _poll_start=$(date +%s); _poll_suspended=0; _poll_baseline=0; }

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
  before=$(date +%s); sleep "$iv"; after=$(date +%s)
  over=$(( after - before - iv ))
  if [ "$over" -gt "$POLL_SUSPEND_SLACK" ]; then
    _poll_suspended=$(( _poll_suspended + over ))
    poll_reset
  fi
  return 0
}
