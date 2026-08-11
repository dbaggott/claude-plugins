#!/usr/bin/env bash
# Shared rendering for the README demos.
#
# These demos are *reenactments*: the dialogue is scripted, because the parts
# worth showing — a skill deciding something, a picker, an agent explaining why
# it diverged from an issue — are Claude Code's own interface and never reach
# stdout for a recorder to capture. Where a demo shows literal command output
# (the check-worktree block message, `gh` results) that text is the real thing,
# copied verbatim rather than invented.
#
# The split-pane renderer is append-only on purpose. Repainting the screen each
# step would make every GIF frame a full-screen change, and the file several
# times larger; emitting one row at a time keeps the frame deltas small and
# makes each row read as a moment shared by both sessions.

# Read by the demo scripts that source this, which shellcheck analyzes
# separately — so every one of them looks unused from in here.
# shellcheck disable=SC2034
C_USER=$'\033[1;36m'   # the operator's prompt
C_TOOL=$'\033[38;5;110m'  # a tool call
C_SAY=$'\033[0;37m'    # the agent talking
C_OK=$'\033[32m'
C_WARN=$'\033[33m'
C_BAD=$'\033[31m'
C_DIM=$'\033[2m'
C_OFF=$'\033[0m'

PANE_W="${PANE_W:-56}"

beat() { sleep "${1:-0.9}"; }

# Visible width, ignoring SGR escapes — pure bash, because shelling out to sed
# once per column per row is slow enough to show up in the recording's timing.
vislen() {
  local s="$1" out=""
  while [[ $s == *$'\033['* ]]; do
    out+="${s%%$'\033['*}"
    s="${s#*$'\033['}"
    s="${s#*m}"
  done
  out+="$s"
  printf '%s' "${#out}"
}

pad() {
  local s="$1" w="$2" n
  n=$(( w - $(vislen "$s") ))
  (( n < 0 )) && n=0
  printf '%s%*s' "$s" "$n" ""
}

# One moment in time: what the left session showed, and what the right one did.
# Either side may be empty.
row() {
  printf '%s %s│%s %s\n' "$(pad "${1:-}" "$PANE_W")" "$C_DIM" "$C_OFF" "${2:-}"
}

# Column headers plus the rule under them.
panes() {
  local l="$1" r="$2" rule=""
  printf -v rule '%*s' "$PANE_W" ''
  row "${C_USER}${l}${C_OFF}" "${C_USER}${r}${C_OFF}"
  printf '%s%s─┼─%s%s\n' "$C_DIM" "${rule// /─}" "${rule// /─}" "$C_OFF"
}

# An AskUserQuestion picker. Claude Code draws this itself, so this is the one
# element that is a drawing rather than a capture — kept to the same shape and
# the same option order the skills specify.
picker_lines() {
  local q="$1"; shift
  PICKER=()
  PICKER+=("${C_DIM}╭─${C_OFF} ${C_USER}${q}${C_OFF}")
  local i=1 opt
  for opt in "$@"; do
    if (( i == 1 )); then
      PICKER+=("${C_DIM}│${C_OFF} ${C_OK}❯ ${i}. ${opt}${C_OFF}")
    else
      PICKER+=("${C_DIM}│${C_OFF}   ${i}. ${opt}")
    fi
    i=$(( i + 1 ))
  done
  PICKER+=("${C_DIM}╰─${C_OFF}")
}
