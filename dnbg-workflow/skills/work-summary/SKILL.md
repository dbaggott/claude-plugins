---
name: work-summary
description: Summarize your GitHub work into an audience-shaped recap — either shipped work (PRs merged, plus issues you filed, over a window — the default) or in-progress work (your open/draft PRs and their status). Gather via `gh search`, read PR/issue descriptions (not code), then settle audience, format, and detail before writing. Load when asked to "summarize yesterday", recap what shipped/got merged over a window ("this week", "since Monday", "last 3 days", a date or range), summarize what you're working on / what's in flight / what's blocked, or draft a standup or Slack update from your PRs. Skip for summarizing a single named PR (just read it) and for summarizing code-level changes rather than work outcomes/status.
---

# Summarizing your work

This skill turns "summarize yesterday" or "what am I working on" into an accurate,
audience-shaped recap of your GitHub work. It is the **judgment layer**: which mode,
which window, whose work, how to read it honestly, and how to shape the same facts
for different readers. The `gh` mechanics are simple; the value is in not
over-claiming and in settling what shapes the output — audience, format, detail —
*before* writing.

The flow is always: **pick the mode → resolve scope/window → gather → read the
descriptions → settle audience/format/detail → write.** Don't write before settling
them — the same work becomes a different artifact for a Slack channel than for a
leadership email.

## 1. Pick the mode

Two modes, because completed and in-flight work need different gathering and a
different shape:

- **Shipped** (the default) — work *produced* over a time window: PRs you merged **and
  issues you filed**. Filing a well-scoped issue is real output — triage and planning —
  so the recap surfaces it, but as its own lighter category, never blurred into the
  merged work (filing scopes a problem; it doesn't ship a fix). Triggers: "summarize
  yesterday", "what shipped this week", a recap/standup of done work. A time window in
  the request points here.
- **In-progress** — work *currently open*: your draft and ready PRs and their status.
  Triggers: "what am I working on", "summarize my in-progress work", "what's in
  flight", "what's blocked", "where am I".

Infer the mode from phrasing; **default to shipped** when ambiguous. If the user
clearly wants the whole picture ("catch me up", "full status"), do **both** — run
each gather and present shipped first (what's done), then in-progress (what's open).

## 2. Resolve scope + window

**Owner scope** comes from this plugin's `owners` setting — `${user_config.owners}`.
`gh search`'s `--owner` takes a comma-separated list, so that value passes straight
through. If it's empty, ask which org or login to search rather than guessing; a
search with no owner filter spans all of GitHub and returns noise.

**Author scope** defaults to **your own** work. Resolve your login once
(`ME=$(gh api user --jq .login)`); `--author "$ME"` filters server-side to just your
PRs. If the user asks for the team's work, drop `--author` — but **bot-authored work
still counts as team output** (working agents and automation are part of what the
team shipped, not noise to strip). Don't filter by `is_bot`. The *only* thing to drop
is **trivial version-bump automation** — mechanical `auto: bump version … [skip ci]`
PRs that nobody recaps — and say you dropped them.

**Window** applies differently per mode:

- *Shipped* — a real date filter. Default **yesterday** (today − 1 from the session's
  `currentDate`). Convert any relative phrase to absolute dates yourself; "yesterday",
  "this week", "since Monday", "last 3 days", or an explicit date resolve to a single
  day or a `START..END` range.
  - **Make the default workweek-aware.** "Yesterday" on a Monday should mean "since the
    last working day" (the Fri→Sun range), not just Sunday — otherwise a Monday recap is
    empty though Friday shipped plenty. When today is Monday (or the day after a known
    stretch off), expand to the range back to the last working day and say which span you
    used ("covering Fri–Sun"). An explicit "yesterday the single day" or a named date wins
    over this expansion.
  - **"Yesterday" means the person's *working day*, not the UTC — or even the local —
    calendar day.** The workweek rule above decides *which* days the window spans; this
    decides *where each day begins and ends*. Two boundary bugs live here, and both need
    the working day pinned in real local time:
    - **Determine the timezone empirically — never infer it.** Run `date +%z` (numeric
      offset, e.g. `-0700`) and `date +%Z` (name); `readlink /etc/localtime` gives the
      zone. Don't guess it from the user's email domain, name, or locale — that once put
      a day boundary 7 hours off by labeling an `America/Los_Angeles` machine "Eastern".
      If the user may be working away from the machine's set zone (travel), ask;
      otherwise the machine's zone is the working zone.
    - **Bound the day at a pre-dawn cutoff, not midnight.** `gh search`'s `merged:` /
      `created:` qualifiers match in **UTC**, so a bare `--merged-at 2026-06-11` is the
      UTC calendar day — which clips the local evening into the next day (a 7-hour-west
      machine loses everything after ~5pm local) *and*, even re-anchored to local time,
      midnight would split a night owl's late session across two recaps. So define a
      working day as **[cutoff, next cutoff)** in local time, cutoff in the pre-dawn
      lull — **default 04:00 local** (captures night-owl work up to 4am as the prior
      day; an early start ≥4am is unaffected). `gh search` accepts a timezone-anchored
      ISO8601 range, so pass the working day directly:
      `--merged-at "2026-06-11T04:00:00-OFFSET..2026-06-12T04:00:00-OFFSET"`, where
      `-OFFSET` is this machine's `date +%z` (the examples below use `-07:00` —
      substitute your own). (gh's range is inclusive, so a merge at the exact cutoff
      second lands in both days — a rare edge not worth special-casing.)
    - **Tune the cutoff empirically when it matters** — a result lands within ~an hour
      of the boundary, or the person is a known odd-hours worker. Pull the trailing
      ~30–90 days of their activity timestamps (merged PRs + created issues/PRs),
      convert to local, histogram by hour, and set the cutoff to the **start of the
      quietest pre-dawn hour**, clamped to `[02:00, 06:00]`, falling back to 04:00 if
      the data is thin or the night is flat. This is what adapts to early-bird vs
      night-owl: the boundary lands in *their* personal trough, so no working session is
      split across two days' recaps. Default to the cheap 04:00 cutoff; reach for the
      histogram only on that signal, the same way the workweek rule defaults sane and
      widens only when it looks off.
