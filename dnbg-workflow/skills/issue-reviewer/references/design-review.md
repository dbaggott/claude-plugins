# Issue reviewer: design review

Part of the `issue-reviewer` skill. Read this when a body under review is a
**tracking issue** — it opens by declaring itself one. Its shape is defined in
`issue-workflow`'s `references/tracking-issue.md`; that file is the standard this
review holds the body to, so read it first.

Everything in `SKILL.md` still runs — both passes, the verdict rules, finding IDs,
posting. This adds checks to each pass, and changes what the round comment says.

## Mechanical additions

- **Every fixed section is present**, under the names `tracking-issue.md` gives.
- **Every cited ID resolves.** Collect every `C#`, `R#`, `D#`, `Q#` and `A#`
  mentioned anywhere in the body, and confirm each has an entry. Then, per
  prefix, confirm no number is missing from the sequence and none is defined
  twice. A gap is a deleted entry, which breaks every citation to it elsewhere;
  a retired entry is marked, not missing.
- **Coverage markings are well-formed.** A requirement line ending in something
  that looks like a marking but is not exactly `*(end-to-end: A<n>)*` or
  `*(deferred: <reason>)*` is a finding, since the coverage check reads it as
  uncovered. An `end-to-end` marking names an `A#` that exists.

## Judgment additions

- **Every requirement is checkable.** Could a reviewer of the work say whether a
  result meets it? One that cannot be failed cannot be accepted either.
- **Every decision carries a rationale, and a reversal condition or `none
  identified`.** A missing rationale is blocking: a later reader meeting a case
  the decision does not name cannot tell whether it covers it. A missing reversal
  clause is blocking too; `none identified` is an answer and passes.
- **Every open question has a default.** Blocking when absent: the resolver who
  reaches it either stalls or picks silently.
- **End-to-end criteria exist, and each names its contributors.** A design with
  none has no definition of done above the children.
- **Interfaces between parts are named.** Where one part hands something to
  another — a script's output another consumes, a file format, a label, a comment
  shape — the body names the thing and its shape. Unnamed, each child invents its
  own side and they meet at review.
- **No decision is a disguised operator question.** A decision the design's
  author could not actually make — a priority, a cost the operator bears, a policy
  that is theirs — recorded as settled. Blocking: everything downstream applies it
  as decided.
- **The candidate decomposition, if present, covers every requirement** — each
  `R#` appears in some row's `Covers`, or carries one of the two markings.

## The round comment

Name the mode in the comment's first line — `Spec review (design mode), round
<n>: READY` — so the author and the next reader know which checks ran.

List every check above in the comment, each with its outcome — the findings it
produced by ID, or `none`. A `READY` that names no checks cannot be told apart
from one where they were skipped.
