Spec reviews now say that `gh issue view --json` cannot read an issue's
`lastEditedAt`, on both the reviewer's and the issue author's side, and the
author's side names the query that does, printing `null` for a body that was
never edited. Agents had been spending a failed call on `gh issue view` before
finding the query.
