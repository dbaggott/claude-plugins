# Git workflow: whether HEAD is approved

Part of the `git-workflow` skill. Read this before telling the operator a PR is
ready to merge, and before merging one yourself if you ever have cause to.
`SKILL.md`'s "Know the repo's merge settings" carries the repo's settings, and
`<skill-dir>` is that skill's Base directory.

**Don't read branch protection to find out whether an approval still counts.** `dismiss_stale_reviews` needs admin, so on a repo you only have write on it answers 403 or 404 and tells you nothing — and where it does answer, it still doesn't say whether HEAD is approved. Ask that question directly:

```bash
"<skill-dir>/../../scripts/pr-verdict.sh" <owner>/<repo> <num>
```

HEAD is approved **iff** the result line reads `verdict=APPROVED at_head=1 reviewed_after_head=1` — necessary always, and sufficient only where `review_decision` prints empty, which is where no approval is required.

**Where `review_decision` carries a value, it must read `APPROVED` too.** It says approvals are *required* here, and it models what the comparison cannot: supersession, and more than one required reviewer. Neither field subsumes the other — a repo that requires approvals without dismissing stale ones keeps `review_decision=APPROVED` across a push, which is the state `reviewed_after_head` exists to catch.

Anything less is an approval of a diff nobody is merging — `APPROVED at_head=1` alone included, which a force-push produces over a tree nobody read. Use this wherever the answer matters: before telling the operator a PR is ready to merge, and before merging one yourself if you ever have cause to.

These returns need a decision rather than a retry. **`reviewed_after_head=unknown`** is not a `1` and no verdict clears it — surface it and let the operator decide. **`result=ERROR`** means the check could not see; it is not a verdict of "not approved". Any other shortfall resolves itself: `reviewer` re-verdicts unprompted on a HEAD move, so the fresh verdict arrives without prompting.

**Don't hand-roll the query** — `tests/pr-verdict.bats` pins each case.
