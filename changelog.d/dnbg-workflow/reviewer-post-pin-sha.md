The reviewer now posts every review through the reviews endpoint with the body
read from a file (`jq --rawfile`), so a finding containing an apostrophe or a
newline no longer breaks the posting command. The review is pinned to the SHA
that was read (`commit_id`), and the head is re-read just before posting: if a
commit landed in between, the reviewer covers it and posts at the new head rather
than attaching its verdict to code it never saw. The unpinned `gh pr review`
verdict-only form is gone; a verdict-only review is the same payload without
inline comments.
