`watch-pr.sh` no longer loses a review that landed before the watch was armed.
Pushes were already detected by comparing state, so one that happened while no
watcher was running was still caught; reviews were counted against `since`, so a
verdict posted during a gap in watching — or before the `since` a re-arm was
given — was invisible for good, and the watch reported `IDLE`, which reads as a
PR nobody has looked at.

The new `--last-verdict=<sha>` argument carries the SHA the caller last handled a
verdict for. Each poll compares the standing verdict against it, ignoring
`since`, so a verdict at the current HEAD wakes the watch however long it has
been sitting there. The watch's own verdicts never wake it, under either spelling
of a bot login. When the check fires, the result line carries `verdict_sha=<sha>`
to re-arm with.

`git-workflow` and `reviewer` both pass it now, so the fix applies without
anything on your side. Omitting the argument leaves the previous behaviour
exactly as it was.

Trailing arguments are now accepted in any order and refused when unrecognised —
`--was-draft` was previously read only in position six, and a second flag would
have silenced one of them depending on typing order.
