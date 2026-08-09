#!/usr/bin/env bats
#
# The tool list that check-worktree.sh gates lives in three places, and its own
# comment says a tool missing from any of them is editable in the main checkout
# without the gate firing. That is a silent, security-relevant failure with no
# other check on it — this is the check.

ROOT="${BATS_TEST_DIRNAME}/.."

@test "the gated tool list agrees across the case, the matcher, and the rules" {
  # From check-worktree.sh's `case` — the set the script itself acts on.
  from_case=$(sed -n 's/^  \(\([A-Za-z]*|\)*[A-Za-z]*\)) ;;$/\1/p' \
    "$ROOT/dnbg-workflow/hooks/check-worktree.sh" | tr '|' '\n' | sort -u)

  # From hooks.json — the set Claude Code actually invokes the hook for. A tool
  # here but not in the case is a wasted invocation; a tool in the case but not
  # here never reaches the script at all.
  from_matcher=$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("check-worktree")) | .matcher' \
    "$ROOT/dnbg-workflow/hooks/hooks.json" | tr '|' '\n' | sort -u)

  [ -n "$from_case" ]
  [ "$from_case" = "$from_matcher" ]

  # And the always-on rule, which is what the agent reads. Loose containment
  # rather than an exact parse: it is prose, and pinning its wording would fail
  # on every legitimate edit.
  rules="$ROOT/dnbg-workflow/always-on-rules.md"
  for tool in $from_case; do
    grep -q "$tool" "$rules" || {
      echo "tool '$tool' is gated but never named in always-on-rules.md"
      false
    }
  done
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
