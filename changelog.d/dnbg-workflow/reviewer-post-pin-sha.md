The reviewer now posts every review through the reviews endpoint with the body
read from a file (`jq --rawfile`), so a finding containing an apostrophe or a
newline no longer breaks the posting command. The review is pinned to the SHA
that was read (`commit_id`), so a commit pushed while the reviewer was writing no
longer receives a verdict on code nobody read; the head is also re-read just
before posting, and a move sends the reviewer back to cover the new commits. The
`<!-- reviewed-sha -->` stamp is now written from that same SHA. The unpinned
`gh pr review` verdict-only form is gone; a verdict-only review is the same
payload without inline comments.
