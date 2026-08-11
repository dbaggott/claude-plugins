#!/usr/bin/env bash
# Regenerates docs/media/demo.cast and demo.gif from docs/media/demo.sh.
#
#   docs/media/render.sh <path-to-a-throwaway-clone>
#
# The clone's `origin` must be a github.com repo whose owner is the one exported
# in demo.sh, or the gate has nothing to fire on. `gh` must be authenticated for
# the second act, which reads real reviews off a real PR.
#
# Needs `asciinema` and `agg` (brew install asciinema agg).
set -euo pipefail

REPO="${1:?usage: render.sh <path-to-throwaway-clone>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAST="$HERE/demo.cast"
GIF="$HERE/demo.gif"

asciinema rec --window-size 96x26 --overwrite -q "$CAST" -c "$HERE/demo.sh $REPO"

# Zero the first event's delay. asciicast v3 timestamps are inter-event
# intervals, so the recorder's own startup gap lands in front of the first
# frame — and agg turns that gap into a leading frame with nothing on it. That
# frame is what a reader with animation suppressed sees, so it has to carry the
# demo's opening rather than an empty terminal.
awk 'NR>1 && !done && /^\[/ { sub(/^\[[0-9.]+,/, "[0.0,"); done=1 } { print }' \
  "$CAST" > "$CAST.tmp" && mv "$CAST.tmp" "$CAST"

agg --font-size 20 --theme asciinema --last-frame-duration 4 "$CAST" "$GIF"

printf '\n%s (%s KB)\n' "$GIF" "$(( $(wc -c < "$GIF") / 1024 ))"