- *In-progress* — usually **no** date filter: "what's open now" is independent of when
  it opened. Only apply a window if the user scopes it ("what have I been working on
  this week" → also filter by `--updated`).

## 3. Gather

**Shipped:**

```bash
# Working-day window from §2 — cutoff..next-cutoff in local time, offset from `date +%z`.
gh search prs --owner ${user_config.owners} --author "$ME" \
  --merged-at "2026-06-11T04:00:00-07:00..2026-06-12T04:00:00-07:00" \
  --json number,title,repository,url,closedAt --limit 100
# multi-day: widen the start to the first working day's cutoff —
#   --merged-at "2026-06-09T04:00:00-07:00..2026-06-12T04:00:00-07:00"
```

`merged-at` matches only merged PRs, so every result is real shipped work; `closedAt`
is the merge time (use it for ordering). There is no `mergedAt` JSON field on
`gh search prs` — ask for `closedAt`.

**Issues you filed (shipped mode):** the same window, by creation date — filing a
well-scoped issue is real work, so gather the issues you *opened* in it:

```bash
# Same working-day window as the PR gather above (§2).
gh search issues --owner ${user_config.owners} --author "$ME" \
  --created "2026-06-11T04:00:00-07:00..2026-06-12T04:00:00-07:00" \
  --json number,title,repository,url,state,createdAt --limit 100
# multi-day: widen the start to the first working day's cutoff, as above.
```

`gh search issues` excludes PRs by default — **don't** pass `--include-prs` here; the
PR gather above already owns them, and including them would double-count. `--created`
filters on the open date, so this captures what you filed in the window whether or not
it's since been closed; `state` tells you which are still open. Run it only for the
shipped mode — in-progress is about your open PRs, not issues you've filed.

The search returns `state` (open/closed) but not *why* an issue closed. For any filed
issue that **closed within the window**, check `stateReason` — it decides whether the
issue is real output or noise to drop (§6):

```bash
gh issue view <num> --repo <owner>/<repo> --json stateReason
# COMPLETED = resolved; NOT_PLANNED = won't-fix / duplicate / invalid
```

Only the closed-in-window issues need this (usually few); a still-open filed issue is
kept as-is.

**In-progress:**

```bash
gh search prs --owner ${user_config.owners} --author "$ME" --state open \
  --json number,title,repository,url,isDraft,createdAt,updatedAt --limit 100
```

`gh search prs` does **not** return review/merge/CI status — for an in-progress recap
that status *is* the substance, so fetch it per PR:

```bash
gh pr view <num> --repo <owner>/<repo> \
  --json title,body,isDraft,reviewDecision,mergeStateStatus,statusCheckRollup,updatedAt
```

`isDraft` (still drafting vs ready), `reviewDecision` (APPROVED / CHANGES_REQUESTED /
REVIEW_REQUIRED), and `mergeStateStatus` + `statusCheckRollup` (mergeable / blocked /
CI red) are what classify each open PR by stage in step 6.

**Bound the per-PR fetch** — it's one `gh pr view` per open PR, so the fan-out scales
with the open-PR count: a handful for your own work, but a **team-scope** query
(no `--author`) can be dozens. Two guards:

- The search already returns `isDraft`, so a **count or headline** (brief detail) can
  split ready-vs-draft with **no** per-PR call. Only fetch full status for the PRs
  you'll actually render review/CI/blocker detail for.
- For team scope, **cap** the per-PR fetch — default **~20, most-recently-`updated`
  first** (adjust for the ask) — and say you capped (per step 6's "what was dropped"
  rule), rather than fanning out over every open PR in the org. A concrete default
  keeps the dropped-set reproducible across invocations over the same snapshot.

## 4. Read the descriptions, not the code

Pull each PR's title + body and summarize from the **body** — this is what makes the
recap trustworthy:

```bash
gh pr view <num> --repo <owner>/<repo> --json title,body --jq '.title + "\n" + .body'
```

- A title routinely under- or over-sells; bodies carry the real impact and the
  `Resolves …` links that say what problem it closed. Note those references — "closed
  the duplicate-session issue" is stronger, truer framing than "changed some files".
- Do **not** read the diff/code. The PR description is the author's own statement of
  intent and impact; the recap reports *that*. Reading code is slower and invites
  claims the PR never made. If a body is empty, say the recap rests on the title alone
  for that PR rather than inferring from code.
- **Filed issues read the same way, lighter.** Summarize each from its *body* — the
  problem it scopes — not its title alone, same rule as a PR. But a filed issue is a
  smaller unit than a merged PR: at brief detail a one-line headline per issue (or just
  a count) is enough without reading each; read bodies for the issues you'll actually
  describe.

## 5. Ask what shapes the output — before writing

**Three independent axes** shape a recap; keep them separate (a *Slack* format can
carry a *peer* audience at *brief* detail, or any other mix — don't conflate format
with audience):

- **Audience** — who's reading. Sets vocabulary and jargon level, what counts as
  high-impact, and whether PR links belong. *Just me / Teammates / Manager or lead /
  Leadership.*
- **Format** — the artifact's shape. *Slack message / Bullet list / Prose paragraphs /
  Email or doc.*
- **Detail** — how much. *Brief* (one headline per item) / *Standard* (a sentence or
  two each) / *Comprehensive* (every PR's impact/status, with caveats).

Detail and audience interact but stay separate: **detail scales depth *within* the
audience's register, it doesn't change the register.** A *Comprehensive* recap for
leadership is more thorough on outcomes and risk but still jargon-free and link-free;
*Comprehensive* for a peer adds mechanics and PR-level detail. Detail sets how much;
audience sets the language and altitude.

**Infer any axis the request already pins down, and ask only the rest.** "Draft a
Slack standup for the team" already fixes format (Slack) and audience (teammates) —
don't re-ask those. A bare "summarize yesterday" fixes none — ask all three in **one**
`AskUserQuestion` call (one question per open axis). Recommend **Standard** detail by
default, and tag a recommended audience/format only when the phrasing hints one;
"Other" is always available.

Audience — not format — drives the impact ordering in step 6, which is exactly why the
two must stay separate.

## 6. Write the recap

Constant rules, both modes:

- **Don't over-promise.** Claim only what the source supports. **In-progress work is
  especially easy to overstate** — say "drafted / opened / awaiting review", never
  "shipped / done", for anything not merged. For shipped work, a defect fixed on one
  reproduction case is not a class-wide guarantee; hedge explicitly ("verified on the
  repro case, not across all inputs"). A confident-but-wrong recap is worse than a
  hedged one.
- **Reference PRs and issues by full URL** per the always-on rule —
  `https://github.com/<owner>/<repo>/pull/<n>`. Exception: the **leadership** audience,
  where bare references read as noise — omit them and offer to append a list if they
  want traceability.
- **Offer a quantitative line where it fits** — *N PRs across M repos, K issues
  closed, J issues filed* (shipped) or *N open: X ready, Y in review, Z drafting*
  (in-progress). *K issues closed* comes from the merged PRs' `Resolves …` links;
  *J issues filed* from the issue gather, after §6's exclusions (dropped `NOT_PLANNED`
  closes, and ones counted under a PR instead). They count different things, so don't
  merge the two numbers.
  Default-on for **manager/lead** and **leadership** audiences (and the bullet-list
  format), offered for the rest, off for **just-me** unless asked. A complement to the
  prose, never a substitute.
- **Say what you compressed or dropped** — PRs folded into one item, the trivial
  version-bump automation excluded, a cross-repo pair collapsed — in a line at the end,
  so the reader knows it's a shaped view, not the raw log.
- **Deliver the recap inside a fenced code block so it copies clean.** A recap is made
  to be lifted out of the terminal and pasted somewhere — Slack, a doc, an issue, an
  email — and the chat markdown renderer reflows prose and adds left-margin
  indentation, so a recap rendered inline copies out with stray leading spaces and
  broken wrapping. A fenced code block renders verbatim and copies clean; default to it
  for **every** format (Slack, bullets, prose, email/doc), not just Slack. **Skip it
  only when the user just wants to read the recap here** rather than paste it — that's
  the one case where rendering inline is right. The literal markup the block exposes
  (`*bold*`, `:emoji:` shortcodes, `#` headers) is the point: that's the raw form the
  paste target — Slack mrkdwn, a markdown doc — will interpret, so it's exactly what you
  want on the clipboard. Two notes worth passing to the user with a Slack recap:
  `:emoji:` shortcodes only render if they exist in the workspace, and older Slack
  composers read `*single asterisks*` as bold while the newer WYSIWYG one may need a
  plain-text paste (Cmd-Shift-V); Slack is trending toward standard markdown, so
  re-check this if the asterisks don't take.

Mode-specific shaping:

- **Shipped** — group by **theme** (area of work), not PR order, and **order themes by
  audience-relative impact**: leadership → user-visible outcomes and reliability/issue
  closes first, polish demoted/dropped; teammates → what unblocks or affects *their*
  work first; manager/lead → progress and risks first; just-me → completeness is fine
  but lead with the headline. When two themes are close, one that closed a tracked
  issue or fixed a user-hit failure outranks pure improvement. If unsure what the user
  ranks highest, lead with the reliability/issue-closing work and say so.
  - **Filed issues are their own group, after the merged themes** — a short "Filed /
    triaged" section, never folded into the shipped work above it. Say "filed" /
    "opened" / "scoped", never "fixed" / "shipped" / "done", for an issue that's only
    been opened — the same anti-over-claim discipline the in-progress mode uses, since
    a filed issue is a problem named, not an outcome delivered. A still-open filed
    issue belongs here as-is. An issue that **closed within the window** is handled by
    *why* it closed (its `stateReason`, per §3):
    - **`NOT_PLANNED`** (won't-fix / duplicate / invalid) — **drop it entirely.** You
      opened it and it was dismissed in the same period; that's not work produced.
      Leave it out of the recap and out of the *J* count.
    - **`COMPLETED` via one of your own merged PRs** — depends on whether that PR is
      *itself in the window*. If it is, the issue is already counted as that PR's
      shipped work: list it **once, under that PR's theme** (the issue it resolved),
      not again under Filed, and **exclude it from *J*** — it lives in *K issues
      closed*, not *J issues filed*. If the resolving PR merged **outside** the window,
      it has no theme in this recap to live under — so keep the issue under Filed /
      triaged and **count it in *J*** instead, or it falls out of both *J* and *K* and
      vanishes from the recap.
    - **`COMPLETED` by someone else** (their PR, or closed by hand) — keep it under
      Filed / triaged and note it's closed: you scoped it, someone else delivered.
    For the **leadership** audience, demote or drop filed issues unless one scopes a
    notable risk or decision — opened-but-unstarted work reads as noise at that
    altitude — and **drop *J* from the quantitative line too** when you've dropped the
    section (reporting a "filed" count while hiding the items reads as odd); keep *J*
    only for a filed issue that cleared the risk/decision bar and stayed in. For
    **manager/lead** and **teammates**, filed issues show planning and what's queued,
    so keep them and keep *J*.
- **In-progress** — group by **stage / status**, ordered by closeness-to-done (or by
  what needs the reader's action): *Ready to merge* (approved + green) → *Awaiting
  review* → *Changes requested* (what the reviewer wants) → *CI failing / blocked*
  (the specific block) → *Still drafting* (what's left). Each item: what it does + its
  next step or blocker. This is a status board, not an accomplishment list.

After delivering, offer the obvious reshape ("want this as standup bullets too?") —
the gathered facts re-shape for free, and users often want more than one form.

## Re-runs and refinement

The expensive steps are gather + read (steps 3–4). A new audience/detail on the
**same mode + window** reuses what you gathered — re-shape, don't re-fetch. Re-run the
`gh` calls only when the mode, window, or scope changes — **or**, for in-progress,
when meaningful time has passed, since open-PR status (review, CI, mergeability) is
live and goes stale.
