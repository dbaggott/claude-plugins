# Issue workflow: picking one up

Part of the `issue-workflow` skill. Read this when resolving an issue someone
filed; `SKILL.md` carries the host check and the reference conventions, and
`references/creating.md` covers writing an issue body.

## Picking up an issue

When resolving an issue, the body is the contract — once the freshness probe below passes, trust the creator's labeling and don't re-research what's already inline. Trusting the inline research is not the same as accepting the issue's conclusions: the body still gets a critical review (below) before any code, the way code gets one before it merges.

### Claim it first — and check it isn't already claimed

An issue being worked must look in-progress from the outside, or the next session (or agent, or human) picks it up in parallel. Both halves apply at pickup time, before any implementation:

**1. Check for an existing claim.** Two calls, because the human signal and the PR signal come from different places:

```bash
# Assignee and labels.
gh issue view <n> --repo <repo> --json assignees,labels

# Every PR that might already be resolving it — closing references, timeline
# cross-references, and text search, unioned and deduped.
"<skill-dir>/../../scripts/pr-sources.sh" <owner>/<repo> <n>
```

`<skill-dir>` is this skill's announced Base directory. The path reaches out of it because the script is shared with `git-workflow` and `reviewer`, which ask the same question from the other side; `CLAUDE_PLUGIN_ROOT` is exported to *hook* processes rather than to yours, so a skill can only address a sibling relative to its own base — and skill directories are always `<plugin>/skills/<name>/`, which makes `../../scripts/` deterministic.

**The PR check is not belt-and-braces, and it must not be narrowed to closing references.** Those list only PRs carrying a closing keyword, and `git-workflow`'s "Multi-repo changes" has **exactly one** sibling close the issue while the rest merely reference it. Check the keyword source alone and an in-flight multi-repo change reads as unclaimed the moment its closer merges — so a second session starts work already half-shipped. `reviewer`'s issue-scoped wait asks the same question and goes through the same union, so neither side maintains a copy of it.

⚠️ **A `count=0` with a failed source is not "unclaimed".** `pr-sources.sh` answers with whatever survived and names any source that didn't, so read those fields before concluding nothing is in flight — starting work over someone else's in-flight PR is exactly what this check exists to prevent. Treat `result=ERROR reason=all-sources` the same way: it means the check could not see.

The issue is already in progress if any of: an assignee is set, **any** `assigned:*` label is present, or `pr-sources.sh` lists a PR that is still open (its URLs carry no PR state — check with `gh pr view <url> --json state`, and note a URL may be in a different repo than `<repo>`, which is why they are URLs rather than numbers). If so, don't start — surface what you found (which signal, which PR, how old the claim comment is — its timestamp comes from a follow-up `gh issue view <n> --json comments`, needed only on a hit) and ask the operator; in an unattended run, ask via a comment on the issue and stop. An open issue with an `assigned:*` label but **no** open linked PR and an old claim comment is the stale-claim signature — the claiming session probably died without finishing. Say so when asking, but proceeding past someone's claim is the operator's call, never yours.

The `assigned:*` namespace is deliberately open: whatever else works these repos — another agent, a bot, a teammate's tooling — claims with its own label in that namespace, and the check above matches the prefix rather than an enumerated list, so a new claimant needs no change here.

One case needs a second look: a claim of `@me` + `assigned:agent-session` — or a legacy `assigned:claude-code`, which claims made before the rename still carry, since claims are never cleaned up — may be this very session's earlier mark, or a sibling session run by the same operator. The assignee can't tell them apart, since every session runs under the operator's account. The **session id in the claim comment** does. Read the comment and compare:

```bash
gh issue view <n> --repo <repo> --json comments --jq '.comments[].body' \
  | grep -i '^Claimed by' | tail -1
```

Test the **latest** claim comment, not any of them — `tail -1` is load-bearing. An issue can carry more than one claim (a sibling claimed, the operator waved you past it, and now you are back), and matching against the whole set means finding your own older id and proceeding straight past a sibling who is working the issue right now. The most recent claim is the one that is live.

- **The id matches `${CLAUDE_CODE_SESSION_ID:0:8}`** — this session's own mark, and still the standing one. Proceed; note it in one line. A resumed session keeps its id, so re-reading your own claim after `claude --resume` matches rather than looking like a stranger's.
- **The id is different** — a sibling session, which is a real claim by another worker. Stop and ask, exactly as for any other claimant.
- **The comment carries no id, or the grep returns nothing at all** — the claim predates this scheme, came from a harness that exports no session id, or the label was applied by hand with no claim comment behind it. Fall back to the old judgement: interactively, note the claim in one line and proceed; in an unattended run, stop and ask via a comment.

