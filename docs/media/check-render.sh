#!/usr/bin/env bash
# Fails if a committed artifact under docs/media/ no longer matches what its
# demo script produces. CI runs this on every PR; run it by hand the same way:
#
#   docs/media/check-render.sh
#
# It exists because the artifacts have four inputs and only one of them is the
# demo script: lib-demo.sh feeds every reenactment, and the hooks whose output
# demo-gate.sh and demo-file-issue.sh print live feed those two. So rewording a
# hook's block message stales a GIF from a PR that never touches this directory,
# where no reviewer would think to look.
#
# What is compared, per demo:
#   - the .cast's output stream against a fresh run of the script
#   - the .cast header's window size against demos.sh
#
# Not the .gif. agg writes it in the same render.sh call that writes the .cast,
# so a fresh .cast implies a fresh .gif unless someone hand-edits one; verifying
# it directly would mean building agg on the runner to buy that.
#
# Fast because `beat` is the only thing in a demo that takes time, and a no-op
# `sleep` first on PATH removes it — the whole suite runs in well under a second.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./demos.sh
. "$HERE/demos.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$WORK/sleep"
chmod +x "$WORK/sleep"
export PATH="$WORK:$PATH"

ESC=$'\033'
# The cast records through a pty, which turns every \n into \r\n; a pipe does
# not. macOS additionally resolves /tmp through a symlink, so the repo root
# demo-gate.sh shows is spelled differently there than on Linux.
normalize() { LC_ALL=C tr -d '\r' | LC_ALL=C sed 's|/private/tmp/|/tmp/|g'; }
visible()   { LC_ALL=C sed "s|${ESC}|<ESC>|g"; }

fail=0
note() { printf '::error::%s\n' "$1" >&2; fail=1; }

# A demo missing from demos.sh is rendered by nothing and checked by nothing.
for script in "$HERE"/demo-*.sh; do
  name="$(basename "$script" .sh)"; name="${name#demo-}"
  case " ${DEMOS[*]} " in
    *" $name:"*) ;;
    *) note "demo-$name.sh is not in demos.sh — it is neither rendered nor checked" ;;
  esac
done

for d in "${DEMOS[@]}"; do
  IFS=: read -r name cols rows <<< "$d"
  cast="$HERE/demo-$name.cast"
  [ -f "$cast" ] || { note "demo-$name: no .cast — run render.sh $name"; continue; }
  [ -f "$HERE/demo-$name.gif" ] || note "demo-$name: no .gif — run render.sh $name"

  # Window size, which decides what fits on screen and what scrolls away.
  read -r had_cols had_rows < <(head -1 "$cast" | jq -r '"\(.term.cols) \(.term.rows)"')
  [ "$had_cols" = "$cols" ] && [ "$had_rows" = "$rows" ] || \
    note "demo-$name: recorded at ${had_cols}x${had_rows}, demos.sh says ${cols}x${rows} — run render.sh $name"

  # stdout and stderr merged: a pty carries both, and the block messages the
  # hooks print — the whole point of two of these demos — go to stderr.
  if ! bash "$HERE/demo-$name.sh" > "$WORK/actual" 2>&1; then
    note "demo-$name: the script exited non-zero"
    continue
  fi
  tail -n +2 "$cast" | jq -j 'select(.[1]=="o") | .[2]' | normalize > "$WORK/expected"
  normalize < "$WORK/actual" > "$WORK/actual.n"

  if ! cmp -s "$WORK/actual.n" "$WORK/expected"; then
    note "demo-$name: the committed .cast does not match the script — run render.sh $name"
    diff -u <(visible < "$WORK/expected") <(visible < "$WORK/actual.n") \
      | sed 's/^/    /' >&2 || true
  fi
done

[ "$fail" = 0 ] && echo "docs/media: ${#DEMOS[@]} demos match their committed artifacts"
exit "$fail"
