#!/usr/bin/env bats
#
# The tool list that check-worktree.sh gates lives in three places, and its own
# comment says a tool missing from any of them is editable in the main checkout
# without the gate firing. That is a silent, security-relevant failure with no
# other check on it — this is the check.

ROOT="${BATS_TEST_DIRNAME}/.."

# The heading of the always-on rule that states the gate. The tool enumeration is
# read from this section alone, so a slash-run anywhere else in the file — a
# future rule mentioning GitHub/GitLab, say — can never be read as a tool list.
GATE_SECTION='All file changes in a covered repo go through a PR'

# The three extractors. Each takes its file as an argument rather than reading a
# fixed path, so the same code that checks the real files is what the induced
# failures below run against — a check that can only be pointed at the passing
# case is a check nobody has seen fail.

# check-worktree.sh's `case` — the set the script itself acts on.
case_tools() {  # <check-worktree.sh>
  sed -n 's/^  \(\([A-Za-z]*|\)*[A-Za-z]*\)) ;;$/\1/p' "$1" | tr '|' '\n' | sort -u
}

# hooks.json — the set Claude Code actually invokes the hook for. A tool here but
# not in the case is a wasted invocation; a tool in the case but not here never
# reaches the script at all.
matcher_tools() {  # <hooks.json>
  jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("check-worktree")) | .matcher' "$1" \
    | tr '|' '\n' | sort -u
}

# always-on-rules.md — what the agent reads. It is prose, so the enumeration is
# taken from the one construct in the gate section that enumerates: the
# slash-delimited run of capitalised names ("Edit/Write/NotebookEdit"). That run
# is the convention, and it costs the rules file nothing — the prose already
# wrote the list that way. A tool claimed gated in free prose *outside* the run
# is not seen here; the run is the enumeration.
rules_tools() {  # <always-on-rules.md>
  # awk rather than a sed range: a `/^## x/,/^## /` range ends *inclusive* of the
  # next heading, so a future heading that itself carried a slash-run would be
  # read as part of the gate enumeration. This stops before it.
  awk -v h="## $GATE_SECTION" '$0 == h { inside = 1; next } /^## / { inside = 0 } inside' "$1" \
    | grep -oE '[A-Z][A-Za-z]+(/[A-Z][A-Za-z]+)+' | tr '/' '\n' | sort -u
}

# Set equality in both directions, which is the whole point: containment in the
# case→rules direction alone misses the case check-worktree.sh:15-18 actually
# warns about — a tool the rules tell the agent is gated while neither the case
# nor the matcher gates it. Equality also makes the substring accident
# structurally impossible, where a per-tool `grep` for `Edit` matched inside
# `NotebookEdit` and passed on a rules file that never named `Edit`.
gate_agrees() {  # <always-on-rules.md> <check-worktree.sh> <hooks.json>
  local from_rules from_case from_matcher
  from_rules=$(rules_tools "$1")
  from_case=$(case_tools "$2")
  from_matcher=$(matcher_tools "$3")

  [ -n "$from_case" ] || { echo "no gated tools found in the case"; return 1; }
  [ "$from_case" = "$from_matcher" ] || {
    echo "the case and the hooks.json matcher disagree:"
    echo "  case:    $(echo "$from_case" | tr '\n' ' ')"
    echo "  matcher: $(echo "$from_matcher" | tr '\n' ' ')"
    return 1
  }
  [ "$from_case" = "$from_rules" ] || {
    echo "the case and always-on-rules.md disagree:"
    echo "  case:  $(echo "$from_case" | tr '\n' ' ')"
    echo "  rules: $(echo "$from_rules" | tr '\n' ' ')"
    echo "the rules must name the gated tools as one slash-delimited run"
    echo "(Edit/Write/NotebookEdit) under '## $GATE_SECTION'"
    return 1
  }
}

