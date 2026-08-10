The issue-scoped wait now wakes on PRs that reference an issue without a closing
keyword, and the claim check now sees them too.

Both asked "which PRs belong to this issue?" using only
`closedByPullRequestsReferences`, which lists PRs carrying a **closing keyword**
and nothing else. `git-workflow`'s multi-repo rule has exactly one sibling close
an issue while the rest merely reference it, so the narrow source misses the
shape that rule mandates.

**`reviewer`'s issue-scoped wait** (`watch-pr.sh --issue`) polls the issue
timeline's cross-references alongside the closing references. Previously a real
resolving PR that linked the issue in prose never woke the watch: it ran its full
window, reported `IDLE`, and the deadline path then presented it as a probably
wrong issue number — a diagnosis that could not be confirmed, because the issue
resolved fine. Meanwhile the unreviewed PR could merge.

**`issue-workflow`'s claim check** gained the same second source. Without it, an
in-flight multi-repo change reads as unclaimed the moment its closing PR merges,
and a second session starts work already half-shipped.

A new `ERROR reason=issue-timeline` reports the timeline source going blind,
rather than letting partial blindness present as a quiet issue.

`tests/coupling.bats` now pins both sites against `reviewer`'s discovery set, so
neither can be narrowed alone. A discovery source a site deliberately skips must
say so inline (`PR-SOURCE-EXEMPT: <source> — <reason>`); `gh search prs` is
exempt at both, since the timeline is authoritative with no index lag and the
search API's rate limit sits well below the watcher's poll floor.

## Migration
`watch-pr.sh --issue` takes a new optional `--exclude=<url,url,...>` of PR URLs
already triaged as not-resolving. It is not optional in practice when re-arming:
a mention-only PR left open satisfies the timeline source on **every** tick, so a
wait re-armed without it wakes immediately and repeatedly. Carry the list forward
across re-arms, and use full PR URLs — the timeline spans repos, where bare
numbers collide. Only the `--exclude=<value>` form is accepted; a valueless
`--exclude` is refused with `result=ERROR reason=bad-args`.
