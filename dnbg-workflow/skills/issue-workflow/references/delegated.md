# Delegated mode

Part of the `issue-workflow` skill. Every place a `dnbg-workflow` skill asks the
operator something points here for the case where nobody can answer: the asking
agent was dispatched by another agent, and the question has to reach whoever
dispatched it.

## When it applies

You are in delegated mode when `AskUserQuestion` is not among your tools, as in
any subagent. Decide on that alone. The operator saying they will be away, a
long silence, or an automated-looking task does not put you in delegated mode;
with the tool present, ask the way the site says.

## Use an answer you were already given

The dispatcher may have answered in advance: "send it to review when done",
"auto-handle the review", "review the draft now". An answer given in advance is
the answer. Act on it and say in your report which question it settled.

An open question in the issue with a stated default is answered the same way:
take the default and say in the PR description which defaults you took.

Only a question nothing answered stops you.

## Otherwise: post it, then stop

1. **Post the question as a comment on the issue you are working**, or on the
   PR when there is no issue. The issue is where the dispatcher watches, so a
   question about a PR still goes on its issue when there is one. A reviewer
   posts on what it was asked to review.
2. **End the turn with the question as your report.** Include the comment's URL.
   Take no step the answer would decide: don't pick an option, don't mark a PR
   ready, don't start the next phase.

Never choose silently. If you went ahead on anything, a pre-answer or a default,
the report says so.

The comment begins with exactly `Delegated question:`. That is how the
dispatcher tells your question from other comments under the same login, so put
nothing before it, not even a heading. Then give it what it needs to answer
without re-deriving your work:

- **The decision needed**, in one sentence.
- **The options you see**, and **what you would do under each**.
- **Your recommendation**, if you have one, and why.

```
Delegated question: send https://github.com/<owner>/<repo>/pull/12 to review?

The draft implements the issue as written; self-review fixed one finding and declined none.

- **Send to review**: I mark it ready and watch for the first review.
- **Not yet**: it stays a draft until you say otherwise.

Recommended: send to review. Nothing in it departs from the issue.
```

## With neither an issue nor a PR

There is nowhere to post. Where the site recommends a default, take it, say in
the report which defaults you took, and finish the work. Where it does not, end
the turn with the question as your report.
