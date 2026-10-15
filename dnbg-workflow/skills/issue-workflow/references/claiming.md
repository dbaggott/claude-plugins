# Issue workflow: claiming one

Part of the `issue-workflow` skill. Read this first when picking up an issue,
before touching any file or opening a worktree; `references/resolving.md`
carries the work once the claim is yours. `SKILL.md` carries the host check
and the reference conventions.

## Claim it first — and check it isn't already claimed

An issue being worked must look in-progress from the outside, or the next session (or agent, or human) picks it up in parallel. Both halves apply at pickup time, before any implementation:

**1. Check for an existing claim.** Two calls, because the human signal and the PR signal come from different places:

```bash
# Assignee, labels, and whose claim it is.
"<skill-dir>/../../scripts/claim-issue.sh" <owner>/<repo> <n>

# Every PR that might already be resolving it — closing references, timeline
# cross-references, and text search, unioned and deduped.
"<skill-dir>/../../scripts/pr-sources.sh" <owner>/<repo> <n>
```

`<skill-dir>` is this skill's announced Base directory. The path reaches out of it because the script is shared with `git-workflow` and `reviewer`, which ask the same question from the other side; `CLAUDE_PLUGIN_ROOT` is exported to *hook* processes rather than to yours, so a skill can only address a sibling relative to its own base — and skill directories are always `<plugin>/skills/<name>/`, which makes `../../scripts/` deterministic.

**The PR check is not belt-and-braces, and it must not be narrowed to closing references.** Those list only PRs carrying a closing keyword, and `git-workflow`'s "Multi-repo changes" has **exactly one** sibling close the issue while the rest merely reference it. Check the keyword source alone and an in-flight multi-repo change reads as unclaimed the moment its closer merges — so a second session starts work already half-shipped. `reviewer`'s issue-scoped wait asks the same question and goes through the same union, so neither side maintains a copy of it.

⚠️ **A `count=0` with a failed source is not "unclaimed".** `pr-sources.sh` answers with whatever survived and names any source that didn't, so read those fields before concluding nothing is in flight — starting work over someone else's in-flight PR is exactly what this check exists to prevent. Treat `result=ERROR reason=all-sources` the same way: it means the check could not see.

The issue is already in progress if `claim-issue.sh` reports anything but `UNCLAIMED` (an assignee is set, or **any** `assigned:*` label is present), or `pr-sources.sh` lists a PR that is still open (its URLs carry no PR state — check with `gh pr view <url> --json state`, and note a URL may be in a different repo than `<repo>`, which is why they are URLs rather than numbers). If so, don't start — surface what you found (which signal, which PR, how old the claim comment is, which is the script's `at=`) and ask the operator (without `AskUserQuestion`: `references/delegated.md`). An open issue with an `assigned:*` label but **no** open linked PR and an old claim comment is the stale-claim signature — the claiming session probably died without finishing. Say so when asking, but proceeding past someone's claim is the operator's call, never yours.

The `assigned:*` namespace is deliberately open: whatever else works these repos — another agent, a bot, a teammate's tooling — claims with its own label in that namespace, and the check above matches the prefix rather than an enumerated list, so a new claimant needs no change here.

One case needs a second look: a claim of `@me` + `assigned:agent-session` — or a legacy `assigned:claude-code`, which claims made before the rename still carry, since claims are never cleaned up — may be this very session's earlier mark, or a sibling session run by the same operator. The assignee can't tell them apart, since every session runs under the operator's account. The **session id in the claim comment** does, and `claim-issue.sh` compares it: `result=OWN`, `FOREIGN` or `UNCLAIMED`, with the claim's id (`claim=none` when it carries none) and its comment's time.

It tests the **latest** claim comment, not any of them. An issue can carry more than one claim (a sibling claimed, the operator waved you past it, and now you are back), and matching against the whole set means finding your own older id and proceeding straight past a sibling who is working the issue right now. The most recent claim is the one that is live.

