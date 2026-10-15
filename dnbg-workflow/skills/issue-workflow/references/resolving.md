# Issue workflow: picking one up

Part of the `issue-workflow` skill. Read this once the issue is claimed
(`references/claiming.md`), before writing any code; `SKILL.md` carries the
host check and the reference conventions, and `references/creating.md` covers
writing an issue body.

## Picking up an issue

When resolving an issue, the body is the contract — once the freshness probe below passes, trust the creator's labeling and don't re-research what's already inline. Trusting the inline research is not the same as accepting the issue's conclusions: the body still gets a critical review (below) before any code, the way code gets one before it merges.

### Working the issue

- **Read the issue body first.** It often contains enough context inline; links are usually supplementary, not load-bearing.
- **Run a cheap freshness probe before implementing.** Bodies rot: work partially ships, referenced mechanisms get superseded. Mechanically check the body's anchors — do the named files/functions exist in the current tree; are referenced PRs in the state the body implies (`gh pr view --json state`)? This is existence/state checking, not re-research — don't read content beyond what the probe needs. If the body contradicts the tree, surface the contradiction instead of proceeding (without `AskUserQuestion`: `references/delegated.md`): the issue may be half-shipped, and faithfully implementing it duplicates landed work.
- **Follow a link only if BOTH are true:**
  1. The current context doesn't answer a specific question you need to proceed (e.g. "what schema does the new column have?", not "what's the general background?").
  2. The link is in "Required reading", or is explicitly called out as holding the answer.
- **Hard recursion cap at depth 1.** If a followed link contains another link, stop. If a second hop seems genuinely necessary, ask the operator the specific question instead (without `AskUserQuestion`: `references/delegated.md`) — a human can answer it or point at the one piece of context that matters, cheaper than transitively reading three more linked PRs.
- **Prefer one targeted fetch over many.** Need one file from a linked PR? Fetch it directly (`gh api /repos/.../contents/<path>`) rather than reading the whole PR.

Anti-patterns:

- Reading every PR in a "Related (optional)" section.
- Reading a linked PR's full diff when only its description is relevant.
- Following links transitively (issue → PR → design doc → discussion) when the original issue already has enough context.

If unsure whether a link is critical, lean toward NOT following — ask the operator if the gap actually blocks progress (without `AskUserQuestion`: `references/delegated.md`).

### Review the issue critically before implementing it

An issue is written by a fallible author, the same as code — and it earns the same scrutiny: a review pass *before* any code is written, not deference. The freshness probe above asks "is the body still true to the tree?"; this asks the prior question, "was the body ever right?" The two are independent — an issue can be perfectly current and still misdiagnosed.

This pass is mandatory and applies to **every** issue, including a fully-researched one with a verified "Proposed approach" — a confident, well-anchored body can still be confidently wrong, and a clean freshness probe is no substitute for it. It is not a rubber stamp: "passes review" is a conclusion you reached by actually probing the body, not the default you fall to when nothing jumps out. Probe for:

- **Misidentified problem** — the reported symptom is real but the stated cause is wrong.
- **Symptom, not root cause** — the proposed fix papers over a downstream effect; the real defect is upstream and will resurface.
- **Wrong approach** — the problem is real and correctly diagnosed, but the proposed direction is costlier, less safe, or less aligned with the code than an alternative.
- **False premise** — the issue assumes a behavior, constraint, or code structure that doesn't actually hold. Verify the load-bearing *assumptions* against the tree, not just the anchors: that anchors exist is the freshness probe's job; whether the claim *about* them holds is this one's.

The output is a position: the issue is sound and you'll implement it, or it has a problem you can name. When you find a problem, surface it to the operator — don't silently re-route (the operator may know something the body doesn't, and the divergence is itself a design decision; see below) and don't faithfully implement what you believe is wrong. Without `AskUserQuestion`, raise it per `references/delegated.md`.

### Match your handling to how grounded the issue is

Issues arrive at two depths, and what the resolver owes differs by depth:

- **Grounded** — the research is done and the approach is articulated against real code (a verified "Proposed approach"). Once the critical review above passes, implement that approach; don't treat a settled direction as one option among many or redesign it for taste.
- **Under-researched** — the issue names a real problem or goal, perhaps with implementation hints, but no code-grounded proposal. Here *you* are doing the design the creator didn't: investigating the code, weighing options, and forming the approach. That approach is a new decision, not a restatement of the issue.

**When you do the design, get buy-in before implementing it.** Make the operator aware of the situation — which depth the issue is, what the critical review found, and the approach you propose — and get approval before writing code. The same gate fires when the critical review re-routes a grounded issue: diverging from the stated direction is a design decision the creator never made, so it needs sign-off. Frame the ask as a recommendation with the alternatives and your reasoning, not an open question. Without `AskUserQuestion`, that ask, with any critical-review concern, is the question in `references/delegated.md`: post it and stop before writing code, as the already-claimed and failed-freshness-probe cases do.

A grounded issue that passes the critical review cleanly needs no separate approval step — the creator already made the design decision and the review is the check on it. The approval gate is for design *you* introduce, not a checkpoint on every pickup. But "no separate approval" is not license to rush to "grounded, proceed" by skimping the review — the gate is cheap because the review was real, not because it was skipped.

### Run the criteria met by a run before send-to-review

A criterion met by a run (an eval, a live exercise) is run before the PR leaves draft, and recorded on it: the output, the commit it ran on, and the invalidating paths the criterion names (`references/creating.md`). A later commit outside those paths leaves the run standing; one inside them means running it again. When the run needs the operator, such as a merge in a test repository or a session only they can start, ask for that part as soon as the branch can be run, in one message, rather than at send-to-review. A run you cannot make yourself, such as one only a main session can make when you are a subagent, is a question to whoever dispatched you, not a criterion to skip.

### Surface design changes that emerge mid-implementation

The buy-in gates above fire *before* code — at pickup, on an under-researched issue, or when the critical review re-routes a grounded one. But design decisions also surface *during* implementation: you start building the agreed approach, then hit a wall, find a better path, or discover a contract has to change, and you course-correct. That mid-flight change had no gate — the operator signed off on the issue's design (or the one agreed at pickup), not this one. Left unsurfaced, it's discovered at review or manual-test time, after the change and any rework are already paid for and after review ran against a design no one approved — the latency this rule exists to remove.

A **substantive** design change is one that departs from the issue's described approach, alters an external contract or interface, or otherwise changes what a reviewer or manual tester would evaluate. Routine implementation choices are not this; don't announce every decision. The litmus: *would the operator be surprised to learn this at review time?*

**Surface a substantive change clearly in chat before you move the PR out of draft** — state what changed from the agreed/issue design and why. The draft→ready transition (the `git-workflow` send-to-review picker) is the gate: it's the moment the operator's attention, the reviewer's, and manual testing all turn to the work, so the notification must come *before* that ask, not be folded silently into the send-to-review step. Recording it in the PR body too (per `git-workflow`'s "surface gaps" rule) is necessary but not sufficient — the PR body is read at review time, which is exactly the latency being removed; the chat notification before send-to-review is what's additional. Without `AskUserQuestion`, post the change and its rationale as a comment on the issue before the PR leaves draft; when send-to-review is a delegated question (`references/delegated.md`), they go in that question.
