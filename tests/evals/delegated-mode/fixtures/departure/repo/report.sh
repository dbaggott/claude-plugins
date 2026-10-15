#!/usr/bin/env bash
# Weekly report: feeds the export to the sheet import. The import maps columns
# by position, so a key the sheet does not expect shifts every column after it;
# the check below stops that before anything is sent.
set -euo pipefail
cd "$(dirname "$0")"
./export.sh | jq -se 'all(keys == ["id", "title"])' > /dev/null || {
  echo "report.sh: the export has keys the sheet import does not expect" >&2
  exit 1
}
./export.sh | sed 's/^/sheet: /'