# A rules file in the shape the extractor expects, with the tool run substituted.
# The decoy run in the first section is load-bearing, but only through the
# positive test below: the two negative tests assert a mismatch, and a decoy
# leaking in through an unscoped extractor only deepens a mismatch they were
# going to see anyway. It takes a fixture that is supposed to *agree* for the
# stray tools to break something.
fixture_rules() {  # <slash-delimited tool run>
  cat > "$BATS_TEST_TMPDIR/rules.md" <<EOF
## No flattery

Not the gate section, and it names Read/Glob to prove the scan ignores it.

## $GATE_SECTION

Any edit to a tracked file goes through a worktree + draft PR. Load the
\`dnbg-workflow:git-workflow\` skill before the first
$1 call so the worktree/PR flow is in context.

## Reference issues and PRs by full URL

Nothing to enumerate here either.
EOF
  echo "$BATS_TEST_TMPDIR/rules.md"
}

@test "the gated tool list agrees across the case, the matcher, and the rules" {
  run gate_agrees "$ROOT/dnbg-workflow/always-on-rules.md" \
    "$ROOT/dnbg-workflow/hooks/check-worktree.sh" \
    "$ROOT/dnbg-workflow/hooks/hooks.json"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "a rules file naming exactly the gated set agrees, decoys and all" {
  # The only one of these fixtures that is supposed to pass, and so the only one
  # that pins the section scoping: drop the scoping and the decoy `Read/Glob` in
  # the fixture's first section joins the enumeration, which makes this fail.
  # It is also the only direction that catches rules_tools returning too little.
  run gate_agrees "$(fixture_rules 'Edit/Write/NotebookEdit')" \
    "$ROOT/dnbg-workflow/hooks/check-worktree.sh" \
    "$ROOT/dnbg-workflow/hooks/hooks.json"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "a rules file naming NotebookEdit but not Edit is caught" {
  # The substring accident, induced rather than asserted against the pattern:
  # `Edit` occurs inside `NotebookEdit`, so the old per-tool containment check
  # passed on exactly this file.
  run gate_agrees "$(fixture_rules 'Write/NotebookEdit')" \
    "$ROOT/dnbg-workflow/hooks/check-worktree.sh" \
    "$ROOT/dnbg-workflow/hooks/hooks.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"always-on-rules.md disagree"* ]]
}

@test "a rules file naming a tool that is gated nowhere is caught" {
  # The reverse direction, which the one-directional check missed entirely: the
  # rules tell the agent Read is gated, the case and the matcher never gate it,
  # and the agent believes a protection it does not have.
  run gate_agrees "$(fixture_rules 'Edit/Write/NotebookEdit/Read')" \
    "$ROOT/dnbg-workflow/hooks/check-worktree.sh" \
    "$ROOT/dnbg-workflow/hooks/hooks.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"always-on-rules.md disagree"* ]]
}

# The "is HEAD approved?" question has exactly one correct source: an APPROVED
# review's commit oid compared to headRefOid. It was answered from
# `dismiss_stale_reviews` instead, in two skills independently, and that field is
# meaningless on a repo with `required_approving_review_count: 0` — which both
# repos these skills run against are. The wrong answer merged two PRs over
# unreviewed diffs. Prose alone did not hold the line, so this pins it.
@test "no skill reaches for branch protection to decide whether an approval counts" {
  # The endpoint itself. Any reintroduction is a regression regardless of intent:
  # it needs admin (403/404 on write-only access) and answers the wrong question.
  # Both skills may still *name* the setting to explain why not to read it, so
  # match the call, not the words.
  if grep -rn 'branches/[^ ]*/protection' "$ROOT/dnbg-workflow/skills"; then
    echo "a skill calls the admin-gated protection endpoint — use the commit-oid comparison instead"
    false
  fi

  # And the comparison is present in both skills, so removing it can't pass by
  # simply deleting the rule along with the endpoint.
  #
  # CHANGES_REQUESTED is pinned alongside APPROVED because the first cut of this
  # check took the last *approval* rather than the last *verdict*, so an approval
  # reversed at the same SHA still read as approved. The verdict set is the fix,
  # and it is the part a later simplification would quietly drop.
  for skill in reviewer git-workflow; do
    f="$ROOT/dnbg-workflow/skills/$skill/SKILL.md"
    grep -q 'headRefOid' "$f" || { echo "$skill/SKILL.md never mentions headRefOid"; false; }
    grep -q 'state=="APPROVED"' "$f" || { echo "$skill/SKILL.md has no APPROVED commit-oid check"; false; }
    grep -q 'state=="CHANGES_REQUESTED"' "$f" || {
      echo "$skill/SKILL.md checks the last approval, not the last verdict"; false; }
  done
}

# The manifest and lib.sh both state a default for each mechanical knob, and they
# are read by different audiences at different times: the manifest's is what the
# configuration dialog pre-fills, lib.sh's is what an unconfigured session
# actually uses. Two statements of one value is a drift risk taken deliberately —
# the manifest cannot supply the running default (an option nobody configured
# exports nothing to a hook), and dropping it from the manifest would leave the
# dialog offering an empty box for a knob that has a documented default. So they
# are pinned together instead.
@test "the manifest's declared defaults match the ones lib.sh falls back to" {
  local manifest="$ROOT/dnbg-workflow/.claude-plugin/plugin.json"
  # shellcheck source=../dnbg-workflow/hooks/lib.sh
  . "$ROOT/dnbg-workflow/hooks/lib.sh"

  local from_manifest
  from_manifest=$(jq -r '.userConfig.worktree_path.default' "$manifest")
  [ "$from_manifest" = "$DEFAULT_WORKTREE_PATH" ] || {
    echo "worktree_path default disagrees: manifest '$from_manifest', lib.sh '$DEFAULT_WORKTREE_PATH'"
    false
  }

  from_manifest=$(jq -r '.userConfig.claim_label.default' "$manifest")
  [ "$from_manifest" = "$DEFAULT_CLAIM_LABEL" ] || {
    echo "claim_label default disagrees: manifest '$from_manifest', lib.sh '$DEFAULT_CLAIM_LABEL'"
    false
  }
}

# The exclusion decision in reverse. "Configurable opinions with opinionated
# defaults" draws its line at mechanical-vs-behavioral, and the behavioral side —
# drafts always, the send-to-review picker and its fixed option order, the
# `[<branch-name>]` sibling title tag, "only a human merges" — is meant to have no
# key at all. Nothing else notices a fourth key appearing, so the surface is
# pinned by equality: a new knob is a decision to make deliberately, and this is
# the test that makes someone make it.
@test "the plugin exposes exactly the three intended configuration keys" {
  local keys
  keys=$(jq -r '.userConfig | keys_unsorted[]' "$ROOT/dnbg-workflow/.claude-plugin/plugin.json" | sort | tr '\n' ' ')
  [ "$keys" = "claim_label owners worktree_path " ] || {
    echo "userConfig keys are: $keys"
    echo "adding one means deciding it is mechanical rather than behavioral — see the README"
    false
  }
}

# Two conventions that a suite opts into by `load`ing a file, and whose absence is
# invisible from inside the suite that forgot: a watch spawned without `trace-dir`
# files its trace in the DEVELOPER'S real directory, and one spawned without `reap`
# is stopped by nothing if an assertion fails before its kill. Both failures are
# silent and land outside the run, which is exactly the shape tests/reap.bash argues
# cannot be left to convention — "the next spawn in the suite without it inherits the
# belief and not the protection".
@test "every suite that spawns a watch loads the reaper and contains its traces" {
  local f missing=0
  # The watcher scripts and the library are the only things that start a watch, so
  # naming one is what makes a suite a watch-spawning suite.
  for f in $(grep -rl 'watch-pr\.sh\|watch-merge\.sh\|lib-poll\.sh' "$ROOT"/tests/*.bats); do
    # ⚠️ SKIP SELF. This file has to name the watcher scripts to select on them, so the
    # selection is one prose mention away from including this file — which spawns no
    # watch and loads neither helper, so it would fail with "coupling.bats spawns a
    # watch but never loads reap": true of the text, useless as a diagnosis. Today the
    # only mention is the pattern above, which happens not to match itself; that is a
    # coincidence of spelling, not a property worth relying on.
    if [ "$(basename "$f")" = "$(basename "$BATS_TEST_FILENAME")" ]; then continue; fi
    grep -q '^load reap$' "$f" || {
      echo "$(basename "$f") spawns a watch but never loads reap"; missing=1; }
    grep -q '^load trace-dir$' "$f" || {
      echo "$(basename "$f") spawns a watch but never loads trace-dir"; missing=1; }
    # `load`ing it is not the same as calling it, and only the call sets TMPDIR.
    grep -q 'contain_traces' "$f" || {
      echo "$(basename "$f") loads trace-dir but never calls contain_traces"; missing=1; }
  done
  [ "$missing" -eq 0 ]
}
