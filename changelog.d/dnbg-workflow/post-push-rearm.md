Fixed the PR watch silently dropping a review that arrived while you were
pushing a fix. `git-workflow` told you to re-arm the watch with a fresh clock
reading after a push, and anything the reviewer posted between the previous
watch returning and the new one arming was filtered out for good — not
deferred. It now says to re-use the line the watch printed and change only the
head.

Also fixed the watch staying quiet about a red build on the commit you just
pushed, when that check was already red before the push. Check results belong to
the commit they ran on, and the watch was matching them by name alone — so the
second failure looked like the one you had already been told about.
