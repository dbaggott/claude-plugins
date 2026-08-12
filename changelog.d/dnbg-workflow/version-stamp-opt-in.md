The version stamp is now opt-in and **off by default**. When it was introduced,
every session stamped an invisible `<!-- dnbg-workflow <version> -->` comment
onto PR descriptions, review bodies, and issue claim comments. That text lands on
artifacts published under your name in repos you may share with people who never
installed this plugin, so it is now something you switch on rather than something
you inherit.

Turn it on with the new `version_stamp` option in `/plugin` (Configure →
dnbg-workflow). With it off, the session-start note that carries the version is
not emitted at all and the three publishing skills leave the stamp out.

## Migration

Nothing to do unless you want the stamp. If you were relying on it — to trace a
published PR or review back to the prompt version that produced it — enable
`version_stamp` from `/plugin`, or the stamps silently stop appearing on
everything published after this update. Artifacts already stamped keep theirs.
