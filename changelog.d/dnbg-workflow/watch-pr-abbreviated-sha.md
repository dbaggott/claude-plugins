`watch-pr.sh` now refuses an abbreviated `<last_head>` instead of reporting a push
that never happened. The value is compared as a string against the 40-character
`headRefOid` GitHub returns, so a short SHA could never match it — two watches
armed with 7-character SHAs both returned `result=COMMITS` within seconds of
starting, each naming the full SHA as `new_head` with nothing having been pushed.
`reviewer` read that as a delta to re-review and `git-workflow` read it as the
author pushing; neither could tell it from the real thing.

Anything that is neither empty nor 40 lowercase hex characters now reports
`result=ERROR reason=bad-args` and exits 0, matching the existing empty-slug bail.
Empty is still accepted and still self-heals from the first observed HEAD, and
`--issue` mode (which never reads the argument) is unaffected.

## Migration
Callers passing a short SHA must switch to the full one —
`gh pr view <n> --repo <repo> --json headRefOid --jq .headRefOid`. Both skills
already do; the `reviewer` skill now says so explicitly at the spawn site.
