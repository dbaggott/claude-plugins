---
name: project-status
description: Say which stage of the project flow a GitHub issue or tracking issue is at, and the exact prompt to paste next. Load when asked "what's next on <issue URL>", "where is <issue URL>", "status of <project or tracking issue URL>", or "what do I do next with this issue". A lookup only — it claims nothing and writes nothing. Skip for picking the issue up, which is `issue-workflow`, and for judging whether its design is any good, which is `issue-reviewer`.
---

# Project status

A lookup: read where an issue stands on GitHub and name the next prompt. It
claims nothing, writes nothing, loads no other skill, and makes no judgment
about the issue's content. `<skill-dir>` is the **Base directory** announced
when this skill loads.

## 1. Read the stage

The issue must be named by full URL, since the host and repo come from it. Given
a bare number, ask for the URL. If the URL's host is not `github.com`, say this
lookup is GitHub-only, name the host, and stop.

```bash
"<skill-dir>/../../scripts/issue-stage.sh" <owner>/<repo> <n>
```

One line comes back: `result=OK kind=<kind> stage=<stage> next=<prompt-id>
evidence=<key=value ...>`. On `result=ERROR`, say what failed and stop:
`not-found` (no such issue, or the token cannot see it), `issue-query` (a GitHub
call failed, or a PR source did, so try again), `issue-query-shape` (GitHub's
answer did not parse), `set-overflow` (too many sub-issues or comments to read
whole), `bad-args` or `unsupported-forge`.

## 2. Report it

Print three things, in this order.

**The stage, in one sentence, with its evidence.** Translate the evidence keys:
`claim` (own, foreign, none), `children` and `open` counts, `verdict` (the
reviewer bot's latest spec verdict), `acceptance_row`, `round` (beside a
`READY` design review: `current`, made in design mode against the body as it
stands; `stale`, against an earlier body or naming none; `not-design`, a round
not marked `(design mode)`), `round_url` (that round's comment), `prs` (open PRs that close the issue), and for a child `parent` and
`parent_stage`.

**The prompt to paste next**, from `next`, with `<URL>` the issue's URL:

| `next` | Say |
| --- | --- |
| `review-spec` | `review <URL> as a spec` (for a plain issue, the "Not now" path of the spec-review picker its filing session was offered, `issue-workflow`'s `references/filing.md`), in a session with the reviewer bot set up (`reviewer-setup`); its findings are answered by the session that wrote the body, or, if that session is gone, by another started with `answer the spec review on <URL>` |
| `accept` | the design review is `READY` and waits on your acceptance: `answer the spec review on <URL>`, which ends on the acceptance question |
| `decompose` | `decompose <URL>` |
| `orchestrate` | `orchestrate <URL>` |
| `resolve` | `resolve <URL>` |
| `merge-closeout` | merge the closeout PR, the URL in `prs`; that is the operator's merge, not a prompt |
| `none` | nothing: it is closed |
| `unknown` | the stage turns on a spec verdict and no reviewer bot is configured; run `reviewer-setup`, or rerun the script with `--slug=<reviewer bot login>` |

For `stage=in-project`, the issue is a child: name the parent from `parent`, its
stage from `parent_stage`, and give the prompt above with the parent's URL,
since a project's children are moved on through their parent.

For `stage=orchestrating` or `stage=in-progress`, a session may be working it
now. Say the prompt is for when that session is gone; the skill it loads checks
the claim and asks before going past it.

**Whether to run it in a fresh session**: yes, for each prompt to paste
(`review-spec`, `accept`, `decompose`, `orchestrate`, `resolve`). Each starts a new stage,
and a fresh session reads that stage from GitHub rather than from this
conversation. The other rows are not prompts, so say nothing about a session.
