`git-workflow` described `watch-pr.sh`'s argument handling wrongly in three
places. All three are corrected; no behaviour changed.

**The watch-guard comment** in "Watching for the first review" said the script
fails quietly on either argument being blank, and that a blank head means its
commit check "can never fire for the whole window". Neither half holds: a blank
`<last_head>` is accepted and self-heals from the first observed HEAD, and a
blank `<bot_slug>` is refused outright with `result=ERROR reason=bad-args`. The
guard is unchanged — a blank value means the `gh` call above it failed — but its
stated rationale now matches what the watcher does.

**`result=ERROR reason=bad-args` now has its own entry** in the result-line
table, which previously routed every `ERROR` to "check `gh auth status`, do not
re-arm". `bad-args` needs the opposite remedy: nothing failed, the watch refused
to start, so fix the argument and re-spawn.

**The re-arm step now says to pass the full 40-character `headRefOid`.** An
abbreviated SHA is how a watch actually earns a `bad-args` here — the spawn's
guard tests for blankness, and an abbreviation is not blank — so it slips
through to the watcher, which refuses it.
