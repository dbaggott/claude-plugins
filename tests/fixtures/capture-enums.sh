#!/usr/bin/env bash
# Pin the GitHub enums the merge-state mapping branches on.
#
#   capture-enums.sh            # refresh the pinned copies, print a diff
#
# Writes tests/fixtures/enums/<enum>.json from GraphQL introspection, so the set
# of values a caller must handle is read off GitHub's own schema rather than
# recalled. `tests/merge-cause.bats` then asserts the mapping covers every value
# in the pinned copy, with no network of its own.
#
# WHY PIN RATHER THAN INTROSPECT IN THE TEST. A suite that queries GitHub fails
# when the network does, and a test that cannot run is a test nobody keeps. The
# split puts the network in a command someone runs deliberately and the coverage
# assertion in a test that always runs. Re-run this when a mapping surprises you;
# a non-empty diff means GitHub moved and the mapping needs a decision.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/enums"
mkdir -p "$OUT"

# Only the enums something branches on. `CheckConclusionState` and friends are
# deliberately absent: `check_state` normalises them by shape (a missing
# conclusion falls back to status), so a new value there lands in an existing
# bucket rather than needing a new branch.
ENUMS="MergeStateStatus PullRequestReviewDecision"

changed=0
for e in $ENUMS; do
  f="$OUT/$e.json"
  new=$(gh api graphql -f query="{ __type(name: \"$e\") { enumValues { name description } } }" \
        --jq '.data.__type.enumValues | sort_by(.name)')
  [ -n "$new" ] || { echo "introspection returned nothing for $e" >&2; exit 1; }
  printf '%s\n' "$new" | jq --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg e "$e" \
    '{_captured: {enum: $e, at: $at, source: "GitHub GraphQL introspection"}, values: .}' > "$f.new"
  if [ -f "$f" ] && diff -q <(jq -S 'del(._captured)' "$f") <(jq -S 'del(._captured)' "$f.new") >/dev/null; then
    # Discarded rather than moved: re-stamping `_captured.at` would leave the
    # file dirty on a run that changed nothing, and the header sends a reader to
    # `git diff` to find out whether GitHub moved.
    rm -f "$f.new"; echo "$e: unchanged"
  else
    if [ -f "$f" ]; then
      echo "$e: CHANGED"
      diff <(jq -r '.values[].name' "$f") <(jq -r '.values[].name' "$f.new") || true
      changed=1
    else
      echo "$e: new"
    fi
    mv "$f.new" "$f"
  fi
done

[ "$changed" = 0 ] || echo "A changed enum needs a mapping decision, not just a re-pin." >&2
exit 0
