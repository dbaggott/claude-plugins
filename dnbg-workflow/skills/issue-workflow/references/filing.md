# Issue workflow: filing an issue

Part of the `issue-workflow` skill. Read this when the body is written per
`references/creating.md` and labeled per `references/labeling.md`; `SKILL.md`
carries the host check and "Writing as the author".

## File it

File it as the author (`SKILL.md`, "Writing as the author"), with the body
drafted in your draft directory (`git-workflow`'s "Draft files"), and
`<skill-dir>` this skill's Base directory:

```bash
"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- \
  gh issue create --repo <owner>/<repo> --title "<title>" --body-file <file> \
  --label <label> [--label <label>…]
```

An update to an existing issue is the body edit in "Writing as the author".

## Offer the spec review

Once an issue filed on its own is created, ask with `AskUserQuestion`:
"Spec-review <URL> now?", `<URL>` being the issue's.

1. **"Spec-review it now (Recommended)"**: "A reviewer subagent reviews the
   issue from GitHub, and this session answers its rounds as the author."
2. **"Not now"**: "Nothing more happens here. Paste `review <URL> as a spec`
   into a new session when you want the review."

On "Spec-review it now", go straight to `references/spec-review-rounds.md`,
"Spawn the reviewer", without its "Who runs the spec review?" picker, and answer
each round per its "Answering". On "Not now", end with the prompt
`review <URL> as a spec` and nothing else.

The offer is not made for a child filed under `references/decomposing.md`,
whose set goes to review at its step 6; for a tracking issue, which "Is this one
issue or a project?" in `references/creating.md` already hands over; for an
issue filed by a flow that offers the batch form below, which would otherwise
ask once per issue and again for the batch; or for a gap reported upstream,
below.

Without `AskUserQuestion`, take "Not now": end with the prompt and say in the
report that the review was not run. This is the default, not a question to post
per `references/delegated.md`.

### Offer the spec review for a batch

A flow that files several issues in one pass asks once for all of them, in place
of the question above. Its input is the list of issue URLs the flow decided to
offer. The prompt is `Review <URL>, <URL> as a set.`, one per repo the issues
were filed in, naming that repo's issues. Ask with the same two options.

On "Spec-review it now", dispatch per `references/spec-review-rounds.md`, "Spawn
the reviewer", once per prompt, with that prompt in place of its
`Review <URL> as a spec.`, and answer each round per its "Answering". On "Not
now", or without `AskUserQuestion`, end with the prompts to paste, in the report
when you have one, and say there that the review was not run.

## Reporting a gap upstream

An issue filed against someone else's project — reporting that tooling you
installed doesn't fit your case — is governed by the always-on rule "When
shipped tooling doesn't fit, tell the user", not by the operator's own
conventions. Two constraints that don't apply to an issue in your own repo:
it is published under the user's identity to a project they don't control, so
it is filed with their own `gh issue create`, not as the author role, and only if they ask for it and only after they have approved the exact
text; and the body is written from the **generic** case, so the session that
exposed the gap contributes the shape of the problem and none of its content.
Everything `references/creating.md` says about being self-documenting still applies to what remains.
