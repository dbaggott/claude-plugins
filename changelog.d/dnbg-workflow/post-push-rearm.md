Fixed the PR watch silently dropping a review that arrived while you were
pushing a fix. `git-workflow` told you to re-arm the watch with a fresh clock
reading after a push, and anything the reviewer posted between the previous
watch returning and the new one starting fell in that gap and was filtered out
for good — not deferred. It now says to re-use the line the watch printed and
change only the head.
