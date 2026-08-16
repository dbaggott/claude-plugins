#!/usr/bin/env bash
# The two jq programs that turn a PR's raw payloads into review activity, shared
# by the only two producers of it: watch-pr.sh, which already holds the payloads
# from the poll that woke it, and pr-round.sh, which fetches them. One definition
# so a caller reads the same objects whichever produced them.
#
# Both take `--arg s <since-iso> --arg slug <login-to-exclude>` and emit one
# compact object per line with `kind`, `author`, `at` and `body`. Both read the
# normalised object fetch-pr-state.sh produces — ACTIVITY_JQ_REVIEWS the whole
# object, ACTIVITY_JQ_INLINE its `.inline` array, since inline findings appear in
# neither of the other sources. ACTIVITY_JQ_SUMMARY projects either result down
# to the body-less form watch-pr.sh reports.
#
# Reading a normalised shape rather than two raw payloads is what lets one
# definition serve a forge these were not written against.
#
# `mine` matches both spellings GitHub uses for one bot: GraphQL reports a Bot
# author's login as `<slug>`, REST as `<slug>[bot]`.

# `$s` and `$slug` are jq variables bound by --arg, not shell ones.
# shellcheck disable=SC2016,SC2034  # sourced; the caller reads both.
ACTIVITY_JQ_REVIEWS='
  def mine: . == $slug or . == ($slug + "[bot]");
  (.reviews[]?  | select(.at > $s and (.author | mine | not))
    | {kind: "review", author, state, at, body}),
  (.comments[]? | select(.at > $s and (.author | mine | not))
    | {kind: "comment", author, at, body})'

# `id` is the REST comment id, which replying via `in_reply_to` takes. It is NOT
# the `PRRT_…` thread id the GraphQL reply mutation takes — that one comes from
# pr-threads.sh, and pr-round.sh's `── threads ──` section carries it. A caller
# that reaches for this `id` against the GraphQL mutation pays a fetch to find
# out they are different namespaces.
# shellcheck disable=SC2016,SC2034
ACTIVITY_JQ_INLINE='
  def mine: . == $slug or . == ($slug + "[bot]");
  .[] | select(.at > $s and (.author | mine | not))
  | {kind: "inline", author, path, line, id, at, body}'

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
