#!/usr/bin/env bats
#
# The merge-state mapping, checked against GitHub's own schema rather than
# against cases somebody thought of.
#
# Every defect this mapping shipped with was the same shape: a real combination
# nobody had enumerated. Cases invented to match the code reproduce that blind
# spot, because the author picks the combinations they already believe in. So
# the coverage assertion here reads the value list out of a pinned copy of
# GitHub's `MergeStateStatus` enum — refresh it with
# `tests/fixtures/capture-enums.sh` — and the behaviour assertions replay
# payloads captured from live PRs.

load trace-dir

FETCH="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/fetch-pr-state.sh"
ENUMS="${BATS_TEST_DIRNAME}/fixtures/enums"
STATES="${BATS_TEST_DIRNAME}/fixtures/pr-state"

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export PAYLOAD="$BATS_TEST_TMPDIR/payload.json"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
# Inline comments are a second request the fixtures do not cover; the mapping
# under test does not read them.
case "$*" in *"pulls/"*"/comments"*) echo '[]'; exit 0 ;; esac
cat "$PAYLOAD"
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
}

# A synthetic payload carrying one merge status. Used only where the question is
# "does this value map at all" — anything about a real combination replays a
# captured fixture instead.
with_status() {  # <mergeStateStatus> [rollup-json] [reviewDecision]
  jq -cn --arg m "$1" --argjson r "${2:-[]}" --arg d "${3:-}" \
    '{state:"OPEN", isDraft:false,
      headRefOid:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      reviews:[], comments:[], statusCheckRollup:$r,
      mergeStateStatus:$m, reviewDecision:$d}' > "$PAYLOAD"
}

merge_of() { "$FETCH" o/r 1 | head -1 | jq -c '.merge'; }
replay() { jq 'del(._captured)' "$STATES/$1.json" > "$PAYLOAD"; }

# --- coverage, read off the schema --------------------------------------------

# The guard the mapping's history argues for: a value GitHub documents that
# nothing branches on lands in `unrecognised`, which is the bucket meaning "the
# schema moved". A documented value in there is a mapping that stopped being
# complete, and today HAS_HOOKS is the one that was — a *mergeable* state read
# as unrecognised, so every PR on a repo with pre-receive hooks looked like a
# state no caller acts on.
@test "every documented MergeStateStatus maps to something with a meaning" {
  local v out
  for v in $(jq -r '.values[].name' "$ENUMS/MergeStateStatus.json"); do
    with_status "$v" '[{"name":"c","status":"COMPLETED","conclusion":"SUCCESS"}]'
    out=$(merge_of)
    [ "$(jq -r '.status' <<<"$out")" != unrecognised ] || {
      echo "$v is documented by GitHub but maps to unrecognised: $out" >&2
      false
    }
  done
}

# The other half: the bucket has to still work. Without this the test above
# passes by mapping everything to a constant.
@test "a value GitHub does not document is unrecognised, not guessed" {
  with_status NEWLY_INVENTED
  [ "$(merge_of | jq -r '.status')" = unrecognised ]
}

# `indeterminate` says "ask again", `unrecognised` says "a person must look".
# Collapsing them into one status — which is what shipped — gives a caller one
# behaviour for a transient GitHub answers routinely and for a schema change.
@test "cannot-determine-yet is not the same status as never-heard-of-it" {
  with_status UNKNOWN
  local a; a=$(merge_of | jq -r '.status')
  with_status NEWLY_INVENTED
  local b; b=$(merge_of | jq -r '.status')
  [ "$a" = indeterminate ]
  [ "$a" != "$b" ]
}

@test "every documented PullRequestReviewDecision is handled under BLOCKED" {
  local v out
  for v in $(jq -r '.values[].name' "$ENUMS/PullRequestReviewDecision.json"); do
    with_status BLOCKED '[{"name":"c","status":"COMPLETED","conclusion":"SUCCESS"}]' "$v"
    out=$(merge_of | jq -r '.cause')
    case "$v" in
      REVIEW_REQUIRED|CHANGES_REQUESTED) [ "$out" = review_required ] ;;
      APPROVED)                          [ "$out" = terminal ] ;;
      *) echo "unhandled decision $v -> $out" >&2; false ;;
    esac
  done
}

# --- behaviour, replayed from live captures ------------------------------------

# What a hand-written payload cannot establish: that GitHub actually pairs these
# fields this way. Each fixture carries the repo, PR and branch protection it was
# taken from, in its own `_captured` key.

@test "a green check with a review outstanding is a review wait" {
  replay blocked-review-required
  [ "$(merge_of | jq -r '.cause')" = review_required ]
}

@test "a red required check outranks the review wait" {
  replay blocked-checks-failing
  [ "$(merge_of | jq -r '.cause')" = checks_failing ]
}

@test "a conflict with base is named as one" {
  replay dirty-conflict
  [ "$(merge_of | jq -r '.status')" = dirty ]
}

# GitHub recomputes mergeability asynchronously and serves this to whoever asks
# during the window. It is not an error and not a mapping gap — the caller polls
# again — but a reader that treats mergeStateStatus as always authoritative will
# act on it.
@test "a recomputing PR reports indeterminate rather than a stale answer" {
  replay unknown-recomputing
  [ "$(merge_of | jq -r '.status')" = indeterminate ]
  [ "$(merge_of | jq -r '.cause')" = recomputing ]
}

# --- the fixtures themselves ----------------------------------------------------

# A fixture nobody can place is a fixture nobody can re-take, and re-taking is
# the whole point: these encode GitHub behaviour, which moves.
@test "every captured fixture records where it came from" {
  local f
  for f in "$STATES"/*.json; do
    [ "$(jq -r '._captured.repo // empty' "$f")" != "" ] || {
      echo "$(basename "$f") has no _captured.repo" >&2; false; }
    [ "$(jq -r '._captured.at // empty' "$f")" != "" ] || {
      echo "$(basename "$f") has no _captured.at" >&2; false; }
  done
}

# The capture script asks for one field list and the fetch reads another; they
# have to be the same list or a fixture silently lacks a field the mapping needs.
@test "the capture script asks for the fields the fetch reads" {
  local cap fetch
  cap=$(grep -oE '^FIELDS=[a-zA-Z,]+' "$BATS_TEST_DIRNAME/fixtures/capture-pr-state.sh" | cut -d= -f2)
  fetch=$(grep -oE '\-\-json [a-zA-Z,]+' "$FETCH" | head -1 | cut -d' ' -f2)
  [ "$cap" = "$fetch" ]
}
