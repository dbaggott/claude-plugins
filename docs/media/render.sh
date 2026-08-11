#!/usr/bin/env bash
# Regenerates every GIF under docs/media/ from its demo script.
#
#   docs/media/render.sh <path-to-a-throwaway-clone>   # all of them
#   docs/media/render.sh <clone> gate                  # just one, by name
#
# The clone is only used by the `gate` demo, which drives the real
# check-worktree.sh against it and creates a worktree inside it. Its `origin`
# must be a github.com repo whose owner is the one demo-gate.sh exports, or the
# gate has nothing to fire on. Pass a path git will not resolve through a
# symlink — on macOS `/tmp` is one, and check-worktree mishandles that
# (https://github.com/dbaggott/claude-plugins/issues/97).
#
# `gh` must be authenticated: the gate demo reads real reviews off a real PR.
#
# Needs `asciinema` and `agg` (brew install asciinema agg).
set -euo pipefail

REPO="${1:?usage: render.sh <path-to-throwaway-clone> [demo-name]}"
ONLY="${2:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# name:cols:rows — rows leave a little headroom over the script's line count so
# nothing scrolls off. A GIF loops, so a scrolled-away opening is gone for good.
DEMOS=(
  "gate:96:26"
  "resolve-review:127:50"
  "file-issue:82:32"
  "work-summary:78:29"
  "vibe-review:127:48"
)

render() {
  local name="$1" cols="$2" rows="$3"
  local script="$HERE/demo-$name.sh" cast="$HERE/demo-$name.cast" gif="$HERE/demo-$name.gif"

  asciinema rec --window-size "${cols}x${rows}" --overwrite -q "$cast" -c "$script $REPO"

  # Zero the first event's delay. asciicast v3 timestamps are inter-event
  # intervals, so the recorder's own startup gap lands in front of the first
  # frame — and agg turns that gap into a leading frame with nothing on it.
  # That frame is what a reader with animation suppressed sees, so it has to
  # carry the demo's opening rather than an empty terminal.
  awk 'NR>1 && !done && /^\[/ { sub(/^\[[0-9.]+,/, "[0.0,"); done=1 } { print }' \
    "$cast" > "$cast.tmp" && mv "$cast.tmp" "$cast"

  agg --font-size 20 --theme asciinema --last-frame-duration 4 "$cast" "$gif"
  printf '  %-16s %s KB\n' "$name" "$(( $(wc -c < "$gif") / 1024 ))"
}

for d in "${DEMOS[@]}"; do
  IFS=: read -r name cols rows <<< "$d"
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue
  render "$name" "$cols" "$rows"
done
