`git-workflow`'s "Watching for the first review" snippet described the wrong
failure for both arguments its guard checks. It said `watch-pr.sh` fails quietly
on either being blank, that a blank head means "its commit check can never fire
for the whole window", and that the guard exists to make those loud. Neither
half holds: a blank `<last_head>` is accepted and self-heals from the first
observed HEAD, and a blank `<bot_slug>` is refused outright with
`result=ERROR reason=bad-args`.

The guard is unchanged and still worth having — a blank value means the `gh`
call above it failed — but the comment now says what the watcher actually does
with each argument, so an agent debugging a watch is not reasoning from a
behaviour the script does not have.