- **`OWN`: the id matches `${CLAUDE_CODE_SESSION_ID:0:8}`** — this session's own mark, and still the standing one. Proceed; note it in one line. A resumed session keeps its id, so re-reading your own claim after `claude --resume` matches rather than looking like a stranger's.
- **`FOREIGN` with an id** — a sibling session, which is a real claim by another worker. Stop and ask, exactly as for any other claimant (without `AskUserQuestion`: `references/delegated.md`).
- **`FOREIGN claim=none`, held only by you (`assignees=` names no one but your own login, and `labels=` only your claim label or `assigned:claude-code`)** — the claim predates this scheme, came from a harness that exports no session id, or the label was applied by hand with no claim comment behind it. With `AskUserQuestion`, note the claim in one line and proceed; without it, stop and ask per `references/delegated.md`.
- **`FOREIGN claim=none` with any other holder** — a teammate assigned by hand, or another tool's `assigned:*` label. A real claim: stop and ask, as for a sibling.

One quirk worth knowing rather than guarding against: a delegated session surfaces an existing claim *as a comment*, so a claim quoted verbatim at line-start can itself become the latest claim line. The id inside a quotation is the sibling's, not yours, so the comparison still lands on stop-and-ask — the benign direction.

The test is deliberately one-directional — only an exact id match licenses proceeding — so every id it can't positively account for lands on stop-and-ask, the safe side. That is what lets a delegated session, which has no one to ask, proceed past its own claim.

The same check guards the dispatch direction: before routing an issue to anyone else — assigning a person, applying another agent's `assigned:*` label — run it and surface any existing claim before applying the new one (without `AskUserQuestion`: `references/delegated.md`).

**2. Claim it.** Three marks, each serving a different reader:

```bash
"<skill-dir>/../../scripts/claim-issue.sh" <owner>/<repo> <n> --claim \
  [--label=<label>] [--stamp=<version>]
```

It creates the label when the repo lacks it, assigns the operator, and posts `Claimed by an agent session (<id>).`, where `<id>` is `${CLAUDE_CODE_SESSION_ID:0:8}`. `result=OK` carries the comment's URL; `result=ERROR reason=claim-write` means a mark may be missing, so check the issue before proceeding.

- The **assignee** makes the claim visible in issue lists and on the issue page.
- The **label** disambiguates what the assignee can't: sessions run under the operator's account, so assignee-alone could mean "the operator will get to this someday". `assigned:agent-session` means an agent session took it. The name stays agent-agnostic on purpose — it matches what the mark actually communicates, and keeps the mark this plugin applies inside the open `assigned:*` namespace described above rather than carving out a vendor-specific corner of it. Creating it on demand makes the claim work first-try in any repo.
- The **stamp**, `--stamp=<version>`, goes on only **if a `## dnbg-workflow <version>` note appeared at session start**, with the version it names. It lands on its own line under the claim, renders invisibly, and records which version of these prompts made the claim. With no note, leave it off — take the version from nowhere else, since nothing downstream can tell a guess from a reading.
- The **comment** timestamps the claim — GitHub's own comment timestamp, no date in the body needed — and names the claiming session. The timestamp is what makes staleness detectable; the id is what makes the own-claim test above mechanical instead of a judgement call. Where no session id is exported the comment says `(id unavailable)` rather than posting an empty pair of parentheses that reads like a match failure.

**`assigned:agent-session` is the default, not a constant.** The label name is configurable, so if a `dnbg-workflow` note at session start names a different one, that note wins and `--label` passes *that* label. With no such note, the literal above is what this session uses. What does **not** change either way is the check for someone else's claim: it matches the whole `assigned:*` prefix, never a single name, so it keeps seeing claims made under any label in the namespace — including the one this session would apply, the one a differently-configured session applies, and the legacy `assigned:claude-code`.

Claims are never cleaned up. Once a linked draft PR exists it supersedes the claim as the in-progress signal, and when the issue closes, closed is closed regardless of labels. A lingering `assigned:*` label on an open issue is informative, not litter — it is exactly what makes the stale-claim signature above detectable.