One quirk worth knowing rather than guarding against: `:92` has an unattended session surface an existing claim *as a comment*, so a claim quoted verbatim at line-start can itself become the `tail -1` match. The id inside a quotation is the sibling's, not yours, so the comparison still lands on stop-and-ask — the benign direction.

The test is deliberately one-directional — only an exact id match licenses proceeding — so every id it can't positively account for lands on stop-and-ask, the safe side. That is what makes it usable unattended, where the old "mechanically indistinguishable" wording forced a stop in precisely the case that stopping costs most.

The same check guards the dispatch direction: before routing an issue to anyone else — assigning a person, applying another agent's `assigned:*` label — run it and surface any existing claim before applying the new one.

**2. Claim it.** Three marks, each serving a different reader:

```bash
SID="${CLAUDE_CODE_SESSION_ID:0:8}"  # short prefix — enough to tell sessions apart, short enough to read
gh label create "assigned:agent-session" --repo <repo> --color BFD4F2 --description "Claimed by an agent session" --force  # idempotent; no-op when the label exists
gh issue edit <n> --repo <repo> --add-assignee "@me" --add-label "assigned:agent-session"
gh issue comment <n> --repo <repo> --body "Claimed by an agent session (${SID:-id unavailable})."
```

- The **assignee** makes the claim visible in issue lists and on the issue page.
- The **label** disambiguates what the assignee can't: sessions run under the operator's account, so assignee-alone could mean "the operator will get to this someday". `assigned:agent-session` means an agent session took it. The name stays agent-agnostic on purpose — it matches what the mark actually communicates, and keeps the mark this plugin applies inside the open `assigned:*` namespace described above rather than carving out a vendor-specific corner of it. The unconditional `gh label create --force` makes the block work first-try in any repo.
- The **stamp** is the one addition to that command, and only **if a `## dnbg-workflow <version>` note appeared at session start**. Extend the `--body` with the version it names, on its own line so the `^Claimed by` grep above — which is line-anchored — cannot see it:

  ```
  Claimed by an agent session (${SID:-id unavailable}).
  <!-- dnbg-workflow <version> -->
  ```

  It renders invisibly, and it records which version of these prompts made the claim. With no note the command above is already correct as written — take the version from nowhere else, since nothing downstream can tell a guess from a reading.
- The **comment** timestamps the claim — GitHub's own comment timestamp, no date in the body needed — and names the claiming session. The timestamp is what makes staleness detectable; the id is what makes the own-claim test above mechanical instead of a judgement call. `${SID:-id unavailable}` keeps the comment honest where no session id is exported, rather than posting an empty pair of parentheses that reads like a match failure.

**`assigned:agent-session` is the default, not a constant.** The label name is configurable, so if a `dnbg-workflow` note at session start names a different one, that note wins and the three commands above apply *that* label. With no such note, the literal above is what this session uses. What does **not** change either way is the check for someone else's claim: it matches the whole `assigned:*` prefix, never a single name, so it keeps seeing claims made under any label in the namespace — including the one this session would apply, the one a differently-configured session applies, and the legacy `assigned:claude-code`.

Claims are never cleaned up. Once a linked draft PR exists it supersedes the claim as the in-progress signal, and when the issue closes, closed is closed regardless of labels. A lingering `assigned:*` label on an open issue is informative, not litter — it is exactly what makes the stale-claim signature above detectable.

### Working the issue

- **Read the issue body first.** It often contains enough context inline; links are usually supplementary, not load-bearing.
- **Run a cheap freshness probe before implementing.** Bodies rot: work partially ships, referenced mechanisms get superseded. Mechanically check the body's anchors — do the named files/functions exist in the current tree; are referenced PRs in the state the body implies (`gh pr view --json state`)? This is existence/state checking, not re-research — don't read content beyond what the probe needs. If the body contradicts the tree, surface the contradiction instead of proceeding: the issue may be half-shipped, and faithfully implementing it duplicates landed work.
- **Follow a link only if BOTH are true:**
  1. The current context doesn't answer a specific question you need to proceed (e.g. "what schema does the new column have?", not "what's the general background?").
  2. The link is in "Required reading", or is explicitly called out as holding the answer.
- **Hard recursion cap at depth 1.** If a followed link contains another link, stop. If a second hop seems genuinely necessary, ask the operator the specific question instead (in an unattended run, ask via a comment on the issue) — a human can answer it or point at the one piece of context that matters, cheaper than transitively reading three more linked PRs.
- **Prefer one targeted fetch over many.** Need one file from a linked PR? Fetch it directly (`gh api /repos/.../contents/<path>`) rather than reading the whole PR.

Anti-patterns:

