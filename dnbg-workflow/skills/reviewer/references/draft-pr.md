# Reviewer: a draft PR you were asked to review

Part of the `reviewer` skill. Read this when a PR the operator or your prompt
named reads `isDraft` true, before reviewing it. A draft that issue mode
discovers is held without asking (`references/issue-mode.md`), so it never
comes here.

**Naming a draft is not evidence the operator noticed it was one.** Say it's a
draft, then call `AskUserQuestion` (the tool auto-appends "Other"):

1. **"Wait until it's ready (Recommended)"** — "Hold the review; watch the PR and
   review when it leaves draft."
2. **"Review it now"** — "Review the draft as asked and post the verdict."

Waiting is recommended because draft is the author's signal that the work is not
yet endorsed for review, and a verdict on a draft spends the attention that
signal is asking you to withhold — the same reason a *discovered* draft is held
back without asking at all.

On 1, post nothing now: arm the watch with `--was-draft` (`SKILL.md`'s "Watch the PR", which gives the first-arm rule)
and review when it reports `READY`. On 2, carry on with `SKILL.md`'s flow. Without
`AskUserQuestion`, a dispatcher's "wait until it's ready" or "review it now" is
the answer; with neither, ask on the PR per `<skill-dir>/../issue-workflow/references/delegated.md`.

**Say what waiting costs when you take option 1**, in the same breath, even
when a pre-answered wait takes it with no picker shown: the watch lives in this
session, so a PR marked ready after the session ends gets no review until
someone asks again. That is the operator's to weigh — option 2 is what buys a
verdict in hand right now.

Skip the picker when they have already answered — "review it even though it's a
draft", "review it once it's ready" — and don't replace it with a prose question.
