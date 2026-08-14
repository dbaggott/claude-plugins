#!/usr/bin/env bash
# Regenerates every GIF under docs/media/ from its demo script.
#
#   docs/media/render.sh          # all of them
#   docs/media/render.sh gate     # just one, by name
#
# Needs `asciinema` and `agg` (brew install asciinema agg). Nothing else — the
# demos build whatever state they drive, and reach neither the network nor any
# path outside /tmp.
#
# check-render.sh verifies the artifacts this writes are still current, and CI
# runs it on every PR. Re-render and commit whenever a demo script, lib-demo.sh,
# or a hook whose output a demo shows changes.
set -euo pipefail

ONLY="${1:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./demos.sh
. "$HERE/demos.sh"

render() {
  local name="$1" cols="$2" rows="$3"
  local script="$HERE/demo-$name.sh" cast="$HERE/demo-$name.cast" gif="$HERE/demo-$name.gif"

  asciinema rec --window-size "${cols}x${rows}" --overwrite -q "$cast" -c "$script"

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