- Reading every PR in a "Related (optional)" section.
- Reading a linked PR's full diff when only its description is relevant.
- Following links transitively (issue → PR → design doc → discussion) when the original issue already has enough context.

If unsure whether a link is critical, lean toward NOT following — ask the operator if the gap actually blocks progress.

### Review the issue critically before implementing it

An issue is written by a fallible author, the same as code — and it earns the same scrutiny: a review pass *before* any code is written, not deference. The freshness probe above asks "is the body still true to the tree?"; this asks the prior question, "was the body ever right?" The two are independent — an issue can be perfectly current and still misdiagnosed.

This pass is mandatory and applies to **every** issue, including a fully-researched one with a verified "Proposed approach" — a confident, well-anchored body can still be confidently wrong, and a clean freshness probe is no substitute for it. It is not a rubber stamp: "passes review" is a conclusion you reached by actually probing the body, not the default you fall to when nothing jumps out. Probe for:

- **Misidentified problem** — the reported symptom is real but the stated cause is wrong.
- **Symptom, not root cause** — the proposed fix papers over a downstream effect; the real defect is upstream and will resurface.
- **Wrong approach** — the problem is real and correctly diagnosed, but the proposed direction is costlier, less safe, or less aligned with the code than an alternative.
- **False premise** — the issue assumes a behavior, constraint, or code structure that doesn't actually hold. Verify the load-bearing *assumptions* against the tree, not just the anchors: that anchors exist is the freshness probe's job; whether the claim *about* them holds is this one's.

The output is a position: the issue is sound and you'll implement it, or it has a problem you can name. When you find a problem, surface it to the operator — don't silently re-route (the operator may know something the body doesn't, and the divergence is itself a design decision; see below) and don't faithfully implement what you believe is wrong. In an unattended run, raise the concern as a comment on the issue and stop.

### Match your handling to how grounded the issue is

Issues arrive at two depths, and what the resolver owes differs by depth:

- **Grounded** — the research is done and the approach is articulated against real code (a verified "Proposed approach"). Once the critical review above passes, implement that approach; don't treat a settled direction as one option among many or redesign it for taste.
- **Under-researched** — the issue names a real problem or goal, perhaps with implementation hints, but no code-grounded proposal. Here *you* are doing the design the creator didn't: investigating the code, weighing options, and forming the approach. That approach is a new decision, not a restatement of the issue.

**When you do the design, get buy-in before implementing it.** Make the operator aware of the situation — which depth the issue is, what the critical review found, and the approach you propose — and get approval before writing code. The same gate fires when the critical review re-routes a grounded issue: diverging from the stated direction is a design decision the creator never made, so it needs sign-off. Frame the ask as a recommendation with the alternatives and your reasoning, not an open question.

A grounded issue that passes the critical review cleanly needs no separate approval step — the creator already made the design decision and the review is the check on it. The approval gate is for design *you* introduce, not a checkpoint on every pickup. But "no separate approval" is not license to rush to "grounded, proceed" by skimping the review — the gate is cheap because the review was real, not because it was skipped.

In an unattended run there is no operator to approve: post the proposed approach (and any critical-review concern) as a comment on the issue and stop — the same stop the already-claimed and failed-freshness-probe cases trigger. Designing and implementing in one unattended shot is exactly the path that ships a confident wrong approach with no review gate.

### Surface design changes that emerge mid-implementation

The buy-in gates above fire *before* code — at pickup, on an under-researched issue, or when the critical review re-routes a grounded one. But design decisions also surface *during* implementation: you start building the agreed approach, then hit a wall, find a better path, or discover a contract has to change, and you course-correct. That mid-flight change had no gate — the operator signed off on the issue's design (or the one agreed at pickup), not this one. Left unsurfaced, it's discovered at review or manual-test time, after the change and any rework are already paid for and after review ran against a design no one approved — the latency this rule exists to remove.

A **substantive** design change is one that departs from the issue's described approach, alters an external contract or interface, or otherwise changes what a reviewer or manual tester would evaluate. Routine implementation choices are not this; don't announce every decision. The litmus: *would the operator be surprised to learn this at review time?*

**Surface a substantive change clearly in chat before you move the PR out of draft** — state what changed from the agreed/issue design and why. The draft→ready transition (the `git-workflow` send-to-review picker) is the gate: it's the moment the operator's attention, the reviewer's, and manual testing all turn to the work, so the notification must come *before* that ask, not be folded silently into the send-to-review step. Recording it in the PR body too (per `git-workflow`'s "surface gaps" rule) is necessary but not sufficient — the PR body is read at review time, which is exactly the latency being removed; the chat notification before send-to-review is what's additional. In an unattended run, post the change and rationale as a comment on the issue before marking the PR ready.
