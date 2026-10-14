#!/usr/bin/env bash
# Print each entry in entries.tsv as one JSON object per line.
set -euo pipefail
cd "$(dirname "$0")"
tail -n +2 entries.tsv | while IFS=$'\t' read -r id title _; do
  jq -cn --argjson id "$id" --arg title "$title" '{id: $id, title: $title}'
done
