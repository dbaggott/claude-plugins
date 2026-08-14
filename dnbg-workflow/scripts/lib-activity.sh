#!/usr/bin/env bash
# The two jq programs that turn a PR's raw payloads into review activity, shared
# by the only two producers of it: watch-pr.sh, which already holds the payloads
# from the poll that woke it, and pr-round.sh, which fetches them. One definition
# so a caller reads the same objects whichever produced them.
#
# Both take `--arg s <since-iso> --arg slug <login-to-exclude>` and emit one
# compact object per line with `kind`, `author`, `at` and `body`. Feed
# ACTIVITY_JQ_REVIEWS the `gh pr view --json reviews,comments` payload and
# ACTIVITY_JQ_INLINE the `pulls/<n>/comments` one — inline findings appear in
# neither the other's source. ACTIVITY_JQ_SUMMARY projects either result down to
# the body-less form watch-pr.sh reports.
#
# `mine` matches both spellings GitHub uses for one bot: GraphQL reports a Bot
# author's login as `<slug>`, REST as `<slug>[bot]`.

# `$s` and `$slug` are jq variables bound by --arg, not shell ones.
# shellcheck disable=SC2016,SC2034  # sourced; the caller reads both.
ACTIVITY_JQ_REVIEWS='
  def mine: . == $slug or . == ($slug + "[bot]");
  (.reviews[]?  | select(.submittedAt > $s and (.author.login | mine | not))
    | {kind: "review", author: (.author.login // ""), state: (.state // ""),
       at: .submittedAt, body: (.body // "")}),
  (.comments[]? | select(.createdAt > $s and (.author.login | mine | not))
    | {kind: "comment", author: (.author.login // ""), at: .createdAt,
       body: (.body // "")})'

# `id` is the REST comment id, which replying via `in_reply_to` takes. It is NOT
# the `PRRT_…` thread id the GraphQL reply mutation takes — that one comes from
# pr-threads.sh, and pr-round.sh's `── threads ──` section carries it. A caller
# that reaches for this `id` against the GraphQL mutation pays a fetch to find
# out they are different namespaces.
# shellcheck disable=SC2016,SC2034
ACTIVITY_JQ_INLINE='
  def mine: . == $slug or . == ($slug + "[bot]");
  .[] | select(.created_at > $s and (.user.login | mine | not))
  | {kind: "inline", author: (.user.login // ""), path: (.path // ""),
     line: (.line // .original_line), id: .id, at: .created_at,
     body: (.body // "")}'

# The same objects with the body dropped, for a producer that signals rather than
# delivers. watch-pr.sh emits this; pr-round.sh emits the full objects. Defined
# here so "the summary" stays a projection of the shared shape rather than a
# second, drifting description of it.
#
# A watcher that printed bodies read as a complete round while carrying neither
# the threads nor the diff a round needs, so a caller could act on it and be
# wrong — and one that ran pr-round.sh afterwards paid for every body twice.
# shellcheck disable=SC2034
ACTIVITY_JQ_SUMMARY='del(.body)'
