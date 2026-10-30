Spec reviews no longer start with a failed `gh issue view --json lastEditedAt`
call. Both the reviewer and the issue author are now told that `gh issue view`
does not expose the field, and the author side names the query that reads it,
printing `null` for a body that was never edited.
