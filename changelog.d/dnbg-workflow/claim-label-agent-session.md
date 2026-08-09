`issue-workflow` now claims an issue with `assigned:agent-session` instead of
`assigned:claude-code`, and the claim comment names the claiming session.

The label rename makes the mark match what it actually communicates — an agent
session took this issue, not a particular product. The skill already described
the `assigned:*` namespace as open to any claimant ("another agent, a bot, a
teammate's tooling"); the label it applied itself was the one thing that
contradicted that.

The claim comment now reads `Claimed by an agent session (<id>).`, where `<id>`
is the first 8 characters of `CLAUDE_CODE_SESSION_ID`. That turns a question the
skill previously called "mechanically indistinguishable" — is this claim my own
earlier mark, or a sibling session's? — into a comparison against the latest
claim comment. Only an exact match licenses proceeding, so any id that can't be
positively accounted for still stops and asks. Where no session id is exported
the comment says `(id unavailable)` and the old judgement applies.

The practical gain is unattended runs, which previously had to stop on *every*
own-account claim, including their own.

Behavior changes, effective as soon as the plugin updates:

- **New claims use the new label.** An issue claimed from now on carries
  `assigned:agent-session`; `gh label create --force` in the claim block creates
  it on first use in any repo.
- **Claims already on your issues keep working, and need no cleanup.** The
  pickup check matches the `assigned:*` prefix rather than an enumerated list,
  so an issue carrying `assigned:claude-code` is still detected as claimed.
  Verified against a real issue in this repo, not by inspection. There is no
  relabeling script and none is needed.
