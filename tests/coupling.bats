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
  for skill in reviewer git-workflow; do
    f="$ROOT/dnbg-workflow/skills/$skill/SKILL.md"
    grep -q 'headRefOid' "$f" || { echo "$skill/SKILL.md never mentions headRefOid"; false; }
    grep -q 'state=="APPROVED"' "$f" || { echo "$skill/SKILL.md has no APPROVED commit-oid check"; false; }
  done
}
