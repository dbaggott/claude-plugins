# shellcheck shell=bash
# The demo list, shared by render.sh (which records) and check-render.sh (which
# verifies the committed artifacts still match). One list, so a demo added for
# one is never invisible to the other.
#
# name:cols:rows — rows leave a little headroom over the script's line count so
# nothing scrolls off. A GIF loops, so a scrolled-away opening is gone for good.
# Read by the two scripts that source this, which shellcheck analyzes
# separately — so it looks unused from in here.
# shellcheck disable=SC2034
DEMOS=(
  "gate:96:26"
  "resolve-review:127:50"
  "file-issue:82:32"
  "work-summary:80:45"
  "vibe-review:127:52"
)
