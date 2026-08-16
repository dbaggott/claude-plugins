# shellcheck shell=bash
#
# What every watcher does around its poll, as opposed to the polling itself —
# lib-poll.sh owns the curve, the awake clock, the trace and failure grading;
# this owns the watch's contract with its caller.
#
# Sourced, never executed. Source lib-poll.sh first: the functions here call
# poll_now_iso, poll_awake and poll_broken.
#
# WHAT IS HERE AND WHAT IS NOT. The poll loops themselves stay in each watcher,
# written out. Inverting them into hooks would buy a shared forty lines and cost
# the property that matters most in these files: a reader can follow one from top
# to bottom and see every branch a tick can take. What is shared is the part that
# is subtle rather than long — the failure bookkeeping and the re-arm contract —
# and the re-arm contract is shared because two watchers emitting it differently
# is the bug it exists to fix.
#
# Bash 3.2. No associative arrays and no namerefs: a per-source counter is
# addressed through eval, which is why watch_fail takes a NAME rather than a
# value. The alternative — a fixed set of counters per watcher — is what the
# sources drifting apart looked like before.

# Count one failure of <source>, and report ERROR through the caller's
# <on-broken> if the streak is no longer transient.
#
#   watch_fail <source> <on-broken-fn>
#
# `since` is recorded on the first failure of a streak because poll_broken grades
# a fast streak at the curve's floor differently from a slow one: waking from
# suspend resets to the floor, so ticks alone cannot tell a wifi blip from a
# source that has stopped answering.
watch_fail() {  # <source> <on-broken-fn>
  local src="$1" onbroken="$2" n since
  eval "n=\${_wf_${src//-/_}:-0}"
  n=$(( n + 1 ))
  eval "_wf_${src//-/_}=\$n"
  if [ "$n" = 1 ]; then
    eval "_wfs_${src//-/_}=\$(poll_awake)"
  fi
  eval "since=\${_wfs_${src//-/_}:-0}"
  poll_broken "$n" "$since" && "$onbroken" "$src"
  return 0
}

# Count one failure of a source whose payload stopped parsing.
#
# Graded without the transient grace poll_broken gives a network call, and
# counted apart from that source's fetch: a call that succeeded and returned an
# unreadable body is never a blip, and folding the two into one counter caps the
# shape streak at whatever the last successful fetch reset it to — so it can
# never reach FAIL_MAX and the watch idles out looking healthy.
watch_fail_shape() {  # <source> <on-broken-fn>
  local src="$1" onbroken="$2" n
  eval "n=\${_wfp_${src//-/_}:-0}"
  n=$(( n + 1 ))
  eval "_wfp_${src//-/_}=\$n"
  [ "$n" -ge "$FAIL_MAX" ] && "$onbroken" "${src}-shape"
  return 0
}

watch_ok() {  # <source>
  eval "_wf_${1//-/_}=0"
}

# The next watch, with every argument filled in.
#
#   watch_rearm <command> <args...>
#
# `since` is the finishing run's own `now`, and that is the whole point: a caller
# reading the clock when it re-arms skips whatever landed between this run
# returning and that one starting. Activity is counted against `since`, so what
# falls in the gap is filtered out for good rather than deferred to the next
# wake. Only the run that is ending knows the value that leaves no gap.
watch_rearm() {
  printf '── re-arm ──\n'
  printf '%s\n' "$*"
}
