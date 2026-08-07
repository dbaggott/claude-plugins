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
